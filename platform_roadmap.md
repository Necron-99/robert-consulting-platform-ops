# Robert Consulting Platform — Infrastructure Roadmap

**Last updated:** June 2026  
**Owner:** Robert Bailey / Robert Consulting LLC  
**Platform:** k3s on Hetzner CX41 + AWS (Route 53, S3 only)

---

## Current State

| Service | Status | Hosting |
|---------|--------|---------|
| threat.robertconsulting.net | Live | S3/CloudFront → migrating |
| compliance.robertconsulting.net | Live | S3/CloudFront → migrating |
| robertconsulting.net | Live | S3/CloudFront → migrating |
| api.threat.robertconsulting.net | Live | k3s (Helm) |
| api.compliance.robertconsulting.net | Live | k3s (Helm) |
| grafana.robertconsulting.net | Live | k3s (Helm) |
| DNS | Live | Route 53 (stays) |
| Terraform state | Live | S3 (stays) |
| DBs | Live | S3 → pod init containers |

**Monthly cost:** ~$90/month  
**Target monthly cost:** ~$13/month

---

## Roadmap

---

### TIER 1 — Complete Platform Migration (In Progress)

**Goal:** Everything on k3s. AWS reduced to Route 53 + S3 only.

---

#### Phase 1 — Helm Charts ✅ COMPLETE
Both APIs converted from raw kubectl manifests to Helm charts. All k3s workloads now Helm-managed.

---

#### Phase 2 — Static Site Migration to k3s nginx
**Status:** Next up  
**Effort:** 1-2 weekends  
**Savings:** ~$65/month (eliminates CloudFront + WAF costs)

Move all three static frontends (robertconsulting.net, threat, compliance) from S3/CloudFront to nginx pods on k3s.

Architecture:
```
Git push → GitHub Actions → builds assets →
  S3 sync (content only, no CloudFront) +
  kubectl rollout restart (nginx pod re-syncs on start)

DNS → Route 53 A record → Hetzner floating IP →
  ingress-nginx → nginx pod (serving /usr/share/nginx/html)
```

Key tasks:
- Create `static-site` Helm chart (reusable for all three sites)
- nginx Deployment + Service + Ingress per site
- Init container syncs from S3 on pod start (same pattern as DBs)
- Update Route 53 A records to Hetzner floating IP
- Remove CloudFront distributions from Terraform
- Remove S3 static website hosting configs (keep buckets for content)
- Move CSP headers from CloudFront policy to nginx `add_header` directives
- Update deploy scripts — single `deploy.sh --service threat` pattern

---

#### Phase 3 — AWS Cleanup
**Status:** Pending Phase 2  
**Effort:** 1 evening  
**Savings:** Included in Phase 2 savings

- Remove guestbook Lambda, API Gateway, DynamoDB, WAF
- Remove contact-form and admin-api WAFs (zero blocks, orphaned)
- Remove CloudFront distributions
- Remove S3 static website hosting
- Remove ACM cert (cert-manager handles TLS on k3s)
- Keep: Route 53, S3 buckets (DBs + state), Secrets Manager, domain registrar

---

#### Phase 4 — Terraform Module Cleanup
**Status:** Pending Phase 3  
**Effort:** 1 evening

Refactor site-specific Terraform modules into generic reusable modules:
- `modules/k3s-node` — Hetzner server + floating IP + firewall
- `modules/dns-record` — Route 53 A record → floating IP
- `modules/s3-storage` — S3 bucket + scoped IAM user
- `modules/ssm-parameter` — SSM parameter store entry

New service deployment = 10 lines of Terraform + one Helm `values.yaml`.

---

#### Phase 5 — Unified Deploy Script
**Status:** Pending Phase 4  
**Effort:** 1 evening

Single `deploy.sh` interface for all services:
```bash
deploy.sh --service threat      # sync content + restart pod
deploy.sh --service compliance
deploy.sh --service all
deploy.sh --infra               # terraform plan/apply
deploy.sh --status              # all pod/service health
```

---

### TIER 2 — CI/CD Platform (Next Infrastructure Project)

**Goal:** Self-hosted, autoscaling GitHub Actions runners on k3s.  
**Priority:** First project after static site migration  
**Effort:** 1-2 weekends

**What:** GitHub Actions Runner Controller (ARC) — Kubernetes-native ephemeral runners that spin up on demand and terminate after each job. Replaces always-on runner model.

**Why:**
- No idle runner costs
- Each job gets a clean environment
- Can use different container images per workflow
- Scales to zero when nothing is running
- Direct cluster access for deployments without storing kubectl credentials in GitHub secrets
- Demonstrates platform engineering capability relevant to job search

**Architecture:**
```
GitHub Actions webhook →
  ARC controller (k3s) →
    ephemeral runner pod (spins up) →
      runs pipeline →
        pod terminates
```

**Key components:**
- `actions/actions-runner-controller` Helm chart
- GitHub App authentication (preferred over PAT)
- Runner scale sets per repo or org
- Custom runner container images with required tooling (terraform, kubectl, helm, aws-cli)
- Scale-to-zero configuration

**Replaces:**
- GitHub-hosted runners (free tier limitations)
- Manual `kubectl rollout restart` deployments
- Manual `aws s3 sync` deploys

---

### TIER 3 — Self-Hosted AI (Replace Anthropic Dependency)

**Goal:** All AI enrichment runs locally. Zero cloud AI API dependency.  
**Effort:** 1 weekend  
**Cost:** ~0 (uses existing cluster capacity)

