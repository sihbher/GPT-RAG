# Project Context — GPT-RAG Custom Fork

> **Purpose**: Rapid ramp-up document for any LLM or developer continuing work on this repository.  
> **Last updated**: 2026-05-14

---

## What This Repository Is

This is a **customized fork** of [Azure/gpt-rag](https://github.com/Azure/gpt-rag) — Microsoft's enterprise RAG solution accelerator. The fork (`sihbher/gptrag-bot1`) adapts the upstream project for deployment into **enterprise network environments** (Hub & Spoke, flat VNet with centralized DNS, multi-instance on shared VNets).

The upstream repo uses `Azure/bicep-ptn-aiml-landing-zone` as an infrastructure submodule. We maintain a **forked submodule** (`sihbher/bicep-ptn-aiml-landing-zone`) with additional fixes for enterprise networking scenarios.

---

## Current State

| Item | Value |
|---|---|
| Release tag | `v2.6.6` |
| Orchestrator | `gpt-rag-orchestrator` v2.6.2 |
| Ingestion | `gpt-rag-ingestion` v2.3.3 |
| UI | `gpt-rag-ui` v2.3.1 |
| Infra submodule | `bicep-ptn-aiml-landing-zone` tracking `main` (was pinned to v1.0.5 → v1.1.4 → v1.1.9 → main) |
| Chat model | `gpt-5-nano` (2025-08-07), GlobalStandard, capacity 100 |
| Embedding model | `text-embedding-3-large` v1, Standard, capacity 40 |
| Target region | Sweden Central |
| Environment name | `gpt-rag-aprl-05` |

---

## Objective

Deploy GPT-RAG in an enterprise environment with:

1. **Pre-existing VNet** (not created by the template)
2. **Pre-existing Private DNS Zones** in a separate Resource Group (not co-located with VNet or deployment RG)
3. **No Hub & Spoke Azure Policy** managing DNS — zones are managed manually or by a different team
4. **Multiple deployment instances** on the same VNet with non-colliding subnet names/CIDRs
5. **No jumpbox VM / Bastion** (access via existing enterprise tooling)
6. **System Assigned Managed Identity** (not User Assigned)
7. **Zero Trust network isolation** with private endpoints

---

## Key Customizations Applied

### 1. Infrastructure Submodule (bicep-ptn-aiml-landing-zone)

The infra submodule was forked and patched with these fixes (documented in `infra-fixes.md`):

| Fix | Problem | Solution |
|---|---|---|
| Hardcoded `pe-subnet` | AI Foundry PEs always looked for `pe-subnet` regardless of `peSubnetName` parameter | Use `${peSubnetName}` in `varPeSubnetId` |
| `varAfNetworkingOverride` logic | DNS zone IDs were omitted when using existing zones without Policy | Added `!_useExistingDnsZones` condition |
| Unconditional subnet creation | All 9 subnets created even when only 3 needed | Refactored to `concat()` with conditional arrays |
| External DNS zone RG support | No way to reference DNS zones in a different RG/subscription | Added `existingDnsZonesResourceGroupName` and `existingDnsZonesSubscriptionId` parameters |

### 2. Main Parameters (main.parameters.json)

New parameters added:
- `policyManagedPrivateDns` — Hub & Spoke: skip DNS zone creation, let Azure Policy register PEs
- `existingDnsZonesResourceGroupName` — Flat VNet: point to pre-existing DNS zones in another RG
- `existingDnsZonesSubscriptionId` — Cross-subscription DNS zone reference
- `deployVpnGateway` — Conditional VPN Gateway subnet creation
- `enablePrivateLogAnalytics` — Disable AMPLS when monitor DNS zones don't exist
- `deployVM` converted from hardcoded `true` to `${DEPLOY_VM}` env var
- Subnet names/prefixes exposed as env vars (`AGENT_SUBNET_NAME`, `PE_SUBNET_NAME`, etc.)

### 3. Frontend UI Fix (gpt-rag-ui)

`AZURE_CLIENT_ID` defaulted to `"*"` which broke `ManagedIdentityCredential` when using System Assigned Identity. Fixed to default to `None`.

### 4. .gitmodules

Points to `sihbher/bicep-ptn-aiml-landing-zone.git` on `main` branch (instead of upstream `Azure/bicep-ptn-aiml-landing-zone` on a pinned tag).

---

## Deployment Scenarios Supported

### Scenario A: Hub & Spoke (Azure Policy manages DNS)

```bash
azd env set POLICY_MANAGED_PRIVATE_DNS   true
azd env set DEPLOY_VM                    false
azd env set USE_EXISTING_VNET            true
azd env set EXISTING_VNET_RESOURCE_ID    "<spoke-vnet-id>"
azd env set DEPLOY_SUBNETS               false
```

- DNS zones NOT created (exist in Hub)
- DNS Zone Groups NOT attached to PEs (Azure Policy registers them)

### Scenario B: Flat VNet with pre-existing DNS Zones in external RG

```bash
azd env set EXISTING_DNS_ZONES_RESOURCE_GROUP_NAME  "rg-dns-zones"
azd env set EXISTING_DNS_ZONES_SUBSCRIPTION_ID      "<sub-id>"  # optional, defaults to current
azd env set DEPLOY_VM                               false
azd env set USE_EXISTING_VNET                       true
azd env set EXISTING_VNET_RESOURCE_ID               "<vnet-id>"
azd env set DEPLOY_SUBNETS                          true
azd env set ENABLE_PRIVATE_LOG_ANALYTICS            false  # if monitor DNS zones missing
azd env set AGENT_SUBNET_NAME                       "agent-subnet-inst1"
azd env set AGENT_SUBNET_PREFIX                     "10.0.1.0/24"
azd env set PE_SUBNET_NAME                          "pe-subnet-inst1"
azd env set PE_SUBNET_PREFIX                        "10.0.2.0/26"
azd env set ACA_ENVIRONMENT_SUBNET_NAME             "aca-env-subnet-inst1"
azd env set ACA_ENVIRONMENT_SUBNET_PREFIX           "10.0.3.0/24"
```

- DNS zones NOT created (exist in external RG)
- DNS Zone Groups ARE attached, pointing to zones in the specified RG
- Only required subnets created (3 core + conditional)

---

## Important Architecture Decisions

1. **Submodule is forked** — upstream PRs cannot be merged directly. Must cherry-pick or rebase.
2. **`main` branch tracking** — the submodule tracks `main` of the fork, not a pinned tag. This means `git submodule update --remote` pulls latest changes.
3. **Environment variables drive all parameterization** — `azd env set` populates `${VAR}` placeholders in `main.parameters.json`.
4. **No MCP Container App** — removed in v2.6.0, MCP consolidated into orchestrator.
5. **Container Apps on D4 workload profile** — orchestrator, frontend, and dataingest all use a `main` profile (D4, 0-1 instances).

---

## File Reference

| File | Purpose |
|---|---|
| `fixes.md` | Detailed documentation of all post-provisioning fixes applied to this fork |
| `infra-fixes.md` | Detailed documentation of all Bicep submodule fixes |
| `CHANGELOG.md` | Release history following Keep a Changelog format |
| `manifest.json` | Component versions and repository references for deployment |
| `main.parameters.json` | All Bicep deployment parameters (env-var driven) |
| `.gitmodules` | Points infra submodule to forked repo on `main` |
| `AGENTS.md` | Full technical stack and repo structure reference |
| `.github/copilot-instructions.md` | Branching strategy and release workflow rules |

---

## Branching & Release Workflow

- `develop` — active development branch
- `main` — stable releases only
- Feature branches: `feature/<name>` → PR to `develop`
- Release branches: `release/x.y.z` → PR to `main`
- Tags use `v` prefix: `v2.6.6`
- Branch names do NOT use `v` prefix: `release/2.6.6`
- `CHANGELOG.md` on `main` must NEVER have `[Unreleased]` section

---

## Known Gotchas

1. **Zero Trust deploy scripts fail** — `az appconfig kv show --name` goes through ARM control plane which is blocked. Manual Container App updates via `az containerapp update` required.
2. **AMPLS requires 3 DNS zones** — `oms.opinsights.azure.com`, `ods.opinsights.azure.com`, `agentsvc.azure-automation.net`. If missing, set `ENABLE_PRIVATE_LOG_ANALYTICS=false`.
3. **System Assigned Identity** — When `USE_UAI=false`, ensure no code passes a wildcard or placeholder as `client_id` to `ManagedIdentityCredential`.
4. **Submodule dirty state** — `.gitmodules` has `ignore = dirty` to avoid noise from local submodule changes.
5. **Sweden Central** — Some services have limited availability. The `aiFoundryLocation` parameter allows placing AI Foundry in a different region if needed.
6. **Embedding capacity** — Was increased from 40 to 100 in v2.6.3 for `text-embedding-3-large` to handle ingestion throughput.

---

## How to Continue Work

1. **Read `fixes.md`** for full context on every change made and why.
2. **Read `infra-fixes.md`** for Bicep-level details in the submodule.
3. **Check `CHANGELOG.md`** for release history and component version evolution.
4. **Check `manifest.json`** for current deployed component versions.
5. **Always branch from `develop`** for new work.
6. **Test Bicep changes** with `az bicep build --file infra/main.bicep` before committing.
7. **Manual re-deploy in Zero Trust** — use `az containerapp update` with built images.
