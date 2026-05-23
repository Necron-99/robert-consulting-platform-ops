# Changelog

All notable changes to the Robert Consulting platform operations repository.

---

## [Unreleased]

---

## [1.0.0] — 2026-05-23

### Added
- Initial release — platform-ops extracted from `robert-consulting-compliance-api`
  where monitoring config had been living since the compliance API was the first
  service deployed

**Monitoring:**
- `kube-prometheus-stack` Helm values (`prometheus-stack-values.yaml`)
  - Prometheus: 30d retention, 8GB size limit, 10Gi persistent storage
  - Grafana: persistent storage, `grafana.robertconsulting.net` ingress
  - Alertmanager: persistent storage
  - `additionalScrapeConfigs` for both `compliance-api` and `threat-api`
  - k3s compatibility: kubeScheduler, kubeControllerManager, kubeEtcd,
    kubeProxy monitors disabled
- Prometheus ingress manifest (`prometheus-ingress.yaml`)
- Robert Consulting Platform Overview Grafana dashboard
  (`dashboards/rc-platform-overview.json`)
  - 5 sections: Platform Overview, Request Traffic, Threat API Endpoints,
    Compliance API Endpoints, Infrastructure
  - 19 panels: uptime stats, request rate, error rate, p95 latency,
    per-endpoint time series and tables, node CPU/memory, pod counts
  - Links to both live tools in dashboard header
  - 30s auto-refresh

**Scripts:**
- `deploy.sh` — platform deployment script v1.0.0
  - S3 database upload (threat and compliance) before rollout
  - `kubectl rollout restart` + status wait with timeout
  - Post-deploy verification
  - `--init`: creates `~/.config/robert-consulting/deploy.env` at 600 permissions
  - `--rotate`: updates credentials in config and k8s secrets
  - `--status`: platform state without deploying
  - `--dry-run`: shows what would happen without executing
  - `--skip-upload`: rollout only, skip S3 upload
  - Supports `aws-vault` and environment variable credential overrides

**Docs:**
- `docs/runbook.md` — operational runbook covering deployment checklist,
  common operations, troubleshooting (CrashLoopBackOff, Prometheus scraping,
  Grafana dashboard import, YAML parse errors), and credential rotation
- `README.md` — platform overview, stack, security notes

**Infrastructure:**
- `.gitignore` — excludes credentials, secrets, DB files, Terraform state,
  OS and editor artifacts
- Added as submodule to both `robert-consulting-threat-api` and
  `robert-consulting-compliance-api`
