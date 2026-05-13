
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
| [4](#fix-4--flat-vnet-pre-existing-private-dns-zones-in-external-resource-group) | `main.parameters.json`, `.gitmodules`, `infra/main.bicep` | Support pre-existing Private DNS Zones in a different Resource Group (flat VNet, no Hub & Spoke) |
| [5](#fix-5--expose-enableprivateloganalytics-and-infra-submodule-fixes) | `main.parameters.json`, `infra/main.bicep` | Expose `enablePrivateLogAnalytics` + fix hardcoded `pe-subnet` + fix AI Foundry DNS override |

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

---

## Fix 4 — Flat VNet: Pre-existing Private DNS Zones in external Resource Group + Conditional Subnet Deployment

**Modified files**: `main.parameters.json`, `.gitmodules`, `infra/main.bicep`

### Problem A — Private DNS Zones in a different Resource Group

**Problem**: Customer has a flat (non-Hub-Spoke) VNet architecture with 14 of 15 required Private DNS Zones already created and linked to their VNet. These zones live in a **different Resource Group** from the deployment target. The Bicep code:
1. Tries to **create DNS zones that already exist**, causing conflicts.
2. Assumes DNS zones live in the **same Resource Group as the VNet** (`varExistingVnetResourceGroupName`), which is incorrect when zones are centralized elsewhere.

**Root cause**: The `_dnsZonesResourceGroupName` variable was derived exclusively from the VNet resource ID segments. There was no mechanism to point DNS zone references to an arbitrary resource group.

### Applied changes (DNS Zones)

**1. `infra/main.bicep` — new parameters:**

```bicep
@description('Resource group name where existing Private DNS Zones are located...')
param existingDnsZonesResourceGroupName string = ''

@description('Subscription ID where existing Private DNS Zones are located...')
param existingDnsZonesSubscriptionId string = ''
```

**2. `infra/main.bicep` — updated logic:**

```bicep
// New variable to detect if existing DNS zones are specified
var _useExistingDnsZones = !empty(existingDnsZonesResourceGroupName)

// DNS zone creation is now also skipped when using existing zones
var _deployPrivateDnsZones = _networkIsolation && !policyManagedPrivateDns && !_useExistingDnsZones

// DNS zone ID resolution uses existing RG/Sub when specified
var _dnsZonesSubscriptionId = _useExistingDnsZones
  ? (!empty(existingDnsZonesSubscriptionId) ? existingDnsZonesSubscriptionId : subscription().subscriptionId)
  : (useExistingVNet && !sideBySideDeploy ? varExistingVnetSubscriptionId : subscription().subscriptionId)
var _dnsZonesResourceGroupName = _useExistingDnsZones
  ? existingDnsZonesResourceGroupName
  : (useExistingVNet && !sideBySideDeploy ? varExistingVnetResourceGroupName : resourceGroup().name)
```

**3. `main.parameters.json` — new parameters:**

```json
"existingDnsZonesResourceGroupName":     { "value": "${EXISTING_DNS_ZONES_RESOURCE_GROUP_NAME}" },
"existingDnsZonesSubscriptionId":        { "value": "${EXISTING_DNS_ZONES_SUBSCRIPTION_ID}" },
```

### Behavior with `existingDnsZonesResourceGroupName` set

| Behavior | Result |
|---|---|
| `_deployPrivateDnsZones` | `false` — does not create any DNS Zones |
| `_peDnsZoneGroup*` (×N) | **Still created** — Private Endpoints get DNS Zone Groups pointing to the existing zones in the specified RG |
| DNS resolution | Private Endpoint A-records resolve via the pre-existing zones already linked to the VNet |

### Difference from `policyManagedPrivateDns`

| | `policyManagedPrivateDns=true` | `existingDnsZonesResourceGroupName` set |
|---|---|---|
| DNS Zones created? | No | No |
| DNS Zone Groups on PEs? | **No** (null) — expects Azure Policy to register | **Yes** — points to existing zones in the specified RG |
| Use case | Hub & Spoke with Azure Policy | Flat VNet with pre-created zones in any RG |

---

### Problem B — Unconditional Subnet Deployment in Multi-Instance Flat VNet

**Problem**: The `baseSubnets` array unconditionally includes all 9 subnets. When `deploySubnets=true` on an existing VNet:
1. All 9 subnets are created even if only 3 are needed (pe, aca, agent).
2. A second deployment instance on the same VNet **fails** because subnet names and/or CIDR ranges collide with the first instance.

**Root cause**: No conditional logic in the `baseSubnets` array. The deployment flags (`deployVM`, `deployAzureFirewall`, etc.) only gated the *resources using* those subnets, not the subnet creation itself.

### Applied changes (Subnets)

**1. `infra/main.bicep` — new parameter:**

```bicep
@description('Deploy a VPN Gateway subnet. Set to true only when a VPN/ExpressRoute gateway is required.')
param deployVpnGateway bool = false
```

**2. `infra/main.bicep` — refactored `baseSubnets` to conditional `concat()`:**

```bicep
var baseSubnets = concat(
  // Core subnets (always included)
  [ agentSubnet, peSubnet, acaEnvironmentSubnet ],
  // Conditional on deployVpnGateway
  deployVpnGateway ? [ gatewaySubnet ] : [],
  // Conditional on deployVM
  deployVM ? [ azureBastionSubnet, jumpboxSubnet ] : [],
  // Conditional on deployAzureFirewall
  deployAzureFirewall ? [ azureFirewallSubnet ] : [],
  // Conditional on _publicIngressEnabled
  _publicIngressEnabled ? [ azureAppGatewaySubnet ] : [],
  // Conditional on _deployAcrTaskAgentPool
  _deployAcrTaskAgentPool ? [ devopsBuildAgentsSubnet ] : []
)
```

**3. `main.parameters.json` — subnet names and prefixes exposed as env vars:**

```json
"deployVpnGateway":                      { "value": "${DEPLOY_VPN_GATEWAY=false}" },
"agentSubnetName":                       { "value": "${AGENT_SUBNET_NAME}" },
"agentSubnetPrefix":                     { "value": "${AGENT_SUBNET_PREFIX}" },
"peSubnetName":                          { "value": "${PE_SUBNET_NAME}" },
"peSubnetPrefix":                        { "value": "${PE_SUBNET_PREFIX}" },
"acaEnvironmentSubnetName":              { "value": "${ACA_ENVIRONMENT_SUBNET_NAME}" },
"acaEnvironmentSubnetPrefix":            { "value": "${ACA_ENVIRONMENT_SUBNET_PREFIX}" },
"jumpboxSubnetName":                     { "value": "${JUMPBOX_SUBNET_NAME}" },
"jumpboxSubnetPrefix":                   { "value": "${JUMPBOX_SUBNET_PREFIX}" },
```

**4. `.gitmodules` — submodule updated to track `main` branch (currently v1.1.9):**

```ini
branch = main
```

### Subnet deployment matrix

| Subnet | Condition | Required env vars |
|---|---|---|
| `agentSubnet` | Always | `AGENT_SUBNET_NAME`, `AGENT_SUBNET_PREFIX` |
| `peSubnet` | Always | `PE_SUBNET_NAME`, `PE_SUBNET_PREFIX` |
| `acaEnvironmentSubnet` | Always | `ACA_ENVIRONMENT_SUBNET_NAME`, `ACA_ENVIRONMENT_SUBNET_PREFIX` |
| `azureBastionSubnet` | `DEPLOY_VM=true` | (uses Bicep defaults — Azure-mandated name) |
| `jumpboxSubnet` | `DEPLOY_VM=true` | `JUMPBOX_SUBNET_NAME`, `JUMPBOX_SUBNET_PREFIX` |
| `gatewaySubnet` | `DEPLOY_VPN_GATEWAY=true` | (uses Bicep defaults) |
| `azureFirewallSubnet` | `DEPLOY_AZURE_FIREWALL=true` | (uses Bicep defaults) |
| `azureAppGatewaySubnet` | Public ingress enabled | (uses Bicep defaults) |
| `devopsBuildAgentsSubnet` | `DEPLOY_ACR_TASK_AGENT_POOL=true` | (uses Bicep defaults) |

### Environment variables for flat VNet multi-instance deployment

```bash
# Instance 1
azd env set AGENT_SUBNET_NAME            "agent-subnet-inst1"
azd env set AGENT_SUBNET_PREFIX          "10.0.1.0/24"
azd env set PE_SUBNET_NAME               "pe-subnet-inst1"
azd env set PE_SUBNET_PREFIX             "10.0.2.0/26"
azd env set ACA_ENVIRONMENT_SUBNET_NAME  "aca-env-subnet-inst1"
azd env set ACA_ENVIRONMENT_SUBNET_PREFIX "10.0.3.0/24"
azd env set DEPLOY_VM                    false

# Instance 2 (different names and non-overlapping CIDRs)
azd env set AGENT_SUBNET_NAME            "agent-subnet-inst2"
azd env set AGENT_SUBNET_PREFIX          "10.0.4.0/24"
azd env set PE_SUBNET_NAME               "pe-subnet-inst2"
azd env set PE_SUBNET_PREFIX             "10.0.5.0/26"
azd env set ACA_ENVIRONMENT_SUBNET_NAME  "aca-env-subnet-inst2"
azd env set ACA_ENVIRONMENT_SUBNET_PREFIX "10.0.6.0/24"
azd env set DEPLOY_VM                    false
```

### Verification

1. `az bicep build --file infra/main.bicep` — compiles without errors ✅
2. With only 3 core subnet env vars set + `DEPLOY_VM=false` → only 3 subnets in deployment
3. With `DEPLOY_VM=true` → bastion + jumpbox subnets added (5 total)
4. With `DEPLOY_VM=false` → jumpbox and bastion subnets are NOT created
5. Two instances with different subnet names/CIDRs on same VNet → no collision

---

## Fix 5 — Expose `enablePrivateLogAnalytics` + Infra Submodule Fixes

**Modified files**: `main.parameters.json`, `infra/main.bicep`

**Problem**: First deployment attempt failed with 3 errors:
1. `InvalidResourceReference: .../subnets/pe-subnet` — PEs for AI Foundry's Cosmos DB and Key Vault use a hardcoded `pe-subnet` name instead of the `peSubnetName` parameter.
2. `InvalidPrivateDnsZoneIds: ... has invalid private dns zone ids ,,.` — The AMPLS Private Endpoint references 3 DNS zones that don't exist (`oms.opinsights`, `ods.opinsights`, `agentsvc.azure-automation`).
3. AI Foundry networking override didn't account for the new `_useExistingDnsZones` flag.

### Applied changes

**1. `main.parameters.json` — expose `enablePrivateLogAnalytics`:**

```json
"enablePrivateLogAnalytics": { "value": "${ENABLE_PRIVATE_LOG_ANALYTICS=true}" },
```

Setting `ENABLE_PRIVATE_LOG_ANALYTICS=false` disables AMPLS deployment, avoiding the need for the 3 missing DNS zones.

**2. `infra/main.bicep` — fix hardcoded `pe-subnet` (line 2032-2034):**

```bicep
// Before:
var varPeSubnetId = empty(existingVnetResourceId!)
  ? '${virtualNetworkResourceId}/subnets/pe-subnet'
  : '${existingVnetResourceId!}/subnets/pe-subnet'

// After:
var varPeSubnetId = empty(existingVnetResourceId!)
  ? '${virtualNetworkResourceId}/subnets/${peSubnetName}'
  : '${existingVnetResourceId!}/subnets/${peSubnetName}'
```

**3. `infra/main.bicep` — fix `varAfNetworkingOverride` (line 2036):**

```bicep
// Before:
var varAfNetworkingOverride = _networkIsolation
  ? (policyManagedPrivateDns
    ? { agentServiceSubnetResourceId: ... }
    : { cognitiveServicesPrivateDnsZoneResourceId: ..., ... })
  : null

// After:
var varAfNetworkingOverride = _networkIsolation
  ? ((policyManagedPrivateDns && !_useExistingDnsZones)
    ? { agentServiceSubnetResourceId: ... }
    : { cognitiveServicesPrivateDnsZoneResourceId: ..., ... })
  : null
```

### Environment variable

```bash
# Disable AMPLS if the 3 monitor DNS zones don't exist:
azd env set ENABLE_PRIVATE_LOG_ANALYTICS false
```

### Infra submodule detailed changes

See [`infra-fixes.md`](infra-fixes.md) for complete documentation of all changes applied to the `bicep-ptn-aiml-landing-zone` submodule (Fixes 1-4).

### Verification

- `az bicep build --file infra/main.bicep` — compiles without errors ✅
