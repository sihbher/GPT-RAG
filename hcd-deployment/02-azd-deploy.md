# Deploy de las Apps GPT RAG en HCD (`azd deploy`, sin Docker)

| Campo             | Valor                                                        |
| ----------------- | ----------------------------------------------------------- |
| Versión           | v1                                                          |
| Fecha inicio      | 2026-08-13                                                  |
| Autor             | Gerardo Reyes                                               |
| Suscripción       | HCD-NON-PROD (`*******`)                                    |
| Tenant            | CA Housing & Community Development (`*******`)              |
| Entorno azd       | `gptrag-bot01`                                              |
| Grupo de recursos | `*******`                                                   |
| Región            | `westus`                                                    |
| Continúa de       | [01-azd-postprovision.md](01-azd-postprovision.md)          |
```toc
```

## Objetivo

Construir y desplegar las imágenes de las 3 Container Apps (`orchestrator`,
`frontend`, `dataingest`) **desde la jump VM**, **sin Docker**, respetando Zero
Trust y la residencia US. Requiere que el **post-provision ya esté completo** (App
Configuration poblado; ver [01-azd-postprovision.md](01-azd-postprovision.md)).

## Historial de versiones

| Versión | Fecha      | Cambios                                                                 |
| ------- | ---------- | ---------------------------------------------------------------------- |
| v1      | 2026-08-13 | Plan de `azd deploy` sin Docker en `westus`: abrir ACR temporal (Opción A) + cerrar. |

---

## Punto de partida

- Post-provision **completo**: App Configuration poblado (label `gpt-rag`), incluida
  `CONTAINER_REGISTRY_NAME`, y knowledge source/base de Foundry IQ creados.
- Entorno `azd` `gptrag-bot01` **rehidratado** en la jump VM.
- La asociación de ACR a las 3 Container Apps ya la dejó el post-provision (3/3).

---

## El bloqueo: sin Docker en `westus`

En red aislada el ACR es Premium con acceso público deshabilitado, y el **agent
pool de ACR Tasks no existe en `westus`** (ver
[00-azd-provision.md](00-azd-provision.md), Paso 16), así que el path por defecto
"sin Docker vía agent pool en la VNet" **no aplica** en esta región. La jumpbox no
trae Docker a propósito. `azd deploy` construye con `az acr build` (builder
compartido de Microsoft), que necesita el ACR **temporalmente accesible**.

### ¿Hay que setear alguna variable para el pool? No.

El `deploy.ps1` toma **dos decisiones separadas**:

1. **Build mode** (`local` vs `acr-task`) → **automático**: con `NETWORK_ISOLATION=true`
   elige `acr-task` (build remoto, sin Docker local).
2. **Agent pool vs builder hosted** → controlado por la env var **`ACR_TASK_AGENT_POOL`**
   (el *nombre* del pool). Si está **seteada**, añade `--agent-pool <nombre>` a
   `az acr build` (pool dedicado en la VNet). Si está **vacía**, usa el **builder
   hosted de Microsoft**, que **requiere el ACR público**.

En este entorno `ACR_TASK_AGENT_POOL=""` (vacío, porque en `westus` no hay pool), así
que el build usa el hosted builder → **por eso hay que abrir el ACR**. **No** setear
`ACR_TASK_AGENT_POOL`: apuntar a un pool inexistente haría fallar la validación
`az acr agentpool show`.

> No confundir: `DEPLOY_ACR_TASK_AGENT_POOL` (infra: *crear* el pool) vs
> `ACR_TASK_AGENT_POOL` (deploy: *usar* un pool por nombre). Ambos off/vacío aquí.

---

## Opción A (recomendada): abrir el ACR temporalmente + `azd deploy`

```powershell
$RG    = (azd env get-value AZURE_RESOURCE_GROUP)
$ACR   = az acr list -g $RG --query "[0].name" -o tsv      # criunaosgptragbot01wus001
$ACRID = az acr show -n $ACR --query id -o tsv

# 1) abrir
az resource update --ids $ACRID --set properties.publicNetworkAccess=Enabled
az resource show   --ids $ACRID --query "properties.publicNetworkAccess" -o tsv   # -> Enabled

# 2) deploy (build + push + update de las 3 apps)
azd deploy

# 3) cerrar SIEMPRE (aunque el deploy falle)
az resource update --ids $ACRID --set properties.publicNetworkAccess=Disabled
az resource show   --ids $ACRID --query "properties.publicNetworkAccess" -o tsv   # -> Disabled
```

Ventana breve de exposición del ACR (el push igual requiere autenticación).

### Notas de la ejecución real (2026-08-13)

Al abrir el ACR surgieron dos obstáculos ya resueltos:

1. **`az acr update --public-network-access` no reconocido.** El `az` CLI de la jump
   VM es viejo y no tiene ese flag (`unrecognized arguments`). Por eso se usa el
   fallback genérico `az resource update --set properties.publicNetworkAccess=...`.
   Alternativa: `az upgrade` para tener los flags nativos.
