
# Applied Fixes — GPT-RAG Post-Provisioning
> **Date**: 2026-04-05  
> **Environment**: `gpt-rag-aprl-05` (Sweden Central)  
> **Release**: v2.6.2 (orchestrator v2.4.2, ingestion v2.2.5, UI v2.2.2, MCP v0.3.5)
---
## Index
| #                                                                               | File                                               | Description                                                                                                                                       |
| ------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| [1](#fix-1--hub--spoke-policymanagedprivatedns)                                 | `main.parameters.json`, `.gitmodules`, `infra/`    | Hub & Spoke support: skip Private DNS Zone creation when zones already exist in the Hub                                                           |
| [2](#fix-2--deployvm-converted-to-environment-variable)                         | `main.parameters.json`                             | Convert `deployVM` from hardcoded `true` to env var `${DEPLOY_VM}`                                                                                |
| [3](#fix-3--frontend-ui-managedidentitycredential-fails-with-system-assigned-identity) | `gpt-rag-ui/connectors/appconfig.py`               | Fix `AZURE_CLIENT_ID` default `"*"` → `None` for System Assigned Identity                                                                        |

---
## Fix 1 — Hub & Spoke: `policyManagedPrivateDns` to avoid duplicating DNS Zones
**Modified files**: `main.parameters.json`, `.gitmodules`, `infra/` (submodule)
**Problem**: When deploying GPT-RAG in a Hub & Spoke environment where Private DNS Zones already exist in the Hub (Connectivity subscription), the Bicep from `bicep-ptn-aiml-landing-zone` v1.0.5 created 15 duplicate DNS zones in the Spoke resource group, causing conflicts with the Hub zones.
### Root cause
- v1.0.5 only conditions DNS Zone creation on `networkIsolation`. There is no parameter to skip them.
- In enterprise Hub & Spoke, private DNS zones live in a Connectivity subscription (Hub). The Spoke must not create its own zones.
- DNS Zone Groups on Private Endpoints must point to the Hub zones (or be left without a DNS Zone Group so that Azure Policy in the Hub registers them automatically).
### Applied changes
**1. `main.parameters.json` — new parameter:**
```json
// Added after existingVnetResourceId:
"policyManagedPrivateDns":               { "value": "${POLICY_MANAGED_PRIVATE_DNS}" },
```
**2. `.gitmodules` — update submodule to v1.1.4:**
```ini
# Before:
branch = v1.0.5
# After:
branch = v1.1.4
```
**3. `infra/` — submodule updated** to commit `de135cf` (tag v1.1.4), which introduces the `policyManagedPrivateDns` parameter.
### Behavior in Bicep v1.1.4 with `policyManagedPrivateDns = true`
| Bicep Variable | Evaluation |
|---|---|
| `_deployPrivateDnsZones` | `false` — does not create any of the 15 DNS Zones |
| `_peDnsZoneGroup*` (×15) | `{}` — Private Endpoints without an attached DNS Zone Group |
Hub zones (registered via Azure Policy or manually) resolve A records when Private Endpoints are created.
### Environment variables for Hub & Spoke
```bash
azd env set AZURE_SUBSCRIPTION_ID        "<spoke-subscription-id>"
azd env set AZURE_RESOURCE_GROUP         "<pre-created-rg-in-spoke>"
azd env set NETWORK_ISOLATION            true
azd env set USE_EXISTING_VNET            true
azd env set EXISTING_VNET_RESOURCE_ID    "<spoke-vnet-resource-id>"
azd env set DEPLOY_SUBNETS               false
azd env set SIDE_BY_SIDE                 false
azd env set POLICY_MANAGED_PRIVATE_DNS   true
azd env set DEPLOY_VM                    false
```

---

## Fix 2 — `deployVM` converted to environment variable

**Modified file**: `main.parameters.json`

**Problem**: The `deployVM` parameter was hardcoded to `"true"`. In Hub & Spoke environments, Bicep tries to create a jumpbox VM + Azure Bastion, which requires an `AzureBastionSubnet` in the Spoke VNet. In enterprise Hub & Spoke, that subnet lives in the Hub, causing the error:

```
Resource .../subnets/AzureBastionSubnet referenced by .../bastionHosts/bas-testvm-xxx was not found.
(Code: InvalidResourceReference)
```

**Root cause**: `deployVM && networkIsolation` triggers Bastion creation. With `USE_EXISTING_VNET=true`, Bicep looks for `AzureBastionSubnet` in the Spoke VNet where it does not exist.

### Applied change

```json
// Before:
"deployVM": { "value": "true" },

// After:
"deployVM": { "value": "${DEPLOY_VM}" },
```

### Environment variable

```bash
azd env set DEPLOY_VM false
```

### Behavior if the variable is not set

If `DEPLOY_VM` is not defined in the environment, `azd` substitutes `${DEPLOY_VM}` with an empty string `""`. The Bicep parameter `deployVM bool` evaluates `""` as `false` — equivalent to not deploying the VM or Bastion. This is safe, but setting it explicitly is recommended.

---

## Fix 3 — Frontend UI: `ManagedIdentityCredential` fails with System Assigned Identity

**Modified file**: `gpt-rag-ui/connectors/appconfig.py`

**Problem**: The `frontend` Container App starts in NOT-READY mode (HTTP 503) with the error:

```
ChainedTokenCredential failed to retrieve a token from the included credentials.
App Service managed identity configuration not found in environment. invalid_scope
```

**Root cause**: In `connectors/appconfig.py`, `AZURE_CLIENT_ID` defaults to `"*"`:

```python
self.client_id = os.environ.get('AZURE_CLIENT_ID', "*")
```

This is then passed to `ManagedIdentityCredential(client_id=self.client_id)`. With `USE_UAI=false` (System Assigned Identity), `AZURE_CLIENT_ID` is not defined as an environment variable in the Container App, so it takes the value `"*"`. The SDK tries to acquire a token for a User Assigned Identity with client_id `"*"`, which does not exist → `invalid_scope`.

### Applied change

```diff
- self.client_id = os.environ.get('AZURE_CLIENT_ID', "*")
+ self.client_id = os.environ.get('AZURE_CLIENT_ID') or None
```

When `client_id=None`, `ManagedIdentityCredential()` automatically uses the Container App's System Assigned Identity.

### Manual re-deploy (when the UI `deploy.ps1` does not work in Zero Trust)

The UI deploy script uses `az appconfig kv show --name` which goes through the ARM control plane and fails in Zero Trust. To re-deploy manually:

```powershell
cd <gpt-rag-ui-repo>

# Commit the fix
git add connectors/appconfig.py
git commit -m "fix: use None default for AZURE_CLIENT_ID to support system-assigned managed identity"

# Build, push, and update
$tag = (git rev-parse --short HEAD)
$acr = "<container-registry-name>"           # e.g. cropufsec2ytxss
$image = "$acr.azurecr.io/azure-gpt-rag/frontend:$tag"
$appName = "ca-<resource-token>-frontend"    # e.g. ca-opufsec2ytxss-frontend
$rg = "<resource-group>"                     # e.g. rg-gptrag-spoke-prod-04

az acr login --name $acr
docker build -t $image .
docker push $image
az containerapp update -n $appName -g $rg --image $image
```

### Verification

```powershell
az containerapp logs show -n $appName -g $rg --type console --tail 15
# Should show: "Configuration loaded from Azure App Configuration"
# Should NOT show: "invalid_scope" or "NOT-READY MODE"
```
