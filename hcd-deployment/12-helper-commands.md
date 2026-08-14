# Helper Commands — Referencia HCD GPT-RAG

> Recopilación de comandos usados durante el despliegue HCD, **agrupados por
> propósito**, con contexto de para qué sirve cada uno. Referencia rápida (puede
> duplicar comandos de otros docs). Todo se corre **desde la jump VM** (dentro de la
> VNet) salvo que se indique.

```toc
```

---

## 🔧 Setup y contexto

### Variables base (setear una vez por sesión)

```powershell
# Identidad / suscripción
$SUB     = "<SUBSCRIPTION_ID>"                          # HCD-NON-PROD
$TENANT  = "<TENANT_ID>"                                # CA Housing & Community Development

# Recursos
$RG      = "HCD-WUS-NP-GENAI-APR-RG-02"                 # grupo de recursos
$ENVName = "gptrag-bot01"                               # entorno azd
$VM      = "testvmiunaoskcf"                            # jump VM
$ACR     = "criunaosgptragbot01wus001"                 # Container Registry
$STORAGE = "stiunaosgptragbot01wus00"                  # storage principal (documents)
$SEARCH  = "srch-iunaos-gptrag-bot01-wus-001"          # AI Search (app)
$FOUNDRY = "aif-iunaos-gptrag-bot01-wus-001"           # Foundry / AI Services
$KV      = "kv-iunaos-gptrag-bot01-w"                  # Key Vault principal
$APPCFG  = "https://appcs-iunaos-gptrag-bot01-wus-001.azconfig.io"
$SEP     = "https://$SEARCH.search.windows.net"        # endpoint data-plane de Search
```

### Login y suscripción

```powershell
# verificar contexto activo (SIEMPRE antes de operar → debe ser HCD-NON-PROD)
az account show -o table

# login al tenant HCD (si hace falta)
az login --tenant $TENANT
azd auth login --tenant-id $TENANT
az account set --subscription $SUB
```

### Rehidratar el entorno azd (jump VM)

```powershell
# recrear el entorno y sus inputs
azd env new $ENVName
azd env set AZURE_SUBSCRIPTION_ID     $SUB
azd env set AZURE_RESOURCE_GROUP      $RG
azd env set AZURE_LOCATION            westus
azd env set NETWORK_ISOLATION         true
azd env set CHAT_DEPLOYMENT_SKU       DataZoneStandard
azd env set EMBEDDING_DEPLOYMENT_SKU  DataZoneStandard
azd env set RUN_FROM_JUMPBOX          true

# traer los OUTPUTS del deployment existente (NO recrea infra)
azd env refresh

# ver variables
azd env get-values
azd env get-value AZURE_RESOURCE_GROUP
```

**Contexto:** "rehidratar" = reconstruir `.azure/<env>/.env` en la VM para que `azd`
conozca el entorno ya aprovisionado sin recrear infraestructura.

---

## 🔐 Conditional Access / tokens (transversal)

```powershell
# si al leer App Config / Search / Storage sale AADSTS53003 (CA), login con el scope:
az login --scope https://appcs-iunaos-gptrag-bot01-wus-001.azconfig.io/.default
az login --scope https://search.azure.com/.default
az login --scope https://storage.azure.com/.default

# obtener un token puntual para un recurso (p. ej. Search)
az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
```

**Contexto:** desde la VM (dispositivo no compliant) CA bloquea la emisión de tokens
de data-plane; un `az login --scope` interactivo (MFA) lo resuelve. Aplica a varias
secciones de abajo.

---

## 🖥️ Jump VM (tamaño / Bastion)

```powershell
# tamaño actual y opciones disponibles en el host
az vm show -g $RG -n $VM --query "hardwareProfile.vmSize" -o tsv
az vm list-vm-resize-options -g $RG -n $VM --query "[].name" -o table

# cambiar tamaño (⚠️ reinicia la VM → se cae Bastion/RDP)
az vm resize -g $RG -n $VM --size Standard_D4s_v3     # subir
az vm resize -g $RG -n $VM --size Standard_D2s_v3     # bajar
# si el destino no está en list-vm-resize-options:
#   az vm deallocate -g $RG -n $VM; az vm resize ...; az vm start -g $RG -n $VM

# resetear password del admin de la VM (para Bastion)
az vm user update -g $RG -n $VM -u testvmuser -p '<nuevo-password>'

# túnel nativo de Bastion (desde workstation) + RDP a localhost:13389
az network bastion tunnel -n <bastion-name> -g $RG `
  --target-resource-id $(az vm show -g $RG -n $VM --query id -o tsv) `
  --resource-port 3389 --port 13389
```

