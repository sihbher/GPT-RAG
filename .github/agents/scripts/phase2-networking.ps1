#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 2 — Networking Setup (Conditional)
.DESCRIPTION
    Creates subnets and/or DNS zones if they don't already exist.
    Only runs if CREATE_SUBNETS or CREATE_DNS_ZONES are true.
.PARAMETER VNET_RESOURCE_GROUP
    Resource group containing the VNet
.PARAMETER VNET_NAME
    Name of the existing VNet
.PARAMETER DNS_ZONES_RG
    Resource group for Private DNS Zones
.PARAMETER INSTANCE_ID
    Instance identifier (bot1, bot2, etc.)
.PARAMETER PE_SUBNET_NAME
    Name for the Private Endpoints subnet
.PARAMETER ACA_SUBNET_NAME
    Name for the Container Apps Environment subnet
.PARAMETER AGENT_SUBNET_NAME
    Name for the Agent subnet
.PARAMETER PE_SUBNET_PREFIX
    CIDR for PE subnet (e.g., 10.3.50.0/26)
.PARAMETER ACA_SUBNET_PREFIX
    CIDR for ACA subnet (e.g., 10.3.51.0/24)
.PARAMETER AGENT_SUBNET_PREFIX
    CIDR for Agent subnet (e.g., 10.3.52.0/24)
.PARAMETER CREATE_SUBNETS
    Whether to create subnets
.PARAMETER CREATE_DNS_ZONES
    Whether to create DNS zones
.PARAMETER LOCATION
    Azure region (for region-specific DNS zone)
#>
param(
    [Parameter(Mandatory)][string]$VNET_RESOURCE_GROUP,
    [Parameter(Mandatory)][string]$VNET_NAME,
    [Parameter(Mandatory)][string]$DNS_ZONES_RG,
    [Parameter(Mandatory)][string]$INSTANCE_ID,
    [string]$PE_SUBNET_NAME = "snet-pe-$INSTANCE_ID",
    [string]$ACA_SUBNET_NAME = "snet-aca-$INSTANCE_ID",
    [string]$AGENT_SUBNET_NAME = "snet-agent-$INSTANCE_ID",
    [string]$PE_SUBNET_PREFIX = "10.3.50.0/26",
    [string]$ACA_SUBNET_PREFIX = "10.3.51.0/24",
    [string]$AGENT_SUBNET_PREFIX = "10.3.52.0/24",
    [bool]$CREATE_SUBNETS = $false,
    [bool]$CREATE_DNS_ZONES = $false,
    [string]$LOCATION = "swedencentral"
)

Write-Host "`n=== Phase 2: Networking Setup ===" -ForegroundColor Cyan

$vnetId = az network vnet show -g $VNET_RESOURCE_GROUP -n $VNET_NAME --query id -o tsv

# ── 2.1 Create Subnets ──
if ($CREATE_SUBNETS) {
    Write-Host "Creating subnets for instance: $INSTANCE_ID" -ForegroundColor Cyan
    $existingSubs = az network vnet subnet list -g $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME --query "[].name" -o tsv

    # Private Endpoints subnet
    if ($existingSubs -notcontains $PE_SUBNET_NAME) {
        Write-Host "Creating: $PE_SUBNET_NAME ($PE_SUBNET_PREFIX)" -ForegroundColor Green
        az network vnet subnet create -g $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME `
            --name $PE_SUBNET_NAME --address-prefix $PE_SUBNET_PREFIX `
            --service-endpoints "Microsoft.AzureCosmosDB" `
            --private-endpoint-network-policies Disabled
    } else {
        Write-Host "Exists: $PE_SUBNET_NAME" -ForegroundColor Yellow
    }

    # Container Apps Environment subnet
    if ($existingSubs -notcontains $ACA_SUBNET_NAME) {
        Write-Host "Creating: $ACA_SUBNET_NAME ($ACA_SUBNET_PREFIX)" -ForegroundColor Green
        az network vnet subnet create -g $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME `
            --name $ACA_SUBNET_NAME --address-prefix $ACA_SUBNET_PREFIX `
            --delegations "Microsoft.App/environments" `
            --service-endpoints "Microsoft.AzureCosmosDB"
    } else {
        Write-Host "Exists: $ACA_SUBNET_NAME" -ForegroundColor Yellow
    }

    # Agent subnet
    if ($existingSubs -notcontains $AGENT_SUBNET_NAME) {
        Write-Host "Creating: $AGENT_SUBNET_NAME ($AGENT_SUBNET_PREFIX)" -ForegroundColor Green
        az network vnet subnet create -g $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME `
            --name $AGENT_SUBNET_NAME --address-prefix $AGENT_SUBNET_PREFIX `
            --delegations "Microsoft.App/environments" `
            --service-endpoints "Microsoft.CognitiveServices"
    } else {
        Write-Host "Exists: $AGENT_SUBNET_NAME" -ForegroundColor Yellow
    }

    # Verify
    az network vnet subnet list -g $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME `
        --query "[?contains(name,'$INSTANCE_ID')].{Name:name,Prefix:addressPrefix}" -o table
} else {
    Write-Host "Skipping subnet creation (CREATE_SUBNETS=false)" -ForegroundColor Gray
}

# ── 2.2 Create Private DNS Zones ──
if ($CREATE_DNS_ZONES) {
    Write-Host "`nCreating Private DNS Zones in $DNS_ZONES_RG" -ForegroundColor Cyan
    $dnsZones = @(
        "privatelink.openai.azure.com",
        "privatelink.cognitiveservices.azure.com",
        "privatelink.services.ai.azure.com",
        "privatelink.search.windows.net",
        "privatelink.documents.azure.com",
        "privatelink.blob.core.windows.net",
        "privatelink.file.core.windows.net",
        "privatelink.queue.core.windows.net",
        "privatelink.table.core.windows.net",
        "privatelink.vaultcore.azure.net",
        "privatelink.azconfig.io",
        "privatelink.azurecr.io",
        "privatelink.azurewebsites.net",
        "privatelink.monitor.azure.com",
        "privatelink.oms.opinsights.azure.com",
        "privatelink.ods.opinsights.azure.com",
        "privatelink.agentsvc.azure-automation.net",
        "privatelink.$LOCATION.azurecontainerapps.io"
    )

    foreach ($zone in $dnsZones) {
        $exists = az network private-dns zone show -g $DNS_ZONES_RG -n $zone --query name -o tsv 2>$null
        if (-not $exists) {
            Write-Host "Creating zone: $zone" -ForegroundColor Green
            az network private-dns zone create -g $DNS_ZONES_RG -n $zone -o none
        }

        # Link to VNet if not already linked
        $links = az network private-dns link vnet list -g $DNS_ZONES_RG -z $zone --query "[].virtualNetwork.id" -o tsv 2>$null
        if ($links -notmatch $VNET_NAME) {
            $linkName = "link-$($zone -replace '\.', '-')"
            Write-Host "Linking: $zone -> $VNET_NAME" -ForegroundColor Green
            az network private-dns link vnet create -g $DNS_ZONES_RG -z $zone `
                -n $linkName --virtual-network $vnetId --registration-enabled false -o none
        }
    }
    Write-Host "All 18 DNS zones ready and linked" -ForegroundColor Green
} else {
    Write-Host "Skipping DNS zone creation (CREATE_DNS_ZONES=false)" -ForegroundColor Gray
}

Write-Host "`n=== Phase 2 COMPLETE ===" -ForegroundColor Green
