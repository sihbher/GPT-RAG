# GPT-RAG HCD Deployment — Continuation Context (jumpbox handoff)

> **Read this first.** This file is the working context for continuing the
> GPT-RAG deployment for the HCD engagement **from inside the deployed jump VM
> (Azure Bastion)**. It is committed to the repo on purpose so that GitHub
> Copilot (and you) have full context after you `git push` here and `git pull`
> on the jump VM. **It contains no passwords or secret values** — credentials
> are retrieved at connect time with the commands below.

---

## TL;DR — where we are

- Infrastructure **provisioning succeeded** end-to-end (`azd provision` → `SUCCESS`).
  All Azure resources are created in the resource group.
- Because the deployment is **Zero Trust / network isolated**, the
  **post-provision data-plane step must run from *inside* the VNet**. Running it
  from a laptop failed by design:
  > `Ensure you run scripts/postProvision.sh from within the VNet … Are you
  > running this script from inside the VNet or via VPN? [Y/n]: n → Exiting.`
- **Remaining work runs on the jump VM:** finish post-provision + deploy the app
  containers. Steps are in [Next steps on the jump VM](#next-steps-on-the-jump-vm).

----

## Engagement constraints (do not break these)

- **US data residency (US-geofencing).** Azure OpenAI model deployments must
  **never** use a `Global*` deployment type (`GlobalStandard`, `GlobalProvisioned`,
  `GlobalBatch`). Only `Standard` (single US geography) or **`DataZoneStandard`**
  (US data zone) are allowed. This deployment uses **`DataZoneStandard`** for both
  the chat and embedding models.
- **Zero Trust posture:** `NETWORK_ISOLATION=true`, single self-contained resource
  group, private endpoints, jump VM, no public ingress.

---

## Environment facts (non-secret)

| Item | Value |
|---|---|
| azd environment name | `gptrag-bot01` |
| Subscription | `*******` (HCD non-prod) |
| Resource group | `*******` |
| Region | `westus` |
| Model chat SKU | `DataZoneStandard` (`CHAT_DEPLOYMENT_SKU`) |
| Model embedding SKU | `DataZoneStandard` (`EMBEDDING_DEPLOYMENT_SKU`) |
| Jump VM | `testvmiunaoskcf` (**Windows**, `Standard_D2s_v3`) |
| Jump VM admin user | `testvmuser` |
| Jump VM admin password | random → in Key Vault `kv-iunaos-gptrag-bot01-w` (retrieve at connect time, see below) |
| Access to VM | **Azure Bastion** (no public IP) |
| AI Landing Zone (infra submodule) | pinned to **`v2.3.0`** |

Isolated Azure CLI/azd config used for this engagement (keeps HCD context
separate from other tenants):

```bash
export AZURE_CONFIG_DIR="$HOME/.azure-hcd"
export AZD_CONFIG_DIR="$HOME/.azd-hcd"
```

(On the Windows jump VM these are not needed unless you replicate the isolation;
use the machine's default `az`/`azd` login to the HCD tenant.)

---

## What is already deployed (provision complete)

Container Registry, Key Vaults (`kv-iunaos-gptrag-bot01-w`, `kv-ai-iunaoskcfg3y2`),
Log Analytics, Application Insights, Storage accounts, Virtual Network + Private
Endpoints, Azure Cosmos DB (workload + Foundry), Container Apps Environment and
the three Container Apps (`orchestrator`, `frontend`, `dataingest`), two Azure AI
Search services, the Microsoft Foundry account + project + connections, and both
model deployments (`chat` = gpt-5-nano, `text-embedding` = text-embedding-3-large),
all on **`DataZoneStandard`**.

**Not done yet:** post-provision configuration (App Configuration data-plane keys,
indexes, RBAC data-plane, etc.) and the application image build/deploy — these are
the Zero-Trust steps that must run from the VNet.

---

## Repo customizations (why this repo differs from upstream GPT-RAG)

These were made to satisfy US residency + to get the network-isolated deploy
through the preflights and Bicep. Keep them; do not revert.

1. **Model SKU parameterized** in [main.parameters.json](../main.parameters.json)
   `modelDeploymentList`:
   - `sku.name = "${CHAT_DEPLOYMENT_SKU=GlobalStandard}"` and
     `"${EMBEDDING_DEPLOYMENT_SKU=Standard}"`.
   - Defaults keep upstream behavior (backward compatible); the azd env overrides
     both to `DataZoneStandard`.

2. **Regional preflight** [scripts/Invoke-RegionalPreflight.ps1](../scripts/Invoke-RegionalPreflight.ps1):
   `Test-ModelReadiness` patched to resolve the nested `${VAR=default}` SKU tokens.

3. **New helper** [scripts/Resolve-ModelDeploymentSkus.ps1](../scripts/Resolve-ModelDeploymentSkus.ps1),
   invoked from [scripts/preProvision.sh](../scripts/preProvision.sh) and
   [scripts/preProvision.ps1](../scripts/preProvision.ps1): after the root
   `main.parameters.json` is copied to `infra/main.parameters.json`, it
   materializes the nested SKU tokens to concrete values (azd env → process env →
   token default). This is why both preflights **and** azd see `DataZoneStandard`
   without relying on nested token substitution.

4. **AI Landing Zone SPL name fix** in `infra/main.bicep` (vendored submodule):
   the three `Microsoft.Search/searchServices/sharedPrivateLinkResources` names
   are wrapped in `cafTrim(..., 60)` because the auto-generated
   `spl-<searchName>-cognitiveservices_account-1` exceeded the 60-char ARM limit
   (64 chars) and failed the deployment.
   - ⚠️ **This edit lives in the vendored `infra/` submodule.** It persists across
     `azd provision` (preProvision runs `git submodule update` **without**
     `--force`), but a forced submodule reset would drop it. If `infra/` ever
     looks broken or reverts, re-apply this `cafTrim` change. The upstream fix is
     tracked to be PR'd to `Azure/bicep-ptn-aiml-landing-zone`.

---

## Next steps on the jump VM

### 1. Connect to the jump VM (from your workstation)

Retrieve the admin password (do **not** paste it into any committed file):

```bash
# isolated context
export AZURE_CONFIG_DIR="$HOME/.azure-hcd"; export AZD_CONFIG_DIR="$HOME/.azd-hcd"

# find the exact secret name, then read the value locally
az keyvault secret list --vault-name kv-iunaos-gptrag-bot01-w --query "[].name" -o tsv
az keyvault secret show  --vault-name kv-iunaos-gptrag-bot01-w --name <secret-name> --query value -o tsv

# (optional) exact Bastion host name
az resource list -g ******* \
  --resource-type Microsoft.Network/bastionHosts --query "[].name" -o tsv
```

Then connect: **Azure Portal → resource group `*******` →
VM `testvmiunaoskcf` → Connect → Bastion → RDP** with user `testvmuser` and the
password above. (Windows VM = RDP over Bastion.)

### 2. Get this repo onto the VM

Push from your workstation, then on the VM:

```powershell
git clone <your-fork-url> gpt-rag
cd gpt-rag
git checkout hcd/test01      # or whatever branch holds these customizations
git submodule update --init --recursive   # brings infra/ (AI Landing Zone v2.3.0)
```

> If the SPL `cafTrim` fix (customization #4) is not present in `infra/main.bicep`
> after the submodule init (because it was an uncommitted vendored edit), re-apply
> it before deploying.

### 3. Re-hydrate the azd environment on the VM

Sign in to the **HCD tenant** with `az login` and `azd auth login`, select the
subscription, then either refresh or recreate the `gptrag-bot01` environment so
it points at the already-provisioned resource group:

```powershell
azd env new gptrag-bot01
azd env set AZURE_SUBSCRIPTION_ID *******
azd env set AZURE_RESOURCE_GROUP  *******
azd env set AZURE_LOCATION        westus
azd env set NETWORK_ISOLATION     true
azd env set CHAT_DEPLOYMENT_SKU       DataZoneStandard
azd env set EMBEDDING_DEPLOYMENT_SKU  DataZoneStandard
azd env set RUN_FROM_JUMPBOX      true
azd env refresh                  # pull outputs from the existing deployment
```

### 4. Complete post-provision + deploy (from inside the VNet)

With `RUN_FROM_JUMPBOX=true`, the post-provision step will proceed instead of
exiting. Run:

```powershell
azd provision   # re-runs; postProvision now executes inside the VNet
azd deploy      # builds/pushes the app images and deploys the container apps
```

If you prefer to run the hook directly, the Windows variant is
`scripts/postProvision.ps1`.

### 5. Validate

- All three container apps (`orchestrator`, `frontend`, `dataingest`) are running
  and healthy.
- App Configuration keys (label `gpt-rag`) are populated.
- The frontend endpoint responds (through the private network / your access path).
- Model deployments are `DataZoneStandard` (residency requirement).

---

## Guardrails

- **Never** switch any model to a `Global*` SKU. Keep `DataZoneStandard`.
- **Do not** set `PREFLIGHT_SKIP=true` / `GPT_RAG_REGIONAL_PREFLIGHT_SKIP=true` to
  bypass failures — fix the cause.
- Keep the four repo customizations above intact.
- Verify the active subscription before any `azd`/`az` action:
  `az account show -o table` → must be `*******`.
- Do not commit secrets. Passwords are retrieved from Key Vault at connect time.

---

## Related (local, not committed to this repo)

Detailed engagement notes and the AI Landing Zone PR plan live in the operator's
local notes folder (outside this repo): a step-by-step log (`00-test.md`) and the
upstream fix handoff (`ailz-improvements.md`). They are intentionally **not**
pushed here.