**Contexto:** la VM es la jumpbox ZTA; el resize acelera builds/ingesta.

---

## 📦 Deploy de las apps

### ACR — abrir/cerrar acceso público

```powershell
$ACRID = az acr show -n $ACR --query id -o tsv

# abrir (para az acr build con el builder hosted) — requiere PIM
az resource update --ids $ACRID --set properties.publicNetworkAccess=Enabled
# cerrar (SIEMPRE al terminar)
az resource update --ids $ACRID --set properties.publicNetworkAccess=Disabled
# verificar
az resource show --ids $ACRID --query "properties.publicNetworkAccess" -o tsv
```

**Contexto:** en `westus` no hay ACR Tasks agent pool, así que el build usa el
builder hosted de Microsoft → el ACR debe estar público durante el `azd deploy`.
(El flag `az acr update --public-network-access` no existe en CLIs viejos → usar
`az resource update`.)

### azd deploy

```powershell
# con el ACR abierto y App Config poblado:
azd deploy
# o por componente:
azd deploy orchestrator ; azd deploy frontend ; azd deploy dataingest
```

**Contexto:** build remoto vía `az acr build` (sin Docker) + update de las Container
Apps. `ACR_TASK_AGENT_POOL` vacío → builder hosted → ACR público.

---

## ⚙️ Post-provision y data-plane

### Correr el post-provision

```powershell
azd env get-value RUN_FROM_JUMPBOX      # debe ser true
azd hooks run postprovision             # SOLO el hook (NO re-despliega el Bicep del AILZ)
```

**Contexto:** en ZTA el Bicep omite poblar App Config; lo hace el post-provision
(`scripts/postProvision.ps1`). `azd hooks run` evita re-desplegar `infra/`.

### App Configuration (verificar)

```powershell
az appconfig kv show --endpoint $APPCFG --key CONTAINER_REGISTRY_NAME `
  --label gpt-rag --auth-mode login --query value -o tsv
az appconfig kv list --endpoint $APPCFG --label gpt-rag --auth-mode login --query "length(@)" -o tsv
```

**Contexto:** confirmar que el post-provision pobló App Config (label `gpt-rag`).

### Shared Private Links (aprobar) — desbloquea Foundry IQ

```powershell
# estado de los 4 SPL del Search
az search shared-private-link-resource list --service-name $SEARCH -g $RG `
  --query "[].{name:name, group:properties.groupId, status:properties.status}" -o table

# SPL Search -> Storage (blob): aprobar la PE connection Pending en el storage
az storage account private-endpoint-connection approve `
  --account-name $STORAGE -g $RG --name "<pe-connection-name-Pending>" `
  --description "AI Search Foundry IQ blob knowledge source"

# SPL Search -> Foundry (account x3): aprobar las PE connections Pending en el Foundry
$FID = az cognitiveservices account show -n $FOUNDRY -g $RG --query id -o tsv
az network private-endpoint-connection list --id $FID `
  --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv
az network private-endpoint-connection approve --id "<pe-connection-id>" `
  --description "AI Search Foundry IQ standard extraction"
```

**Contexto:** AILZ crea los 4 SPL en estado **Pending** y no los auto-aprueba; hay
que aprobar **blob + los 3 del Foundry account** o el knowledge source falla con
`403 Public access is disabled`.

---

## 📄 Documentos y retrieval (Foundry IQ)

### Subir documentos al contenedor `documents`

```powershell
# el contenedor 'documents' YA existe (lo crea el provision); solo verificar
az storage container list --account-name $STORAGE --auth-mode login --query "[].name" -o table

# subir / listar / borrar (AAD, sin account key)
az storage blob upload-batch --account-name $STORAGE --auth-mode login `
  --destination documents --source "C:\ruta\a\pdfs" --pattern "*.pdf"
