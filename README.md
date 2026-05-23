# robert-consulting-platform-ops

Kubernetes platform operations, monitoring stack configuration, and deployment tooling for the Robert Consulting platform running on k3s (Hetzner CX33, nbg1).

## Platform Overview

| Service | URL | Repo |
|---------|-----|------|
| Threat Intelligence API | https://api.threat.robertconsulting.net | [robert-consulting-threat-api](https://github.com/Necron-99/robert-consulting-threat-api) |
| Compliance Framework API | https://api.compliance.robertconsulting.net | [robert-consulting-compliance-api](https://github.com/Necron-99/robert-consulting-compliance-api) |
| Threat Intelligence UI | https://threat.robertconsulting.net | [robert-consulting-content](https://github.com/Necron-99/robert-consulting-content) |
| Compliance Mapper UI | https://compliance.robertconsulting.net | [robert-consulting-content](https://github.com/Necron-99/robert-consulting-content) |
| Grafana | https://grafana.robertconsulting.net | this repo |
| Prometheus | https://prometheus.robertconsulting.net | this repo |

## Repository Structure

```
.
├── k8s/
│   └── monitoring/
│       ├── prometheus-stack-values.yaml    # kube-prometheus-stack Helm values
│       ├── prometheus-ingress.yaml         # Prometheus ingress (nginx + cert-manager)
│       └── dashboards/
│           └── rc-platform-overview.json   # Robert Consulting platform Grafana dashboard
├── scripts/
│   └── deploy.sh                           # Platform deployment script
└── docs/
    └── runbook.md                          # Operational runbook
```

## Monitoring Stack

Built on [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

### Initial Install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values k8s/monitoring/prometheus-stack-values.yaml
```

### Upgrade

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml
```

### Import Grafana Dashboard

```bash
GRAFANA_URL="https://grafana.robertconsulting.net"
GRAFANA_PASS="<admin password>"

curl -s -X POST "${GRAFANA_URL}/api/dashboards/import" \
  -H "Content-Type: application/json" \
  -u "admin:${GRAFANA_PASS}" \
  -d "{
    \"dashboard\": $(cat k8s/monitoring/dashboards/rc-platform-overview.json),
    \"overwrite\": true,
    \"inputs\": [{\"name\": \"DS_PROMETHEUS\", \"type\": \"datasource\", \"pluginId\": \"prometheus\", \"value\": \"prometheus\"}],
    \"folderId\": 0
  }"
```

## Deployment Script

`scripts/deploy.sh` uploads databases to S3 and rolls out Kubernetes deployments.

### First-time setup

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh --init
# Edit ~/.config/robert-consulting/deploy.env with your values
```

### Usage

```bash
# Deploy everything (upload DBs + rollout both APIs)
./scripts/deploy.sh --all

# Deploy threat-api only
./scripts/deploy.sh --threat

# Deploy compliance-api only
./scripts/deploy.sh --compliance

# Rollout only (skip S3 DB upload)
./scripts/deploy.sh --all --skip-upload

# Dry run — show what would happen
./scripts/deploy.sh --all --dry-run

# Show current platform state
./scripts/deploy.sh --status

# Rotate AWS credentials
./scripts/deploy.sh --rotate
```

### Configuration

All sensitive values are stored in `~/.config/robert-consulting/deploy.env` (permissions: 600).
Environment variables take precedence over the config file.
Compatible with `aws-vault`:

```bash
aws-vault exec <profile> -- ./scripts/deploy.sh --all
```

## Stack

- **k3s** — lightweight Kubernetes on Hetzner CX33
- **kube-prometheus-stack** v85.1.3 — Prometheus, Grafana, Alertmanager, node-exporter
- **cert-manager** — TLS via Let's Encrypt
- **ingress-nginx** — ingress controller
- **FastAPI** — both APIs, instrumented with prometheus-fastapi-instrumentator
- **SQLite** — databases stored in S3, fetched by init containers on pod start

## Notes

- k3s embeds etcd, scheduler, and controller-manager — their monitors are disabled in values to avoid false alerts
- Prometheus scrapes both APIs via `additionalScrapeConfigs` (static configs to ClusterIP services)
- Grafana persistent storage via `local-path` provisioner — survives pod restarts, not node deletion
- AWS credentials for init containers stored as k8s secrets (`aws-threat-api-credentials`, `aws-compliance-api-credentials`)
