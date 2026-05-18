#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 5 — Provision Infrastructure
.DESCRIPTION
    Runs azd provision to deploy ~54 Azure resources.
    IMPORTANT: The agent MUST get user approval before running this script.
    This creates billable resources immediately.
.PARAMETER DEPLOY_NAME
    azd environment name
.PARAMETER SUBSCRIPTION_ID
    Azure subscription ID
.PARAMETER LOCATION
    Azure region
.PARAMETER INSTANCE_ID
    Instance identifier
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG
.PARAMETER VNET_NAME
    VNet name (for display)
.PARAMETER VNET_RESOURCE_GROUP
    VNet resource group (for display)
.PARAMETER DNS_ZONES_RG
    DNS zones resource group (for display)
.PARAMETER PE_SUBNET_NAME
    PE subnet name (for display)
.PARAMETER PE_SUBNET_PREFIX
    PE subnet CIDR (for display)
.PARAMETER ACA_SUBNET_NAME
    ACA subnet name (for display)
.PARAMETER ACA_SUBNET_PREFIX
    ACA subnet CIDR (for display)
.PARAMETER AGENT_SUBNET_NAME
    Agent subnet name (for display)
.PARAMETER AGENT_SUBNET_PREFIX
    Agent subnet CIDR (for display)
.PARAMETER CREATE_SUBNETS
    Whether subnets were created (for display)
.PARAMETER CREATE_DNS_ZONES
    Whether DNS zones were created (for display)
.PARAMETER ENABLE_PRIVATE_LOG_ANALYTICS
    Private LA flag (for display)
.PARAMETER SkipConfirmation
    Skip the confirmation prompt (for automation)
#>
param(
    [Parameter(Mandatory)][string]$DEPLOY_NAME,
    [Parameter(Mandatory)][string]$SUBSCRIPTION_ID,
    [Parameter(Mandatory)][string]$LOCATION,
    [Parameter(Mandatory)][string]$INSTANCE_ID,
    [Parameter(Mandatory)][string]$GPTRAG_RG,
    [Parameter(Mandatory)][string]$VNET_NAME,
    [Parameter(Mandatory)][string]$VNET_RESOURCE_GROUP,
    [Parameter(Mandatory)][string]$DNS_ZONES_RG,
    [string]$PE_SUBNET_NAME,
    [string]$PE_SUBNET_PREFIX,
    [string]$ACA_SUBNET_NAME,
    [string]$ACA_SUBNET_PREFIX,
    [string]$AGENT_SUBNET_NAME,
    [string]$AGENT_SUBNET_PREFIX,
    [bool]$CREATE_SUBNETS = $false,
    [bool]$CREATE_DNS_ZONES = $false,
    [bool]$ENABLE_PRIVATE_LOG_ANALYTICS = $false,
    [switch]$SkipConfirmation
)

Write-Host "`n=== Phase 5: Provision Infrastructure ===" -ForegroundColor Cyan

# ── 5.0 Pre-Provision Confirmation ──
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          PRE-PROVISION CONFIRMATION — REVIEW CAREFULLY          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n── Core ──" -ForegroundColor Yellow
Write-Host "  Subscription:      $SUBSCRIPTION_ID"
Write-Host "  Location:          $LOCATION"
Write-Host "  Instance ID:       $INSTANCE_ID"
Write-Host "  Resource Group:    $GPTRAG_RG"
Write-Host "  Environment Name:  $DEPLOY_NAME"

Write-Host "`n── Networking ──" -ForegroundColor Yellow
Write-Host "  VNet:              $VNET_NAME (RG: $VNET_RESOURCE_GROUP)"
Write-Host "  DNS Zones RG:      $DNS_ZONES_RG"
Write-Host "  PE Subnet:         $PE_SUBNET_NAME ($PE_SUBNET_PREFIX)"
Write-Host "  ACA Subnet:        $ACA_SUBNET_NAME ($ACA_SUBNET_PREFIX)"
Write-Host "  Agent Subnet:      $AGENT_SUBNET_NAME ($AGENT_SUBNET_PREFIX)"

Write-Host "`n── Flags ──" -ForegroundColor Yellow
Write-Host "  Create Subnets:    $CREATE_SUBNETS"
Write-Host "  Create DNS Zones:  $CREATE_DNS_ZONES"
Write-Host "  Private LA:        $ENABLE_PRIVATE_LOG_ANALYTICS"
Write-Host "  Side-by-Side:      true"
Write-Host "  USE_UAI:           true"

Write-Host "`n── What Will Happen ──" -ForegroundColor Yellow
Write-Host "  * ~54 Azure resources will be created in RG: $GPTRAG_RG"
Write-Host "  * Estimated cost: ~`$15-30/day (depending on model capacity)"
Write-Host "  * Estimated time: 15-30 minutes"
Write-Host "  * Resources are billable immediately upon creation"

Write-Host "`n══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan

if (-not $SkipConfirmation) {
    $response = Read-Host "`nDo you approve running azd provision with these settings? [Y/n]"
    if ($response -and $response -notin @('Y','y','yes','Yes','YES')) {
        Write-Host "Provisioning cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

# ── 5.1 Execute Provision ──
Write-Host "`nStarting azd provision..." -ForegroundColor Cyan
Write-Host "Deploying ~54 resources. Estimated time: 15-30 minutes." -ForegroundColor Gray

# Auto-answer the VNet prompt by piping 'Y' to stdin
"Y" | azd provision

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nWARNING — azd provision exited with code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "  - Token timeout on App Config → Re-run azd provision" -ForegroundColor Gray
    Write-Host "  - Quota exceeded → Check fixes.md, adjust model capacity" -ForegroundColor Gray
    Write-Host "  - Subnet CIDR conflict → Pick non-overlapping ranges" -ForegroundColor Gray
    exit 1
}

Write-Host "`n=== Phase 5 COMPLETE ===" -ForegroundColor Green