az storage blob list   --account-name $STORAGE --container-name documents --auth-mode login --query "[].name" -o table
az storage blob delete --account-name $STORAGE --container-name documents --auth-mode login --name "<archivo.pdf>"
```

**Contexto:** subir documentos de prueba para RAG. Si `403`, concederse **Storage
Blob Data Contributor** (PIM) sobre el storage.

### Indexer del knowledge source (Foundry IQ)

```powershell
$API = "2025-05-01-preview"
$tok = az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
$hdr = @{ Authorization = "Bearer $tok" }

# status resumido (lastResult.status=success, itemsProcessed>0, itemsFailed)
$st = Invoke-RestMethod -Headers $hdr -Uri "$SEP/indexers/knowledge-base-blob-ks-indexer/status?api-version=$API"
$st | Select-Object status, @{n='last';e={$_.lastResult.status}},
                     @{n='items';e={$_.lastResult.itemsProcessed}},
                     @{n='failed';e={$_.lastResult.itemsFailed}} | Format-List

# correr on-demand (ingiere blobs nuevos)
Invoke-RestMethod -Method Post -Headers $hdr -Uri "$SEP/indexers/knowledge-base-blob-ks-indexer/run?api-version=$API"

# errores por documento (p. ej. límite de 300 páginas de Content Understanding)
$st.lastResult.errors | ConvertTo-Json -Depth 6
```

**Contexto:** con `RETRIEVAL_BACKEND=foundry_iq` el orchestrator consulta la KB de
Foundry IQ (no el `ragindex`). Si el knowledge source se creó **antes** de subir los
PDFs, correr su indexer. `401` = token de Search expirado → refrescar `$tok`.

---

## ✅ Validación (Container Apps)

```powershell
# estado + FQDN de las 3 apps
az containerapp list -g $RG `
  --query "[].{name:name, running:properties.runningStatus, fqdn:properties.configuration.ingress.fqdn}" -o table

# FQDN del frontend + prueba de salud (ingress interno → desde la VNet)
$FE = az containerapp show -g $RG -n ca-iunaoskcfg3y2-frontend --query "properties.configuration.ingress.fqdn" -o tsv
curl.exe -sS -o NUL -w "%{http_code}`n" "https://$FE/"

# réplicas y logs
az containerapp replica list -g $RG -n ca-iunaoskcfg3y2-orchestrator --query "[].{replica:name, state:properties.runningState}" -o table
az containerapp logs show -g $RG -n ca-iunaoskcfg3y2-orchestrator --tail 50
az containerapp logs show -g $RG -n ca-iunaoskcfg3y2-frontend     --tail 50
az containerapp logs show -g $RG -n ca-iunaoskcfg3y2-dataingest   --tail 50
```

**Contexto:** validar que las apps corren, el endpoint responde (200) y revisar el
flujo del orchestrator (retrieval, timings, errores).

---

## 🧰 Git / preparación de PR

```powershell
git diff --stat main...HEAD                      # archivos cambiados vs main
git --no-pager diff main...HEAD -- <archivo>     # diff de un archivo
git status --short                               # cambios sin commitear
```

**Contexto:** preparar la PR upstream (ver `gpt-rag-PR-Doc.md`).

---

## ⚠️ Gotchas rápidos

| Síntoma | Causa / fix |
|---|---|
| `AADSTS53003` | Conditional Access → `az login --scope <recurso>/.default` |
| `401` en Search REST | token expirado → refrescar `$tok` |
| `AuthorizationFailed` (write) | PIM expirado → reactivar PIM |
| `403 Public access is disabled` (knowledge source) | SPL Pending → aprobar (sección Post-provision) |
| `401 Unable to retrieve blob ... 'stiunaoskcfg3y2'` | nombre de storage mal resuelto → fix en `postProvision.ps1` (prefijo `st`) |
| `InputPageCountExceeded` | PDF > 300 pág. → partir (`qpdf --split-pages=300`) o `minimal` |
| ACR build falla en ZTA | abrir ACR público temporalmente (sección Deploy) |