2. **`AuthorizationFailed` (PIM expirado)** en el primer intento
   (`Microsoft.ContainerRegistry/registries/write`). Tras **reactivar PIM** funcionó
   y el ACR quedó `Enabled` (`networkRuleSet.defaultAction: Allow`, SKU Premium).

> ⚠️ **Volver a cerrar el ACR** con el mismo mecanismo al terminar, aunque el deploy
> falle, para no dejar el registro expuesto.

### Resultado del deploy (2026-08-14) — SUCCESS

Con el ACR abierto y el post-provision completo (App Config poblado), `azd deploy`
terminó **OK**. Salida relevante:

```
Docker is not available; component deploys will use ACR remote builds.
Deploying gpt-rag-ui (tag:v2.3.13)          -> deploy script finished
Deploying gpt-rag-orchestrator (tag:v3.8.0) -> deploy script finished
Deploying gpt-rag-ingestion (tag:v2.5.0)    -> deploy script finished
All components processed.
SUCCESS: Your application was deployed to Azure ...
```

| Componente | Tag desplegado |
|---|---|
| `gpt-rag-ui` | v2.3.13 |
| `gpt-rag-orchestrator` | v3.8.0 |
| `gpt-rag-ingestion` | v2.5.0 |

- Cada componente se construyó con **`az acr build`** (builder hosted, sin Docker
  local) y se actualizó su Container App.
- Los repos de los componentes ya estaban clonados localmente (`skipping clone`).
- **No hizo falta ninguna variable extra** (`ACR_TASK_AGENT_POOL` vacío → hosted
  builder → ACR público, que ya estaba abierto).

> Tras el SUCCESS, **cerrar el ACR** (`publicNetworkAccess=Disabled`).

---

## Opción B: cambiar a una región con agent pools

Redeploy completo en `westus2` / `eastus2` / `southcentralus` y re-verificar que
`DataZoneStandard` esté disponible allí para ambos modelos. Implica re-aprovisionar.

## Opción C: Docker dentro de la VNet

Instalar Docker en la jumpbox u otra VM — es, efectivamente, usar Docker (lo que se
quería evitar).

---

## Validación

```powershell
# estado de las 3 Container Apps
az containerapp list -g $RG `
  --query "[].{name:name, running:properties.runningStatus, image:properties.template.containers[0].image}" -o table
```

- Las 3 Container Apps (`orchestrator`, `frontend`, `dataingest`) **running** y healthy.
- Cada app corre la imagen recién publicada en el ACR.
- El endpoint del frontend responde por la ruta de acceso privada.
- Model deployments en `DataZoneStandard` (requisito de residencia).
- La *retrieval* funciona (knowledge base de Foundry IQ creada en el post-provision).

---

## Guardrails

- **Nunca** cambiar un modelo a SKU `Global*`. Mantener `DataZoneStandard`.
- **Cerrar el ACR** (`publicNetworkAccess=Disabled`) al terminar el deploy.
- **No** usar `PREFLIGHT_SKIP` / `GPT_RAG_REGIONAL_PREFLIGHT_SKIP` para saltar
  fallos — arreglar la causa.
- Mantener intactas las 4 customizaciones del repo (ver [README.md](README.md)).
- Verificar la suscripción activa antes de cualquier acción
  (`az account show -o table`).
- No commitear secretos.

---

## Estado actual

- ✅ **`azd deploy` = SUCCESS (2026-08-14):** las 3 componentes construidas por ACR
  remote build y desplegadas (`gpt-rag-ui` v2.3.13, `gpt-rag-orchestrator` v3.8.0,
  `gpt-rag-ingestion` v2.5.0). El build usó el **builder hosted** (`ACR_TASK_AGENT_POOL`
  vacío) con el **ACR abierto temporalmente**.
- ✅ **Retrieval end-to-end validado (2026-08-14):** tras correr el indexer nativo,
  el chat respondió con contexto del documento ingerido (*Attention Is All You
  Need*), citando la fuente. Cadena completa OK: frontend → orchestrator → Foundry
  IQ KB → modelo.
- ⚠️ California Constitution (463 pág.) queda sin ingerir por el **límite de 300
  páginas** de Content Understanding (`itemsFailed: 1`) — partir en ≤300 y re-ingestar.
- Pendiente: **cerrar el ACR**.

## Próximos pasos

- [x] Abrir el ACR temporalmente (`publicNetworkAccess=Enabled`).
- [x] `azd deploy` — build + deploy de las 3 Container Apps (**SUCCESS**).
- [x] Subir PDFs al contenedor `documents` + correr el indexer nativo de Foundry IQ.
- [x] Validar apps (orchestrator / frontend / dataingest) + endpoint + **retrieval (chat)**.
- [ ] **Cerrar el ACR** (`publicNetworkAccess=Disabled`).
- [ ] (Opcional) partir la Constitution en ≤300 páginas y re-ingestar (`itemsFailed → 0`).
- [ ] Abrir el PR a `Azure/bicep-ptn-aiml-landing-zone` (`ailz-improvements.md`, Changes 1–5).

---

## Anexo: subir documentos de prueba al contenedor `documents`

Storage `stiunaosgptragbot01wus00`, contenedor `documents` (público deshabilitado;
la jump VM llega por private endpoint). AAD auth, sin account key.

> El contenedor `documents` **ya lo crea el provision (Bicep)** — está en
> `storageAccountContainersList` de [infra/main.parameters.json](infra/main.parameters.json)
> (`"name": "documents"`). **No** hay que crearlo; solo verificar y subir.

```powershell
$STORAGE   = "stiunaosgptragbot01wus00"
$CONTAINER = "documents"

