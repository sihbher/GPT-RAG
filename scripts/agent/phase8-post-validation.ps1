#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 8 — Post-Deployment Validation
.DESCRIPTION
    Verifies Container Apps are running, PEs are approved,
    UAI is injected, and ACR is associated.
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG resources
#>
param(
    [Parameter(Mandatory)][string]$GPTRAG_RG
)

Write-Host "`n=== Phase 8: Post-Deployment Validation ===" -ForegroundColor Cyan

# ── 8.1 Container Apps status ──
Write-Host "`nContainer Apps:" -ForegroundColor Cyan
$apps = az containerapp list -g $GPTRAG_RG --query "[].{Name:name,FQDN:properties.configuration.ingress.fqdn}" -o json | ConvertFrom-Json

if (-not $apps -or $apps.Count -eq 0) {
    Write-Host "  No Container Apps found in $GPTRAG_RG" -ForegroundColor Red
    exit 1
}

foreach ($app in $apps) {
    $revisions = az containerapp revision list -g $GPTRAG_RG -n $app.Name --query "[?properties.active].properties.runningState" -o tsv
    $status = if ($revisions -match "Running") { "Running" } else { $revisions }
    if ($status -eq "Running") {
        Write-Host "  [OK] $($app.Name) — $status" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] $($app.Name) — $status" -ForegroundColor Yellow
    }
}

# ── 8.2 PE Approval status ──
Write-Host "`nPrivate Endpoints:" -ForegroundColor Cyan
$peList = az network private-endpoint list -g $GPTRAG_RG `
    --query "[].{Name:name,Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o json | ConvertFrom-Json
$pending = $peList | Where-Object { $_.Status -ne "Approved" }
if ($pending.Count -gt 0) {
    Write-Host "  PEs not approved:" -ForegroundColor Yellow
    $pending | ForEach-Object { Write-Host "    - $($_.Name): $($_.Status)" -ForegroundColor Yellow }
} else {
    Write-Host "  [OK] All $($peList.Count) Private Endpoints approved" -ForegroundColor Green
}

# ── 8.3 Check UAI injection (Fix 3 verification) ──
Write-Host "`nUAI Verification:" -ForegroundColor Cyan
$frontendApp = $apps | Where-Object { $_.Name -match "frontend" }
if ($frontendApp) {
    $clientId = az containerapp show -n $frontendApp.Name -g $GPTRAG_RG `
        --query "properties.template.containers[0].env[?name=='AZURE_CLIENT_ID'].value | [0]" -o tsv
    if ($clientId -and $clientId -ne "*") {
        Write-Host "  [OK] AZURE_CLIENT_ID injected: $clientId" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] AZURE_CLIENT_ID missing or invalid — check Fix 3 in fixes.md" -ForegroundColor Yellow
    }
}

# ── 8.4 Check ACR association (Fix 6 verification) ──
Write-Host "`nACR Association:" -ForegroundColor Cyan
$orchApp = $apps | Where-Object { $_.Name -match "orchestrator" }
if ($orchApp) {
    $registry = az containerapp registry list -n $orchApp.Name -g $GPTRAG_RG --query "[].server" -o tsv
    if ($registry) {
        Write-Host "  [OK] ACR registered: $registry" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] ACR not associated with orchestrator — check Fix 6" -ForegroundColor Yellow
    }
}

# ── Summary ──
Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  GPT-RAG Infrastructure Deployed" -ForegroundColor Green
Write-Host "  Resource Group: $GPTRAG_RG" -ForegroundColor Gray
Write-Host "  Container Apps: $($apps.Count)" -ForegroundColor Gray
Write-Host "  Private Endpoints: $($peList.Count)" -ForegroundColor Gray
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n=== Phase 8 COMPLETE ===" -ForegroundColor Green
