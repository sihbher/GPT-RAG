# GPT-RAG vs. Custom Solution — Structured Analysis for Monday Session

> **Customer:** BeneLynk (Link-In Benefits)  
> **Prepared by:** Gerardo Reyes (MSFT CSA)  
> **Date:** June 4, 2026  
> **Purpose:** Framework for the Monday June 9 comparison session with Robert

---

```toc

```

## 1. What Robert's Solution Likely LACKS vs. GPT-RAG Enterprise

### 🔒 Network Security & Zero-Trust

| Capability | GPT-RAG (verified in Bicep v2.5.1) | Robert's Solution (likely) | How it protects PHI |
|---|---|---|---|
| **Private Endpoints on ALL services** | ✅ AI Search, Cosmos DB, Storage, Key Vault, AI Foundry — all with `publicNetworkAccess: Disabled` | ❌ Likely uses public endpoints (serverless pattern) | Data never traverses public internet — even within Azure, traffic stays inside the VNet via Private Link |
| **VNet + Private DNS Zones** | ✅ `192.168.0.0/21` VNet with dedicated subnets + private DNS for name resolution | ❌ No VNet = no network boundary | Creates a network perimeter that auditors can point to as the "data boundary" for PHI |
| **NSG per subnet** | ✅ 10 subnets, each with Network Security Group rules (`deployNsgs=true`) | ❌ No network segmentation | Limits blast radius: if one component is compromised, NSGs prevent lateral movement to other services |
| **Managed Identities (zero secrets)** | ✅ Each Container App has its own System/User-Assigned Identity with RBAC roles | ❌ Likely connection strings or API keys in code/env vars | No credentials to steal, rotate, or leak — authentication is automatic and auditable |
| **RBAC least-privilege per component** | ✅ Orchestrator gets `SearchIndexDataReader`; Ingestion gets `SearchIndexDataContributor` — each app only what it needs | ❌ Likely single shared key with full access | If one Container App is compromised, it can only access its authorized scope — not the entire system |
| **Data-in-transit isolation** | ✅ Traffic between services flows through Private Endpoints within the VNet | ⚠️ TLS encryption yes, but data traverses public endpoints | Satisfies HIPAA §164.312(e) Transmission Security — data is encrypted AND isolated at network level |
| **NSG flow logs** | ✅ Available for all subnets when enabled | ❌ No network-layer logging | Provides forensic evidence of who accessed what, when — critical for breach investigation |

**Why this matters for BeneLynk:** If the chatbot processes PHI (Protected Health Information) — member eligibility, benefits data, Social Security numbers — having data traverse public endpoints, even with TLS, may not satisfy HIPAA network safeguards requirements or their own compliance team's interpretation. The GPT-RAG architecture ensures that PHI **never leaves the private network boundary**, and every access is auditable via Managed Identity + RBAC + NSG logs.

> **⚠️ Important clarification:** The current v2.5.1 accelerator does NOT deploy Azure Firewall (marked "Coming Soon" in Bicep), Application Gateway/WAF, or a DDoS Protection Plan. These are subnet reservations for future use. The security posture relies on **Private Endpoints + NSGs + Managed Identity + RBAC** — which is already a strong Zero-Trust baseline that satisfies HIPAA requirements.

---

### 🔍 Search Quality & Retrieval

| Capability | GPT-RAG (AI Search) | Robert's Solution (SQL Vector) |
|---|---|---|
| Hybrid search (BM25 + vector) | ✅ Combines keyword + semantic | ❌ Vector-only (misses exact keyword matches) |
| Semantic Ranker (cross-encoder reranking) | ✅ L2 reranking for precision | ❌ No reranking layer |
| Agentic Retrieval (multi-query decomposition) | ✅ LLM generates sub-queries for complex questions | ❌ Single query → single retrieval |
| Faceted filtering + metadata | ✅ Native facets, tags, filters | ⚠️ SQL WHERE clauses (manual) |
| Scale to millions of chunks | ✅ AI Search optimized for this | ⚠️ SQL vector search degrades at scale |
| Multi-index federation | ✅ Can query across multiple indexes | ❌ Single table |

