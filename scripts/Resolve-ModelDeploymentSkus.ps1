<#
.SYNOPSIS
    Materializes azd environment tokens nested inside the modelDeploymentList
    parameter so downstream tooling sees concrete values.

.DESCRIPTION
    azd and the AI Landing Zone preflight only resolve ${VAR=default} tokens on
    top-level string parameter values; tokens nested inside the
    modelDeploymentList array (e.g. sku.name) are passed through unresolved.
    This helper resolves those nested SKU tokens in the copied
    infra/main.parameters.json using the azd environment (falling back to the
    process environment, then the token default), so both the landing-zone
    preflight and the actual Bicep deployment receive the effective SKU.

    The root main.parameters.json keeps its ${VAR=default} tokens untouched, so
    the default (backward-compatible) behavior is preserved when no override is
    set. Only the discovered SKU token substrings are replaced textually; the
    rest of the file is left byte-for-byte intact.

.PARAMETER ParameterFile
    Path to the (already copied) infra/main.parameters.json to resolve in place.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ParameterFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $ParameterFile)) { return }

function Get-AzdEnvValues {
    $values = @{}
    if (-not (Get-Command azd -ErrorAction SilentlyContinue)) { return $values }
    try {
        $raw = & azd env get-values 2>$null
        if ($LASTEXITCODE -ne 0) { return $values }
        foreach ($line in $raw) {
            if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*"?(.*?)"?\s*$') {
                $values[$matches[1]] = $matches[2]
            }
        }
    }
    catch { return $values }
    return $values
}

function Resolve-TokenName {
    param([string]$Name, [string]$Default, [hashtable]$EnvValues)
    if ($EnvValues.ContainsKey($Name) -and -not [string]::IsNullOrEmpty($EnvValues[$Name])) {
        return $EnvValues[$Name]
    }
    $procVal = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrEmpty($procVal)) { return $procVal }
    return $Default
}

$raw = Get-Content -Path $ParameterFile -Raw
try {
    $json = $raw | ConvertFrom-Json
}
catch {
    Write-Host "Resolve-ModelDeploymentSkus: '$ParameterFile' is not valid JSON; skipping." -ForegroundColor Yellow
    return
}

$paramsProp = $json.PSObject.Properties['parameters']
if (-not $paramsProp) { return }
$mdlProp = $paramsProp.Value.PSObject.Properties['modelDeploymentList']
if (-not $mdlProp) { return }
$deployments = $mdlProp.Value.PSObject.Properties['value']
if (-not $deployments) { return }

$tokenRegex = [regex]'\$\{([A-Z0-9_]+)(?:=([^}]*))?\}'
$envValues = Get-AzdEnvValues
$replacements = @{}

foreach ($d in @($deployments.Value)) {
    if (-not $d) { continue }
    $skuProp = $d.PSObject.Properties['sku']
    if (-not $skuProp) { continue }
    $nameProp = $skuProp.Value.PSObject.Properties['name']
    if (-not $nameProp -or ($nameProp.Value -isnot [string])) { continue }

    $tokenStr = [string]$nameProp.Value
    $m = $tokenRegex.Match($tokenStr)
    if (-not $m.Success) { continue }

    $varName = $m.Groups[1].Value
    $default = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '' }
    $resolved = Resolve-TokenName -Name $varName -Default $default -EnvValues $envValues
    if (-not $replacements.ContainsKey($tokenStr)) { $replacements[$tokenStr] = $resolved }
}

if ($replacements.Count -eq 0) { return }

$out = $raw
foreach ($token in $replacements.Keys) {
    $out = $out.Replace($token, $replacements[$token])
}

if ($out -ne $raw) {
    Set-Content -Path $ParameterFile -Value $out -NoNewline -Encoding utf8
    $summary = ($replacements.GetEnumerator() | ForEach-Object { "$($_.Key) -> $($_.Value)" }) -join '; '
    Write-Host "Resolved model deployment SKU tokens in infra parameters: $summary" -ForegroundColor Cyan
}
