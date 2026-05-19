#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 0 — Initialize: Create or Review environment
.DESCRIPTION
    Entry point for the GPT-RAG VNet Deployer agent.
    Asks the user whether to CREATE a new environment or REVIEW an existing one.
    Both paths produce a standardized .env file as the source of truth.
.PARAMETER Mode
    "create" or "review". If omitted, prompts the user.
.PARAMETER InstanceName
    Short name for the instance (e.g., "poc1", "staging"). Used in paths and labels.
.PARAMETER ResourceGroup
    (Review mode) Resource group to discover existing resources from.
.PARAMETER EnvFilePath
    Override output path for the .env file. Default: logs/{instance}/.env
#>
param(
    [ValidateSet("create","review","")]
    [string]$Mode = "",
    [string]$InstanceName = "",
    [string]$ResourceGroup = "",
    [string]$EnvFilePath = ""
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# Load shared modules
. "$scriptRoot\lib\logger.ps1"
. "$scriptRoot\lib\env-generator.ps1"
. "$scriptRoot\lib\change-tracker.ps1"

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  GPT-RAG VNet Deployer — Phase 0: Initialize    ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ── 0.1 Determine mode ──
if (-not $Mode) {
    Write-Host "What would you like to do?" -ForegroundColor White
    Write-Host "  [A] Create a new GPT-RAG environment" -ForegroundColor Green
    Write-Host "  [B] Review an existing GPT-RAG environment" -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "Select (A/B)"
    $Mode = switch ($choice.ToUpper()) {
        "A" { "create" }
        "B" { "review" }
        default { Write-Host "Invalid choice. Exiting." -ForegroundColor Red; exit 1 }
    }
}

Write-AgentLog -Phase "phase0" -Action "mode-selected" -Message "Mode: $Mode"

# ── 0.2 Get instance name ──
if (-not $InstanceName) {
    $InstanceName = Read-Host "Instance name (e.g., poc1, staging, prod)"
    if (-not $InstanceName) {
        Write-Host "Instance name is required." -ForegroundColor Red
        exit 1
    }
}

# ── 0.3 Setup log directory ──
$logsDir = Join-Path (Split-Path $scriptRoot -Parent | Split-Path -Parent) "logs" $InstanceName
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
if (-not $EnvFilePath) {
    $EnvFilePath = Join-Path $logsDir ".env"
}

# Initialize change tracker
Initialize-ChangeTracker -OutputDir $logsDir -InstanceName $InstanceName

# ── 0.4 Execute based on mode ──
switch ($Mode) {
    "create" {
        Write-Host "`n── Creating new environment: $InstanceName ──`n" -ForegroundColor Cyan

        # Collect parameters
        $params = @{}
        $params.InstanceName = $InstanceName

        if (-not $params.SubscriptionId) {
            $currentSub = az account show --query "{id:id,name:name}" -o json 2>$null | ConvertFrom-Json
            if ($currentSub) {
                Write-Host "Current subscription: $($currentSub.name) ($($currentSub.id))" -ForegroundColor Gray
                $useCurrent = Read-Host "Use this subscription? (Y/n)"
                if ($useCurrent -ne "n") {
                    $params.SubscriptionId = $currentSub.id
                } else {
                    $params.SubscriptionId = Read-Host "Subscription ID"
                }
            } else {
                $params.SubscriptionId = Read-Host "Subscription ID"
            }
        }

        $params.TenantId = az account show --query tenantId -o tsv 2>$null
        $params.Location = Read-Host "Azure region (e.g., swedencentral, eastus2)"

        Write-Host "`nNetworking:" -ForegroundColor Cyan
        $params.VNetRG = Read-Host "  VNet resource group"
        $params.VNetName = Read-Host "  VNet name"
        $params.PESubnet = Read-Host "  Private Endpoint subnet name"
        $params.DnsZonesRG = Read-Host "  DNS Zones resource group (Enter if same as VNet RG)"
        if (-not $params.DnsZonesRG) { $params.DnsZonesRG = $params.VNetRG }

        # Capture initial state BEFORE any changes
        Write-Host "`nCapturing initial state snapshot..." -ForegroundColor Cyan
        $snapshot = Get-InitialStateSnapshot -Params $params
        $snapshotPath = Join-Path $logsDir "${timestamp}_initial_state.json"
        $snapshot | ConvertTo-Json -Depth 10 | Set-Content $snapshotPath -Encoding UTF8
        Write-AgentLog -Phase "phase0" -Action "snapshot-captured" -Resource $snapshotPath -Message "Initial state saved"
        Write-Host "  Saved: $snapshotPath" -ForegroundColor Green

        # Generate .env with known parameters (resources don't exist yet)
        $envContent = New-EnvFileContent -Mode "create" -Params $params
        Set-Content -Path $EnvFilePath -Value $envContent -Encoding UTF8
        Write-Host "`n.env generated: $EnvFilePath" -ForegroundColor Green

        Write-Host "`nNext: Run phase1-validate.ps1 to verify prerequisites" -ForegroundColor Yellow
    }

    "review" {
        Write-Host "`n── Reviewing existing environment: $InstanceName ──`n" -ForegroundColor Cyan

        # Get resource group
        if (-not $ResourceGroup) {
            $ResourceGroup = Read-Host "Resource group containing GPT-RAG resources"
        }

        # Discover and validate
        Write-Host "Discovering resources in $ResourceGroup..." -ForegroundColor Cyan
        $discovered = Get-ExistingEnvironment -ResourceGroup $ResourceGroup

        if (-not $discovered) {
            Write-Host "No GPT-RAG resources found in $ResourceGroup" -ForegroundColor Red
            exit 1
        }

        # Health checks
        Write-Host "`nRunning health checks..." -ForegroundColor Cyan
        $health = Test-EnvironmentHealth -Discovered $discovered
        foreach ($check in $health) {
            $color = switch ($check.Status) {
                "OK"   { "Green" }
                "WARN" { "Yellow" }
                "FAIL" { "Red" }
            }
            Write-Host "  [$($check.Status)] $($check.Name): $($check.Detail)" -ForegroundColor $color
        }

        # Generate .env from discovered state
        $envContent = New-EnvFileContent -Mode "review" -Discovered $discovered -Health $health
        Set-Content -Path $EnvFilePath -Value $envContent -Encoding UTF8
        Write-Host "`n.env generated: $EnvFilePath" -ForegroundColor Green

        # Show summary
        Write-Host "`n── Environment Summary ──" -ForegroundColor Cyan
        Write-Host "  Resource Group:  $ResourceGroup" -ForegroundColor White
        Write-Host "  Container Apps:  $($discovered.ContainerApps.Count)" -ForegroundColor White
        Write-Host "  Search Index:    $($discovered.SearchIndex ?? 'none')" -ForegroundColor White
        Write-Host "  Index Chunks:    $($discovered.IndexChunkCount ?? 0)" -ForegroundColor White
        Write-Host "  App Config:      $($discovered.AppConfigEndpoint)" -ForegroundColor White

        $failCount = ($health | Where-Object { $_.Status -eq "FAIL" }).Count
        if ($failCount -gt 0) {
            Write-Host "`n  ⚠ $failCount health check(s) FAILED — see above" -ForegroundColor Red
        } else {
            Write-Host "`n  ✓ All health checks passed" -ForegroundColor Green
        }
    }
}

# ── 0.5 Output next steps ──
Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  .env file ready: $EnvFilePath" -ForegroundColor Cyan
Write-Host   "║  " -ForegroundColor Cyan
Write-Host   "║  Available actions:" -ForegroundColor Cyan
Write-Host   "║    • Deploy      → phase7-deploy.ps1" -ForegroundColor White
Write-Host   "║    • Upload docs → phase9-functional-test.ps1" -ForegroundColor White
Write-Host   "║    • Test        → phase9-functional-test.ps1" -ForegroundColor White
Write-Host   "║    • Scale       → (manual / agent-assisted)" -ForegroundColor White
Write-Host   "║    • Rollback    → lib/change-tracker.ps1 -Rollback" -ForegroundColor White
Write-Host   "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-AgentLog -Phase "phase0" -Action "completed" -Message "Mode=$Mode, EnvFile=$EnvFilePath"
