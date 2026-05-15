
# Applied Fixes — GPT-RAG Post-Provisioning
> **Date**: 2026-04-05 (started), 2026-05-15 (latest update)  
> **Scope**: Post-provisioning fixes for enterprise deployment scenarios  
> **Base release**: v2.6.2+
---
## Index
| #                                                                               | File                                               | Description                                                                                                                                       |
| ------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| [1](#fix-1--hub--spoke-policymanagedprivatedns)                                 | `main.parameters.json`, `.gitmodules`, `infra/`    | Hub & Spoke support: skip Private DNS Zone creation when zones already exist in the Hub                                                           |
| [2](#fix-2--deployvm-converted-to-environment-variable)                         | `main.parameters.json`                             | Convert `deployVM` from hardcoded `true` to env var `${DEPLOY_VM}`                                                                                |
| [3](#fix-3--container-apps-managedidentitycredential-fails-with-system-assigned-identity) | `azd env set USE_UAI true` (no code changes)       | Enable User Assigned Identities so `AZURE_CLIENT_ID` is injected with real UAI clientId           |
| [4](#fix-4--flat-vnet-pre-existing-private-dns-zones-in-external-resource-group) | `main.parameters.json`, `.gitmodules`, `infra/main.bicep` | Support pre-existing Private DNS Zones in a different Resource Group (flat VNet, no Hub & Spoke) |
| [5](#fix-5--expose-enableprivateloganalytics-and-infra-submodule-fixes) | `main.parameters.json`, `infra/main.bicep` | Expose `enablePrivateLogAnalytics` + fix hardcoded `pe-subnet` + fix AI Foundry DNS override |
| [6](#fix-6--container-apps-acr-association-blocked-by-mfa-policy) | `config/containerapps/setup.py` | CLI fallback when Python SDK is blocked by Conditional Access MFA policy |
| [7](infra-fixes.md#fix-7--cosmos-db-analytical-storage) | `infra/main.bicep` (submodule) | Disable Cosmos DB analytical storage (`enableAnalyticalStorage: false`) — fails in regions without Synapse Link |
| [8](#fix-8--dataingest-azure_client_id-collision-in-app-config-with-use_uai) | `config/containerapps/setup.py` | Limit `AZURE_CLIENT_ID` App Config seeding to dataingest only — prevents cross-label collision causing `invalid_scope` |

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

## Fix 3 — Container Apps: `ManagedIdentityCredential` fails with System Assigned Identity

**Resolution**: Enable `USE_UAI=true` (no code changes required)

**Problem**: All Container Apps (frontend, orchestrator, ingestion) start in NOT-READY mode (HTTP 503) with the error:

```
ChainedTokenCredential failed to retrieve a token from the included credentials.
App Service managed identity configuration not found in environment. invalid_scope
```

**Root cause**: The component code (e.g. `gpt-rag-ui/connectors/appconfig.py`) does:

```python
self.client_id = os.environ.get('AZURE_CLIENT_ID', "*")
# ...
ManagedIdentityCredential(client_id=self.client_id)
```

With `USE_UAI=false` (System Assigned Identity), the Bicep template intentionally does **not** inject `AZURE_CLIENT_ID` into the Container App env vars (because an empty/invalid value breaks `DefaultAzureCredential`). The code then defaults to `"*"`, and the SDK attempts to acquire a token for a User Assigned Identity with client_id `"*"`, which does not exist → `invalid_scope`.

The Bicep has a comment explaining this at L2409-2415:
```bicep
// Only inject AZURE_CLIENT_ID when a UAI is actually configured (#38).
// Emitting an empty AZURE_CLIENT_ID alongside AZURE_TENANT_ID breaks
// DefaultAzureCredential on the SystemAssigned path...
```

### Applied fix — enable User Assigned Identities

```bash
azd env set USE_UAI true
azd provision
azd deploy
```

This activates the `useUAI` parameter in `main.bicep` (L379), which:

1. **Creates UAIs** for each Container App: `uai-ca-{resourceToken}-{service_name}` (L2347-2352)
2. **Switches Container Apps** from SystemAssigned → UserAssigned identity (L2378-2381)
3. **Injects `AZURE_CLIENT_ID`** with the real UAI clientId into the container env vars (L2416-2420)
4. **Reassigns all RBAC** (App Config Data Reader, Key Vault, Cognitive Services, AI Search, Storage, Cosmos) to the UAI principals (L2884-3123)

The component code then correctly resolves `AZURE_CLIENT_ID` → real UUID → `ManagedIdentityCredential(client_id="real-uuid")` → finds the UAI → authenticates successfully.

### Why not fix the code instead?

Changing `os.environ.get('AZURE_CLIENT_ID', "*")` → `os.environ.get('AZURE_CLIENT_ID') or None` would also work for System Assigned Identity. However:
- It requires modifying 3 component repos (UI, orchestrator, ingestion)
- UAI is the recommended approach for production (identity survives container recreation)
- The Bicep already has full UAI support — just needs the flag enabled

### Verification

```powershell
# Check env var injection
az containerapp show --name ca-<token>-frontend --resource-group <rg> \
  --query "properties.template.containers[0].env[?name=='AZURE_CLIENT_ID'].value" -o tsv
# Should return a real UUID (e.g., d5ab6b4b-6ff6-4fdf-84e5-3c1abd16ccdf)

# Check application logs
az containerapp logs show --name ca-<token>-frontend --resource-group <rg> --type console --tail 15
# Should show: "Application startup complete." and HTTP 200 responses
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

---

## Fix 6 — Container Apps ACR association blocked by MFA policy

**Modified files**: `config/containerapps/setup.py`

**Problem**: In tenants with Conditional Access Policies requiring MFA for Azure resource management, the Python SDK (`azure-mgmt-appcontainers`) fails with `RequestDisallowedByAzure` when calling `begin_create_or_update` to associate the ACR registry with each Container App. However, the Azure CLI (`az containerapp registry set`) succeeds because the CLI app ID satisfies the MFA policy differently.

### Root cause

Conditional Access Policies evaluate the client application ID requesting the token. The `az` CLI uses a first-party Microsoft app ID that may be excluded from or satisfies MFA policies. The Python SDK's `AzureCliCredential` delegates to `az account get-access-token`, but when the resulting token is presented to ARM by the SDK's HTTP client (which uses a different client context), it can be rejected by resource-provider-specific MFA enforcement.

Data-plane operations (App Configuration, AI Search) are unaffected because they target different resource providers not covered by the same policy.

### Applied change

Added a `_fallback_cli_registry_set()` function that executes `az containerapp registry set` via subprocess. The `update_single_container_app()` function now catches `RequestDisallowedByAzure` / MFA errors and automatically falls back to the CLI command.

```python
def _fallback_cli_registry_set(resource_group, name, acr_server, desired_identity):
    """Fallback: use 'az containerapp registry set' when the Python SDK is blocked by MFA policies."""
    cmd = [
        "az", "containerapp", "registry", "set",
        "--name", name,
        "--resource-group", resource_group,
        "--server", acr_server,
        "--identity", desired_identity,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, shell=True)
    ...
```

**Note**: `shell=True` is required on Windows because `az` is a `.cmd` batch file — without it, `subprocess.run` raises `[WinError 2] The system cannot find the file specified`.

In the exception handler:
```python
except Exception as e:
    error_str = str(e)
    if "RequestDisallowedByAzure" in error_str or "MFA" in error_str:
        success, msg = _fallback_cli_registry_set(resource_group, name, acr_server, desired_identity)
        return name, success, msg
```

### Verification

- Run `postProvision.ps1` in a tenant with MFA Conditional Access — Container Apps should succeed via CLI fallback ✅
- In tenants without MFA policies, the SDK path executes normally (fallback is never triggered)
- Confirmed working: 3/3 apps updated successfully via CLI fallback (2026-05-15)

### Validation commands

```powershell
# Verify each Container App has ACR associated with the correct UAI identity
az containerapp registry list --name ca-<token>-orchestrator --resource-group <rg> -o table
az containerapp registry list --name ca-<token>-frontend --resource-group <rg> -o table
az containerapp registry list --name ca-<token>-dataingest --resource-group <rg> -o table
```

Expected output: each app shows `cr<token>.azurecr.io` as Server with the corresponding UAI identity resource ID.

---

## Fix 8 — Dataingest `AZURE_CLIENT_ID` collision in App Config with `USE_UAI`

**Modified files**: `config/containerapps/setup.py`

**Problem**: After `azd deploy`, dataingest failed to index documents. All 5 PDFs failed with:
```
ChainedTokenCredential failed to retrieve a token from the included credentials.
  AzureCliCredential: Azure CLI not found on path
  ManagedIdentityCredential: App Service managed identity configuration not found in environment. invalid_scope
```
Storage and Search scopes worked fine — only `cognitiveservices.azure.com` failed.

### Root cause

When `USE_UAI=true`, the `postProvision` script creates separate User-Assigned Identities per component and writes each `AZURE_CLIENT_ID` into App Config under a component-specific label:

| Label | `AZURE_CLIENT_ID` | Component |
|---|---|---|
| `gpt-rag-ingestion` | `72678e6b-...` | dataingest |
| `gpt-rag-orchestrator` | `6b5c9f5c-...` | orchestrator |
| `gpt-rag-frontend` | `ec95dd19-...` | frontend |

The ingestion `appconfig.py` loads config with three `SettingSelector`s:
```python
selects=[
    SettingSelector(label_filter='gpt-rag-ingestion', key_filter='*'),
    SettingSelector(label_filter='gpt-rag', key_filter='*'),
    SettingSelector(label_filter=None, key_filter='*'),
]
```

In `azure-appconfiguration-provider` v2.1.0, `SettingSelector(label_filter=None)` loads **all labels** (not "unlabeled keys only"). Because selectors are processed in order and later ones overwrite earlier values, the orchestrator's `AZURE_CLIENT_ID` (`6b5c9f5c-...`) overwrote the correct ingestion value (`72678e6b-...`).

When `doc_intelligence.py` and `content_understanding.py` called:
```python
client_id = app_config_client.get('AZURE_CLIENT_ID', None, allow_none=True) or None
cred = ChainedTokenCredential(AzureCliCredential(), ManagedIdentityCredential(client_id=client_id))
token = cred.get_token('https://cognitiveservices.azure.com/.default')
```
…it tried to acquire a token using the **orchestrator's** UAI, which is not assigned to the dataingest container — resulting in `invalid_scope`.

### Why storage/search worked but cognitiveservices didn't

The `appconfig.py` class itself uses `os.environ.get('AZURE_CLIENT_ID')` (the correct container env var) to authenticate against App Config and other services. The bug only manifested in `doc_intelligence.py` and `content_understanding.py`, which read `AZURE_CLIENT_ID` from App Config (not env vars) to create a separate credential for Cognitive Services calls.

### Applied fix

**Modified files**: `config/containerapps/setup.py`

The `seed_uai_client_ids()` function in `config/containerapps/setup.py` wrote `AZURE_CLIENT_ID` to App Config for all three components (dataingest, orchestrator, frontend). Only dataingest actually reads it from App Config — the other two read it from their container env vars.

Removed orchestrator and frontend from the `SERVICE_NAME_TO_APPCONFIG_LABEL` mapping so only dataingest's value is written:

```python
# Before:
SERVICE_NAME_TO_APPCONFIG_LABEL = {
    "dataingest": "gpt-rag-ingestion",
    "orchestrator": "gpt-rag-orchestrator",
    "frontend": "gpt-rag-frontend",
}

# After:
SERVICE_NAME_TO_APPCONFIG_LABEL = {
    "dataingest": "gpt-rag-ingestion",
}
```

This prevents the collision permanently — future `azd provision` runs will only write the ingestion entry.

**For existing deployments** where the entries already exist, delete them manually:

```powershell
az appconfig kv delete --name appcs-<token> --key "AZURE_CLIENT_ID" --label "gpt-rag-orchestrator" --auth-mode login --yes
az appconfig kv delete --name appcs-<token> --key "AZURE_CLIENT_ID" --label "gpt-rag-frontend" --auth-mode login --yes
```

After removing the conflicting entries, only the `gpt-rag-ingestion` label remains:
```
KEY              VALUE                                 LABEL
AZURE_CLIENT_ID  72678e6b-cbdc-4b11-9c45-aab89d5bd72e  gpt-rag-ingestion
```

### Verification

Force a new container revision (not just restart) so the app reloads its config:
```powershell
$ts = Get-Date -Format 'yyyyMMddHHmmss'
az containerapp update --name ca-<token>-dataingest --resource-group <rg> --set-env-vars "RESTART_TRIGGER=$ts" -o none
```

Check logs after ~2-3 minutes:
```powershell
az containerapp logs show --name ca-<token>-dataingest --resource-group <rg> --type console --tail 50 --format text
```

Expected: `"indexedItems": N` with `"failed": 0` instead of `invalid_scope` errors.

### Note on the configuration conflict

The root issue is a combination of two behaviors:
1. `config/containerapps/setup.py` wrote `AZURE_CLIENT_ID` under per-component App Config labels
2. `gpt-rag-ingestion` v2.3.3's `appconfig.py` uses `SettingSelector(label_filter=None)` which loads **all labels** (documented SDK behavior in `azure-appconfiguration-provider` v2.1.0), causing cross-component key collisions

The code fix (limiting writes to dataingest only) prevents the collision permanently. Setting `USE_UAI=false` does **not** solve this — it introduces a worse problem (see [Fix 3](#fix-3--container-apps-managedidentitycredential-fails-with-system-assigned-identity)).

### Quick diagnosis guide

This issue took significant time to diagnose because the error (`invalid_scope`) is generic and multiple services use `AZURE_CLIENT_ID`. Use this checklist to identify it in minutes:

**Symptom fingerprint** — all three must be true:
1. `USE_UAI=true` is set
2. Dataingest logs show `invalid_scope` or `ManagedIdentityCredential` errors **only for `cognitiveservices.azure.com`** (storage, search, and App Config work fine)
3. Orchestrator and frontend are healthy (HTTP 200)

**Why it's confusing**: The error looks like a missing RBAC assignment or wrong identity, but the real problem is a **config value collision** — the container has the right identity, but the code reads the wrong client_id from App Config.

**Fast confirmation (< 2 minutes)**:

```powershell
# Step 1: Get the EXPECTED client_id (from the container env var — always correct)
az containerapp show --name ca-<token>-dataingest --resource-group <rg> \
  --query "properties.template.containers[0].env[?name=='AZURE_CLIENT_ID'].value" -o tsv

# Step 2: Check what App Config ACTUALLY returns for AZURE_CLIENT_ID
az appconfig kv list --name appcs-<token> --key "AZURE_CLIENT_ID" --auth-mode login -o table

# Step 3: Compare — if there are multiple entries with different labels and values,
# this is the collision. The last label alphabetically wins due to load order.
```

**If Step 2 shows multiple `AZURE_CLIENT_ID` entries** with different labels (e.g., `gpt-rag-ingestion`, `gpt-rag-orchestrator`, `gpt-rag-frontend`) and **different values** → this is the bug. The ingestion code's `label_filter=None` selector loads all of them, and the last one processed overwrites the correct value.

**Immediate fix**:
```powershell
# Delete the entries that don't belong to dataingest
az appconfig kv delete --name appcs-<token> --key "AZURE_CLIENT_ID" --label "gpt-rag-orchestrator" --auth-mode login --yes
az appconfig kv delete --name appcs-<token> --key "AZURE_CLIENT_ID" --label "gpt-rag-frontend" --auth-mode login --yes
# Force reload
$ts = Get-Date -Format 'yyyyMMddHHmmss'
az containerapp update --name ca-<token>-dataingest --resource-group <rg> --set-env-vars "RESTART_TRIGGER=$ts" -o none
```

**Key differentiator from other auth issues**:

| Symptom | Likely cause | Check |
|---|---|---|
| ALL services fail with `invalid_scope` | Wrong/missing UAI assignment | Fix 3 — `USE_UAI` not enabled |
| Only `cognitiveservices` fails, storage/search work | App Config collision (this fix) | Compare env var vs App Config values |
| `"*"` in error for client_id | `USE_UAI=false` with code defaulting to `"*"` | Fix 3 — enable `USE_UAI` |
| `RequestDisallowedByAzure` during provisioning | MFA policy blocking SDK | Fix 6 — CLI fallback |
