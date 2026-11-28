@description('Name of the existing Azure Cosmos DB account.')
param databaseAccountName string

@description('Name of the Azure Cosmos DB for NoSQL database to deploy.')
param databaseName string

@description('Optional database-level throughput. Ignored for serverless accounts.')
param databaseThroughput int?

@description('Azure Cosmos DB for NoSQL containers to deploy.')
param containers array

resource databaseAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: databaseAccountName
}

resource sqlDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  name: databaseName
  parent: databaseAccount
  properties: {
    resource: {
      id: databaseName
    }
    options: contains(databaseAccount.properties.capabilities, { name: 'EnableServerless' })
      ? null
      : {
          throughput: databaseThroughput
          autoscaleSettings: null
        }
  }
}

resource sqlContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = [
  for container in containers: {
    name: container.name
    parent: sqlDatabase
    properties: {
      // The Cosmos DB RP rejects an explicit null vectorEmbeddingPolicy; send it
      // only when the container defines one (same as the Terraform provider).
      resource: union({
        conflictResolutionPolicy: {}
        defaultTtl: container.?defaultTtl ?? -1
        id: container.name
        indexingPolicy: empty(container.?indexingPolicy ?? {}) ? null : container.indexingPolicy
        partitionKey: {
          paths: map(container.paths, path => startsWith(path, '/') ? path : '/${path}')
          kind: 'Hash'
          version: 1
        }
        uniqueKeyPolicy: null
      }, empty(container.?vectorEmbeddingPolicy ?? {}) ? {} : { vectorEmbeddingPolicy: container.vectorEmbeddingPolicy })
      options: contains(databaseAccount.properties.capabilities, { name: 'EnableServerless' })
        ? null
        : {
            throughput: databaseThroughput != null && container.?throughput == null
              ? null
              : container.?throughput ?? 400
            autoscaleSettings: null
          }
    }
  }
]
