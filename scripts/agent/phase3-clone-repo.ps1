#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 3 — Clone Repository and Validate
.DESCRIPTION
    Clones the GPT-RAG fork, initializes the infra submodule,
    and validates that critical enterprise fixes are present.
.PARAMETER INSTANCE_ID
    Instance identifier (bot1, bot2, etc.)
.PARAMETER REPO_URL
    Git repository URL
.PARAMETER BRANCH
    Branch to clone
.PARAMETER WORK_DIR
    Working directory (defaults to ~/source/repos/gptrag-$INSTANCE_ID)
#>
param(
    [Parameter(Mandatory)][string]$INSTANCE_ID,
    [string]$REPO_URL = "https://github.com/sihbher/GPT-RAG",
    [string]$BRANCH = "tests/dns-test",
    [string]$WORK_DIR
)

if (-not $WORK_DIR) {
    $WORK_DIR = "$HOME\source\repos\gptrag-$INSTANCE_ID"
}

Write-Host "`n=== Phase 3: Clone Repository and Validate ===" -ForegroundColor Cyan

# ── 3.1 Clone ──
if (-not (Test-Path $WORK_DIR)) { New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null }
Set-Location $WORK_DIR

if (Test-Path ".git") {
    Write-Host "Repo exists — pulling latest from $BRANCH" -ForegroundColor Yellow
    git fetch origin
    git checkout $BRANCH
    git pull origin $BRANCH
} else {
    Write-Host "Cloning $REPO_URL branch $BRANCH" -ForegroundColor Cyan
    git clone --branch $BRANCH $REPO_URL .
}

# ── 3.2 Initialize infra submodule (MUST get latest from main) ──
Write-Host "Updating infra submodule..." -ForegroundColor Cyan
git submodule update --init --remote --recursive

# ── 3.3 Validate infra has required enterprise fixes ──
Write-Host "`nValidating enterprise fixes in infra/main.bicep..." -ForegroundColor Cyan
$checks = @(
    @{ Name="Fix 4: existingDnsZonesResourceGroupName param"; Pattern="param existingDnsZonesResourceGroupName" }
    @{ Name="Fix 4: _useExistingDnsZones var";                Pattern="var _useExistingDnsZones" }
    @{ Name="Fix 1: varPeSubnetId uses peSubnetName";         Pattern='\$\{peSubnetName\}' }
    @{ Name="Fix 3: baseSubnets uses concat";                 Pattern="var baseSubnets = concat" }
    @{ Name="Fix 5: tempPublicAppConfig param";               Pattern="param tempPublicAppConfig" }
    @{ Name="Fix 7: enableAnalyticalStorage false";           Pattern="enableAnalyticalStorage: false" }
)

$allGood = $true
foreach ($c in $checks) {
    $found = Select-String -Path infra/main.bicep -Pattern $c.Pattern -Quiet
    if ($found) {
        Write-Host "  [OK] $($c.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($c.Name) — NOT FOUND" -ForegroundColor Red
        $allGood = $false
    }
}

if (-not $allGood) {
    Write-Host "`nInfra submodule stale — re-cloning from main..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force infra
    git clone --depth 1 --branch main https://github.com/sihbher/bicep-ptn-aiml-landing-zone.git infra
    Write-Host "Infra submodule refreshed" -ForegroundColor Green
}

# ── 3.4 Show version info ──
Write-Host "`nRepo state:" -ForegroundColor Cyan
Write-Host "  GPT-RAG: $(git log --oneline -1)" -ForegroundColor Gray
Write-Host "  Infra:   $(git -C infra log --oneline -1)" -ForegroundColor Gray
Write-Host "  WorkDir: $WORK_DIR" -ForegroundColor Gray

Write-Host "`n=== Phase 3 COMPLETE ===" -ForegroundColor Green
