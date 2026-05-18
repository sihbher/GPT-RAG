#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 1 — Environment Validation
.DESCRIPTION
    Verifies the Jumpbox is ready: tools installed, Azure/azd/gh authenticated,
    Docker running, VNet exists, resource group ready.
    STOPS if critical tools or auth are missing.
.PARAMETER SUBSCRIPTION_ID
    Azure subscription ID (inferred if not provided)
.PARAMETER VNET_RESOURCE_GROUP
    Resource group containing the VNet
.PARAMETER VNET_NAME
    Name of the existing VNet
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG resources
.PARAMETER LOCATION
    Azure region (inferred from VNet if not provided)
#>
param(
    [string]$SUBSCRIPTION_ID,
    [string]$VNET_RESOURCE_GROUP,
    [string]$VNET_NAME,
    [string]$GPTRAG_RG,
    [string]$LOCATION
)

Write-Host "`n=== Phase 1: Environment Validation ===" -ForegroundColor Cyan

# ── 1.1 Verify required tools ──
$requiredTools = @(
    @{ Name="git";      Cmd="git --version" }
    @{ Name="az";       Cmd="az version" }
    @{ Name="azd";      Cmd="azd version" }
    @{ Name="python";   Cmd="python --version" }
    @{ Name="docker";   Cmd="docker --version" }
)
$missingTools = @()
foreach ($tool in $requiredTools) {
    try { Invoke-Expression $tool.Cmd 2>$null | Out-Null }
    catch { $missingTools += $tool.Name }
    if ($LASTEXITCODE -ne 0) { $missingTools += $tool.Name }
}

if ($missingTools.Count -gt 0) {
    Write-Host "BLOCKED — Missing tools: $($missingTools -join ', ')" -ForegroundColor Red
    Write-Host "   Install with:" -ForegroundColor Yellow
    Write-Host "   winget install Git.Git Microsoft.AzureCLI Microsoft.Azd Python.Python.3.12 --accept-package-agreements" -ForegroundColor Gray
    Write-Host "   Docker Desktop must be installed separately (requires WSL2 + reboot)." -ForegroundColor Gray
    exit 1
}
Write-Host "All tools available" -ForegroundColor Green

# ── 1.2 Verify Azure CLI auth ──
$account = az account show -o json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in to Azure CLI. Requesting login..." -ForegroundColor Yellow
    Write-Host "   Please run:" -ForegroundColor Cyan
    Write-Host "   az login --tenant <TENANT_ID> --use-device-code" -ForegroundColor White
    Write-Host ""
    Write-Host "   (Use --use-device-code to avoid MFA popup issues on Jumpbox)" -ForegroundColor Gray
    exit 1
}

# ── 1.2.1 Verify token is NOT expired and MFA is not blocking ──
$tokenTest = az account get-access-token --query expiresOn -o tsv 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Azure CLI session expired or MFA required." -ForegroundColor Yellow
    Write-Host "   Please re-authenticate with device-code flow:" -ForegroundColor Cyan
    Write-Host "   az login --tenant $($account.tenantId) --use-device-code" -ForegroundColor White
    Write-Host ""
    Write-Host "   WHY: Device-code flow avoids MFA browser popups that fail on Jumpboxes" -ForegroundColor Gray
    Write-Host "   without GUI browser access or with Conditional Access policies." -ForegroundColor Gray
    exit 1
}
Write-Host "az CLI: $($account.name) (tenant: $($account.tenantId))" -ForegroundColor Green

# ── 1.3 Verify azd auth ──
$azdToken = azd auth token 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in to azd. Requesting login..." -ForegroundColor Yellow
    Write-Host "   Please run:" -ForegroundColor Cyan
    Write-Host "   azd auth login --use-device-code" -ForegroundColor White
    Write-Host ""
    Write-Host "   (Must use device-code to match az CLI auth method)" -ForegroundColor Gray
    exit 1
}
Write-Host "azd authenticated" -ForegroundColor Green

# ── 1.3.1 Verify git authentication (for private fork) ──
$gitAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in to GitHub CLI." -ForegroundColor Yellow
    Write-Host "   Please run:" -ForegroundColor Cyan
    Write-Host "   gh auth login" -ForegroundColor White
    Write-Host ""
    Write-Host "   (Required to clone the private GPT-RAG fork)" -ForegroundColor Gray
    exit 1
}
Write-Host "gh CLI authenticated" -ForegroundColor Green

# ── 1.3.2 Validate deployment won't be blocked by MFA ──
$armToken = az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or $armToken -match "AADSTS") {
    Write-Host "BLOCKED — ARM token acquisition failed (likely MFA/Conditional Access)" -ForegroundColor Red
    Write-Host "   The deployment will fail during azd provision." -ForegroundColor Yellow
    Write-Host "   Fix: Re-login with device-code (satisfies MFA):" -ForegroundColor Cyan
    Write-Host "   az login --tenant $($account.tenantId) --use-device-code" -ForegroundColor White
    Write-Host "   azd auth login --use-device-code" -ForegroundColor White
    exit 1
}
Write-Host "ARM token valid — no MFA blocking" -ForegroundColor Green

# ── 1.4 Set subscription ──
if ($SUBSCRIPTION_ID) {
    az account set --subscription $SUBSCRIPTION_ID
} else {
    $SUBSCRIPTION_ID = az account show --query id -o tsv
}
Write-Host "Subscription: $SUBSCRIPTION_ID" -ForegroundColor Green

# ── 1.5 Verify VNet exists ──
$vnetId = az network vnet show -g $VNET_RESOURCE_GROUP -n $VNET_NAME --query id -o tsv 2>$null
if (-not $vnetId) {
    Write-Host "BLOCKED — VNet '$VNET_NAME' not found in RG '$VNET_RESOURCE_GROUP'" -ForegroundColor Red
    exit 1
}
Write-Host "VNet: $vnetId" -ForegroundColor Green

# ── 1.6 Verify/Create GPT-RAG resource group ──
if ($GPTRAG_RG) {
    $rgExists = az group show -n $GPTRAG_RG --query name -o tsv 2>$null
    if (-not $rgExists) {
        Write-Host "Creating resource group: $GPTRAG_RG" -ForegroundColor Cyan
        az group create -n $GPTRAG_RG -l $LOCATION -o none
    }
    Write-Host "GPT-RAG RG: $GPTRAG_RG" -ForegroundColor Green
}

# ── 1.7 Verify Docker ──
docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker not running. Attempting to start..." -ForegroundColor Yellow
    & "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    Start-Sleep -Seconds 45
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BLOCKED — Docker failed to start" -ForegroundColor Red
        Write-Host "   Human must start Docker Desktop manually." -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "Docker running" -ForegroundColor Green

# ── 1.8 Force PATH refresh ──
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "`n=== Phase 1 COMPLETE ===" -ForegroundColor Green
