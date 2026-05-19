#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 4 — Configure azd Environment
.DESCRIPTION
    Creates the azd environment and sets all required variables for
    GPT-RAG deployment in an existing VNet.
.PARAMETER DEPLOY_NAME
    azd environment name
.PARAMETER SUBSCRIPTION_ID
    Azure subscription ID
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG resources
.PARAMETER VNET_RESOURCE_GROUP
    Resource group containing the VNet
.PARAMETER VNET_NAME
    Name of the existing VNet
.PARAMETER DNS_ZONES_RG
    Resource group for Private DNS Zones
.PARAMETER PE_SUBNET_NAME
    Name for the Private Endpoints subnet
.PARAMETER ACA_SUBNET_NAME
    Name for the Container Apps Environment subnet
.PARAMETER AGENT_SUBNET_NAME
    Name for the Agent subnet
.PARAMETER ENABLE_PRIVATE_LOG_ANALYTICS
    Whether to enable private Log Analytics (false if AMPLS exists)
#>
param(
    [Parameter(Mandatory)][string]$DEPLOY_NAME,
    [Parameter(Mandatory)][string]$SUBSCRIPTION_ID,
    [Parameter(Mandatory)][string]$GPTRAG_RG,
    [Parameter(Mandatory)][string]$VNET_RESOURCE_GROUP,
    [Parameter(Mandatory)][string]$VNET_NAME,
    [Parameter(Mandatory)][string]$DNS_ZONES_RG,
    [Parameter(Mandatory)][string]$PE_SUBNET_NAME,
    [Parameter(Mandatory)][string]$ACA_SUBNET_NAME,
    [Parameter(Mandatory)][string]$AGENT_SUBNET_NAME,
    [bool]$ENABLE_PRIVATE_LOG_ANALYTICS = $false
)

Write-Host "`n=== Phase 4: Configure azd Environment ===" -ForegroundColor Cyan

# Get VNet resource ID
$vnetId = az network vnet show -g $VNET_RESOURCE_GROUP -n $VNET_NAME --query id -o tsv

# ── 4.1 Create environment ──
Write-Host "Creating azd environment: $DEPLOY_NAME" -ForegroundColor Cyan
azd env new $DEPLOY_NAME --no-prompt
azd env select $DEPLOY_NAME

# ── 4.2 Set all variables ──
Write-Host "Setting environment variables..." -ForegroundColor Cyan

# Core
azd env set AZURE_SUBSCRIPTION_ID $SUBSCRIPTION_ID
azd env set AZURE_RESOURCE_GROUP $GPTRAG_RG

# Network isolation (Zero Trust)
azd env set NETWORK_ISOLATION true
azd env set USE_EXISTING_VNET true
azd env set EXISTING_VNET_RESOURCE_ID $vnetId
azd env set DEPLOY_SUBNETS false
azd env set SIDE_BY_SIDE true

# DNS — use existing zones, create DNS Zone Groups on PEs
azd env set POLICY_MANAGED_PRIVATE_DNS false
azd env set EXISTING_DNS_ZONES_RESOURCE_GROUP_NAME $DNS_ZONES_RG

# Subnets
azd env set PE_SUBNET_NAME $PE_SUBNET_NAME
azd env set ACA_ENVIRONMENT_SUBNET_NAME $ACA_SUBNET_NAME
azd env set AGENT_SUBNET_NAME $AGENT_SUBNET_NAME

# Identity
azd env set USE_UAI true

# App Config workaround (temporarily public during provisioning)
azd env set TEMP_PUBLIC_APP_CONFIG true

# Disabled features
azd env set DEPLOY_VM false
azd env set DEPLOY_AZURE_FIREWALL false
azd env set DEPLOY_ACR_TASK_AGENT_POOL false
azd env set ENABLE_PRIVATE_LOG_ANALYTICS "$($ENABLE_PRIVATE_LOG_ANALYTICS.ToString().ToLower())"

# ── 4.3 Verify ──
Write-Host "`n=== Environment Configuration ===" -ForegroundColor Cyan
azd env get-values

Write-Host "`n=== Phase 4 COMPLETE ===" -ForegroundColor Green
