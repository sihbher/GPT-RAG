#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 6 — Validate DNS Resolution
.DESCRIPTION
    Ensures all Private Endpoints resolve to private IPs.
    This is the most critical validation step.
    Auto-fixes by running link-dns-zones.ps1 if available.
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG resources
.PARAMETER VNET_NAME
    Name of the VNet
.PARAMETER DNS_ZONES_RG
    Resource group for Private DNS Zones
#>
param(
    [Parameter(Mandatory)][string]$GPTRAG_RG,
    [string]$VNET_NAME,
    [string]$DNS_ZONES_RG
)

Write-Host "`n=== Phase 6: DNS Validation ===" -ForegroundColor Cyan

# ── 6.1 Flush DNS ──
ipconfig /flushdns | Out-Null
Write-Host "DNS cache flushed" -ForegroundColor Gray

# ── 6.2 Get all PE FQDNs ──
$peFqdns = az network private-endpoint list -g $GPTRAG_RG --query "[].customDnsConfigs[].fqdn" -o tsv
if (-not $peFqdns) {
    Write-Host "No Private Endpoints found in $GPTRAG_RG" -ForegroundColor Red
    Write-Host "   Likely azd provision failed. Check Azure Portal." -ForegroundColor Yellow
    exit 1
}

$fqdnList = $peFqdns -split "`n" | Where-Object { $_ -ne '' }
Write-Host "Found $($fqdnList.Count) PE FQDNs to validate" -ForegroundColor Cyan

# ── 6.3 Validate resolution ──
$failures = @()
$successes = 0
foreach ($fqdn in $fqdnList) {
    $result = Resolve-DnsName $fqdn -ErrorAction SilentlyContinue
    $privateIp = $result | Where-Object { $_.QueryType -eq 'A' -and $_.IP4Address -match '^10\.' }
    if ($privateIp) {
        Write-Host "  [OK] $fqdn -> $($privateIp.IP4Address)" -ForegroundColor Green
        $successes++
    } else {
        Write-Host "  [FAIL] $fqdn — NOT resolving to private IP" -ForegroundColor Red
        $failures += $fqdn
    }
}

Write-Host "`nResults: $successes OK, $($failures.Count) FAILED" -ForegroundColor Cyan

# ── 6.4 Auto-fix if failures ──
if ($failures.Count -gt 0 -and $VNET_NAME -and $DNS_ZONES_RG) {
    Write-Host "`n$($failures.Count) DNS failures. Attempting auto-fix..." -ForegroundColor Yellow

    $linkScript = Join-Path $PSScriptRoot "..\link-dns-zones.ps1"
    if (Test-Path $linkScript) {
        & $linkScript -ResourceGroup $GPTRAG_RG -VNetName $VNET_NAME -DnsZoneResourceGroup $DNS_ZONES_RG
    } else {
        Write-Host "   link-dns-zones.ps1 not found at: $linkScript" -ForegroundColor Yellow
        Write-Host "   Manual fix required: link DNS zones to VNet in Azure Portal" -ForegroundColor Yellow
        exit 1
    }

    # Re-validate after fix
    Start-Sleep -Seconds 15
    ipconfig /flushdns | Out-Null
    $stillFailing = @()
    foreach ($fqdn in $failures) {
        $result = Resolve-DnsName $fqdn -ErrorAction SilentlyContinue
        $privateIp = $result | Where-Object { $_.QueryType -eq 'A' -and $_.IP4Address -match '^10\.' }
        if (-not $privateIp) { $stillFailing += $fqdn }
    }

    if ($stillFailing.Count -gt 0) {
        Write-Host "`nBLOCKED — DNS still failing for:" -ForegroundColor Red
        $stillFailing | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
        Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
        Write-Host "  - Returns public IP → Zone not linked to VNet or A-record missing" -ForegroundColor Gray
        Write-Host "  - Returns NXDOMAIN → Zone doesn't exist" -ForegroundColor Gray
        Write-Host "  - Wrong private IP → Duplicate zone with stale record" -ForegroundColor Gray
        exit 1
    }
    Write-Host "All DNS failures resolved after auto-fix!" -ForegroundColor Green
}
elseif ($failures.Count -gt 0) {
    Write-Host "`nBLOCKED — Cannot auto-fix without VNET_NAME and DNS_ZONES_RG" -ForegroundColor Red
    Write-Host "   Provide these parameters or fix DNS manually." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nAll Private Endpoints resolve to private IPs" -ForegroundColor Green
Write-Host "`n=== Phase 6 COMPLETE ===" -ForegroundColor Green
