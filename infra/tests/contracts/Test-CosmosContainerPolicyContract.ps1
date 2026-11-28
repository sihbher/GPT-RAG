<#
.SYNOPSIS
    Validates that Cosmos SQL containers never send a null vectorEmbeddingPolicy.

.DESCRIPTION
    The Cosmos DB RP rejects an explicit "vectorEmbeddingPolicy": null with
    "The Vector Embedding Policy has an invalid payload", so containers without
    a vector policy (the default) could not be created. The test compiles
    main.bicep and proves that:
      - vectorEmbeddingPolicy is only emitted inside the conditional branch;
      - no unconditional vectorEmbeddingPolicy property remains;
      - partition key normalization is unchanged; and
      - the bounded inverse rejects a mutated container payload.
    Offline evidence only; it does not prove deployed behavior.
#>

[CmdletBinding()]
param(
    [string]$MainFile = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'bicep/main.bicep')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScopedResourceGroupNormalization.ps1')
$compiledFile = Join-Path ([System.IO.Path]::GetTempPath()) "cosmos-container-policy-contract-$([guid]::NewGuid()).json"
$script:checks = 0

function Assert-Contract {
    param([Parameter(Mandatory)] [bool]$Condition, [Parameter(Mandatory)] [string]$Message)
    if (-not $Condition) { throw "Cosmos container policy contract failed: $Message" }
    $script:checks++
}

function Assert-Rejected {
    param([Parameter(Mandatory)] [string]$Message, [Parameter(Mandatory)] [scriptblock]$Action)
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true }
    Assert-Contract $rejected $Message
}

try {
    & az bicep build --file $MainFile --outfile $compiledFile
    if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed: $LASTEXITCODE" }
    $raw = Get-Content -LiteralPath $compiledFile -Raw
    $t = $raw | ConvertFrom-Json -AsHashtable -Depth 100

    $containers = $t.resources.cosmosSqlDatabase.properties.template.resources.sqlContainers
    Assert-Contract ($null -ne $containers) 'cosmosSqlDatabase deploys sqlContainers'
    $resource = $containers.properties.resource
    Assert-Contract ($resource -is [string]) 'container resource is a single conditional expression'
    $policyBranch = "if(empty(coalesce(tryGet(parameters('containers')[copyIndex()], 'vectorEmbeddingPolicy'), createObject())), createObject(), createObject('vectorEmbeddingPolicy', parameters('containers')[copyIndex()].vectorEmbeddingPolicy))"
    Assert-Contract ($resource.StartsWith('[union(createObject(') -and $resource.EndsWith(", $policyBranch)]")) 'vectorEmbeddingPolicy is added only by the conditional union branch'
    Assert-Contract (([regex]::Matches($resource, "'vectorEmbeddingPolicy'")).Count -eq 2) 'no unconditional vectorEmbeddingPolicy property is emitted'
    Assert-Contract ($resource.Contains("'paths', map(parameters('containers')[copyIndex()].paths, lambda('path', if(startsWith(lambdaVariables('path'), '/'), lambdaVariables('path'), format('/{0}', lambdaVariables('path')))))")) 'partition key paths keep the leading-slash normalization'

    $null = ConvertTo-PreCosmosContainerPolicyGraph ($raw | ConvertFrom-Json -AsHashtable -Depth 100)
    $script:checks++
    $mutated = $raw | ConvertFrom-Json -AsHashtable -Depth 100
    $mutated.resources.cosmosSqlDatabase.properties.template.resources.sqlContainers.properties.resource = "$resource "
    Assert-Rejected 'bounded inverse rejects a mutated container payload' { ConvertTo-PreCosmosContainerPolicyGraph $mutated }

    Write-Host "Cosmos container policy contract passed: $script:checks checks (offline, not deployed parity)." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $compiledFile -Force -ErrorAction SilentlyContinue
}
