
# Fixes Aplicados — GPT-RAG Post-Provisioning
> **Fecha**: 2026-04-05  
> **Entorno**: `gpt-rag-aprl-05` (Sweden Central)  
> **Release**: v2.6.2 (orchestrator v2.4.2, ingestion v2.2.5, UI v2.2.2, MCP v0.3.5)
---
## Índice
| # | Archivo | Descripción |
|---|---------|-------------|
| [1](#fix-1--campo-parent_id-faltante-en-el-índice-de-ai-search) | `config/search/search.j2` | Campo `parent_id` faltante en el índice de AI Search |
| [2](#fix-2--incompatibilidad-sdk-azure-ai-projects-200b3-rompe-nl2sql-strategy) | `src/strategies/nl2sql_strategy.py` (orchestrator) | Incompatibilidad SDK `azure-ai-projects==2.0.0b3` rompe NL2SQL strategy |
| [3](#fix-3--nl2dax-no-funciona-prompt-plugin-e-índices-vacíos) | Prompt, plugin, índices, streaming (orchestrator) | NL2DAX no funciona: prompt solo maneja SQL, token DAX requiere obtención manual, índices NL2SQL vacíos, mensajes internos se filtran en respuesta |
| [4](#fix-4--hub--spoke-policyManagedPrivateDns) | `main.parameters.json`, `.gitmodules`, `infra/` | Soporte Hub & Spoke: no crear Private DNS Zones cuando ya existen en el Hub |
| [5](#fix-5--deployvm-convertido-a-variable-de-entorno) | `main.parameters.json` | `deployVM` hardcodeado en `true`, convertido a variable `${DEPLOY_VM}` |
---
## Fix 1 — Campo `parent_id` faltante en el índice de AI Search
**Archivo modificado**: `config/search/search.j2`  
**Problema**: La ingestion de documentos fallaba con el error:
```
Field 'parent_id' is not a valid field in the index 'ragindex-fiv7jmtqte7cc'
```
### Causa raíz
El componente `gpt-rag-ingestion` (v2.2.5) escribe un campo `parent_id` en cada chunk al indexarlo en AI Search. Este campo vincula cada chunk con su documento padre, permitiendo operaciones como purgar todos los chunks de un documento al re-indexar.
Sin embargo, la plantilla Jinja2 `config/search/search.j2` (que define la estructura del índice durante `azd provision`) **no incluía** la definición del campo `parent_id`. Esto causaba que toda operación de indexación fallara al intentar escribir un campo inexistente.
### Síntomas observados
- `azd provision` completaba sin errores (el índice se creaba correctamente, pero sin el campo).
- Al subir documentos y reiniciar el container `dataingest`, los logs mostraban:
  ```
  Field 'parent_id' is not a valid field in the index 'ragindex-fiv7jmtqte7cc'
  ```
- El index permanecía con 0 documentos indefinidamente.
### Cambio aplicado
Se agregó la definición del campo `parent_id` en la lista de fields del índice RAG en `config/search/search.j2`:
**Antes** (líneas 15-16):
```json
{ "name": "metadata_security_rbac_scope",   "type": "Edm.String",   "searchable": false, "retrievable": true, "filterable": true, "permissionFilter": "rbacScope" },
{ "name": "chunk_id",                       "type": "Edm.Int32",    "searchable": false, "retrievable": true },
```
**Después** (líneas 15-17):
```json
{ "name": "metadata_security_rbac_scope",   "type": "Edm.String",   "searchable": false, "retrievable": true, "filterable": true, "permissionFilter": "rbacScope" },
{ "name": "parent_id",                      "type": "Edm.String",   "searchable": false, "retrievable": true, "filterable": true },
{ "name": "chunk_id",                       "type": "Edm.Int32",    "searchable": false, "retrievable": true },
```
### Actualización del índice existente en Azure
Además de modificar la plantilla (para futuros despliegues), se actualizó el índice ya existente en Azure directamente via REST API, agregando el campo sin necesidad de recrear el índice:
```bash
# Obtener definición actual del índice
token=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $token" \
  "https://srch-fiv7jmtqte7cc.search.windows.net/indexes/ragindex-fiv7jmtqte7cc?api-version=2025-05-01-preview" \
  > /tmp/index_def.json
# Agregar campo parent_id al JSON (usando jq o manualmente)
# PUT de vuelta con la definición actualizada
curl -X PUT \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  "https://srch-fiv7jmtqte7cc.search.windows.net/indexes/ragindex-fiv7jmtqte7cc?api-version=2025-05-01-preview" \
  -d @/tmp/index_def_updated.json
```
### Verificación
Después del fix, se reinició el container `dataingest` y se verificó:
- **Antes del fix**: 0 documentos en el índice, errores en logs.
- **Después del fix**: **184 chunks** indexados exitosamente a partir de 6 documentos subidos al storage.
### Notas
- Este es un problema de **incompatibilidad entre versiones**: la plantilla del índice (en el repo principal `GPT-RAG`) no está sincronizada con lo que espera el componente `gpt-rag-ingestion` v2.2.5.
- El campo `parent_id` es tipo `Edm.String`, filterable y retrievable, consistente con su uso como identificador de documento padre para operaciones de purge/re-index.
---
## Fix 2 — Incompatibilidad SDK `azure-ai-projects==2.0.0b3` rompe NL2SQL strategy
**Archivo modificado**: `src/strategies/nl2sql_strategy.py` (en `gpt-rag-orchestrator`)  
**Problema**: Cualquier query NL2SQL/NL2DAX retornaba `event: error / data: An internal server error occurred.`
### Causa raíz
El orchestrator v2.6.1 usa `azure-ai-projects==2.0.0b3`, que introdujo un **breaking change** en la API:
| Aspecto | `azure-ai-projects<=1.0.0b11` | `azure-ai-projects==2.0.0b3` |
|---|---|---|
| `AIProjectClient.agents` retorna | `AgentsClient` (de `azure-ai-agents`) | `AgentsOperations` (nuevo, limitado) |
| `client.agents.create_agent()` | ✅ Existe | ❌ Solo `client.agents.create()` |
| `client.agents.threads` | ✅ `ThreadsOperations` | ❌ No existe |
| `client.agents.runs` | ✅ `RunsOperations` | ❌ No existe |
Semantic Kernel 1.34.0 (`AzureAIAgentThread._create()`) llama internamente a `client.agents.threads.create(...)`, asumiendo que `client.agents` es un `AgentsClient` con acceso completo a threads, runs, y messages. Con `2.0.0b3`, `AgentsOperations` solo expone CRUD de agents (create/update/delete/get/list), sin ningún atributo `.threads`, `.runs`, ni `.messages`.
Esto causa **dos errores en cadena**:
1. **`'AgentsOperations' object has no attribute 'create_agent'`** — El código original llama `client.agents.create_agent(...)`, pero en 2.0.0b3 el método se renombró a `client.agents.create(...)`.
2. **`'AgentsOperations' object has no attribute 'threads'`** — Semantic Kernel intenta crear un thread via `client.agents.threads.create(...)`, pero `AgentsOperations` no tiene `.threads`.
### Impacto
- **No es posible hacer downgrade global** a `azure-ai-projects==1.0.0b11` porque `agent_framework_azure_ai` (usado por `MafAgentServiceStrategy`) importa `ApproximateLocation` de `azure.ai.projects.models`, que solo existe en `2.0.0b3`.
- El conflicto es entre dos strategies del mismo orchestrator que requieren versiones incompatibles del SDK.
### Cambio aplicado
Se modificó `nl2sql_strategy.py` para crear una instancia de `AgentsClient` (de `azure.ai.agents.aio`) directamente y reemplazar `client.agents` con ella:
```python
from azure.ai.agents.aio import AgentsClient as RealAgentsClient
# ... dentro de initiate_agent_flow:
async with self.credential as creds, \
           AzureAIAgent.create_client(
               credential=creds,
               endpoint=self.project_endpoint
           ) as client:
    # FIX: azure-ai-projects 2.0.0b3 returns AgentsOperations from client.agents,
    # which lacks .threads/.messages/.runs needed by SK 1.34.0.
    # Replace it with AgentsClient from azure-ai-agents which has the full API.
    real_agents = RealAgentsClient(
        endpoint=self.project_endpoint,
        credential=creds
    )
    client.agents = real_agents
```
Con este monkey-patch:
- `client.agents.create_agent(...)` → funciona (método de `AgentsClient`)
- `client.agents.threads.create(...)` → funciona (`AgentsClient.threads` es `ThreadsOperations`)
- `client.agents.runs` → funciona (`AgentsClient.runs` es `RunsOperations`)
- `agent_framework_azure_ai` sigue usando su propio `AIProjectClient.agents` sin afectar
También se actualizó `_schedule_agent_deletion()` para usar `RealAgentsClient` directamente, evitando el mismo problema en la limpieza de agents.
### Método de despliegue
Dado que el orchestrator se despliega como imagen de container (`crfiv7jmtqte7cc.azurecr.io/azure-gpt-rag/orchestrator:b3e1311`), el fix se aplicó inyectando el archivo parcheado via variable de entorno base64 en el startup command del Container App:
```bash
# Startup command del Container App:
echo $NL2SQL_PATCH | base64 -d > /app/src/strategies/nl2sql_strategy.py && \
  uvicorn main:app --host 0.0.0.0 --port 8080
```
**Nota**: Este es un fix temporal. El fix permanente requiere actualizar el repositorio `gpt-rag-orchestrator` y reconstruir la imagen del container.
### Verificación
**Antes del fix**:
```
$ curl -X POST .../orchestrator -d '{"ask":"budget 2027"}'
event: error
data: An internal server error occurred.
```
Container logs mostraban:
```
'AgentsOperations' object has no attribute 'create_agent'
'AgentsOperations' object has no attribute 'threads'
```
**Después del fix**:
```
$ curl -X POST .../orchestrator -d '{"ask":"budget 2027"}'
No relevant data source found to answer your question. QUESTION_ANSWERED.
```
Container logs muestran ejecución limpia de los 3 agents (TriageAgent → SQLQueryAgent → SyntetizerAgent) sin errores. La respuesta indica que no hay `sql_endpoint` configurado, lo cual es correcto — la funcionalidad NL2SQL requiere configurar un data source SQL/DAX.
### Notas
- La causa raíz es que `azure-ai-projects` 2.0.0b3 rompió retrocompatibilidad con Semantic Kernel 1.34.0 al cambiar `AIProjectClient.agents` de `AgentsClient` (full API) a `AgentsOperations` (solo CRUD de agents).
- La solución de monkey-patch es segura: `AgentsClient` de `azure-ai-agents` habla con el mismo endpoint y usa la misma credential, proporcionando la API completa que SK espera.
- SDKs involucrados: `azure-ai-projects==2.0.0b3`, `azure-ai-agents==1.2.0b5`, `semantic-kernel==1.34.0`.
---
## Fix 3 — NL2DAX no funciona: prompt, plugin e índices vacíos
**Archivos modificados**:
- `src/prompts/nl2sql/sqlquery_agent.txt` (orchestrator) — Prompt actualizado para soportar DAX
- `src/plugins/nl2sql/plugin.py` (orchestrator) — Patch para obtener token de Power BI automáticamente
- Índices AI Search NL2SQL — Poblados manualmente (3 tablas, 5 queries)
**Problema**: Al seguir el tutorial NL2DAX, las consultas retornaban "No relevant data source found" o "I can't determine [...] because no sql_endpoint data source is currently selected."
### Causa raíz (3 sub-problemas)
#### 3a. Índices NL2SQL vacíos — dataingest atascado
El container `dataingest` estaba atrapado en un loop infinito de polling a Document Intelligence para el archivo `BUDGET-2027-APP.pdf`. El log mostraba:
```
Polling Document Intelligence... Status: running (elapsed: 1800s)
```
Este loop impedía que el CRON job de NL2SQL (configurado como `CRON_RUN_NL2SQL_INDEX=*/15 * * * *`) se ejecutara. Resultado: los 3 índices de AI Search para NL2SQL permanecían en 0 documentos a pesar de tener 8 archivos en el blob storage (`stfiv7jmtqte7cc/nl2sql`).
#### 3b. Prompt del SQLQueryAgent solo maneja `sql_endpoint`
El prompt original (`src/prompts/nl2sql/sqlquery_agent.txt`) contiene la instrucción explícita:
> "If no `sql_endpoint` data sources are selected, take no action and respond that you cannot generate a query."
Esto causa que el agent rechace cualquier datasource de tipo `semantic_model` (Fabric/DAX), a pesar de que el TriageAgent lo selecciona correctamente.
#### 3c. `ExecuteDAXQuery` requiere `access_token` que el agent no puede proveer
La función `ExecuteDAXQuery` en `plugin.py` tiene un parámetro `access_token` obligatorio:
```python
@kernel_function(description="Execute a DAX query against a semantic model.")
async def execute_dax_query(self, datasource: str, query: str, access_token: str) -> str:
```
Internamente, pasa el `access_token` del parámetro directamente a:
```python
results = await semantic_client.execute_restapi_dax_query(dax_query=query, user_token=access_token)
```
Sin embargo, `SemanticModelClient` ya tiene un método `_get_restapi_access_token()` que obtiene el token automáticamente usando el service principal configurado en Key Vault. El agent no tiene forma de obtener un token válido, por lo que la ejecución siempre fallaba.
### Cambios aplicados
#### Fix 3a — Indexación manual de NL2SQL
Se creó un script Python (`/tmp/nl2sql_index.py`) para indexar manualmente los 8 archivos del blob storage en AI Search, generando embeddings via Bearer token (ya que `disableLocalAuth=true` en AOAI):
```bash
# Los archivos en stfiv7jmtqte7cc/nl2sql:
# 3 tablas: adventureworks-fabric-Customer.json, adventureworks-fabric-Product.json, adventureworks-fabric-Sales.json
# 5 queries: adventureworks-fabric-query-*.json
python3 /tmp/nl2sql_index.py
# Output: Uploaded 3/3 tables, 5/5 queries
```
Verificación post-indexación:
```
nl2sql-fiv7jmtqte7cc-tables:   3 documentos ✅
nl2sql-fiv7jmtqte7cc-queries:  5 documentos ✅
nl2sql-fiv7jmtqte7cc-measures: 0 documentos (correcto, no hay archivos de measures)
```
#### Fix 3b — Prompt del SQLQueryAgent actualizado para DAX
Se reescribió el prompt para soportar ambos tipos de datasource:
**Cambios clave**:
- Determinar el lenguaje de query basado en `datasource_type`: `sql_endpoint` → T-SQL, `semantic_model` → DAX
- Guía de sintaxis DAX: `EVALUATE`, single quotes para tablas, brackets para columnas
- Instrucción de usar `execute_dax_query` con `access_token="auto"` para semantic models
- Patrones DAX comunes: `EVALUATE ROW(...)`, `SUMMARIZE`, `TOPN`, `FILTER`
- Mantener soporte T-SQL/SQL para datasources `sql_endpoint`
#### Fix 3c — Plugin parcheado para obtener token automáticamente
Se modificó `plugin.py` para que `ExecuteDAXQuery` obtenga el token de Power BI automáticamente en lugar de depender del parámetro `access_token` del agent:
**Antes**:
```python
results = await semantic_client.execute_restapi_dax_query(dax_query=query, user_token=access_token)
```
**Después**:
```python
real_token = await semantic_client._get_restapi_access_token()
results = await semantic_client.execute_restapi_dax_query(dax_query=query, user_token=real_token)
```
El token se obtiene via `ClientSecretCredential` usando el `tenant_id` y `client_id` del datasource en Cosmos DB, y el `client_secret` del Key Vault (`adventureworks-fabric-secret`).
### Método de despliegue
Los 3 cambios se desplegaron como patches inyectados via variables de entorno base64 en el startup command del Container App:
```bash
# Startup command:
echo $NL2SQL_PATCH | base64 -d > /app/src/strategies/nl2sql_strategy.py && \
echo $SQLQUERY_PROMPT | base64 -d > /app/src/prompts/nl2sql/sqlquery_agent.txt && \
echo $DAX_PATCH | base64 -d > /tmp/dax_patch.py && \
python3 /tmp/dax_patch.py && \
uvicorn main:app --host 0.0.0.0 --port 8080
```
Variables de entorno:
- `NL2SQL_PATCH`: Strategy parcheada (Fix 2, mantenido)
- `SQLQUERY_PROMPT`: Prompt actualizado (Fix 3b)
- `DAX_PATCH`: Script Python que parchea `plugin.py` en runtime (Fix 3c)
Se desplegó via REST API:
```bash
az rest --method PATCH \
  --url "$(az containerapp show -g gpt-rag-001 -n ca-fiv7jmtqte7cc-orchestrator --query id -o tsv)?api-version=2024-03-01" \
  --body @/tmp/fix3_patch.json
```
### Verificación
Todos los queries del tutorial NL2DAX funcionan correctamente:
```
Q: "What is the total revenue?"
A: Total Revenue: 109,809,274.20
Q: "How many customers are in the database?"
A: Total customers: 18,485.
Q: "What are the top 10 products by sales?"
A: 1) Mountain-200 Black, 38 — $4,400,592.80
   2) Mountain-200 Black, 42 — $4,009,494.76
   3) Mountain-200 Silver, 38 — $3,693,678.03
   ... (10 products listed)
Q: "Show sales by category"
A: Components: 11,799,076.66 | Accessories: 1,272,057.89
   Clothing: 2,117,613.45 | Bikes: 94,620,526.21
Q: "What is the average order value?"
A: Avg Order Value: 905.62
```
Logs del container muestran el flujo completo:
```
TriageAgent → DATASOURCE_SELECTED (adventureworks-fabric, semantic_model)
SQLQueryAgent → GetAllTablesInfo → QueriesRetrieval → ExecuteDAXQuery
[fabric] Access token acquired successfully for Semantic Model.
[fabric] Rest API endpoint: https://api.powerbi.com/v1.0/myorg/datasets/.../executeQueries
SyntetizerAgent → Respuesta al usuario
```
### Notas
- **Fix 3a es un workaround**: La indexación manual es temporal. El fix permanente es resolver el loop de Document Intelligence en el container `dataingest` para que el CRON de NL2SQL se ejecute.
- **Fix 3b y 3c son necesarios para NL2DAX**: El repositorio `gpt-rag-orchestrator` v2.6.1 no soporta `semantic_model` datasources out-of-the-box. El prompt y el plugin necesitan actualizarse en el repo fuente.
- **Fix 3d es un bug pre-existente**: El streaming bug existía en el código original del orchestrator, pero estaba enmascarado porque antes de Fix 2+3 el pipeline NL2SQL nunca completaba una ejecución end-to-end. Solo se manifestó al resolver los sub-problemas anteriores.
- **Todos los fixes son temporales** (inyección base64 en startup). El fix permanente requiere PRs en `gpt-rag-orchestrator` y rebuild de la imagen del container.
#### Fix 3d — Mensajes internos de agentes se filtran en la respuesta al usuario
**Archivo modificado**: `src/strategies/nl2sql_strategy.py` (streaming logic)  
**Observado después de**: Fix 3a+3b+3c (bug pre-existente, solo visible cuando el pipeline completa end-to-end)
**Problema**: Las respuestas al usuario contienen mensajes internos del multi-agent group chat:
```
I'm sorry, but I cannot assist with that request.I'm sorry, but I cannot assist with that request.
{
  "datasource_name": "adventureworks-fabric",
  "datasource_type": "semantic_model"
} DATASOURCE_SELECTEDHere are the top 10 products by sales...
```
**Causa raíz**: El pipeline multi-agente NL2SQL funciona así:
1. **TriageAgent** → Selecciona datasource, emite `{JSON} DATASOURCE_SELECTED`
2. **SyntetizerAgent** (turno intermedio) → Ve que no hay QUESTION_ANSWERED, emite `"I'm sorry..." IN_PROGRESS`
3. **SQLQueryAgent** → Ejecuta la query, emite resultado + `QUESTION_ANSWERED`
4. **SyntetizerAgent** (turno final) → Copia el resultado y emite `TERMINATE`
El código de streaming original acumulaba TODOS los tokens del SyntetizerAgent en un buffer sin resetear entre turnos, concatenando mensajes IN_PROGRESS con la respuesta final.
**Cambio aplicado** — Reescritura de la lógica de streaming con 4 mejoras:
1. **Reset de buffer por turno**: Detecta cambio de speaker y descarta buffer previo
2. **Extracción antes del primer TERMINATE**: `buffer[:match.start()]` en vez de `re.sub` global
3. **Post-procesamiento de tokens de control**: Regex para limpiar `QUESTION_ANSWERED`, `DATASOURCE_SELECTED`, `I'm sorry...`, `TERMINATE`, `IN_PROGRESS`
4. **Break inmediato**: Detiene procesamiento después de la primera respuesta válida
**Verificación**:
```
# Antes del fix:
fix4-test-002 {"datasource_name":"adventureworks-fabric"...} DATASOURCE_SELECTEDThere are 18,485 customers...
# Después del fix:
timing-test-001 There are 18,485 customers in the database.
```
---
## Análisis de rendimiento — NL2DAX (~60-114s por query)
### Mediciones reales (container logs, 2026-04-05)
**Query: "How many customers?" — 59.8s (1 ciclo)**
| Fase | Tiempo | Tipo |
|---|---|---|
| Request + Cosmos setup | 1.5s | Setup |
| TriageAgent: LLM pre-tools | 7s | **LLM** |
| TriageAgent: GetAllDatasourcesInfo | <0.1s | Tool |
| TriageAgent: LLM entre tools | 4s | **LLM** |
| TriageAgent: TablesRetrieval | <0.2s | Tool |
| TriageAgent: LLM post-tools | 9s | **LLM** |
| SQLQueryAgent: LLM pre-tools | 9s | **LLM** |
| SQLQueryAgent: GetAllTablesInfo | <0.1s | Tool |
| SQLQueryAgent: LLM entre tools | 7s | **LLM** |
| SQLQueryAgent: QueriesRetrieval | <0.2s | Tool |
| SQLQueryAgent: LLM genera DAX | 6s | **LLM** |
| SQLQueryAgent: ExecuteDAXQuery (Fabric) | 1.1s | Tool |
| SQLQueryAgent: LLM post-DAX | 6s | **LLM** |
| SyntetizerAgent: LLM respuesta final | 8s | **LLM** |
| **Total** | **~60s** | |
**Desglose**: LLM reasoning ~56s (93%), tools ~1.7s (3%), overhead ~2s (4%)
**Query: "Total revenue" (desde UI) — 114s (2 ciclos)**
| Ciclo | Agentes | Tiempo |
|---|---|---|
| Ciclo 1 | Triage(20s) → SQL(47s) → Synth(7s) | ~74s |
| Ciclo 2 (desperdiciado) | Triage(8s) → SQL(7s) → Synth(18s) | ~33s |
| Setup | | ~5s |
El 2do ciclo ocurre porque SyntetizerAgent emite `IN_PROGRESS` en vez de `TERMINATE` después del 1er ciclo, forzando la sequential strategy a repetir Triage→SQL→Synth.
### Hallazgos clave
1. **El 93% del tiempo es LLM reasoning** — Los tools (AI Search, Cosmos, DAX/Fabric) responden en <2s total. El cuello de botella es Azure OpenAI en Sweden Central (~5-9s por llamada LLM).
2. **Hay 7-8 llamadas LLM por query**: 3 del TriageAgent, 4 del SQLQueryAgent, 1 del SyntetizerAgent.
3. **Algunas queries hacen 2 ciclos** (6 agent turns en vez de 3), duplicando el tiempo a ~114s. Esto pasa cuando el SyntetizerAgent no detecta `QUESTION_ANSWERED` en el primer ciclo.
4. **TriageAgent es redundante** cuando solo hay 1 datasource. Gasta ~21s en 2 tool calls para descubrir el único datasource que existe.
### Posibles optimizaciones (no implementadas)
| Optimización | Ahorro estimado | Complejidad |
|---|---|---|
| Reducir `maximum_iterations` de 10 a 4 | ~33s (en queries de 2 ciclos) | Baja — cambiar 1 parámetro |
| Eliminar TriageAgent (hardcodear datasource) | ~21s por query | Media — requiere nueva strategy |
| Eliminar SyntetizerAgent (usar output directo de SQL) | ~8-18s por query | Media — cambiar streaming logic |
| Cambiar a región con menor latencia LLM | Variable | Alta — re-despliegue completo |
| Reducir prompts (menos tokens = menos latencia) | ~5-10s | Baja — editar prompts |
---
## Limitación conocida — "budget 2027" y queries de documentos (RAG)
**Esto NO es un bug** sino una limitación de diseño del sistema actual.
### Problema observado
Al preguntar "budget 2027" con `AGENT_STRATEGY=nl2sql`, el sistema intenta buscar datos de presupuesto en el semantic model de AdventureWorks (Fabric) en vez de consultar los PDFs indexados en el RAG index.
### Causa
Las estrategias de agente en GPT-RAG son **mutuamente excluyentes**:
| Estrategia | Qué hace | Qué NO hace |
|---|---|---|
| `single_agent_rag` | Busca en el RAG index (documentos/PDFs) | No consulta bases de datos ni Fabric |
| `nl2sql` | Consulta bases de datos SQL y semantic models DAX | No busca en el RAG index |
| `mcp` | Ejecuta tools via MCP server | Depende de las tools configuradas |
No existe una estrategia `multiagent` que combine RAG + NL2SQL (el enum `MULTIAGENT` existe pero su implementación está comentada en `AgentStrategyFactory`).
### Estado actual
- `AGENT_STRATEGY=nl2sql` en App Configuration
- El RAG index (`ragindex-fiv7jmtqte7cc`) tiene **184 documentos** indexados, incluyendo contenido de "Budget 2027"
- Las queries de documentos como "budget 2027" se ruetan incorrectamente al pipeline NL2SQL
### Recomendación
Para queries de documentos (PDFs):
```bash
az appconfig kv set --endpoint "https://appcs-fiv7jmtqte7cc.azconfig.io" \
  --auth-mode login --key "AGENT_STRATEGY" --label "gpt-rag-orchestrator" \
  --value "single_agent_rag" --yes
```
Para queries de base de datos (NL2SQL/NL2DAX):
```bash
az appconfig kv set --endpoint "https://appcs-fiv7jmtqte7cc.azconfig.io" \
  --auth-mode login --key "AGENT_STRATEGY" --label "gpt-rag-orchestrator" \
  --value "nl2sql" --yes
```
**Nota**: Después de cambiar `AGENT_STRATEGY`, es necesario reiniciar el orchestrator container para que tome efecto.
---
## Fix 5 — Smart Router: Consultas de documentos devuelven datos NL2SQL en vez de contenido PDF
**Archivo modificado**: `src/strategies/nl2sql_strategy.py` (orchestrator)  
**Problema**: Con `AGENT_STRATEGY=nl2sql`, al preguntar sobre documentos PDF (ej. "The 2027 Federal Credit Supplement"), el sistema devolvía datos de Power BI/NL2SQL en vez del contenido del documento.
### Causa raíz
El `NL2SQLStrategy` original enruta **todas** las consultas al pipeline NL2SQL de 3 agentes (TriageAgent → SQLQueryAgent → Synthesizer). Incluso para queries sobre documentos, el TriageAgent siempre selecciona un datasource porque la búsqueda semántica siempre retorna algo, aunque no sea relevante. No existe un fallback a RAG (búsqueda de documentos).
### Solución: Smart Router con clasificación híbrida
Se reimplementó `NL2SQLStrategy` como un **Smart Router** con tres fases:
1. **Clasificación híbrida** (`_is_nl2sql_relevant`):
   - Intenta clasificación LLM (YES/NO) primero
   - Si el LLM retorna vacío (problema conocido con modelos o-series como o1/o3/o4-mini), aplica **keyword fallback**
   - Keywords de datos (`how many`, `customers`, `sales`, `revenue`, `count`, `total`, etc.) → NL2SQL
   - Keywords de documentos (`document`, `report`, `supplement`, `budget`, `federal`, `policy`, etc.) → RAG
   - Score: `data_keywords > doc_keywords` → NL2SQL, de lo contrario → RAG
2. **RAG fallback** (`_rag_fallback`):
   - Búsqueda híbrida (vector + keyword) en Azure AI Search via `SearchClient.search_knowledge_base()`
   - Síntesis de resultados con LLM (`max_completion_tokens=4096`)
   - Parámetros compatible con modelos o-series (sin `temperature`, sin rol `system`)
3. **NL2SQL pipeline** (`_run_nl2sql_chat`):
   - Pipeline de 3 agentes estándar (Triage → SQLQuery → Synthesizer)
   - Si el pipeline detecta "no relevant datasource", retorna el sentinel `__RAG_FALLBACK__`, que activa un fallback secundario a RAG
### Compatibilidad con modelos o-series
Los modelos o-series (o1, o3, o4-mini) tienen restricciones específicas:
- No soportan `temperature` → se omite
- No soportan `max_tokens` → se usa `max_completion_tokens`
- No soportan role `system` → todo en role `user`
- Frecuentemente retornan vacío para prompts cortos YES/NO → keyword fallback resuelve esto
### Resultados de pruebas
| Query | Ruta | Tiempo | Resultado |
|---|---|---|---|
| "How many customers are in the database?" | NL2SQL (keyword: data=3, doc=0) | 66s | 18,485 customers ✓ |
| "The 2027 Federal Credit Supplement" | RAG (keyword: data=0, doc=2) | 27s | Contenido completo del PDF con citas ✓ |
### Logs de routing
```
[routing] LLM inconclusive (raw=''), using keyword fallback
[routing] Keyword classification: data=3 doc=0 → NL2SQL for: How many customers are in the database?
[routing] NL2SQL path for: How many customers are in the database?
[routing] LLM inconclusive (raw=''), using keyword fallback
[routing] Keyword classification: data=0 doc=2 → RAG for: The 2027 Federal Credit Supplement
[routing] Direct RAG path for: The 2027 Federal Credit Supplement
```
### Keywords de clasificación
**Data keywords** (→ NL2SQL):
```
how many, count, total, sum, average, revenue, sales, customers, orders,
products, employees, transactions, units, quantity, top N, bottom N,
highest, lowest, most, least, per month, per year, by category, by region,
group by, database, table, profit, margin, cost, price, amount, growth,
trend, compare, percentage, ratio, adventureworks, fabric, semantic model, sql
```
**Document keywords** (→ RAG):
```
document, report, supplement, budget, federal, government, policy, regulation,
law, act, legislation, publication, whitepaper, article, paper, chapter,
section, guide, guideline, manual, handbook, overview, summary, explain,
describe, what is, tell me about, definition
```
### Despliegue
Se despliega via `az containerapp update --yaml` con el código base64-encoded inyectado como variable de entorno `NL2SQL_PATCH`, decodificado en el startup command.
**Revisión activa**: `ca-fiv7jmtqte7cc-orchestrator--0000017`
---
## Fix 4 — Hub & Spoke: `policyManagedPrivateDns` para evitar duplicar DNS Zones
**Archivos modificados**: `main.parameters.json`, `.gitmodules`, `infra/` (submodule)
**Problema**: Al desplegar GPT-RAG en un entorno Hub & Spoke donde las Private DNS Zones ya existen en el Hub (Connectivity subscription), el Bicep de `bicep-ptn-aiml-landing-zone` v1.0.5 creaba 15 zonas DNS duplicadas en el resource group del Spoke, causando conflicto con las zonas del Hub.
### Causa raíz
- v1.0.5 solo condiciona la creación de DNS Zones a `networkIsolation`. No existe ningún parámetro para omitirlas.
- En Hub & Spoke enterprise, las zonas DNS privadas viven en una suscripción de Conectividad (Hub). El Spoke no debe crear zonas propias.
- Los DNS Zone Groups en los Private Endpoints deben apuntar a las zonas del Hub (o bien dejarse sin DNS Zone Group para que Azure Policy del Hub los registre automáticamente).
### Cambios aplicados
**1. `main.parameters.json` — nuevo parámetro:**
```json
// Agregado después de existingVnetResourceId:
"policyManagedPrivateDns":               { "value": "${POLICY_MANAGED_PRIVATE_DNS}" },
```
**2. `.gitmodules` — actualizar submodule a v1.1.4:**
```ini
# Antes:
branch = v1.0.5
# Después:
branch = v1.1.4
```
**3. `infra/` — submodule actualizado** al commit `de135cf` (tag v1.1.4), que introduce el parámetro `policyManagedPrivateDns`.
### Comportamiento en Bicep v1.1.4 con `policyManagedPrivateDns = true`
| Variable Bicep | Evaluación |
|---|---|
| `_deployPrivateDnsZones` | `false` — no crea ninguna de las 15 DNS Zones |
| `_peDnsZoneGroup*` (×15) | `{}` — Private Endpoints sin DNS Zone Group adjunto |
Las zonas del Hub (registradas vía Azure Policy o manualmente) resuelven los A records cuando se crean los Private Endpoints.
### Variables de entorno para Hub & Spoke
```bash
azd env set AZURE_SUBSCRIPTION_ID        "<spoke-subscription-id>"
azd env set AZURE_RESOURCE_GROUP         "<rg-pre-creado-en-spoke>"
azd env set NETWORK_ISOLATION            true
azd env set USE_EXISTING_VNET            true
azd env set EXISTING_VNET_RESOURCE_ID    "<resource-id-del-vnet-spoke>"
azd env set DEPLOY_SUBNETS               false
azd env set SIDE_BY_SIDE                 false
azd env set POLICY_MANAGED_PRIVATE_DNS   true
azd env set DEPLOY_VM                    false
```

---

## Fix 5 — `deployVM` convertido a variable de entorno

**Archivo modificado**: `main.parameters.json`

**Problema**: El parámetro `deployVM` estaba hardcodeado en `"true"`. En entornos Hub & Spoke el Bicep intenta crear una VM jumpbox + Azure Bastion, lo que requiere `AzureBastionSubnet` en el Spoke VNet. En Hub & Spoke enterprise esa subnet vive en el Hub, causando el error:

```
Resource .../subnets/AzureBastionSubnet referenced by .../bastionHosts/bas-testvm-xxx was not found.
(Code: InvalidResourceReference)
```

**Causa raíz**: `deployVM && networkIsolation` dispara la creación de Bastion. Con `USE_EXISTING_VNET=true` el Bicep busca `AzureBastionSubnet` en el Spoke VNet donde no existe.

### Cambio aplicado

```json
// Antes:
"deployVM": { "value": "true" },

// Después:
"deployVM": { "value": "${DEPLOY_VM}" },
```

### Variable de entorno

```bash
azd env set DEPLOY_VM false
```

### Comportamiento si no se setea la variable

Si `DEPLOY_VM` no está definida en el entorno, `azd` sustituye `${DEPLOY_VM}` por string vacío `""`. El parámetro Bicep `deployVM bool` evalúa `""` como `false` — equivalente a no desplegar VM ni Bastion. Es seguro pero se recomienda setearlo explícitamente.
