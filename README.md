# robert-consulting-platform-ops

Platform operations, monitoring stack, and deployment tooling for the Robert Consulting threat intelligence and compliance platform — running on k3s (Hetzner CX33, nbg1).

This repo is the operational backbone for two production APIs and their frontends, providing a single source of truth for cluster-level configuration, observability, and deployment automation.

---

## Platform

| Service | URL | Repo |
|---------|-----|------|
| Threat Intelligence API | https://api.threat.robertconsulting.net | [robert-consulting-threat-api](https://github.com/Necron-99/robert-consulting-threat-api) |
| Compliance Framework API | https://api.compliance.robertconsulting.net | [robert-consulting-compliance-api](https://github.com/Necron-99/robert-consulting-compliance-api) |
| Threat Intelligence UI | https://threat.robertconsulting.net | [robert-consulting-content](https://github.com/Necron-99/robert-consulting-content) |
| Compliance Mapper UI | https://compliance.robertconsulting.net | [robert-consulting-content](https://github.com/Necron-99/robert-consulting-content) |
| Grafana | https://grafana.robertconsulting.net | this repo |
| Prometheus | https://prometheus.robertconsulting.net | this repo |

---

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

---

## Monitoring Stack

Built on [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) v85.1.3 — Prometheus, Grafana, Alertmanager, and node-exporter on a single k3s node.

Both APIs are instrumented with `prometheus-fastapi-instrumentator` and scraped via `additionalScrapeConfigs`. The Grafana dashboard surfaces request rates, response time percentiles (p50/p95/p99), error rates, per-endpoint breakdowns, and node-level CPU/memory metrics.

### Install

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

### Import Grafana dashboard

```bash
GRAFANA_PASS=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode)

curl -s -X POST "https://grafana.robertconsulting.net/api/dashboards/import" \
  -H "Content-Type: application/json" \
  -u "admin:${GRAFANA_PASS}" \
  -d "{
    \"dashboard\": $(cat k8s/monitoring/dashboards/rc-platform-overview.json),
    \"overwrite\": true,
    \"inputs\": [{\"name\": \"DS_PROMETHEUS\", \"type\": \"datasource\",
                  \"pluginId\": \"prometheus\", \"value\": \"prometheus\"}],
    \"folderId\": 0
  }"
```

---

## Deployment Script

`scripts/deploy.sh` handles the full deployment cycle — S3 database upload and Kubernetes rollout — with credential management, dry-run support, and post-deploy verification.

### First-time setup

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh --init
# Edit ~/.config/robert-consulting/deploy.env
./scripts/deploy.sh --all --dry-run
./scripts/deploy.sh --all
```

### Usage

```bash
./scripts/deploy.sh --all                  # Upload DBs + rollout both APIs
./scripts/deploy.sh --threat               # Threat API only
./scripts/deploy.sh --compliance           # Compliance API only
./scripts/deploy.sh --all --skip-upload    # Rollout only, skip S3 upload
./scripts/deploy.sh --all --dry-run        # Show what would happen
./scripts/deploy.sh --status               # Platform state without deploying
./scripts/deploy.sh --rotate               # Rotate AWS credentials
```

### Why the deploy script matters

Both APIs load their SQLite databases from S3 via Kubernetes init containers on pod start. A `kubectl rollout restart` without a prior S3 upload will pull the old database. The deploy script enforces the correct order — upload first, rollout second — and verifies both steps completed successfully.

### Configuration

All sensitive values live in `~/.config/robert-consulting/deploy.env` (permissions: 600). Environment variables take precedence. Compatible with `aws-vault`:

```bash
aws-vault exec <profile> -- ./scripts/deploy.sh --all
```

---

## Stack

| Component | Version | Role |
|-----------|---------|------|
| k3s | latest | Lightweight Kubernetes |
| kube-prometheus-stack | 85.1.3 | Prometheus + Grafana + Alertmanager |
| cert-manager | — | TLS via Let's Encrypt |
| ingress-nginx | — | Ingress controller |
| Python | 3.12 | API runtime |
| FastAPI | 0.115.0 | API framework |
| SQLite | — | Database (read-only, S3-backed) |

### k3s compatibility notes

k3s embeds etcd, scheduler, and controller-manager in a single binary and exposes their metrics on `127.0.0.1` only. The following monitors are disabled in `prometheus-stack-values.yaml` to avoid false alerts:
- `kubeScheduler`
- `kubeControllerManager`
- `kubeEtcd`
- `kubeProxy`

CoreDNS metrics are accessible and enabled.

---

## Security notes

- AWS credentials for init containers are stored as Kubernetes secrets (`aws-threat-api-credentials`, `aws-compliance-api-credentials`) — never in code or this repo
- Grafana admin password is stored as a Kubernetes secret — retrieve with `kubectl get secret`
- The `deploy.sh` config file is created at `~/.config/robert-consulting/deploy.env` with 600 permissions
- All container images run as non-root users
- Databases are mounted read-only inside pods

---

## Related

- **[robert-consulting-threat-api](https://github.com/Necron-99/robert-consulting-threat-api)** — Threat intelligence API
- **[robert-consulting-compliance-api](https://github.com/Necron-99/robert-consulting-compliance-api)** — Compliance framework API
- **[robert-consulting-content](https://github.com/Necron-99/robert-consulting-content)** — Frontend UIs

© 2026 Robert Consulting LLC. All rights reserved.
