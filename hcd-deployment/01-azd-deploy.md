# Despliegue de las Apps GPT RAG en HCD (azd deploy)

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
| Continúa de       | [00-test.md](00-test.md) (Paso 16)                          |
```toc
```

## Objetivo

Continuar el despliegue **desde la jump VM (dentro de la VNet)**: rehidratar el
entorno `azd` en la máquina, completar el **post-provision** (data-plane) y
**desplegar las Container Apps**, respetando la postura Zero Trust y la
residencia US (`DataZoneStandard`).

## Historial de versiones

| Versión | Fecha      | Cambios                                                                                                             |
| ------- | ---------- | ----------------------------------------------------------------------------------------------------------------- |
| v1      | 2026-08-13 | Rehidratación del entorno `azd` en la jump VM confirmada (`.env` con outputs). Plan de `azd deploy` sin Docker en `westus`. |

---

## Punto de partida

Al terminar [00-test.md](00-test.md):

- `azd provision` = **SUCCESS**; toda la infraestructura creada en el RG.
- Acceso a la jump VM por Bastion (túnel nativo + RDP) **confirmado**.
- Pendiente: **post-provision + deploy de apps**, que deben correr **dentro de la VNet**.
- Bloqueo abierto: **ACR Tasks agent pool no disponible en `westus`** → deploy sin
  Docker requiere una alternativa (ver Paso 3).

---

## Paso 1: Rehidratar el entorno `azd` en la jump VM

"Rehidratar" = reconstruir el estado local de `azd` (`.azure/<env>/.env`) en la VM,
para que `azd` vuelva a conocer el entorno ya aprovisionado **sin recrear
infraestructura**. Son dos partes: (1) recrear inputs y (2) traer outputs.

### 1.1 Login al tenant HCD

```powershell
az login --tenant *******
azd auth login --tenant-id *******
az account set --subscription *******
az account show -o table   # debe decir HCD-NON-PROD
```

### 1.2 Traer el repo con las customizaciones

```powershell
git clone <tu-fork-url> gpt-rag
cd gpt-rag
git checkout hcd/test01
git submodule update --init --recursive   # trae infra/ (AILZ v2.3.0)
```

