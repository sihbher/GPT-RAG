#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 7 — Deploy Applications
.DESCRIPTION
    Builds container images and deploys to Container Apps via azd deploy.
    Requires Docker to be running.
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG resources (for validation)
#>
param(
    [string]$GPTRAG_RG
)

Write-Host "`n=== Phase 7: Deploy Applications ===" -ForegroundColor Cyan

# ── 7.1 Verify Docker is running ──
docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "BLOCKED — Docker not running." -ForegroundColor Red
    Write-Host "   Human must start Docker Desktop manually." -ForegroundColor Yellow
    exit 1
}
Write-Host "Docker running" -ForegroundColor Green

# ── 7.2 Run azd deploy ──
Write-Host "Building images and deploying. Estimated time: 10-25 minutes." -ForegroundColor Gray
azd deploy

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nWARNING — azd deploy exited with code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "  - MFA blocks ACR association → Fix 6 handles this (CLI fallback)" -ForegroundColor Gray
    Write-Host "  - Image push timeout → Re-run azd deploy" -ForegroundColor Gray
    Write-Host "  - Container App NOT-READY → Check Fix 3 (USE_UAI), Fix 8 (App Config collision)" -ForegroundColor Gray
    exit 1
}

Write-Host "`n=== Phase 7 COMPLETE ===" -ForegroundColor Green