**What:** Ollama on k3s running Llama 3.1 8B or Mistral 7B for:
- Future ATT&CK enrichment (new technique versions, sub-technique context)
- Compliance control plain English generation
- RAG/chat interface over threat + compliance data
- RockfishNDR alert enrichment (future)

**Why now:**
- Anthropic API tokens depleting — no plan to replenish
- OT/ICS customers (RockfishNDR target market) won't accept cloud telemetry
- Air-gap narrative strengthens the platform story
- Self-hosted LLM running in production is a strong demo talking point

**Architecture:**
```
Ollama pod (k3s) → persistent volume (model storage)
Enrichment scripts → Ollama API (localhost:11434)
RAG service → Ollama API + SQLite vector store
```

**Model selection:**
- Llama 3.1 8B — best quality/resource tradeoff for enrichment tasks
- Mistral 7B — faster, lower memory, good for simple summarization
- CX41 has 4 vCPU / 7.7GB RAM — 8B models run at ~5-6GB, tight but feasible

---

### TIER 4 — RockfishNDR Integration

**Goal:** Run RockfishNDR on the cluster, integrate with threat platform.  
**Dependencies:** License key from Randy Caldejon (Fidelis Machines)  
**Effort:** 1-2 weekends after key arrives

**What:** Deploy RockfishNDR on k3s ingesting homelab/local network traffic via Suricata eve.log. Integrate findings with the threat intelligence platform.

**Integration opportunities:**
- RockfishNDR detections → threat platform technique mapping
- CVE findings → compliance gap analysis
- OT protocol detection → ICS sector threat profile
- Alert enrichment via local Ollama (Tier 3 dependency)

**Demo value:**
- Live NDR data flowing into threat/compliance platform
- End-to-end story: detect → map to ATT&CK → check compliance coverage → identify gap
- Directly relevant to Randy's commercial use case (factory floors, OT environments)

**Liebherr connection:**
- Warm introduction to IT contacts at Liebherr facility
- RockfishNDR's OT protocol support (Modbus, DNP3, OPC-UA) maps to dump truck autonomous vehicle environment
- NIS2 regulatory pressure on European manufacturers creates urgency

---

### TIER 5 — SIEM (Wazuh)

**Goal:** Production SIEM running on k3s. First SIEM hands-on experience.  
**Effort:** 2-3 weekends  
**Learning objective:** SIEM administration, log aggregation, detection rules, compliance reporting

**What:** Wazuh — open source SIEM covering:
- Log aggregation and correlation
- Intrusion detection (HIDS)
- File integrity monitoring
- Vulnerability detection
- Compliance reporting (PCI-DSS, HIPAA, NIST)
- Active response

**Why Wazuh:**
- Open source, well-documented
- Kubernetes-native deployment
- Built-in compliance framework mappings (relevant to compliance mapper)
- Active community
- Natural integration with threat platform — Wazuh alerts → ATT&CK technique mapping

**Architecture:**
```
Wazuh manager (k3s) ←
  Wazuh agent (k3s nodes) +
  Wazuh agent (homelab machines: gandalf, tuxedosys, faramir) +
  Filebeat → Wazuh → OpenSearch → Grafana
```

**Integration with existing platform:**
- Wazuh alerts enriched with ATT&CK technique mappings from threat API
- Compliance gap analysis surfaced when Wazuh detects techniques with no control coverage

---

### TIER 6 — Platform RAG Chat Interface

**Goal:** Natural language query interface over threat + compliance data.  
**Dependencies:** Tier 3 (Ollama) recommended  
**Effort:** 2-3 weekends

**What:** A chat interface where users ask questions like:
- "Which threat groups are targeting healthcare organizations right now?"
- "What NIST controls address the techniques used by APT29?"
- "Show me the compliance gap for GDPR vs NIST 800-53"
- "What CVEs should a government contractor patch first?"

**Architecture:**
```
Chat UI (React) →
  RAG service (FastAPI) →
    Query planner →
      SQLite FTS5 (threat + compliance DBs) +
      Ollama embeddings + vector store →
    Response synthesizer →
      Ollama LLM (local) →
    Formatted response
```

**Value:**
- Transforms the platform from a dashboard into an analyst tool
- Directly addresses the "threat-informed defense" narrative
- Compelling demo for Brennan, Randy, and future commercial conversations
- No ongoing API costs (Tier 3 dependency)

---

## Cost Trajectory

| Phase | Monthly AWS | Monthly Hetzner | Total |
|-------|-------------|-----------------|-------|
| Current | ~$83 | ~$7 | ~$90 |
| After WAF cleanup (done) | ~$68 | ~$7 | ~$75 |
| After guestbook removal | ~$53 | ~$7 | ~$60 |
| After static site migration | ~$6 | ~$7 | ~$13 |
| Target (steady state) | ~$6 | ~$7 | ~$13 |

**Annual savings vs current:** ~$924/year

---

## Tech Debt Log

| Item | Priority | Notes |
|------|----------|-------|
| UFW rules on k3s node not in Terraform | Medium | `ufw allow from 10.42.0.0/16 to any port 9100` — add to cloud-init template |
| Hetzner firewall rules for 9100 added via CLI | Medium | Not in Terraform, will be lost on node rebuild |
| Old k8s/ raw manifests in API repos | Low | Superseded by Helm charts, keep for reference only — never `kubectl apply` |
| batch_collect.py / batch_submit.py split delimiter | Low | Fixed in production, ensure local scripts match |
| compliance DB indexes | Low | Add at next DB rebuild — attack_technique_mappings queries benefit from indexing |
