#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Robert Consulting Platform Deployment Script
# =============================================================================
# Uploads databases to S3 and rolls out Kubernetes deployments.
#
# Config precedence (highest to lowest):
#   1. Environment variables
#   2. ~/.config/robert-consulting/deploy.env
#   3. Built-in defaults (non-sensitive only)
#
# First-time setup:
#   ./deploy.sh --init
#
# Rotate credentials:
#   ./deploy.sh --rotate
#
# Usage:
#   ./deploy.sh [--threat] [--compliance] [--all] [--dry-run] [--help]
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

SCRIPT_VERSION="1.0.0"
CONFIG_DIR="${HOME}/.config/robert-consulting"
CONFIG_FILE="${CONFIG_DIR}/deploy.env"
CONFIG_PERMS="600"
CONFIG_DIR_PERMS="700"

# Non-sensitive defaults
DEFAULT_THREAT_BUCKET="robert-consulting-threat"
DEFAULT_THREAT_DB_KEY="data/threat.db"
DEFAULT_THREAT_NAMESPACE="threat-api"
DEFAULT_THREAT_DEPLOYMENT="threat-api"
DEFAULT_THREAT_DB_PATH="${HOME}/threat.db"

DEFAULT_COMPLIANCE_BUCKET="robert-consulting-compliance"
DEFAULT_COMPLIANCE_DB_KEY="data/compliance.db"
DEFAULT_COMPLIANCE_NAMESPACE="compliance-api"
DEFAULT_COMPLIANCE_DEPLOYMENT="compliance-api"
DEFAULT_COMPLIANCE_DB_PATH="${HOME}/compliance.db"

DEFAULT_AWS_REGION="us-east-1"

# =============================================================================
# Colours (suppressed if not a tty)
# =============================================================================

if [ -t 1 ]; then
  RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; BLUE=''; CYAN=''; BOLD=''; RESET=''
fi

# =============================================================================
# Logging
# =============================================================================

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }
dry()     { echo -e "${YELLOW}[DRY]${RESET}   $*"; }

die() { error "$*"; exit 1; }

# =============================================================================
# Config loading
# =============================================================================

load_config() {
  # Load config file if it exists
  if [[ -f "${CONFIG_FILE}" ]]; then
    local perms
    perms=$(stat -c "%a" "${CONFIG_FILE}" 2>/dev/null || stat -f "%OLp" "${CONFIG_FILE}" 2>/dev/null)
    if [[ "${perms}" != "600" ]]; then
      warn "Config file permissions are ${perms}, expected 600. Fixing..."
      chmod 600 "${CONFIG_FILE}"
    fi
    # shellcheck disable=SC1090
    set -a; source "${CONFIG_FILE}"; set +a
    info "Loaded config from ${CONFIG_FILE}"
  fi

  # Apply defaults for any unset non-sensitive variables
  : "${THREAT_BUCKET:=${DEFAULT_THREAT_BUCKET}}"
  : "${THREAT_DB_KEY:=${DEFAULT_THREAT_DB_KEY}}"
  : "${THREAT_NAMESPACE:=${DEFAULT_THREAT_NAMESPACE}}"
  : "${THREAT_DEPLOYMENT:=${DEFAULT_THREAT_DEPLOYMENT}}"
  : "${THREAT_DB_PATH:=${DEFAULT_THREAT_DB_PATH}}"

  : "${COMPLIANCE_BUCKET:=${DEFAULT_COMPLIANCE_BUCKET}}"
  : "${COMPLIANCE_DB_KEY:=${DEFAULT_COMPLIANCE_DB_KEY}}"
  : "${COMPLIANCE_NAMESPACE:=${DEFAULT_COMPLIANCE_NAMESPACE}}"
  : "${COMPLIANCE_DEPLOYMENT:=${DEFAULT_COMPLIANCE_DEPLOYMENT}}"
  : "${COMPLIANCE_DB_PATH:=${DEFAULT_COMPLIANCE_DB_PATH}}"

  : "${AWS_DEFAULT_REGION:=${DEFAULT_AWS_REGION}}"
}

# =============================================================================
# Prerequisite checks
# =============================================================================

