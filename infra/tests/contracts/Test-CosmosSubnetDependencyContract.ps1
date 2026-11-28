<#
.SYNOPSIS
    Validates that the Cosmos DB account waits for reused-VNet subnet writes.

.DESCRIPTION
    With useExistingVNet the subnets are written by the virtualNetworkSubnets
    module while the virtualNetwork module is not deployed. The Cosmos DB
    account registers its virtual network rules with the VNet, and the network
    resource provider rejects that with SubnetsNotProvisioned while any subnet
    write is in flight, leaving the account in a Failed state. The test compiles
    main.bicep and proves that:
      - cosmosDBAccount depends on virtualNetworkSubnets and virtualNetwork;
      - virtualNetworkSubnets is the module that writes reused-VNet subnets; and
      - the Cosmos DB virtual network rules target those subnets.
    Offline evidence only; it does not prove deployed ordering.
#>

[CmdletBinding()]
param(
    [string]$MainFile = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'bicep/main.bicep')
)

$ErrorActionPreference = 'Stop'
$compiledFile = Join-Path ([System.IO.Path]::GetTempPath()) "cosmos-subnet-dependency-contract-$([guid]::NewGuid()).json"
$script:checks = 0

function Assert-Contract {
    param([Parameter(Mandatory)] [bool]$Condition, [Parameter(Mandatory)] [string]$Message)
    if (-not $Condition) { throw "Cosmos subnet dependency contract failed: $Message" }
    $script:checks++
}

try {
    & az bicep build --file $MainFile --outfile $compiledFile
    if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed: $LASTEXITCODE" }
    $t = Get-Content -LiteralPath $compiledFile -Raw | ConvertFrom-Json -AsHashtable -Depth 100

    $cosmos = $t.resources.cosmosDBAccount
    Assert-Contract ($null -ne $cosmos) 'cosmosDBAccount module exists'
    Assert-Contract (@($cosmos.dependsOn) -ccontains 'virtualNetworkSubnets') 'cosmosDBAccount waits for reused-VNet subnet writes'
    Assert-Contract (@($cosmos.dependsOn) -ccontains 'virtualNetwork') 'cosmosDBAccount still waits for a new VNet'
    Assert-Contract (@($cosmos.dependsOn | Where-Object { $_ -ceq 'virtualNetworkSubnets' }).Count -eq 1) 'cosmosDBAccount declares the subnet dependency once'

    $subnets = $t.resources.virtualNetworkSubnets
    Assert-Contract ($null -ne $subnets) 'virtualNetworkSubnets module exists'
    Assert-Contract ([string]$subnets.condition).Contains("parameters('useExistingVNet')") 'virtualNetworkSubnets writes reused-VNet subnets'

    $rules = [string]$cosmos.properties.parameters.virtualNetworkSubnetIds
    Assert-Contract $rules.Contains("parameters('existingVnetResourceId')") 'Cosmos virtual network rules use the reused VNet'
    $targeted = @('peSubnetName', 'acaEnvironmentSubnetName', 'applicationPeSubnetName' | Where-Object { $rules.Contains("parameters('$_')") })
    Assert-Contract ($targeted.Count -eq 3) 'Cosmos virtual network rules target the subnets written by virtualNetworkSubnets'

    Write-Host "Cosmos subnet dependency contract passed: $script:checks checks (offline, not deployed ordering)." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $compiledFile -Force -ErrorAction SilentlyContinue
}