# el contenedor ya existe (creado por el provision); solo verificar
az storage container list --account-name $STORAGE --auth-mode login --query "[].name" -o table
az storage blob upload-batch --account-name $STORAGE --auth-mode login `
  --destination $CONTAINER --source "C:\ruta\a\pdfs" --pattern "*.pdf"
az storage blob list --account-name $STORAGE --container-name $CONTAINER --auth-mode login --query "[].name" -o table
```

- **`403 AuthorizationPermissionMismatch`** → falta rol de datos; concederse
  **Storage Blob Data Contributor** sobre el storage (PIM) y reintentar.
- **`AADSTS53003`** (Conditional Access) → `az login --scope https://storage.azure.com/.default`.
- Tras subir, Foundry IQ ingiere vía `knowledge-base-blob-ks` (indexer
  `knowledge-base-blob-ks-indexer`, `executionEnvironment: Private`); tarda unos
  minutos en indexar.

### Validación de ingesta (2026-08-14) — ✅ OK

Log del contenedor `dataingest` tras subir 2 PDFs (California Constitution +
*Attention Is All You Need*):

```json
[blob-storage-indexer] RUN-COMPLETE  status: "finished"
  sourceContainer: "documents"
  sourceFiles: 2, itemsDiscovered: 2, indexedItems: 2
  success: 2, failed: 0, skippedBlocked: 0
  totalChunksUploaded: 259, durationSeconds: 278.3
```

- **Content Understanding** (extracción `standard`, OCR/layout): `202` →
  *"Analysis succeeded"* contra el AI Services del Foundry (habilitado por los SPL
  aprobados).
- **Embeddings** `text-embedding-3-large` → `200 OK` (West US), **259 chunks**.
- Todo con **managed identity** por private endpoint; **0 fallos, sin 4xx/5xx**.
- El PDF de 463 páginas se dividió en 2 partes (≤300 c/u) — normal.

### Validación de retrieval (Foundry IQ) — dos almacenes distintos

Al probar el chat, la respuesta fue *"no tengo información en la knowledge base"*
aunque el dataingest había indexado 259 chunks. **Causa:** con
`RETRIEVAL_BACKEND=foundry_iq` el orchestrator consulta la **knowledge base de
Foundry IQ** (`knowledge-base`), **no** el `ragindex` que puebla el dataingest. Son
**dos almacenes separados**:

| Almacén | Lo puebla | Lo consulta |
|---|---|---|
| `ragindex-iunaoskcfg3y2` | dataingest (`blob-storage-indexer`) | backend `ai_search` (no este) |
| KB `knowledge-base` (via `knowledge-base-blob-ks`) | indexer nativo `knowledge-base-blob-ks-indexer` | **orchestrator (foundry_iq)** |

El knowledge source se creó (14:24) **antes** de subir los PDFs (15:06), así que su
indexer no tenía nada. **Fix:** correr el indexer nativo:

```powershell
$SEP = "https://srch-iunaos-gptrag-bot01-wus-001.search.windows.net"; $API = "2025-05-01-preview"
$tok = az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
$hdr = @{ Authorization = "Bearer $tok" }
Invoke-RestMethod -Method Post -Headers $hdr -Uri "$SEP/indexers/knowledge-base-blob-ks-indexer/run?api-version=$API"
# status: buscar lastResult.status=success, itemsProcessed>0
Invoke-RestMethod -Headers $hdr -Uri "$SEP/indexers/knowledge-base-blob-ks-indexer/status?api-version=$API" | ConvertTo-Json -Depth 6
```

> Requiere token de `https://search.azure.com` (si CA lo bloquea:
> `az login --scope https://search.azure.com/.default`) y rol **Search Service
> Contributor** sobre el Search.

### ⚠️ Límite de 300 páginas de Content Understanding (`standard`)

El indexer nativo terminó `success` pero con **`itemsFailed: 1`**: el PDF de la
California Constitution (**463 páginas**) falló con
`InputPageCountExceeded: exceeds the maximum allowed page count of 300`. El modo
`standard` usa Content Understanding, que **topa en 300 páginas por documento**. La
ingesta nativa de Foundry IQ (a diferencia del dataingest) **no divide** el PDF.

Opciones:
- **A (recomendada):** partir el PDF en partes ≤300 páginas (`qpdf --split-pages=300 ...`),
  borrar el grande del contenedor, subir las partes y re-correr el indexer.
- **B:** `FOUNDRY_IQ_CONTENT_EXTRACTION_MODE=minimal` (sin límite de páginas, sin
  OCR) — **inmutable**: obliga a recrear el knowledge source + knowledge base.

El *Attention Is All You Need* (chico) **sí** se ingirió → la retrieval ya funciona
para ese documento.
