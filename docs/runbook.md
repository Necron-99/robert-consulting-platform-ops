# Platform Operations Runbook

## Deployment Checklist

Before every `kubectl rollout restart`:

1. Upload updated databases to S3:
   ```bash
   aws s3 cp ~/threat.db s3://robert-consulting-threat/data/threat.db
   aws s3 cp ~/compliance.db s3://robert-consulting-compliance/data/compliance.db
   ```
2. Or use the deploy script (preferred):
   ```bash
   ./scripts/deploy.sh --all
   ```

---

## Common Operations

### Restart an API

```bash
# Both
./scripts/deploy.sh --all --skip-upload

# One at a time
kubectl rollout restart deployment/threat-api -n threat-api
kubectl rollout restart deployment/compliance-api -n compliance-api
```

### Check Pod Status

```bash
kubectl get pods -n threat-api
kubectl get pods -n compliance-api
kubectl get pods -n monitoring
```

### View API Logs

```bash
kubectl logs -n threat-api -l app=threat-api --tail=50 -f
kubectl logs -n compliance-api -l app=compliance-api --tail=50 -f
```

### Check Prometheus Scrape Targets

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job == "threat-api" or .labels.job == "compliance-api") | {job: .labels.job, health: .health, lastError: .lastError}'
```

---

## Troubleshooting

### Pod CrashLoopBackOff — Database Not Found

The init container failed to fetch the DB from S3.

```bash
# Check init container logs
kubectl logs -n threat-api <pod-name> -c fetch-database
kubectl logs -n compliance-api <pod-name> -c fetch-database

# Verify DB exists in S3
aws s3 ls s3://robert-consulting-threat/data/
aws s3 ls s3://robert-consulting-compliance/data/

# Re-upload if missing
aws s3 cp ~/threat.db s3://robert-consulting-threat/data/threat.db
aws s3 cp ~/compliance.db s3://robert-consulting-compliance/data/compliance.db

# Then rollout (skip upload since we just did it)
./scripts/deploy.sh --all --skip-upload
```

### Prometheus Not Scraping an API

```bash
# Check target health
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "threat-api")'

# Verify /metrics endpoint is exposed
kubectl exec -n threat-api <pod-name> -- curl -s http://localhost:8000/metrics | head -5

# Check additionalScrapeConfigs in prometheus-stack-values.yaml
grep -A5 "additionalScrapeConfigs" k8s/monitoring/prometheus-stack-values.yaml
```

### Grafana Dashboard Missing

```bash
# Re-import
GRAFANA_PASS=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode)

curl -s -X POST "https://grafana.robertconsulting.net/api/dashboards/import" \
  -H "Content-Type: application/json" \
  -u "admin:${GRAFANA_PASS}" \
  -d "{
    \"dashboard\": $(cat k8s/monitoring/dashboards/rc-platform-overview.json),
    \"overwrite\": true,
    \"inputs\": [{\"name\": \"DS_PROMETHEUS\", \"type\": \"datasource\", \"pluginId\": \"prometheus\", \"value\": \"prometheus\"}],
    \"folderId\": 0
  }"
```

### Helm Upgrade Fails — YAML Parse Error

```bash
# Validate values file before upgrading
python3 -c "import yaml; yaml.safe_load(open('k8s/monitoring/prometheus-stack-values.yaml'))" && echo "YAML valid"
```

---

## Credential Rotation

```bash
./scripts/deploy.sh --rotate
```

This updates:
1. `~/.config/robert-consulting/deploy.env`
2. k8s secrets `aws-threat-api-credentials` and `aws-compliance-api-credentials`

After rotation, restart both deployments to pick up new credentials:
```bash
./scripts/deploy.sh --all --skip-upload
```

---

## Monitoring Stack Upgrade

```bash
helm repo update
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml
```

Check current chart version:
```bash
helm list -n monitoring
```
