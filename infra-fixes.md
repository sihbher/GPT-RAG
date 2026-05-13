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