**Why this matters for BeneLynk:** With 197 documents today but a growing document corpus (compliance updates, state-specific benefit rules, policy changes), search quality at scale is where SQL vector falls behind. Also: hybrid search catches questions where users use exact terminology (plan names, form numbers) that pure vector misses.

---

### 📄 Document Processing & Ingestion

| Capability | GPT-RAG | Robert's Solution |
|---|---|---|
| Content Understanding (OCR, tables, forms) | ✅ Handles scanned PDFs, complex tables, multi-column layouts | ❌ Custom Python script — likely text extraction only |
| Automatic chunking with overlap | ✅ Configurable chunk size/overlap | ⚠️ Custom implementation (quality depends on Robert's code) |
| Document format support | ✅ PDF, DOCX, XLSX, PPTX, images, HTML | ⚠️ Likely limited to text-extractable formats |
| Incremental ingestion (add/update/delete) | ✅ Container App pipeline with change detection | ❌ Likely full re-ingestion |
| Document-level security (ACL per document) | ✅ Security trimming per user/group | ❌ All users see all documents |

**Why this matters for BeneLynk:** Benefits documents often include scanned forms, multi-column benefit tables, and state-specific eligibility charts. Simple text extraction misses tabular data entirely. Also: as they grow, they'll need ingestion that handles updates without re-processing everything.

---

### 🛡️ Responsible AI & Content Safety

| Capability | GPT-RAG | Robert's Solution |
|---|---|---|
| Azure AI Content Safety filters | ✅ Pre-configured content filtering | ❌ No filtering layer (raw model output) |
| Prompt injection protection | ✅ Input/output filtering | ❌ No jailbreak protection |
| Grounding detection (hallucination check) | ✅ Built-in groundedness evaluation | ❌ No guardrails |
| Citation/attribution | ✅ Source document references in responses | ⚠️ Depends on prompt engineering |
| PII redaction capabilities | ✅ Can integrate PII detection | ❌ Not built-in |

**Why this matters for BeneLynk:** A healthcare/benefits company CANNOT have an AI system that hallucinates eligibility information or leaks PHI from one member's context into another's response. Content safety is not optional — it's regulatory.

---

### 📊 Observability & Operations

| Capability | GPT-RAG | Robert's Solution |
|---|---|---|
| Application Insights (end-to-end tracing) | ✅ Full telemetry pipeline | ❌ Likely minimal logging |
| Log Analytics workspace | ✅ Centralized, queryable logs | ❌ No centralized logging |
| Token usage tracking | ✅ Per-request token consumption | ❌ Only Azure billing (aggregate) |
| Response quality metrics | ✅ Can evaluate groundedness, relevance | ❌ No automated quality monitoring |
| Alerting on failures/degradation | ✅ Azure Monitor alerts | ❌ No alerting |
| Conversation history & audit | ✅ Cosmos DB with full session state | ❌ Likely stateless (no conversation memory) |

**Why this matters for BeneLynk:** When a compliance officer asks "what did the AI tell Member X about their benefits on March 15?" — you need an audit trail. Robert's solution likely can't answer that.

---

### 🏗️ Enterprise ALM & Maintainability

| Capability | GPT-RAG | Robert's Solution |
|---|---|---|
| Infrastructure as Code (Bicep) | ✅ Full IaC, reproducible deployments | ❌ Manual Azure Portal provisioning |
| CI/CD ready | ✅ `azd` pipeline with env promotion | ❌ Manual deployment |
| Environment promotion (dev → QA → prod) | ✅ Same IaC, different parameters | ❌ Recreate manually per environment |
| Multi-repo architecture | ✅ Independent component updates | ❌ Single script monolith |
| Configuration management | ✅ Azure App Configuration (centralized) | ❌ Hardcoded or env vars |
| Bus factor | ⚠️ Documented, team-maintainable | 🔴 **Robert is a single point of failure** |

---

## 2. The "10 VMs" Explanation

### The Truth: The accelerator deploys exactly 1 VM (temporary)

In the **Zero-Trust GPT-RAG deployment** (network-isolated mode), the Bicep deploys:

| Resource | Bicep Condition | Purpose |
|---|---|---|
| **1× Windows VM** (`Standard_D8s_v5`) | `deployVM && networkIsolation` | Jumpbox to run `postProvision` scripts and initial `azd deploy` from INSIDE the VNet (since all services have public access disabled) |
| **1× Azure Bastion** (Standard SKU) | `deployVM && networkIsolation` | Secure browser-based RDP access to the jumpbox without exposing RDP to the internet |
| **1× NAT Gateway + Public IP** | `deployVM && networkIsolation` | Allows the jumpbox to reach the internet (pull Docker images, pip packages) while remaining inside the VNet |

**Critical fact:** Without `networkIsolation=true`, the accelerator deploys **ZERO VMs**. The VM only exists because private endpoints block all external access — someone has to run the deployment scripts from inside.

### These resources are TEMPORARY

The VM and Bastion are **deployment-time infrastructure only**. Once `azd provision` and `azd deploy` complete successfully:

1. The VM has served its purpose (ran postProvision scripts, built/pushed Docker images)
2. It can be **deleted** immediately to eliminate ongoing cost
3. Future deployments can use a CI/CD agent inside the VNet, or a temporary Container Apps Job

**Post-deployment, the VM and Bastion are eliminated.** They are not part of the production runtime architecture.

### What happened in BeneLynk's case

- The **previous failed deployment** (`rg-oma-gpt-prod-01`) deployed with `deployVM=true` + `networkIsolation=true`
- The **QA deployment** (`callQA-prod-01`) has `deployVM=false` — Pranal created ONE VM manually just to run the provisioning from inside the VNet
- The "10 VMs" claim requires further investigation — the current Bicep (`v2.5.1`) only deploys 1 VM. The 10 VMs may have come from: (a) an older version of the accelerator, (b) a VMSS build agent pool from a different Azure component, or (c) the supplier team's manual additions. **We need to validate this with the supplier team before Monday.**

### How to frame it

> "The accelerator deploys ONE temporary VM as a deployment tool — it's how the scripts run inside a fully private network where nothing has public access. Think of it as the 'construction crane' you remove after the building is done. In QA, we've already set `deployVM=false` because we handled deployment manually. In production, the VM is deleted after initial setup. It's not a runtime component — it's a one-time deployment utility."

---

## 3. Network Ingress — How Users Access the Chat UI

### Current Architecture (v2.5.1)

In the current accelerator deployment, Container Apps are configured as `external: true` — meaning they get their own HTTPS endpoints managed by the Container Apps Environment:

```
User → HTTPS → Container Apps Environment (managed TLS) → Chat UI Container App
```

| Component | What it provides |
|---|---|
| **Container Apps managed ingress** | Automatic TLS certificates, HTTPS endpoint, load balancing across replicas |
| **Container Apps FQDN** | Azure-provided domain (e.g., `frontend.<unique>.azurecontainerapps.io`) |
| **VNet integration** | Container Apps Environment runs inside the VNet (`aca-environment-subnet`) |

### With Network Isolation enabled

When `networkIsolation=true`, the Container Apps Environment becomes **internal-only** (no public IP). Access options for the chat UI in this mode:

1. **Azure Bastion → Jumpbox → browser** (current pattern for admin/QA)
2. **Future: App Gateway** (subnet is reserved at `192.168.3.0/27` but resource is NOT deployed yet — marked "Coming Soon" in Bicep)
3. **VPN/ExpressRoute** to the VNet for corporate user access

### What does NOT exist yet (subnet reserved, resource not deployed)

| Component | Status in v2.5.1 | Subnet reserved? |
|---|---|---|
| Application Gateway / WAF | ❌ **Not deployed** ("Coming Soon") | ✅ `AppGatewaySubnet 192.168.3.0/27` |
| Azure Firewall | ❌ **Not deployed** ("Coming Soon") | ✅ `AzureFirewallSubnet 192.168.2.128/26` |
| DDoS Protection Plan | ❌ **Not deployed** | N/A |

### How to frame it

> "Today, the Container Apps expose the chat UI via managed HTTPS ingress with automatic TLS. In the Zero-Trust mode, access goes through Azure Bastion during deployment. For production user access, BeneLynk has options: VPN/ExpressRoute connectivity to the VNet, or we can add an App Gateway with WAF as the public entry point — the subnet is already reserved for it. This is an architecture decision to make together based on how your users will access the chatbot."

### Why Jaime's question was reasonable

Jaime questioned why there was an App Gateway. If the supplier team told them it was deployed, that was either (a) an older version, or (b) incorrect information. **In v2.5.1, it is not deployed.** We should clarify this proactively on Monday rather than let it become a credibility issue.

---

## 4. Framing Strategy — "Both Solutions Have Their Place"

### ❌ DON'T say:
- "Robert's solution isn't enterprise-ready"
- "That won't work in production"
- "You need all these resources"
- "Your solution is a PoC / toy"

### ✅ DO say:

#### Opening frame:
> "Robert's solution demonstrates strong engineering fundamentals — he identified the core RAG pattern and implemented it efficiently. That's exactly the right instinct for validating an idea quickly. What we want to do today is help you understand what additional capabilities the accelerator provides so you can make an informed decision about which approach fits your production needs."

#### The spectrum frame:
> "Think of it as a spectrum. On one end, you have a purpose-built RAG solution optimized for speed and simplicity. On the other end, you have an enterprise platform designed for healthcare compliance, security audits, and operational maturity. The question isn't 'which one works' — they both answer questions. The question is 'what does your compliance team, your security team, and your future scale require?'"

#### The gap discovery approach:
> "Let's walk through a few scenarios together and you tell us which ones matter for BeneLynk:
> 1. If a compliance auditor asks for a record of what the AI told a specific member — can you produce it?
> 2. If you need to restrict which documents different user groups can access — can you enforce that?
> 3. If a stolen connection string gives an attacker access to your vector database — what network controls prevent that?
> 4. If Robert leaves the company — who maintains and updates the ingestion pipeline?
> 5. If document volume grows 10x — does search quality degrade?"

#### The "right-sizing" pivot:
> "One valid outcome of today is that we right-size the accelerator for your needs. Not every feature needs to be on for QA. We've already turned off VMs (`deployVM=false`). The accelerator is modular — you pick what you need. For QA, the core value is: Private Endpoints + Managed Identity + AI Search + Content Safety. That's the security baseline."

---

## 5. Healthcare Compliance & Security Arguments

### HIPAA Technical Safeguards (45 CFR § 164.312)

| HIPAA Requirement | GPT-RAG | Robert's Solution |
|---|---|---|
| **Access Control** (§164.312(a)) — Unique user identification, emergency access, auto logoff, encryption | ✅ Entra ID integration, document-level ACLs, session timeout via Cosmos | ⚠️ Likely shared access, no per-user audit |
| **Audit Controls** (§164.312(b)) — Record and examine activity | ✅ App Insights + Log Analytics with full request/response tracing | ❌ No audit trail of AI interactions |
| **Integrity** (§164.312(c)) — Protect ePHI from improper alteration | ✅ Immutable logs, content safety filters prevent manipulation | ❌ No integrity controls on AI output |
| **Transmission Security** (§164.312(e)) — Guard against unauthorized access during transmission | ✅ Private Endpoints = data never on public internet | ⚠️ TLS yes, but data traverses public endpoints |

### Additional Compliance Considerations

- **BAA Coverage**: Azure AI services under Microsoft's BAA — but only when deployed in compliant configurations (private endpoints, proper access controls). A serverless deployment with public endpoints may not be covered under the same BAA interpretation.

- **PHI in Vector Embeddings**: Document chunks stored as vectors in SQL still contain PHI. Without network isolation, those embeddings are accessible via public endpoint. An attacker with a stolen connection string has access to all vectorized member data.

- **Right to Audit**: Healthcare contracts typically require the ability to demonstrate security controls to auditors. "It's serverless" is not an acceptable answer to "show me your network security controls."

- **Incident Response**: If a breach occurs, the GPT-RAG architecture provides: NSG flow logs (who accessed what at network level), App Insights traces (what data was returned to which user), Cosmos DB records (full conversation history with timestamps). Robert's solution provides: Azure billing data.

### Risk Statement for Leadership

> "Robert's solution works functionally. The risk is not 'will it answer questions correctly' — it will. The risk is: can BeneLynk demonstrate to auditors, compliance officers, and potential breach investigators that PHI was properly safeguarded during AI interactions? The accelerator provides that evidence trail. A custom serverless solution requires building that compliance layer from scratch — which is possible, but represents significant additional engineering that erases the cost savings."

---

## Summary: Decision Framework for BeneLynk

| If BeneLynk needs... | Recommendation |
|---|---|
| Quick internal tool, non-PHI data, single team | Robert's solution is sufficient |
| Member-facing chatbot, PHI data, audit requirements | GPT-RAG accelerator (right-sized) |
| Hybrid: start simple, grow into compliance | Start with Robert's for internal testing, deploy accelerator for production with PHI |
| Cost-optimized QA | GPT-RAG with minimal flags (`deployVM=false`, network isolation on, no optional add-ons) |

---

## Appendix: Quick Reference — GPT-RAG Bicep Flags for Cost Reduction

### Verified flags (confirmed in `main.parameters.json` and `main.bicep` v2.5.1)

```bash
# Set via: azd env set VARIABLE_NAME value

NETWORK_ISOLATION=true                # Keep private endpoints (security baseline)
DEPLOY_VM=false                       # Skip jumpbox VM + Bastion (use manual VM or run from VNet)
DEPLOY_SUBNETS=true                   # Required for networking
ENABLE_AGENTIC_RETRIEVAL=false        # Disable if not needed (reduces AI Search complexity)
USE_UAI=false                         # Use System-Assigned Identity (simpler)
USE_CAPP_API_KEY=false                # Skip API key auth between Container Apps
```

### Feature flags that control deployment (set in `main.parameters.json`)

| Flag | Default | Set to `false` to skip |
|---|---|---|
| `deployVM` | true | Skip jumpbox VM + Bastion + NAT Gateway |
| `deployGroundingWithBing` | false | Already off — Bing Search |
| `deployPostgres` | false | Already off — PostgreSQL |
| `deployMcp` | true | Skip MCP server if not using agentic tools |
| `deployContainerRegistry` | true | Skip ACR (use pre-built images) |

### What does NOT have a feature flag (always reserved, never deployed)

| Component | Status |
|---|---|
| Application Gateway | Subnet reserved, resource marked "Coming Soon" |
| Azure Firewall | Subnet reserved, resource marked "Coming Soon" |
| DDoS Protection Plan | Not referenced in Bicep |

### Minimal QA cost footprint

With `deployVM=false` and `networkIsolation=true`, the QA deployment consists of:

- Container Apps Environment (D4 profile, 4 apps × 1 replica)
- Azure AI Search (Standard S1)
- Azure AI Foundry (gpt-5-mini + text-embedding-3-large)
- Azure Cosmos DB (Serverless)
- Azure Storage Account
- Azure Key Vault
- Azure App Configuration
- Application Insights + Log Analytics
- VNet + Private Endpoints + Private DNS

This is the security-compliant minimum for a healthcare RAG workload.