> Verificar que el fix `cafTrim(..., 60)` siga en `infra/main.bicep`
> (customización #4). Si falta tras el `submodule update`, reaplicarlo.

### 1.3 Recrear inputs del entorno

```powershell
azd env new gptrag-bot01

azd env set AZURE_SUBSCRIPTION_ID     *******
azd env set AZURE_RESOURCE_GROUP      *******
azd env set AZURE_LOCATION            westus
azd env set NETWORK_ISOLATION         true
azd env set CHAT_DEPLOYMENT_SKU       DataZoneStandard
azd env set EMBEDDING_DEPLOYMENT_SKU  DataZoneStandard
azd env set RUN_FROM_JUMPBOX          true
```

### 1.4 Traer los outputs desde Azure

```powershell
azd env refresh
```

Consulta el deployment existente en el RG y rellena el `.env` con todos los
outputs (nombres de recursos, endpoints, etc.). **No crea ni modifica
infraestructura.**

### 1.5 Verificación (rehidratación confirmada)

```powershell
azd env get-values
```

El `.env` quedó poblado con outputs que no se setearon a mano — confirmando que
`azd env refresh` trajo el estado del deployment. Valores relevantes observados:

| Clave | Valor |
|---|---|
| `AZURE_ENV_NAME` | `gptrag-bot01` |
| `AZURE_LOCATION` | `westus` |
| `RELEASE` | `v3.7.0` |
| `RESOURCE_TOKEN` | `iunaoskcfg3y2` |
| `NETWORK_ISOLATION` | `true` |
| `RUN_FROM_JUMPBOX` | `true` |
| `CHAT_DEPLOYMENT_SKU` / `EMBEDDING_DEPLOYMENT_SKU` | `DataZoneStandard` |
| `APP_CONFIG_ENDPOINT` | `https://appcs-iunaos-gptrag-bot01-wus-001.azconfig.io` |
| `APP_RUNTIME_CONFIGURATION_MODE` | `appConfig` |
| `KEY_VAULT_NAME` | `kv-iunaos-gptrag-bot01-w` |
| `KNOWLEDGE_BASE_ENDPOINT` | `https://srch-iunaos-gptrag-bot01-wus-001.search.windows.net` |
| `KNOWLEDGE_BASE_NAME` | `knowledge-base` |
| `RETRIEVAL_BACKEND` | `foundry_iq` |
| `FOUNDRY_IQ_PATTERN` | `azureBlob` |
| `CONTAINER_APP_INTERNAL_FQDN` | `ca-iunaoskcfg3y2-orchestrator.<...>.westus.azurecontainerapps.io` |
| `PUBLIC_INGRESS_ENABLED` | `false` |
| `DEPLOY_ACR_TASK_AGENT_POOL` | `false` |

> ✅ **Rehidratación confirmada (2026-08-13):** el `.env` contiene inputs **y**
> outputs. Si solo aparecieran las variables seteadas a mano, el `refresh` no
> trajo outputs → revisar suscripción / RG / nombre de entorno.

---

## Paso 2: Completar el post-provision (data-plane, dentro de la VNet)

> **Importante — no uses `azd provision` aquí.** `azd provision` re-ejecuta el
> **Bicep del AILZ** (submodulo) además del post-provision. En esta VM el
> submodulo **no** tiene el fix local del SPL (`cafTrim`, customización #4), así
> que el Bicep **re-fallaría** por el nombre de 64 chars y **ni llegaría** a
> poblar App Config; además revertiría drift (p. ej. re-cerraría el ACR). Corre
> **solo el hook**:

```powershell
azd env get-value RUN_FROM_JUMPBOX     # debe ser true
azd hooks run postprovision            # ejecuta scripts/postProvision.ps1 SIN tocar infra
```

> **Por qué el post-provision es obligatorio en ZTA:** en modo aislado el Bicep
> **omite** poblar App Configuration — el módulo `appConfigPopulate` de
> [infra/main.bicep](infra/main.bicep) está guardado por
> `if (... && !_networkIsolation)`. Quien escribe las claves `gpt-rag` (incluida
> `CONTAINER_REGISTRY_NAME`) es [scripts/postProvision.ps1](scripts/postProvision.ps1)
> (`Set-GptRagAppConfiguration -Label 'gpt-rag'`). Por eso un `azd deploy` previo
> al post-provision falla con *"Missing required App Configuration key"*.

### Ejecución real (2026-08-13) — éxito parcial

El hook completó **la mayoría** del data-plane:

| Fase | Resultado |
|---|---|
| Poblar App Configuration (label `gpt-rag`) | ✅ **136 claves** escritas |
| Governance / audit (defaults + HMAC secret + KV reference) | ✅ OK |
| AI Foundry (RAI blocklist + policy + asociación al deployment `chat`) | ✅ OK |
| Container Apps → asociación de ACR (identity system) | ✅ **3/3** |
| Índices de AI Search (`ragindex-*`, `nl2sql-*`) | ✅ creados |
| **Foundry IQ: knowledge source / knowledge base** | ❌ **FALLÓ** (bloquea el hook, exit 1) |

Dos errores en el log; **solo uno es fatal**:

1. **Benigno (ignorar):** al inyectar la API key de Foundry en Key Vault:
   `Failed to list key. disableLocalAuth is set to be true`. Es **esperado en
   ZTA/keyless** — Foundry tiene local auth deshabilitado, no hay API key que
   guardar. El script lo registra pero **continúa** (`✅ ... complete`).

2. **Fatal (causa del exit 1):** creación del knowledge source `azureBlob`:

   ```
   PUT knowledgesources/knowledge-base-blob-ks failed 400:
     Unexpected error validating provided resource.
     {"error":{"code":"403","message":"Public access is disabled. Please configure private endpoint."}}
   Failed to create knowledge source 'knowledge-base-blob-ks'
   PUT knowledgebases/knowledge-base failed 400:
     Could not find target Knowledge Source with name 'knowledge-base-blob-ks'
   RuntimeError: Foundry IQ knowledge source/base provisioning failed
   ```

   **Causa:** el AI Search (`srch-...`) no pudo alcanzar el **blob del Storage**
   (`stiunaoskcfg3y2`, contenedor `documents`) para validar el knowledge source.
   El Storage tiene **acceso público deshabilitado** (ZTA) y la conexión privada
   Search→blob (**shared private link**, groupId `blob`, definido en
   [infra/main.bicep](infra/main.bicep) línea 2957) **no está aprobada/operativa**,
   así que Search cae a acceso público → **403**. Sin el knowledge source, la
   knowledge base tampoco se crea.

### Estado tras la corrida

- ✅ **App Configuration poblado → el bloqueo original (`CONTAINER_REGISTRY_NAME`)
  quedó resuelto.** El `azd deploy` ya no fallará en esa primera lectura.
- ❌ **Foundry IQ sin knowledge base** → la *retrieval* no funcionará hasta
  crear el knowledge source/base (Search→Storage privado).

### Resolver el knowledge source (Search→Storage privado) — causa raíz confirmada

Diagnóstico (read-only) del shared private link y del storage real:

```powershell
# nombres reales de storage (¡stiunaoskcfg3y2 NO existe; es un fallback cosmético del log!)
az storage account list -g HCD-WUS-NP-GENAI-APR-RG-02 `
  --query "[].{name:name, publicAccess:publicNetworkAccess}" -o table

# estado y destino del SPL blob
az search shared-private-link-resource show `
  --service-name srch-iunaos-gptrag-bot01-wus-001 -g HCD-WUS-NP-GENAI-APR-RG-02 `
  --name spl-srch-iunaos-gptrag-bot01-wus-001-blob-0 `
  --query "{status:properties.status, target:properties.privateLinkResourceId}" -o json
```

Resultado (2026-08-13):

| Ítem | Valor |
|---|---|
| Storage real (main) | `stiunaosgptragbot01wus00` — `publicNetworkAccess: Disabled` |
| Storage Foundry | `staifiunaosgptragbot01wu` — `Disabled` |
| SPL `spl-...-blob-0` | `provState: Succeeded`, **`status: Pending`** → `stiunaosgptragbot01wus00` |
| PE conn. en el storage | `...d476327a` **Approved** (VNet), `...01ead489` **Pending** (SPL de Search) |

**Causa raíz:** la conexión del SPL Search→blob está **Pending** (sin aprobar).
Sin ruta privada aprobada, Search cae a acceso público y el storage (público
deshabilitado) responde **403** → falla la creación del knowledge source. Es el
patrón estándar de los shared private link de Search (nacen `Pending` y hay que
**aprobarlos** en el destino); AILZ/post-provision **no** los auto-aprueba
→ **candidato a Change 5** en `ailz-improvements.md`.

**Fix (requiere PIM activo — acción `privateEndpointConnectionsApproval/action`):**

```powershell
az storage account private-endpoint-connection approve `
  --account-name stiunaosgptragbot01wus00 -g HCD-WUS-NP-GENAI-APR-RG-02 `
  --name "stiunaosgptragbot01wus00.01ead489-b080-403f-8cef-7b2abe093963" `
  --description "AI Search Foundry IQ blob knowledge source"

# verificar que el SPL pase a Approved (1–2 min de propagación)
az search shared-private-link-resource show `
  --service-name srch-iunaos-gptrag-bot01-wus-001 -g HCD-WUS-NP-GENAI-APR-RG-02 `
  --name spl-srch-iunaos-gptrag-bot01-wus-001-blob-0 --query "properties.status" -o tsv   # -> Approved

# reintentar SOLO el post-provision (idempotente; re-crea knowledge source/base)
azd hooks run postprovision
```

> El deploy de las **imágenes** (Paso 3) **no depende** del knowledge base, así
> que puede hacerse en paralelo; la retrieval se habilita al aprobar el SPL.

> ✅ **Aprobación aplicada (2026-08-13):** `az storage account
> private-endpoint-connection approve` devolvió `status: Approved` y el SPL
> `spl-...-blob-0` pasó a **`Approved`**. (El private endpoint del SPL vive en
> una suscripción/RG gestionados por AI Search — `.../resourceGroups/azscbyd` —
> lo cual es normal para los shared private link de Search.) Reintento del
> post-provision en curso.

### ¿Por qué se provisiona Foundry IQ si "no lo vamos a usar"?

No es un extra opcional: **Foundry IQ es el *retrieval backend* configurado en
este despliegue**. El entorno tiene `RETRIEVAL_BACKEND=foundry_iq` y
`FOUNDRY_IQ_PATTERN=azureBlob` (es el **default** de GPT-RAG en esta versión). Con
ese valor:

- El **Bicep** ya creó infraestructura real dependiente de `foundry_iq`: la
  **conexión knowledge-base** de AI Foundry y los **shared private links**
  Search→Foundry/OpenAI/CogSvc (ver [infra/main.bicep](infra/main.bicep), guard
  `retrievalBackend == 'foundry_iq'`).
- El **post-provision** crea el **knowledge source** (`knowledge-base-blob-ks`,
  ingesta nativa del blob `documents`) y la **knowledge base** (`knowledge-base`)
  que el orquestador consulta para recuperar. **Sin ellos no hay retrieval** — el
  RAG no tendría de dónde traer contexto.

Es decir, para este despliegue **Foundry IQ ES el motor de recuperación**, no una
función secundaria. Si de verdad no se quisiera usar, habría que cambiar
`RETRIEVAL_BACKEND` al backend clásico de AI Search (`ai_search`), lo que **no**
crea knowledge sources/bases — pero es una decisión de arquitectura que implicaría
reconfigurar (y re-aprovisionar parte de) lo ya desplegado con `foundry_iq`.

---

## Paso 3: Desplegar las Container Apps sin Docker (`westus`)

Recordatorio del bloqueo (00-test.md, Paso 16): en red aislada el ACR es Premium
con acceso público deshabilitado, y el **agent pool de ACR Tasks no existe en
`westus`**, así que el path por defecto "sin Docker vía agent pool en la VNet" no
aplica. La jumpbox no trae Docker a propósito.

### Opción A (recomendada): abrir el ACR temporalmente + `azd deploy`

```powershell
$ACR = "criunaosgptragbot01wus001"
az acr update -n $ACR --public-network-access Enabled     # requiere PIM (Network write)
azd deploy
az acr update -n $ACR --public-network-access Disabled    # volver a cerrar
```

Ventana breve de exposición del ACR (el push igual requiere autenticación).

#### Ejecución real (2026-08-13)

Se toparon dos obstáculos antes de que el ACR quedara abierto:

1. **`az acr update --public-network-access` no reconocido.** El `az` CLI de la
   jump VM es viejo y ese flag no existe en su `az acr update`:

   ```
   unrecognized arguments: --public-network-access Enabled
   ```

   **Fallback (sin actualizar CLI):** parchear la propiedad por el plano de
   recursos genérico con `az resource update`:

   ```powershell
   $RG    = (azd env get-value AZURE_RESOURCE_GROUP)
   $ACR   = az acr list -g $RG --query "[0].name" -o tsv   # criunaosgptragbot01wus001
   $ACRID = az acr show -n $ACR --query id -o tsv

   az resource update --ids $ACRID --set properties.publicNetworkAccess=Enabled
   az resource show   --ids $ACRID --query "properties.publicNetworkAccess" -o tsv   # -> Enabled
   ```

2. **`AuthorizationFailed` en el primer intento (PIM expirado).**

   ```
   (AuthorizationFailed) ... does not have authorization to perform action
   'Microsoft.ContainerRegistry/registries/write' ...
   If access was recently granted, please refresh your credentials.
   ```

   El rol es PIM-elegible; tras **reactivar PIM** y reintentar, el
   `az resource update` funcionó y el ACR quedó `publicNetworkAccess: Enabled`
   (con `networkRuleSet.defaultAction: Allow`, SKU Premium). Luego se lanzó
   `azd deploy`.

> ⚠️ **Recordatorio:** al terminar el deploy, **volver a cerrar** el ACR con el
> mismo mecanismo:
>
> ```powershell
> az resource update --ids $ACRID --set properties.publicNetworkAccess=Disabled
> az resource show   --ids $ACRID --query "properties.publicNetworkAccess" -o tsv   # -> Disabled
> ```
>
> Hazlo aunque el deploy falle, para no dejar el ACR expuesto.

> Alternativa: `az upgrade` para tener los flags nativos
> (`az acr update -n $ACR --public-network-access Enabled/Disabled`).

### Opción B: cambiar a una región con agent pools

Redeploy completo en `westus2` / `eastus2` / `southcentralus` y re-verificar que
`DataZoneStandard` esté disponible allí para ambos modelos.

### Opción C: Docker dentro de la VNet

Instalar Docker en la jumpbox u otra VM — es, efectivamente, usar Docker.

---

## Paso 4: Validación

- Las 3 Container Apps (`orchestrator`, `frontend`, `dataingest`) **running** y healthy.
- Claves de App Configuration (label `gpt-rag`) pobladas.
- El endpoint del frontend responde por la ruta de acceso privada.
- Model deployments en `DataZoneStandard` (requisito de residencia).

---

## Guardrails

- **Nunca** cambiar un modelo a SKU `Global*`. Mantener `DataZoneStandard`.
- **No** usar `PREFLIGHT_SKIP` / `GPT_RAG_REGIONAL_PREFLIGHT_SKIP` para saltar
  fallos — arreglar la causa.
- Mantener intactas las 4 customizaciones del repo (ver [README.md](README.md)).
- Verificar la suscripción activa antes de cualquier acción
  (`az account show -o table`).
- No commitear secretos.

---

## Estado actual

- Entorno `azd` `gptrag-bot01` **rehidratado** en la jump VM (`.env` con 54 outputs
  vía `azd env refresh`, deployment `gptrag-bot01-1786492185`).
- ACR `criunaosgptragbot01wus001` **abierto temporalmente**
  (`publicNetworkAccess: Enabled`) vía `az resource update`.
- Conditional Access (AADSTS53003) sobre App Config/Graph desde la VM → **resuelto**
  con `az login --scope` interactivo (era MFA, no device-compliance).
- **Post-provision** ejecutado vía `azd hooks run postprovision`: App Config poblado
  (**136 claves**), governance/Foundry/Container-Apps/índices OK; **falla solo** la
  creación del knowledge source/base de **Foundry IQ** (Search→Storage blob 403 por
  SPL no operativo).
- SPL Search→Storage `blob` **aprobado** (`status: Approved`) → reintentando el
  post-provision para crear el knowledge source/base.
- Pendiente: confirmar knowledge base creada; deploy de imágenes; cerrar el ACR.

## Próximos pasos

- [x] Rehidratar el entorno `azd` en la jump VM (`azd env refresh`).
- [x] Resolver Conditional Access para App Config (`az login --scope`).
- [x] Abrir el ACR temporalmente (`publicNetworkAccess=Enabled`).
- [x] Post-provision vía `azd hooks run postprovision` → App Config poblado (136 claves).
- [x] Aprobar el SPL Search→Storage `blob` (`status: Approved`).
- [ ] Reintentar `azd hooks run postprovision` → knowledge source/base creados.
- [ ] `azd deploy` — build + deploy de las 3 Container Apps (App Config ya listo).
- [ ] **Cerrar el ACR** (`publicNetworkAccess=Disabled`) al terminar el deploy.
- [ ] Validar apps (orchestrator / frontend / dataingest) + endpoint + retrieval.
- [ ] Abrir el PR a `Azure/bicep-ptn-aiml-landing-zone` (`ailz-improvements.md`, Changes 1–5).
