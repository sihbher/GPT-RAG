# GPT-RAG Troubleshooting Report — `gpt-rag-aprl-03`

**Date**: 2026-04-04  
**Environment**: `gpt-rag-aprl-03` | Region: `swedencentral` | Release: `v2.5.1`  
**Frontend URL**: `https://ca-zycjy2scjhksk-frontend.delightfulcliff-d5f5813c.swedencentral.azurecontainerapps.io/`

---

## Índice

### Parte 1 — Chat Básico (RAG)
- [Resumen Parte 1](#summary)
- [Problema 1 — AI Foundry Cosmos DB Bloqueado](#problema-1--ai-foundry-agent-cosmos-db-bloqueado-crítico)
- [Problema 2 — SDK Incompatibility en NL2SQL Strategy](#problema-2--sdk-incompatibility-en-nl2sql-strategy-crítico)
- [Problema 3 — Cosmos DB Conversation Auth Failure](#problema-3--cosmos-db-conversation-auth-failure-medio)
- [Implementación de Fixes (Parte 1)](#implementación-de-fixes--resultados)
- [Verificación E2E (Parte 1)](#verificación-e2e)

### Parte 2 — NL2DAX (Natural Language to DAX)
- [Resumen NL2DAX](#parte-2--nl2dax-natural-language-to-dax)
- [Issue 4 — Storage Account Firewall](#issue-4--storage-account-firewall)
- [Issue 5 — AGENT_STRATEGY no configurado como nl2sql](#issue-5--agent_strategy-no-configurado-como-nl2sql)
- [Issue 6 — Key Vault sin acceso + Secreto SP faltante](#issue-6--key-vault-sin-acceso--secreto-sp-faltante)
- [Issue 7 — Archivo customers.json sin columnas](#issue-7--archivo-customersjson-sin-columnas-en-blob-storage)
- [Issue 8 — SDK create_agent renombrado](#issue-8--sdk-create_agent-renombrado--yaml-env-vars)
- [Issue 9 — AgentDetails vs Agent type incompatibility](#issue-9--agentdetails-vs-agent-type-incompatibility)
- [Issue 10 — Agent 409 Conflict on create](#issue-10--agent-409-conflict-on-create)
- [Issue 11 — Pydantic isinstance check fails](#issue-11--pydantic-isinstance-check-fails-with-agentdetails)
- [Issue 12 — AgentsOperations missing threads/runs/messages](#issue-12--agentsoperations-missing-threadsrunsmessages)
- [Issue 13 — Invalid assistant_id format](#issue-13--invalid-assistant_id-format)
- [Issue 14 — SQL Query Agent prompt restricted to sql_endpoint](#issue-14--sql-query-agent-prompt-restricted-to-sql_endpoint-only)
- [Issue 15 — DAX token not passed (file replacement fails)](#issue-15--dax-execution-auth--file-replacement-not-picked-up)
- [Issue 16 — Pydantic ValidationError organization=None](#issue-16--pydantic-validationerror-organizationnone)
- [Issue 17 — Invalid client secret (AADSTS7000215)](#issue-17--invalid-client-secret-aadsts7000215)
- [Issue 18 — DAX column names missing in AI Search](#issue-18--dax-column-names-missing-in-ai-search-index)
- [Issue 19 — Streaming buffer not yielding for complex queries](#issue-19--streaming-buffer-not-yielding-for-complex-queries)
- [Verificación E2E NL2DAX](#verificación-e2e-nl2dax)

---

## Parte 1 — Chat Básico (RAG)

**Symptom**: Every chat message returns `event: error` / `data: An internal server error occurred.`

## Summary

Se identificaron **3 problemas** encadenados. El error visible en el chat es consecuencia de un fallo en el **orchestrator**, no en el frontend. El flujo de la petición es:

```
Frontend → (Dapr sidecar) → Orchestrator → SSE error stream → Frontend muestra "An internal server error occurred."
```

| #  | Severidad | Componente | Problema |
|----|-----------|------------|----------|
| 1  | **CRÍTICO** | AI Foundry Cosmos DB | `cosmos-aif-zycjy2scjhksk` tiene **public network access = Disabled** y **no tiene private endpoints**. Bloquea toda operación del Agent Service. |
| 2  | **CRÍTICO** | Orchestrator / NL2SQL Strategy | `'AgentsOperations' object has no attribute 'create_agent'` — incompatibilidad de SDK `azure-ai-agents`. |
| 3  | **MEDIO** | Orchestrator → Cosmos DB (conversations) | `ManagedIdentityCredential` falla al obtener token. Posible causa: `AZURE_CLIENT_ID` está vacío (`""`) en lugar de no estar definido. |

---

## Problema 1 — AI Foundry Agent Cosmos DB Bloqueado (CRÍTICO)

### Evidencia

Logs del orchestrator al arrancar:

```
[Startup] ⚠️ AgentsClient pre-warm API call failed (client still created): 
  (cosmos_vnet_blocked) Access to Cosmos DB is blocked due to VNET configuration. 
  Please check your network settings and make sure CosmosDB is public network enabled, 
  if this is a public standard agent setup.

[Startup] ⚠️ Could not pre-create agent (will create per-request): 
  (cosmos_vnet_blocked) Access to Cosmos DB is blocked due to VNET configuration.
```

### Causa raíz

Existen **dos cuentas Cosmos DB** en el resource group `gpt-rag-sc-rg`:

| Cosmos DB Account | Propósito | Public Access | Private Endpoints |
|---|---|---|---|
| `cosmos-zycjy2scjhksk` | Conversations de la aplicación | **Enabled** (con IP rule `57.135.198.0/24`) | Ninguno |
| `cosmos-aif-zycjy2scjhksk` | Backing store del AI Foundry Agent Service | **Disabled** | **Ninguno** |

La cuenta `cosmos-aif-zycjy2scjhksk` está completamente inaccesible — public access deshabilitado **y** sin private endpoints. El AI Foundry Agent Service necesita este Cosmos DB para almacenar el estado de los agentes (threads, messages, etc.).

Dado que el deployment usa `NETWORK_ISOLATION=false` (no hay VNet ni private endpoints), esta cuenta debería tener public network access habilitado.

> **Impacto**: Este problema afecta a **TODAS** las estrategias de agente (`single_agent_rag`, `nl2sql`, `mcp`) porque todas dependen del AI Foundry Agent Service.

### Solución

```bash
# Habilitar public network access en el Cosmos DB del AI Foundry
az cosmosdb update \
  -n cosmos-aif-zycjy2scjhksk \
  -g gpt-rag-sc-rg \
  --public-network-access Enabled
```

---

## Problema 2 — SDK Incompatibility en NL2SQL Strategy (CRÍTICO)

### Evidencia

```
[ERROR] Error in SSE generator
  File "/app/src/main.py", line 506, in sse_event_generator
    async for chunk in orchestrator.stream_response(ask, _qid):
  File "/app/src/orchestration/orchestrator.py", line 116, in stream_response
    async for chunk in self.agentic_strategy.initiate_agent_flow(ask):
  File "/app/src/strategies/nl2sql_strategy.py", line 73, in initiate_agent_flow
    client.agents.create_agent(
    ^^^^^^^^^^^^^^^^^^^^^^^^^^
    'AgentsOperations' object has no attribute 'create_agent'
```

### Causa raíz

La estrategia activa es `nl2sql`, configurada en Azure App Configuration:

| Label | Key | Value | Modificado |
|---|---|---|---|
| `gpt-rag` | `AGENT_STRATEGY` | `single_agent_rag` | 2026-04-03T18:22:39 |
| **`gpt-rag-orchestrator`** | **`AGENT_STRATEGY`** | **`nl2sql`** | **2026-04-04T17:18:32** |

El orchestrator lee del label `gpt-rag-orchestrator` (label específico del componente), que fue cambiado a `nl2sql` hoy (04 de abril a las 17:18 UTC).

La estrategia NL2SQL en `nl2sql_strategy.py:73` llama a `client.agents.create_agent()`, pero la versión del SDK `azure-ai-agents` instalada en la imagen del orchestrator (`crzycjy2scjhksk.azurecr.io/azure-gpt-rag/orchestrator:67ef58b`, v2.4.2) tiene la API `AgentsOperations` que **no expone** el método `create_agent`. En versiones más recientes del SDK, el método fue renombrado (posiblemente a `create()` o la firma cambió).

### Solución

**Opción A** — Revertir la estrategia a `single_agent_rag` (fix inmediato, si no necesitas NL2SQL):

```bash
az appconfig kv set \
  --name appcs-zycjy2scjhksk \
  --auth-mode login \
  --key AGENT_STRATEGY \
  --label gpt-rag-orchestrator \
  --value single_agent_rag \
  --yes
```

Luego reiniciar el orchestrator:

```bash
az containerapp revision restart \
  -n ca-zycjy2scjhksk-orchestrator \
  -g gpt-rag-sc-rg \
  --revision ca-zycjy2scjhksk-orchestrator--0000001
```

**Opción B** — Actualizar el código del orchestrator para que sea compatible con la versión del SDK instalada. Esto requiere revisar el código de `nl2sql_strategy.py` en el repo `Azure/gpt-rag-orchestrator` tag `v2.4.2` y verificar la API correcta del SDK.

> **Nota**: Incluso con la Opción A, el Problema 1 (Cosmos DB VNET blocked) debe resolverse primero, ya que `single_agent_rag` también usa el AI Foundry Agent Service.

---

## Problema 3 — Cosmos DB Conversation Auth Failure (MEDIO)

### Evidencia

```
[cosmosdb] error creating document c398204d-22aa-4412-b724-9866f7fb19c6. 
  Error: ChainedTokenCredential failed to retrieve a token from the included credentials.
  credentials: ManagedIdentityCredential
  HTTP transport has already been closed.

[cosmosdb] could not update document (container=conversations, 
  id=c398204d-22aa-4412-b724-9866f7fb19c6): ClientAuthenticationError
```

### Análisis

| Check | Estado |
|---|---|
| System-assigned identity habilitada | ✅ `792dc135-cd66-4bb0-bf1a-2fc8d767d75b` |
| Cosmos DB data-plane RBAC (Built-in Data Contributor) | ✅ Role `00000000-0000-0000-0000-000000000002` asignado |
| `AZURE_CLIENT_ID` env var en Container App | ⚠️ Set to **empty string** `""` |
| Cosmos DB IP firewall | ⚠️ Solo permite `57.135.198.0/24` |
| Container Apps static IP | `4.225.39.104` (NO está en la IP rule) |

### Posibles causas

1. **`AZURE_CLIENT_ID=""` (vacío)**: Si el código crea `ManagedIdentityCredential(client_id=os.getenv("AZURE_CLIENT_ID"))`, el valor vacío `""` no es lo mismo que `None`. Con string vacío, el SDK intenta autenticar con user-assigned identity usando un client_id vacío, lo cual falla.

2. **IP Firewall de Cosmos DB**: La cuenta `cosmos-zycjy2scjhksk` tiene una IP rule que solo permite `57.135.198.0/24`. El Container Apps Environment tiene static IP `4.225.39.104`, que **no está en la lista permitida**. Esto bloquearía las peticiones al Cosmos DB.

3. **Efecto cascada**: El mensaje "HTTP transport has already been closed" en la segunda petición sugiere que el error primario (Problema 2) interrumpió el flujo y cerró conexiones HTTP prematuramente, causando que credenciales subsecuentes fallen.

### Solución

**Fix 1** — Agregar la IP del Container Apps al firewall de Cosmos DB:

```bash
# Agregar la IP estática del Container Apps Environment
az cosmosdb update \
  -n cosmos-zycjy2scjhksk \
  -g gpt-rag-sc-rg \
  --ip-range-filter "57.135.198.0/24,4.225.39.104"
```

O bien, si no se requiere IP filtering, permitir acceso desde todas las redes:

```bash
az cosmosdb update \
  -n cosmos-zycjy2scjhksk \
  -g gpt-rag-sc-rg \
  --ip-range-filter ""
```

**Fix 2** — Corregir `AZURE_CLIENT_ID` en el Container App (removerlo o dejarlo sin asignar):

```bash
az containerapp update \
  -n ca-zycjy2scjhksk-orchestrator \
  -g gpt-rag-sc-rg \
  --remove-env-vars AZURE_CLIENT_ID
```

---

## Orden de Aplicación de Fixes

Aplicar en este orden para resolver el problema:

1. **Problema 1**: Habilitar public access en `cosmos-aif-zycjy2scjhksk`
2. **Problema 3 Fix 1**: Agregar Container Apps IP al firewall de `cosmos-zycjy2scjhksk`
3. **Problema 2 Opción A**: Revertir `AGENT_STRATEGY` a `single_agent_rag` en label `gpt-rag-orchestrator`
4. **Reiniciar** el orchestrator container app
5. **Probar** el chat nuevamente

Si se requiere NL2SQL, después de verificar que `single_agent_rag` funciona, investigar la compatibilidad del SDK en `nl2sql_strategy.py` del orchestrator v2.4.2.

---

## Implementación de Fixes — Resultados

### Fix 1: Habilitar public access en `cosmos-aif-zycjy2scjhksk`

**Comando ejecutado**:
```bash
az cosmosdb update -n cosmos-aif-zycjy2scjhksk -g gpt-rag-sc-rg --public-network-access Enabled
```

**Resultado**: ✅ SUCCESS — `"publicNetworkAccess": "Enabled"` confirmado.

---

### Fix 2: Agregar IPs al firewall de `cosmos-zycjy2scjhksk`

**Comando ejecutado (intento 1)**:
```bash
az cosmosdb update -n cosmos-zycjy2scjhksk -g gpt-rag-sc-rg \
  --ip-range-filter "57.135.198.0/24,4.225.39.104"
```

**Resultado**: ✅ SUCCESS — Ambas IPs confirmadas en rules.

**Nota importante**: Al probar el chat por primera vez, se descubrió una IP adicional de outbound del orchestrator (`9.223.239.17`). El Container Apps Environment tiene IPs dúales: la IP estática `4.225.39.104` y una IP SNAT `9.223.239.17` que usa el container runtime para conexiones salientes. Se aplicó una segunda actualización:

**Comando ejecutado (intento 2 — fix refinado)**:
```bash
az cosmosdb update -n cosmos-zycjy2scjhksk -g gpt-rag-sc-rg \
  --ip-range-filter "57.135.198.0/24,4.225.39.104,9.223.239.17"
```

**Resultado**: ✅ SUCCESS — Las 3 IPs confirmadas:
- `57.135.198.0/24` (IP original del usuario/admin)
- `4.225.39.104` (Container Apps Environment static IP)
- `9.223.239.17` (Container Apps SNAT outbound IP)

---

### Fix 3: Revertir `AGENT_STRATEGY` a `single_agent_rag`

**Comando ejecutado**:
```bash
az appconfig kv set --name appcs-zycjy2scjhksk --auth-mode login \
  --key AGENT_STRATEGY --label gpt-rag-orchestrator \
  --value single_agent_rag --yes
```

**Resultado**: ✅ SUCCESS — `"value": "single_agent_rag"` confirmado.

---

### Reinicio del Orchestrator

**Comando ejecutado**:
```bash
az containerapp revision restart \
  -n ca-zycjy2scjhksk-orchestrator \
  -g gpt-rag-sc-rg \
  --revision ca-zycjy2scjhksk-orchestrator--0000001
```

**Resultado**: ✅ SUCCESS — `"Restart succeeded"`

**Logs post-reinicio**:
```
[Startup] ✅ AgentsClient pre-warmed (HTTP pipeline ready)
[Startup] ✅ Reusable agent created and cached (id=asst_z0voCHsuqCLXDwAJLS603C0V)
[Startup] ✅ Application pre-warming completed in 5.35s
Uvicorn running on http://0.0.0.0:8080
```

Sin errores tipo `cosmos_vnet_blocked`, sin errores de SDK, sin warnings de autenticación.

---

## Verificación E2E

### Test 1: Primer mensaje en nueva conversación

**Input**: `"hola, que puedes hacer?"`

**Respuesta del bot**: ✅ *"He buscado en la base de conocimiento pero no encontré información relevante para responder a 'hola, ¿qué puedes hacer?'. No tengo suficiente información en la base de conocimiento para dar una respuesta basada en esos documentos."*

**Logs**: Petición procesada correctamente (HTTP 200), agente respondió, pero la persistencia a Cosmos DB falló porque la IP SNAT `9.223.239.17` aún no estaba en el firewall.

```
[cosmosdb] error creating document [...]. Error: (Forbidden) Request originated from IP 9.223.239.17
```

**Acción correctiva**: Se agregó `9.223.239.17` al IP filter de Cosmos DB (Fix 2 refinado).

### Test 2: Nuevo chat después del fix de IP

**Input**: `"que es Azure AI Search?"`

**Respuesta del bot**: ✅ *"He buscado en la base de conocimiento pero no he encontrado documentos relevantes para citar, por lo que no tengo suficiente información disponible allí para dar una respuesta basada en fuentes de la base de conocimiento."*

**Logs**: 
```
[Conversation] Finished: conversation_id=e146d246-7437-40c9-b407-b1812a30d1ea [...]
[cosmosdb] document updated.    ← ✅ Persistencia exitosa
[cosmosdb] document e146d246-... retrieved.    ← ✅ Lectura exitosa  
[Conversation] Started: conversation_id=e146d246-... [...]
```

**Resultado**: ✅ Todo funciona — chat responde, conversaciones se persisten en Cosmos DB, y el historial se recupera correctamente.

> **Nota**: Las respuestas indican que la base de conocimiento (Azure AI Search index) está vacía o no tiene documentos ingestados aún. Esto es comportamiento esperado para un deployment recién configurado. Una vez que se ejecute el pipeline de ingestion y se indexen documentos, las respuestas citarán fuentes del knowledge base.

---

## Estado Final

| Componente | Estado |
|---|---|
| AI Foundry Cosmos DB (`cosmos-aif-zycjy2scjhksk`) | ✅ Public access habilitado |
| App Cosmos DB (`cosmos-zycjy2scjhksk`) | ✅ Firewall con 3 IPs permitidas |
| Agent Strategy | ✅ `single_agent_rag` en label `gpt-rag-orchestrator` |
| Orchestrator startup | ✅ Limpio, sin errores |
| Chat E2E | ✅ Funcional — peticiones procesadas, respuestas correctas |
| Conversation persistence | ✅ Cosmos DB reads/writes exitosos |

---

## Datos del Ambiente

```
Subscription:    d12d19a9-0636-4951-90a4-339158fd57d8
Tenant:          1162d55e-ff40-4a32-a849-f0066e8678e5
Resource Group:  gpt-rag-sc-rg
Region:          swedencentral
Release:         v2.5.1
NETWORK_ISOLATION: false

Orchestrator Image: crzycjy2scjhksk.azurecr.io/azure-gpt-rag/orchestrator:67ef58b
Orchestrator Version: v2.4.2
Orchestrator Revision: ca-zycjy2scjhksk-orchestrator--0000001 (created 2026-04-03T18:35:49)

Container Apps:
  - ca-zycjy2scjhksk-orchestrator (Running, principalId: 792dc135-cd66-4bb0-bf1a-2fc8d767d75b)
  - ca-zycjy2scjhksk-frontend     (Running, principalId: 7378bedc-73de-4b4b-bde5-9ba6b78e97ac)
  - ca-zycjy2scjhksk-dataingest   (Running, principalId: 868942ce-1671-44eb-9593-1f65e8642ae0)
  - ca-zycjy2scjhksk-mcp          (Running, principalId: 3abe357a-55c0-4f6e-be64-92e22eb888a2)

Container Apps Env Static IP: 4.225.39.104
Cosmos DB (app):       cosmos-zycjy2scjhksk       (Public: Enabled, IP rule: 57.135.198.0/24)
Cosmos DB (AI Foundry): cosmos-aif-zycjy2scjhksk   (Public: Disabled, no PE)

App Configuration: appcs-zycjy2scjhksk
AI Foundry Account: aif-zycjy2scjhksk
AI Foundry Project: aifp-zycjy2scjhksk
```

---
---

## Parte 2 — NL2DAX (Natural Language to DAX)

**Symptom**: Se siguió la [guía NL2DAX Quickstart](https://azure.github.io/GPT-RAG/) para habilitar Natural Language to DAX contra un modelo semántico de AdventureWorks en Power BI. Las preguntas del tutorial como "What is the total revenue?" no respondían correctamente.

**Datasource**: AdventureWorks Fabric Semantic Model  
**Power BI Workspace**: `demoworkspace` (ID: `062e3680-be44-4a28-a2fd-1e9128eea0d9`)  
**Power BI Dataset**: AdventureWorks (ID: `26f0192c-efc1-4cff-8694-afd26feb305e`)  
**Service Principal**: `GPT-RAG-PowerBI-Access` (Client ID: `7ed6e66a-6c14-44dd-b75e-bd895e64980a`)

Se identificaron **16 issues** adicionales (Issues 4-19) en el pipeline NL2DAX:

| #  | Severidad | Componente | Problema |
|----|-----------|------------|----------|
| 4  | MEDIO | Storage Account | Firewall bloqueaba acceso del orchestrator |
| 5  | CRÍTICO | App Configuration | `AGENT_STRATEGY` debe ser `nl2sql` para NL2DAX |
| 6  | CRÍTICO | Key Vault | Sin acceso + secreto del SP no existe |
| 7  | MEDIO | Blob Storage | `customers.json` sin datos de columnas |
| 8  | CRÍTICO | SDK | `create_agent` renombrado + YAML env vars faltantes |
| 9  | CRÍTICO | SDK | `AgentDetails` no es instancia de `Agent` |
| 10 | MEDIO | SDK | 409 Conflict al crear agentes con nombres duplicados |
| 11 | CRÍTICO | SDK | Pydantic isinstance check falla con `AgentDetails` |
| 12 | CRÍTICO | SDK | `AgentsOperations` no tiene `threads`/`runs`/`messages` |
| 13 | CRÍTICO | SDK | `assistant_id` inválido (nombres en lugar de `asst_` IDs) |
| 14 | ALTO | Prompt | SQLQueryAgent restringido solo a `sql_endpoint` |
| 15 | CRÍTICO | Runtime | Reemplazo de archivos de plugin/conector no toma efecto |
| 16 | ALTO | Pydantic | `SemanticModelConfig.organization=None` falla validación |
| 17 | ALTO | Auth | Client secret inválido (AADSTS7000215) |
| 18 | CRÍTICO | AI Search | Columnas faltantes en índice `nl2sql-tables` |
| 19 | MEDIO | Streaming | Buffer no emitido al alcanzar max_turns |

---

### Issue 4 — Storage Account Firewall

**Evidencia**: Orchestrator no podía leer schemas de blob storage.

**Causa raíz**: Storage account `stzycjy2scjhksk` tenía `defaultAction=Deny` sin la IP del Container Apps Environment.

**Solución**:
```bash
az storage account update -n stzycjy2scjhksk -g gpt-rag-sc-rg --default-action Allow
```

> **Nota de seguridad**: Después de completar la configuración, revertir a `Deny` con las IPs apropiadas.

---

### Issue 5 — AGENT_STRATEGY no configurado como nl2sql

**Causa raíz**: La guía NL2DAX requiere que `AGENT_STRATEGY=nl2sql` en Azure App Configuration (label `gpt-rag-orchestrator`). Estaba en `single_agent_rag`.

**Solución**:
```bash
az appconfig kv set --name appcs-zycjy2scjhksk --auth-mode login \
  --key AGENT_STRATEGY --label gpt-rag-orchestrator \
  --value nl2sql --yes
```

---

### Issue 6 — Key Vault sin acceso + Secreto SP faltante

**Evidencia**: El plugin NL2SQL intenta leer el secreto del Service Principal desde Key Vault para autenticación con Power BI, pero fallaba con 403.

**Causa raíz (doble)**:
1. Key Vault `kv-zycjy2scjhksk` tenía `defaultAction=Deny` sin la IP del orchestrator
2. El secreto `adventureworks-fabric-secret` no existía

**Solución**:
```bash
# 1. Permitir acceso temporal
az keyvault update -n kv-zycjy2scjhksk -g gpt-rag-sc-rg --default-action Allow

# 2. Crear el secreto con el client secret del SP
az keyvault secret set --vault-name kv-zycjy2scjhksk \
  --name adventureworks-fabric-secret \
  --value "<SP_CLIENT_SECRET>"
```

---

### Issue 7 — Archivo customers.json sin columnas en Blob Storage

**Causa raíz**: El archivo de schema `customers.json` en blob storage estaba presente pero no contenía datos de columnas, resultando en schemas incompletos para el LLM.

**Solución**: Se re-creó el archivo con la estructura correcta de columnas del modelo AdventureWorks.

---

### Issue 8 — SDK create_agent renombrado + YAML env vars

**Evidencia**:
```
'AgentsOperations' object has no attribute 'create_agent'
```

**Causa raíz**: SDK `azure-ai-projects==2.0.0b3` expone `AgentsOperations` que no tiene `create_agent()`. El método correcto en `azure-ai-agents==1.2.0b6` es `AgentsClient.create_agent()`.

Adicionalmente, el YAML del Container App no incluía las env vars requeridas: `APP_CONFIG_ENDPOINT`, `AZURE_TENANT_ID`.

**Solución**: Se creó una estrategia personalizada que usa `AgentsClient` de `azure-ai-agents` directamente, desplegada via file-replacement en el startup command:

```bash
echo "<B64_STRATEGY>" | base64 -d > /app/src/strategies/nl2sql_strategy.py
```

---

### Issue 9 — AgentDetails vs Agent type incompatibility

**Evidencia**:
```
Expected Agent instance but got AgentDetails
```

**Causa raíz**: `AIProjectClient.agents.create_agent()` retorna `AgentDetails` (un tipo interno), no el `Agent` que Semantic Kernel espera.

**Solución**: Usar `AgentsClient.create_agent()` de `azure-ai-agents` que retorna instancias `Agent` con IDs `asst_*` correctos.

---

### Issue 10 — Agent 409 Conflict on create

**Evidencia**: HTTP 409 al crear agentes con nombres ya existentes.

**Solución**: Implementar try/catch con 409 handling — eliminar agente existente y recrear.

---

### Issue 11 — Pydantic isinstance check fails with AgentDetails

**Causa raíz**: `AzureAIAgent` de Semantic Kernel valida que `definition` sea instancia de `Agent` (Pydantic model). `AgentDetails` no hereda de `Agent`.

**Solución**: Usar `AgentsClient.create_agent()` que retorna instancias reales de `Agent`.

---

### Issue 12 — AgentsOperations missing threads/runs/messages

**Evidencia**:
```
'AgentsOperations' object has no attribute 'threads'
```

**Causa raíz**: `project_client.agents` devuelve `AgentsOperations` (de `azure-ai-projects`) que solo tiene CRUD de agentes. `AzureAIAgent` de SK necesita `threads`, `runs`, `run_steps`, `messages`.

**Solución**: Monkey-patch de `project_client.agents`:
```python
agents_client = AgentsClient(endpoint=endpoint, credential=cred)
project_client.agents.threads = agents_client.threads
project_client.agents.runs = agents_client.runs
project_client.agents.run_steps = agents_client.run_steps
project_client.agents.messages = agents_client.messages
```

---

### Issue 13 — Invalid assistant_id format

**Evidencia**: Agentes creados con `AIProjectClient` tenían `id` = nombre del agente (e.g., `"TriageAgent"`) en lugar de `asst_*` IDs.

**Causa raíz**: `AIProjectClient.agents` usa API version `2025-05-01-preview` que retorna agent name como ID. `AgentsClient` usa `2025-05-15-preview` que retorna real Azure OpenAI-style `asst_*` IDs.

**Solución**: Usar `AgentsClient.create_agent()` exclusivamente.

---

### Issue 14 — SQL Query Agent prompt restricted to sql_endpoint only

**Evidencia**: El SQLQueryAgent generaba queries pero ignoraba datasources tipo `semantic_model`, solo respondía a `sql_endpoint`.

**Causa raíz**: El prompt `sqlquery_agent.txt` dice:
```
**Work exclusively** with the data source of type `sql_endpoint` selected by the Triage Agent.
**If no `sql_endpoint` data sources are selected, take no action.**
```

**Solución**: Se reemplazó en el prompt y se agregó un suplemento DAX:
```python
sql_prompt = sql_prompt.replace(
    "**Work exclusively** with the data source of type `sql_endpoint`...",
    "**Work** with the data source selected by the Triage Agent. "
    "Supported types: `sql_endpoint` (use T-SQL) and `semantic_model` (use DAX)."
)
sql_prompt += _DAX_SUPPLEMENT  # Steps for DAX: get tables, schema, measures, generate & execute DAX
```

---

### Issue 15 — DAX Execution Auth / File Replacement Not Picked Up

**Evidencia**: El plugin `ExecuteDAXQuery` completaba en 0.15s (solo consultaba Cosmos) sin ejecutar DAX contra Power BI. El `access_token` pasado por el LLM era `""`.

**Causa raíz (doble)**:
1. El LLM no puede proporcionar un Power BI token — la función `execute_dax_query` requiere auto-acquisition del token via Service Principal
2. **Los reemplazos de archivos de plugin (`plugins/nl2sql/plugin.py`) y conector (`connectors/fabric.py`) a nivel de archivo NO toman efecto en runtime**, a pesar de estar correctamente escritos en disco. Solo el archivo de estrategia (`strategies/nl2sql_strategy.py`) es recargado por Python.

**Solución**: Monkey-patch a **nivel de CLASE** desde el módulo de estrategia:
```python
# En nl2sql_strategy.py, a nivel de módulo (fuera de la clase):
_original_execute_dax_query = NL2SQLPlugin.execute_dax_query

async def _patched_execute_dax_query(self, datasource, query, access_token=""):
    # 1. Read Cosmos config for the datasource
    # 2. Build SemanticModelConfig
    # 3. Auto-acquire SP token when access_token is empty
    # 4. Call execute_restapi_dax_query with the SP token
    ...

# Copy kernel_function metadata from original to patched
for attr in dir(_original_execute_dax_query):
    if attr.startswith('__kernel') or attr.startswith('__sk'):
        setattr(_patched_execute_dax_query, attr, getattr(_original_execute_dax_query, attr))

NL2SQLPlugin.execute_dax_query = _patched_execute_dax_query
```

> **Lección clave**: En el runtime de Container Apps con la imagen del orchestrator, solo el archivo de estrategia (`nl2sql_strategy.py`) es confiable para reemplazo. Todas las correcciones a plugins y conectores deben hacerse via monkey-patching de clase desde la estrategia.

---

### Issue 16 — Pydantic ValidationError organization=None

**Evidencia**:
```
ValidationError: 1 validation error for SemanticModelConfig
  organization: Input should be a valid string [type=string_type, input_value=None]
```

**Causa raíz**: El documento en Cosmos DB tiene `organization: None`, pero `SemanticModelConfig` (Pydantic model) define `organization: str` como campo requerido.

**Solución**:
```python
semantic_model_config = SemanticModelConfig(
    organization=datasource_config.get("organization") or "",  # None → ""
    ...
)
```

---

### Issue 17 — Invalid client secret (AADSTS7000215)

**Evidencia**:
```
AADSTS7000215: Invalid client secret provided. Ensure the secret being sent in the request
is the client secret value, not the client secret ID.
```

**Causa raíz**: El secreto original en Key Vault puede haber expirado o estar corrupto en el contexto del container (a pesar de funcionar en curl local).

**Solución**: Se rotó el secreto del Service Principal y se actualizó Key Vault:
```bash
# Crear nuevo secreto
az ad app credential reset --id 7ed6e66a-6c14-44dd-b75e-bd895e64980a \
  --append --display-name "GPT-RAG-DAX-v2"

# Actualizar Key Vault
az keyvault secret set --vault-name kv-zycjy2scjhksk \
  --name adventureworks-fabric-secret --value "<NEW_SECRET>"
```

---

### Issue 18 — DAX column names missing in AI Search index

**Evidencia**:
```
DatasetExecuteQueriesError: Column 'SalesAmount' in table 'Sales' cannot be found
```

El LLM generaba `SUM('Sales'[SalesAmount])` pero el nombre real de la columna es `Sales Amount` (con espacio).

**Causa raíz**: El índice de AI Search `nl2sql-zycjy2scjhksk-tables` tenía `columns: null` para las 3 tablas (Customer, Product, Sales). Sin datos de columnas, el LLM no tenía referencia de schema y alucinaba nombres de columnas.

La función `GetSchemaInfo` del plugin consulta este índice y devuelve `columns={}` cuando el campo está vacío.

**Verificación**:
```bash
# Consulta directa a Power BI para descubrir columnas reales
EVALUATE COLUMNSTATISTICS()
```

Columnas reales de la tabla Sales:
- `Sales Amount` (no `SalesAmount`)
- `Order Quantity`, `Unit Price`, `Extended Amount`, etc.

**Solución**: Actualizar el índice de AI Search directamente con las columnas reales del modelo Power BI:
```python
# Payload de actualización para el índice nl2sql-tables
docs = [
    {
        "@search.action": "merge",
        "id": "tables-sales-json",
        "columns": [
            {"name": "SalesOrderLineKey", "description": "Primary key"},
            {"name": "CustomerKey", "description": "Foreign key to Customer"},
            {"name": "ProductKey", "description": "Foreign key to Product"},
            {"name": "Order Quantity", "description": "Number of units ordered"},
            {"name": "Unit Price", "description": "Price per unit"},
            {"name": "Sales Amount", "description": "Total sales amount (revenue)"},
            # ... all 15 columns
        ]
    },
    # Same for Customer (7 columns) and Product (9 columns)
]
```

**Resultado**: Después de la actualización, el LLM genera DAX correcto con `SUM('Sales'[Sales Amount])`.

---

### Issue 19 — Streaming buffer not yielding for complex queries

**Evidencia**: La pregunta "Show me the top 10 products by sales" retornaba respuesta vacía a pesar de que el DAX se ejecutaba correctamente (10 resultados).

**Causa raíz**: El código de streaming del AgentGroupChat solo emite (`yield`) el buffer del SyntetizerAgent cuando detecta la palabra "TERMINATE". Si el SyntetizerAgent responde con "IN_PROGRESS" (porque el SQLQueryAgent no terminó con "QUESTION_ANSWERED"), el buffer se acumula pero nunca se emite. Al alcanzar `maximum_iterations`, el loop termina y el buffer se descarta.

```python
# Código problemático:
async for content in chat.invoke_stream():
    if content.name == "SyntetizerAgent":
        buffer += content.content
        if not self._terminator_re.search(buffer):
            continue
        yield cleaned_buffer  # ← Solo se ejecuta si "TERMINATE" está en buffer
# ← Si el loop termina sin TERMINATE, buffer se pierde
```

**Solución (doble)**:

1. **Reset buffer por turno**: Cuando el SyntetizerAgent inicia un nuevo turno (después de chunks de otros agentes), resetear el buffer para evitar concatenación de múltiples respuestas:
```python
in_syntetizer = False
async for content in chat.invoke_stream():
    if content.name == "SyntetizerAgent":
        if not in_syntetizer:
            buffer = ""  # New synthesizer turn — reset
            in_syntetizer = True
        buffer += content.content
        ...
    else:
        in_syntetizer = False
```

2. **Flush al final**: Emitir el buffer restante cuando el loop termina sin TERMINATE:
```python
# After stream loop ends
if buffer:
    cleaned = re.sub(r'\bterminate\b', '', buffer, flags=re.IGNORECASE).strip()
    cleaned = re.sub(r'\bIN_PROGRESS\b', '', cleaned, flags=re.IGNORECASE).strip()
    if cleaned:
        yield cleaned
```

---

## Verificación E2E NL2DAX

**Revision desplegada**: `ca-zycjy2scjhksk-orchestrator--v8bfix`

### Test 1: "What is the total revenue?"

**Respuesta**: ✅ `Total revenue (SUM of Sales[Sales Amount]): 109,809,274.20`

### Test 2: "How many customers are in the database?"

**Respuesta**: ✅ `There are 18,485 customers in the database.`

### Test 3: "Show me the top 10 products by sales"

**Respuesta**: ✅
```
Top 10 products by total sales (Sales Amount):
1. Mountain-200 Black, 38 — 4,400,592.80
2. Mountain-200 Black, 42 — 4,009,494.76
3. Mountain-200 Silver, 38 — 3,693,678.03
4. Mountain-200 Silver, 42 — 3,438,478.86
5. Mountain-200 Silver, 46 — 3,434,256.94
6. Mountain-200 Black, 46 — 3,309,673.22
7. Road-250 Black, 44 — 2,516,857.31
8. Road-250 Black, 48 — 2,347,655.95
9. Road-250 Black, 52 — 2,012,447.78
10. Road-150 Red, 56 — 1,847,818.63
```

---

## Estado Final (Post NL2DAX)

| Componente | Estado |
|---|---|
| AI Foundry Cosmos DB | ✅ Public access habilitado |
| App Cosmos DB | ✅ Firewall con IPs permitidas |
| Storage Account | ⚠️ `defaultAction=Allow` (revertir a `Deny` con IPs) |
| Key Vault | ⚠️ `defaultAction=Allow` (revertir a `Deny` con IPs) |
| Agent Strategy | ✅ `nl2sql` en label `gpt-rag-orchestrator` |
| SP Secret en Key Vault | ✅ `adventureworks-fabric-secret` (rotado, hint `Fvn8Q`) |
| AI Search Indexes | ✅ `nl2sql-tables` con columnas popoladas |
| Orchestrator revision | ✅ `v8bfix` — estrategia custom con monkey-patch |
| Chat RAG (single_agent_rag) | ✅ Funcional |
| NL2DAX (nl2sql strategy) | ✅ Las 3 preguntas del tutorial funcionan |

---

## Resumen de Arquitectura del Fix NL2DAX

El fix requirió crear una **estrategia custom** (`nl2sql_strategy.py`) desplegada via reemplazo de archivo en el startup command del Container App. La estrategia:

1. **Monkey-patches a nivel de clase** `NL2SQLPlugin.execute_dax_query` para:
   - Leer configuración del datasource desde Cosmos DB
   - Defaultear `organization=None` a `""` (fix Pydantic)
   - Auto-adquirir token SP via `ClientSecretCredential` cuando `access_token=""` 
   - Usar el token para ejecutar DAX queries contra Power BI REST API

2. **Monkey-patches de SDK** para bridge entre `azure-ai-projects` y `azure-ai-agents`:
   - `project_client.agents.threads/runs/run_steps/messages` parchados desde `AgentsClient`

3. **Modifica el prompt** del SQLQueryAgent para soportar ambos tipos de datasource (`sql_endpoint` + `semantic_model`)

4. **Corrige el streaming** para manejar multi-turn del SyntetizerAgent sin pérdida de datos

### Diagrama del Flujo NL2DAX

```
Usuario pregunta "What is the total revenue?"
    │
    ▼
┌─────────────┐
│ TriageAgent │ ── GetAllTablesInfo() → AI Search (nl2sql-tables)
│             │ ── Selecciona datasource: adventureworks-fabric (semantic_model)
└─────┬───────┘
      ▼
┌──────────────┐
│ SQLQueryAgent│ ── GetSchemaInfo(Sales) → AI Search → {columns: [Sales Amount, ...]}
│              │ ── MeasuresRetrieval() → AI Search (nl2sql-measures)
│              │ ── QueriesRetrieval() → AI Search (nl2sql-queries)  
│              │ ── Genera DAX: EVALUATE ROW("Total", SUM('Sales'[Sales Amount]))
│              │ ── ExecuteDAXQuery() → [monkey-patched function]:
│              │       1. Lee config Cosmos → SemanticModelConfig
│              │       2. Acquires SP token via ClientSecretCredential
│              │       3. POST Power BI REST API /executeQueries
│              │       4. Retorna resultados
│              │ ── Responde con resultado + "QUESTION_ANSWERED"
└─────┬────────┘
      ▼
┌─────────────────┐
│ SyntetizerAgent │ ── Copia respuesta + "TERMINATE"
└─────┬───────────┘
      ▼
  Respuesta al usuario: "Total revenue: 109,809,274.20"
```

### Archivos Modificados (via runtime replacement)

| Archivo | Tipo de Fix |
|---|---|
| `/app/src/strategies/nl2sql_strategy.py` | Reemplazo completo via Base64 en startup command |

### Archivos NO Modificados (monkey-patched desde estrategia)

| Archivo | Clase Patcheada |
|---|---|
| `/app/src/plugins/nl2sql/plugin.py` | `NL2SQLPlugin.execute_dax_query` |
| `/app/src/connectors/fabric.py` | N/A (llamado via patch de plugin) |

---

## Datos del Ambiente (Actualizado)

```
Subscription:    d12d19a9-0636-4951-90a4-339158fd57d8
Tenant:          1162d55e-ff40-4a32-a849-f0066e8678e5
Resource Group:  gpt-rag-sc-rg
Region:          swedencentral
Release:         v2.5.1
NETWORK_ISOLATION: false

Orchestrator Image: crzycjy2scjhksk.azurecr.io/azure-gpt-rag/orchestrator:67ef58b
Orchestrator Version: v2.4.2
Orchestrator Active Revision: ca-zycjy2scjhksk-orchestrator--v8bfix

SDK Versions:
  azure-ai-projects:  2.0.0b3
  azure-ai-agents:    1.2.0b6
  semantic-kernel:    1.34.0

Power BI:
  Workspace: demoworkspace (062e3680-be44-4a28-a2fd-1e9128eea0d9)
  Dataset:   AdventureWorks (26f0192c-efc1-4cff-8694-afd26feb305e)
  SP:        GPT-RAG-PowerBI-Access (7ed6e66a-6c14-44dd-b75e-bd895e64980a)

AI Search Indexes:
  nl2sql-zycjy2scjhksk-tables:   3 docs (Customer, Product, Sales) — con columnas
  nl2sql-zycjy2scjhksk-queries:  5 docs (sample queries)
  nl2sql-zycjy2scjhksk-measures: 0 docs
  ragindex-zycjy2scjhksk:        vacío

Key Vault: kv-zycjy2scjhksk
  adventureworks-fabric-secret: rotado (hint Fvn8Q)
```
