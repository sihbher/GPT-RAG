# Applied Fixes — Infra Submodule (bicep-ptn-aiml-landing-zone)

> **Base version**: v1.1.9 (commit `1d2151a`)  
> **Repo**: `Azure/bicep-ptn-aiml-landing-zone`

---

## Index

| # | Line(s) | Description |
|---|---|---|
| [1](#fix-1--hardcoded-pe-subnet-in-varpesubnetid) | 2032-2034 | `pe-subnet` hardcoded instead of using `peSubnetName` parameter |
| [2](#fix-2--varAfNetworkingOverride-ignores-_useExistingDnsZones) | 2036-2048 | AI Foundry networking override not accounting for existing DNS zones |
| [3](#fix-3--conditional-subnet-deployment) | 846-937 | `baseSubnets` unconditionally includes all 9 subnets |
| [4](#fix-4--existing-dns-zones-in-external-resource-group) | 98-106, 531, 1586, 1837-1838 | DNS zone support for external Resource Group |
| [5](#fix-5--appconfigpopulate-skipped-under-network-isolation) | 3436 | `appConfigPopulate` module skipped when `networkIsolation=true` |
| [6](#fix-6--uai-client_id-not-available-in-app-configuration) | config/containerapps/setup.py | Content Understanding auth fails when `USE_UAI=true` |
| [7](#fix-7--cosmos-db-enableanalyticalstorage-no-longer-supported) | 2467 | `enableAnalyticalStorage: true` fails on new account creation |

---

## Fix 1 — Hardcoded `pe-subnet` in `varPeSubnetId`

**File**: `main.bicep` (lines 2032-2034)

**Problem**: The `varPeSubnetId` variable constructs the Private Endpoint subnet resource ID using a hardcoded string `'pe-subnet'` instead of the `peSubnetName` parameter. When the customer provides a custom subnet name (e.g., `snet-pe-bot1`), the PEs for AI Foundry's Cosmos DB and Key Vault fail with `InvalidResourceReference` because they look for a subnet named `pe-subnet` that doesn't exist.

**Root cause**: The variable was introduced specifically for the AI Foundry module and bypasses the `_peSubnetId` variable (which correctly uses `peSubnetName`).

### Applied change

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

---

## Fix 2 — `varAfNetworkingOverride` ignores `_useExistingDnsZones`

**File**: `main.bicep` (lines 2036-2048)

**Problem**: The `varAfNetworkingOverride` variable conditions its DNS zone ID injection solely on `policyManagedPrivateDns`. When using `existingDnsZonesResourceGroupName` (our new parameter for pre-existing zones in an external RG), `policyManagedPrivateDns` is `false` but we still want DNS zone IDs passed to the AI Foundry module. However, when `policyManagedPrivateDns=true` WITHOUT existing zones, the override correctly omits DNS zone IDs (expecting Azure Policy). The fix ensures that when existing DNS zones are specified, the networking override always includes the zone IDs.

**Root cause**: The condition only checked `policyManagedPrivateDns` without considering the new `_useExistingDnsZones` flag.

### Applied change

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

**Logic**: Only skip DNS zone IDs when `policyManagedPrivateDns=true` AND we are NOT using existing DNS zones. If existing zones are specified, always pass their IDs regardless of `policyManagedPrivateDns`.

---

## Fix 3 — Conditional Subnet Deployment

**File**: `main.bicep` (lines 846-937)

**Problem**: The `baseSubnets` array unconditionally includes all 9 subnets. When deploying multiple instances on the same VNet with `deploySubnets=true`, subnet names and CIDR ranges collide.

**Root cause**: No conditional logic in the array; deployment flags only gated the resources using those subnets, not the subnet creation itself.

### Applied change

Replaced the static array with a `concat()`-based construction:

```bicep
var baseSubnets = concat(
  // Core (always): agentSubnet, peSubnet, acaEnvironmentSubnet
  [...],
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

Also added `param deployVpnGateway bool = false`.

---

## Fix 4 — Existing DNS Zones in External Resource Group

**File**: `main.bicep` (lines 98-106, 531, 1586, 1837-1838)

**Problem**: When Private DNS Zones exist in a Resource Group different from both the VNet RG and the deployment RG, the Bicep code had no way to reference them. The `_dnsZonesResourceGroupName` was derived from the VNet resource ID, which is incorrect in flat-VNet scenarios where DNS zones are centralized elsewhere.

### Applied change

Added two new parameters:

```bicep
param existingDnsZonesResourceGroupName string = ''
param existingDnsZonesSubscriptionId string = ''
```

Updated logic:

```bicep
var _useExistingDnsZones = !empty(existingDnsZonesResourceGroupName)
var _deployPrivateDnsZones = _networkIsolation && !policyManagedPrivateDns && !_useExistingDnsZones

var _dnsZonesSubscriptionId = _useExistingDnsZones
  ? (!empty(existingDnsZonesSubscriptionId) ? existingDnsZonesSubscriptionId : subscription().subscriptionId)
  : (useExistingVNet && !sideBySideDeploy ? varExistingVnetSubscriptionId : subscription().subscriptionId)

var _dnsZonesResourceGroupName = _useExistingDnsZones
  ? existingDnsZonesResourceGroupName
  : (useExistingVNet && !sideBySideDeploy ? varExistingVnetResourceGroupName : resourceGroup().name)
```

---

## Fix 5 — `appConfigPopulate` skipped under network isolation

**Files**: `infra/main.bicep`, `main.parameters.json`, `scripts/postProvision.ps1`

**Problem**: The `appConfigPopulate` and `cosmosConfigKeyVaultPopulate` modules have the condition `!_networkIsolation`, which means App Configuration is **never populated** when Zero Trust is enabled. This leaves App Config empty, causing all downstream scripts (AI Foundry, Container Apps, Search setup) to fail.

**Root cause**: Writing key-values via ARM (`Microsoft.AppConfiguration/configurationStores/keyValues`) is a data-plane proxy operation. With `publicNetworkAccess: Disabled`, ARM cannot reach the App Config data plane — even though `privateLinkDelegation: Enabled` is set. ARM requires an [Azure Resource Manager private link](https://learn.microsoft.com/en-us/azure/azure-app-configuration/quickstart-deployment-overview?tabs=portal#private-network-access) which is not provisioned.

### Applied change — `tempPublicAppConfig` flag

Instead of populating App Config manually from the script, we added a `tempPublicAppConfig` parameter that temporarily deploys App Config with public access so ARM can write key-values during provisioning. `postProvision.ps1` then disables public access at the end.

**Bicep changes** (`infra/main.bicep`):
1. New parameter: `param tempPublicAppConfig bool = false`
2. App Config resource: `publicNetworkAccess: (_networkIsolation && !tempPublicAppConfig) ? 'Disabled' : 'Enabled'`
3. `appConfigPopulate` condition: `deployAppConfig && (!_networkIsolation || tempPublicAppConfig)`
4. `cosmosConfigKeyVaultPopulate` condition: `deployCosmosDb && deployAppConfig && (!_networkIsolation || tempPublicAppConfig)`

---

## Fix 7 — Cosmos DB `enableAnalyticalStorage` no longer supported

**File**: `main.bicep` (line 2467)

**Problem**: Provisioning fails with `BadRequest`: "Enabling Analytical Storage during account creation is no longer supported." The `enableAnalyticalStorage` property was hardcoded to `true`.

**Root cause**: Azure deprecated enabling Analytical Storage (Synapse Link) during Cosmos DB account creation as of May 2026. Existing accounts with the feature already enabled continue to work, but new accounts cannot enable it at creation time. Microsoft recommends Fabric Mirroring as the strategic replacement.

**Reference**: https://learn.microsoft.com/en-us/answers/questions/5888858/cosmos-not-able-to-enable-synapse-link

**Impact**: GPT-RAG does not use Synapse Link / Analytical Storage. The Cosmos DB account stores conversations and configuration data only.

### Applied change

```bicep
// Before:
enableAnalyticalStorage: true

// After:
enableAnalyticalStorage: false
```

**Decision**: Changed to `false` without parameterization since Azure rejects `true` on all new account creations regardless of configuration.

**Parameters** (`main.parameters.json`):
- `"tempPublicAppConfig": { "value": "${TEMP_PUBLIC_APP_CONFIG=false}" }`

**postProvision.ps1**:
- Added lock-down block at the end: when `NETWORK_ISOLATION=true` and `TEMP_PUBLIC_APP_CONFIG=true`, disables public access via `az appconfig update --enable-public-network false`

### Usage

```bash
azd env set TEMP_PUBLIC_APP_CONFIG true
azd provision   # App Config is public → ARM writes all keys
                # postProvision.ps1 runs config modules, then disables public access
```

Private endpoints are created during provisioning regardless, so after lock-down only the private endpoint route remains.

---

## Fix 6 — UAI client_id not available in App Configuration

**File**: `config/containerapps/setup.py`

**Problem**: When `USE_UAI=true`, the `content_understanding` module in `gpt-rag-ingestion` fails to authenticate against the AI Foundry endpoint with error:
```
ManagedIdentityCredential: App Service managed identity configuration not found in environment. invalid_scope
```
Documents are discovered but never indexed (indexedItems=0, all fail or are blocked).

**Root cause**: The Bicep template injects `AZURE_CLIENT_ID` as a **container environment variable**, but the `ContentUnderstandingClient` class (`tools/content_understanding.py`) reads it from **App Configuration** via `app_config_client.get("AZURE_CLIENT_ID")`. Since that key was never written to App Config, the lookup returns `None`, and `ManagedIdentityCredential(client_id=None)` attempts to use a system-assigned identity — which doesn't exist when `USE_UAI=true` (Bicep sets `systemAssigned: false`).

Other ingestion operations (Storage, Search) succeed because the `AppConfigClient.__init__()` reads `AZURE_CLIENT_ID` from the container env var to build its own credential chain. Only modules that later query App Config for `AZURE_CLIENT_ID` are affected.

**Why this fix lives here (not in component repos)**: The `content_understanding` module's behavior of reading `AZURE_CLIENT_ID` from App Config is intentional — it allows per-service identity configuration. The gap is that the platform provisioning never wrote this key. The fix seeds the value during `postProvision`, keeping component repos unchanged.

### Applied change

Added to `config/containerapps/setup.py`:

1. **Service-to-label mapping** — maps each Container App `service_name` to the App Config label used by that component:
   ```python
   SERVICE_NAME_TO_APPCONFIG_LABEL = {
       "dataingest": "gpt-rag-ingestion",
       "orchestrator": "gpt-rag-orchestrator",
       "frontend": "gpt-rag-frontend",
   }
   ```

2. **`seed_uai_client_ids()` function** — when `USE_UAI=true`, reads each Container App's UAI `clientId` from Azure and writes it to App Config with the service-specific label:
   ```python
   # For each container app with a UAI:
   ConfigurationSetting(
       key="AZURE_CLIENT_ID",
       label="gpt-rag-ingestion",  # (or gpt-rag-orchestrator, gpt-rag-frontend)
       value="<uai-client-id>",
   )
   ```

3. **Invocation in `main()`** — called after the ACR association step, only when `USE_UAI=true`.

### Effect

After `azd provision` (postProvision hook), App Config contains:
```
Key: AZURE_CLIENT_ID | Label: gpt-rag-ingestion | Value: e709119d-...
Key: AZURE_CLIENT_ID | Label: gpt-rag-orchestrator | Value: <orchestrator-uai-client-id>
Key: AZURE_CLIENT_ID | Label: gpt-rag-frontend | Value: <frontend-uai-client-id>
```

Each component's `AppConfigClient` loads its own label first, so it picks up its own UAI client_id. The `ContentUnderstandingClient` then correctly calls `ManagedIdentityCredential(client_id="e709119d-...")` and authenticates successfully.
