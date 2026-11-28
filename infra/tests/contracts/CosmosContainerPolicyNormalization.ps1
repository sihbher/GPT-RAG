# Exact, bounded inverse of the Cosmos SQL container payload fix. The Cosmos DB
# RP rejects an explicit null vectorEmbeddingPolicy, so the container resource
# is now a union() that adds the policy only when one is defined. The fixture
# pins the complete compiled before/after value of that one property; any other
# change still reaches the historical fingerprints.
function ConvertTo-PreCosmosContainerPolicyGraph {
    param([Parameter(Mandatory)] $Template)
    $copy = ConvertTo-Json -InputObject $Template -Depth 100 -Compress |
        ConvertFrom-Json -AsHashtable -Depth 100
    $fixture = Get-Content (Join-Path $PSScriptRoot 'fixtures\cosmos-container-policy-normalization.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 100
    $module = $copy.resources['cosmosSqlDatabase']
    $containers = if ($module -is [System.Collections.IDictionary]) { $module.properties.template.resources['sqlContainers'] }
    if ($containers -isnot [System.Collections.IDictionary]) { throw "SCOPED: missing reviewed resource at $($fixture.path)." }
    Assert-ScopedValue $containers.properties.resource $fixture.after $fixture.path
    $containers.properties.resource = $fixture.before
    return $copy
}