check_prereqs() {
  header "Checking prerequisites"
  local missing=()

  for cmd in aws kubectl; do
    if command -v "${cmd}" &>/dev/null; then
      local ver
      if [[ "${cmd}" == "kubectl" ]]; then
        ver=$(kubectl version --client 2>&1 | grep -i client | head -1 || echo "kubectl")
      else
        ver=$(${cmd} --version 2>&1 | head -1)
      fi
      ok "${cmd} found (${ver})"
    else
      missing+=("${cmd}")
      error "${cmd} not found"
    fi
  done

  [[ ${#missing[@]} -gt 0 ]] && die "Missing required tools: ${missing[*]}"
}

# =============================================================================
# AWS credential check
# =============================================================================

check_aws_auth() {
  header "Checking AWS credentials"
  local identity
  if identity=$(aws sts get-caller-identity --output json 2>&1); then
    local account arn
    account=$(echo "${identity}" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    arn=$(echo "${identity}" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
    ok "AWS authenticated — Account: ${account}"
    info "Identity: ${arn}"
  else
    die "AWS authentication failed. Check credentials:\n${identity}"
  fi
}

# =============================================================================
# kubectl check
# =============================================================================

check_k8s_auth() {
  header "Checking Kubernetes access"
  if kubectl cluster-info &>/dev/null; then
    ok "Kubernetes cluster reachable"
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    info "Context: ${context}"
  else
    die "Cannot reach Kubernetes cluster. Check kubeconfig."
  fi
}

# =============================================================================
# S3 upload
# =============================================================================

upload_db() {
  local name="$1" local_path="$2" bucket="$3" key="$4"
  local s3_uri="s3://${bucket}/${key}"

  header "Uploading ${name} database"
  info "Source : ${local_path}"
  info "Target : ${s3_uri}"

  if [[ ! -f "${local_path}" ]]; then
    die "Database not found at ${local_path}"
  fi

  local size
  size=$(du -sh "${local_path}" | cut -f1)
  info "Size   : ${size}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    dry "Would run: aws s3 cp ${local_path} ${s3_uri}"
    return
  fi

  if aws s3 cp "${local_path}" "${s3_uri}" \
    --metadata "deployed=$(date -u +%Y-%m-%dT%H:%M:%SZ),deployer=$(whoami)"; then
    ok "${name} database uploaded successfully"
  else
    die "Failed to upload ${name} database"
  fi

  # Verify upload
  local remote_size
  remote_size=$(aws s3api head-object \
    --bucket "${bucket}" \
    --key "${key}" \
    --query "ContentLength" \
    --output text 2>/dev/null || echo "unknown")
  info "Remote size: ${remote_size} bytes"
}

# =============================================================================
# S3 freshness check
# =============================================================================

check_db_freshness() {
  local name="$1" bucket="$2" key="$3" local_path="$4"

  local last_modified
  last_modified=$(aws s3api head-object \
    --bucket "${bucket}" \
    --key "${key}" \
    --query "LastModified" \
    --output text 2>/dev/null || echo "NOT FOUND")

  if [[ "${last_modified}" == "NOT FOUND" ]]; then
    warn "${name} DB not found in S3 — upload required"
    return 1
  fi

  info "${name} DB last uploaded: ${last_modified}"

  # Compare local vs remote modification time
  if [[ -f "${local_path}" ]]; then
    local local_mtime
    local_mtime=$(date -r "${local_path}" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                  stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "${local_path}" 2>/dev/null || \
                  echo "unknown")
    info "${name} local DB modified: ${local_mtime}"
  fi
}

# =============================================================================
# Kubernetes rollout
# =============================================================================

rollout() {
  local name="$1" namespace="$2" deployment="$3"

  header "Rolling out ${name}"
  info "Namespace  : ${namespace}"
  info "Deployment : ${deployment}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    dry "Would run: kubectl rollout restart deployment/${deployment} -n ${namespace}"
    dry "Would run: kubectl rollout status deployment/${deployment} -n ${namespace}"
    return
  fi

  kubectl rollout restart "deployment/${deployment}" -n "${namespace}"

  info "Waiting for rollout to complete..."
  if kubectl rollout status "deployment/${deployment}" -n "${namespace}" \
    --timeout=300s; then
    ok "${name} rollout complete"
  else
    error "${name} rollout failed or timed out"
    info "Pod status:"
    kubectl get pods -n "${namespace}"
    info "Recent events:"
    kubectl describe deployment "${deployment}" -n "${namespace}" | tail -15
    return 1
  fi
}

# =============================================================================
# Post-deploy verification
# =============================================================================

verify() {
  local name="$1" namespace="$2" deployment="$3"

  header "Verifying ${name}"
  local ready
  ready=$(kubectl get deployment "${deployment}" -n "${namespace}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  local desired
  desired=$(kubectl get deployment "${deployment}" -n "${namespace}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

  if [[ "${ready}" == "${desired}" ]]; then
    ok "${name}: ${ready}/${desired} replicas ready"
  else
    warn "${name}: ${ready}/${desired} replicas ready"
  fi
}

# =============================================================================
# Init — create config file
# =============================================================================

cmd_init() {
  header "Initialising configuration"

  if [[ -f "${CONFIG_FILE}" ]]; then
    warn "Config file already exists at ${CONFIG_FILE}"
    read -r -p "Overwrite? [y/N] " confirm
    [[ "${confirm}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
  fi

  mkdir -p "${CONFIG_DIR}"
  chmod "${CONFIG_DIR_PERMS}" "${CONFIG_DIR}"

  cat > "${CONFIG_FILE}" << 'EOF'
# Robert Consulting Platform — Deployment Configuration
# Generated by deploy.sh --init
# Permissions: 600 (owner read/write only)
#
# Sensitive values (AWS credentials) should be set here OR as environment
# variables. Environment variables take precedence.
#
# NEVER commit this file to version control.

# ── AWS Credentials ──────────────────────────────────────────────────────────
# Prefer environment variables or aws-vault / instance profiles over hardcoding.
# If using aws-vault: comment these out and prefix commands with aws-vault exec.
#AWS_ACCESS_KEY_ID=
#AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1

# ── Threat API ───────────────────────────────────────────────────────────────
THREAT_BUCKET=robert-consulting-threat
THREAT_DB_KEY=data/threat.db
THREAT_DB_PATH=${HOME}/threat.db
THREAT_NAMESPACE=threat-api
THREAT_DEPLOYMENT=threat-api

# ── Compliance API ───────────────────────────────────────────────────────────
COMPLIANCE_BUCKET=robert-consulting-compliance
COMPLIANCE_DB_KEY=data/compliance.db
COMPLIANCE_DB_PATH=${HOME}/compliance.db
COMPLIANCE_NAMESPACE=compliance-api
COMPLIANCE_DEPLOYMENT=compliance-api
EOF

  chmod "${CONFIG_PERMS}" "${CONFIG_FILE}"
  ok "Config written to ${CONFIG_FILE} (permissions: ${CONFIG_PERMS})"
  info "Edit the file to set your values, then run: ./deploy.sh --all"
  info ""
  info "To use aws-vault instead of hardcoded credentials:"
  info "  aws-vault exec <profile> -- ./deploy.sh --all"
}

# =============================================================================
# Rotate — update AWS credentials in config and k8s secrets
# =============================================================================

cmd_rotate() {
  header "Credential rotation"

  [[ -f "${CONFIG_FILE}" ]] || die "Config file not found. Run --init first."

  info "Enter new AWS credentials (leave blank to keep current):"
  echo ""

  read -r -p "  AWS_ACCESS_KEY_ID     : " new_key_id
  read -r -s -p "  AWS_SECRET_ACCESS_KEY : " new_secret
  echo ""
  read -r -p "  AWS_DEFAULT_REGION    : " new_region

  echo ""

  # Update config file
  if [[ -n "${new_key_id}" ]]; then
    if grep -q "^AWS_ACCESS_KEY_ID=" "${CONFIG_FILE}"; then
      sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=${new_key_id}|" "${CONFIG_FILE}"
    else
      echo "AWS_ACCESS_KEY_ID=${new_key_id}" >> "${CONFIG_FILE}"
    fi
    ok "Updated AWS_ACCESS_KEY_ID in config"
  fi

  if [[ -n "${new_secret}" ]]; then
    if grep -q "^AWS_SECRET_ACCESS_KEY=" "${CONFIG_FILE}"; then
      sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=${new_secret}|" "${CONFIG_FILE}"
    else
      echo "AWS_SECRET_ACCESS_KEY=${new_secret}" >> "${CONFIG_FILE}"
    fi
    ok "Updated AWS_SECRET_ACCESS_KEY in config"
  fi

  if [[ -n "${new_region}" ]]; then
    sed -i "s|^AWS_DEFAULT_REGION=.*|AWS_DEFAULT_REGION=${new_region}|" "${CONFIG_FILE}"
    ok "Updated AWS_DEFAULT_REGION in config"
  fi

  chmod "${CONFIG_PERMS}" "${CONFIG_FILE}"

  # Optionally update k8s secrets
  echo ""
  read -r -p "Update Kubernetes secrets as well? [y/N] " update_k8s
  if [[ "${update_k8s}" =~ ^[Yy]$ ]]; then
    load_config

    for ns_secret in \
      "threat-api:aws-threat-api-credentials" \
      "compliance-api:aws-compliance-api-credentials"; do
      local ns="${ns_secret%%:*}"
      local secret="${ns_secret##*:}"

      info "Updating ${secret} in namespace ${ns}..."

      local patch_data="{}"
      [[ -n "${new_key_id}" ]] && patch_data=$(echo "${patch_data}" | \
        python3 -c "import sys,json,base64; d=json.load(sys.stdin); d['AWS_ACCESS_KEY_ID']=base64.b64encode('${new_key_id}'.encode()).decode(); print(json.dumps(d))")
      [[ -n "${new_secret}" ]] && patch_data=$(echo "${patch_data}" | \
        python3 -c "import sys,json,base64; d=json.load(sys.stdin); d['AWS_SECRET_ACCESS_KEY']=base64.b64encode('${new_secret}'.encode()).decode(); print(json.dumps(d))")
      [[ -n "${new_region}" ]] && patch_data=$(echo "${patch_data}" | \
        python3 -c "import sys,json,base64; d=json.load(sys.stdin); d['AWS_DEFAULT_REGION']=base64.b64encode('${new_region}'.encode()).decode(); print(json.dumps(d))")

      if kubectl patch secret "${secret}" -n "${ns}" \
        --type='json' \
        -p="[{\"op\":\"replace\",\"path\":\"/data\",\"value\":${patch_data}}]" \
        2>/dev/null; then
        ok "Updated ${secret} in ${ns}"
      else
        warn "Could not update ${secret} in ${ns} — may need manual update"
      fi
    done

    info ""
    info "Restart deployments to pick up new credentials:"
    info "  ./deploy.sh --all --skip-upload"
  fi

  ok "Rotation complete"
  info "Verify with: aws sts get-caller-identity"
}

# =============================================================================
# Status — show current state without deploying
# =============================================================================

cmd_status() {
  header "Platform status"
  load_config
  check_aws_auth

  echo ""
  info "S3 database state:"
  check_db_freshness "Threat" "${THREAT_BUCKET}" "${THREAT_DB_KEY}" "${THREAT_DB_PATH}" || true
  check_db_freshness "Compliance" "${COMPLIANCE_BUCKET}" "${COMPLIANCE_DB_KEY}" "${COMPLIANCE_DB_PATH}" || true

  echo ""
  info "Kubernetes deployment state:"
  verify "Threat API" "${THREAT_NAMESPACE}" "${THREAT_DEPLOYMENT}" || true
  verify "Compliance API" "${COMPLIANCE_NAMESPACE}" "${COMPLIANCE_DEPLOYMENT}" || true

  echo ""
  info "Prometheus scrape targets:"
  if kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus \
    9091:9090 &>/dev/null & sleep 2; then
    curl -s "http://localhost:9091/api/v1/targets" 2>/dev/null | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for t in data.get('data', {}).get('activeTargets', []):
        ns = t.get('labels', {}).get('namespace', '')
        if ns in ('threat-api', 'compliance-api'):
            print(f\"  {t['labels'].get('job','?'):20} health={t['health']:5} last={t.get('lastScrape','?')[:19]}\")
except:
    print('  Could not reach Prometheus')
" || true
    kill %% 2>/dev/null || true
  fi
}

# =============================================================================
# Argument parsing
# =============================================================================

DRY_RUN="false"
DO_THREAT="false"
DO_COMPLIANCE="false"
SKIP_UPLOAD="false"

usage() {
  cat << EOF
${BOLD}deploy.sh${RESET} v${SCRIPT_VERSION} — Robert Consulting platform deployment

${BOLD}USAGE${RESET}
  ./deploy.sh [options]

${BOLD}DEPLOYMENT OPTIONS${RESET}
  --threat          Deploy threat-api only
  --compliance      Deploy compliance-api only
  --all             Deploy both (default if neither specified)
  --skip-upload     Skip S3 DB upload (rollout only)
  --dry-run         Show what would happen without doing it

${BOLD}MANAGEMENT${RESET}
  --init            Create config file at ${CONFIG_FILE}
  --rotate          Rotate AWS credentials in config and k8s secrets
  --status          Show current platform state without deploying

${BOLD}OTHER${RESET}
  --help            Show this help

${BOLD}CONFIG${RESET}
  File    : ${CONFIG_FILE}
  Env     : All variables can be set as environment variables
  Perms   : ${CONFIG_PERMS} (owner read/write only)

${BOLD}EXAMPLES${RESET}
  ./deploy.sh --init
  ./deploy.sh --all
  ./deploy.sh --threat --dry-run
  ./deploy.sh --compliance --skip-upload
  aws-vault exec myprofile -- ./deploy.sh --all

EOF
}

[[ $# -eq 0 ]] && { usage; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threat)      DO_THREAT="true"      ;;
    --compliance)  DO_COMPLIANCE="true"  ;;
    --all)         DO_THREAT="true"; DO_COMPLIANCE="true" ;;
    --skip-upload) SKIP_UPLOAD="true"    ;;
    --dry-run)     DRY_RUN="true"        ;;
    --init)        cmd_init; exit 0      ;;
    --rotate)      cmd_rotate; exit 0    ;;
    --status)      cmd_status; exit 0    ;;
    --help|-h)     usage; exit 0         ;;
    *) die "Unknown option: $1. Use --help for usage." ;;
  esac
  shift
done

# Default to --all if neither specified
if [[ "${DO_THREAT}" == "false" && "${DO_COMPLIANCE}" == "false" ]]; then
  DO_THREAT="true"
  DO_COMPLIANCE="true"
fi

# =============================================================================
# Main deployment flow
# =============================================================================

header "Robert Consulting Platform Deploy v${SCRIPT_VERSION}"
[[ "${DRY_RUN}" == "true" ]] && warn "DRY RUN MODE — no changes will be made"

load_config
check_prereqs
check_aws_auth
check_k8s_auth

# ── Upload DBs ──
if [[ "${SKIP_UPLOAD}" == "false" ]]; then
  [[ "${DO_THREAT}" == "true" ]] && \
    upload_db "Threat" "${THREAT_DB_PATH}" "${THREAT_BUCKET}" "${THREAT_DB_KEY}"
  [[ "${DO_COMPLIANCE}" == "true" ]] && \
    upload_db "Compliance" "${COMPLIANCE_DB_PATH}" "${COMPLIANCE_BUCKET}" "${COMPLIANCE_DB_KEY}"
else
  warn "Skipping DB upload (--skip-upload)"
fi

# ── Rollouts ──
ROLLOUT_FAILED="false"
[[ "${DO_THREAT}" == "true" ]] && \
  rollout "Threat API" "${THREAT_NAMESPACE}" "${THREAT_DEPLOYMENT}" || ROLLOUT_FAILED="true"
[[ "${DO_COMPLIANCE}" == "true" ]] && \
  rollout "Compliance API" "${COMPLIANCE_NAMESPACE}" "${COMPLIANCE_DEPLOYMENT}" || ROLLOUT_FAILED="true"

# ── Verify ──
header "Post-deploy verification"
[[ "${DO_THREAT}" == "true" ]] && \
  verify "Threat API" "${THREAT_NAMESPACE}" "${THREAT_DEPLOYMENT}"
[[ "${DO_COMPLIANCE}" == "true" ]] && \
  verify "Compliance API" "${COMPLIANCE_NAMESPACE}" "${COMPLIANCE_DEPLOYMENT}"

# ── Summary ──
header "Done"
if [[ "${ROLLOUT_FAILED}" == "true" ]]; then
  error "One or more rollouts failed — check output above"
  exit 1
else
  ok "All deployments complete"
  [[ "${DRY_RUN}" == "true" ]] && warn "DRY RUN — no actual changes were made"
fi
