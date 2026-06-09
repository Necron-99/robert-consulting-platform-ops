# GitHub Actions Runner Controller (ARC)

Self-hosted ephemeral runners on k3s.

## Components
- Controller: `arc-systems` namespace
- Runner scale set: `arc-runners` namespace
- GitHub App: `robert-consulting-arc` (App ID: 4009059)
- Installation ID: 139132888
- Credentials: SSM `/robert-consulting/arc/*`

## Install

### Controller
```bash
helm install arc \
  --namespace arc-systems \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

### Secret
```bash
kubectl create secret generic arc-github-app-secret \
  --namespace arc-runners \
  --from-literal=github_app_id="4009059" \
  --from-literal=github_app_installation_id="139132888" \
  --from-file=github_app_private_key=<path-to-pem>
```

### Runner scale set
```bash
helm install arc-runner-set \
  --namespace arc-runners \
  --create-namespace \
  --set githubConfigUrl="https://github.com/Necron-99/robert-consulting-platform-ops" \
  --set githubConfigSecret="arc-github-app-secret" \
  --set minRunners=0 \
  --set maxRunners=5 \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

## Usage
In any workflow in the robert-consulting-platform-ops repo:
```yaml
jobs:
  deploy:
    runs-on: arc-runner-set
```

## Scale set scope
Currently scoped to robert-consulting-platform-ops repo only.
Add additional scale sets for other repos as needed.
