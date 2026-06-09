#!/bin/bash
# Deploy platform overview dashboard to Grafana
set -e

GRAFANA_PASS=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d)

GRAFANA_POD=$(kubectl get pod -n monitoring \
  -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}')

kubectl cp k8s/monitoring/dashboards/platform-overview.json \
  monitoring/$GRAFANA_POD:/tmp/dashboard.json

kubectl exec -n monitoring $GRAFANA_POD -c grafana -- \
  curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "admin:$GRAFANA_PASS" \
  http://localhost:3000/api/dashboards/db \
  -d @/tmp/dashboard.json

echo "Dashboard deployed"
