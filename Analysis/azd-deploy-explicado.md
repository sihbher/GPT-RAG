# Qué hace `azd deploy` — Explicación paso a paso

> **Proyecto:** `azure-gpt-rag` (`my-gpt-rag-try01`)  
> **Comando:** `azd deploy` (o `azd deploy <servicio>` para un componente específico)

---

## Resumen general

`azd deploy` **no despliega infraestructura** (eso lo hace `azd provision`). Su función es tomar el código de los 4 componentes de la solución, construir imágenes Docker para cada uno, subirlas al Azure Container Registry (ACR), y actualizar los Azure Container Apps para que corran la nueva versión.

```
Tu máquina (Apple Silicon)
       │
       ▼
scripts/preDeploy.sh          ← hook PRE-deploy (disparado por azd)
       │  lee infra/manifest.json
       │  git clone cada componente
       │  por cada componente:
       │      scripts/deploy.sh  (en el repo del componente)
       │           ├─ docker build --platform linux/amd64
       │           ├─ docker push → ACR (Azure Container Registry)
       │           └─ az containerapp update  → Azure Container Apps
       ▼
Azure Container Apps (4 apps corriendo la nueva imagen)
```

---

## Fase 1 — azd lee `azure.yaml` y dispara el hook `predeploy`

Al correr `azd deploy`, lo primero que hace el CLI de Azure Developer es leer el archivo `azure.yaml` en la raíz del proyecto:

```yaml
hooks:
  predeploy:
    posix:
      shell: sh
      run: scripts/preDeploy.sh
      interactive: true
```

Antes de hacer cualquier despliegue, azd ejecuta **`scripts/preDeploy.sh`**.

---

## Fase 2 — `scripts/preDeploy.sh` prepara los 4 repositorios de componentes

Este script es el orquestador central del deploy. Hace lo siguiente:

### 2.1 — Verificaciones iniciales

- **Zero Trust check:** Si `AZURE_ZERO_TRUST=TRUE`, pide confirmación de que los recursos Azure son accesibles (necesario cuando la infraestructura está en una VNET privada con Bastion).
- **Docker check:** Verifica que Docker Desktop esté corriendo. Si no, termina con error:  
  `"Docker daemon is not running. Start Docker Desktop and try again"`
- **Localización del repo raíz:** Busca el directorio que contiene `infra/manifest.json` para anclar todas las rutas relativas.
- **Variables de entorno:** Lee `AZURE_RESOURCE_GROUP` y `AZURE_SUBSCRIPTION_ID` del entorno azd (archivo `.azure/<env>/.env`).
- **Validación del Resource Group:** Ejecuta `az group exists` para confirmar que el RG existe en Azure antes de continuar.

### 2.2 — Lee `infra/manifest.json`

El archivo `manifest.json` define los 4 componentes a desplegar y las versiones exactas:

```json
{
  "components": [
    { "name": "gpt-rag-ui",           "repo": "https://github.com/azure/gpt-rag-ui.git",           "tag": "v2.2.1" },
    { "name": "gpt-rag-mcp",          "repo": "https://github.com/azure/gpt-rag-mcp.git",          "tag": "v0.3.5" },
    { "name": "gpt-rag-orchestrator", "repo": "https://github.com/azure/gpt-rag-orchestrator.git", "tag": "v2.4.1" },
    { "name": "gpt-rag-ingestion",    "repo": "https://github.com/azure/gpt-rag-ingestion.git",    "tag": "v2.2.2" }
  ]
}
```

### 2.3 — Por cada componente: clona y ejecuta su deploy script

Para cada uno de los 4 componentes, el script hace:

1. **Verifica que el tag exista** en GitHub (`git ls-remote --tags`). Si no existe, omite el componente con un warning.
2. **Borra el directorio local** si ya existía: `rm -rf ../gpt-rag-ui`, etc.
3. **Clona el repo** en la carpeta hermana del proyecto actual:
   ```
   git clone --depth 1 https://github.com/azure/gpt-rag-ui.git ../gpt-rag-ui
   git fetch --tags origin v2.2.1
   git checkout v2.2.1
   ```
   El destino es `../` relativo al repo raíz, es decir todos los repos quedan en:
   ```
   /Users/gerardoreyes/Repos/ai-demos/
   ├── my-gpt-rag-try01/      ← repo principal
   ├── gpt-rag-ui/            ← clonado aquí
   ├── gpt-rag-mcp/           ← clonado aquí
   ├── gpt-rag-orchestrator/  ← clonado aquí
   └── gpt-rag-ingestion/     ← clonado aquí
   ```
4. **Copia `.azure/`** del repo principal al clonado, para que el componente tenga acceso a las variables de entorno azd.
5. **Ejecuta `scripts/deploy.sh`** dentro del componente clonado, redirigiendo toda la salida a un log:
   ```
   cd ../gpt-rag-mcp && bash scripts/deploy.sh > .logs/deploy_<timestamp>.log 2>&1
   ```

> ⚠️ **Importante:** Como el repo es clonado desde el tag oficial en GitHub en cada deploy, cualquier cambio local en el repo del componente (ej: el fix de `--platform linux/amd64` en gpt-rag-mcp) **se pierde**. Ver sección de problemas conocidos al final.

---

## Fase 3 — `scripts/deploy.sh` de cada componente: build, push y actualización

Cada componente tiene su propio `scripts/deploy.sh`. Todos siguen el mismo patrón (ejemplo: `gpt-rag-mcp`):

### 3.1 — Obtiene la configuración desde Azure App Configuration

El script se conecta a la instancia de **Azure App Configuration** (`appcs-lceaba747tjgw.azconfig.io`) y lee 4 valores con el label `gpt-rag`:

| Clave en App Config          | Ejemplo de valor                          | Para qué se usa               |
|------------------------------|-------------------------------------------|-------------------------------|
| `CONTAINER_REGISTRY_NAME`    | `crlceaba747tjgw`                        | Login en ACR                  |
| `CONTAINER_REGISTRY_LOGIN_SERVER` | `crlceaba747tjgw.azurecr.io`        | Tag y push de la imagen       |
| `AZURE_RESOURCE_GROUP`       | `GPT-RAG-001`                            | Actualizar el Container App   |
| `MCP_APP_NAME`               | `ca-lceaba747tjgw-mcp`                   | Nombre del Container App      |

### 3.2 — Login en Azure Container Registry

```bash
az acr login --name crlceaba747tjgw
```

Autentica Docker contra el ACR de Azure usando las credenciales del Azure CLI.

### 3.3 — Define el tag de la imagen

```bash
tag=$(git rev-parse --short HEAD)   # ej: bba88fb
```

Usa el hash corto del commit actual del repo clonado como identificador de versión de la imagen.

### 3.4 — Construye la imagen Docker

```bash
docker build \
  --platform linux/amd64 \
  -t crlceaba747tjgw.azurecr.io/azure-gpt-rag/mcp:bba88fb \
  .
```

**`--platform linux/amd64` es crítico:** Azure Container Apps solo acepta imágenes `linux/amd64`. En Apple Silicon (arm64), Docker construye para `arm64` por defecto, lo que causa que Azure rechace la imagen con error:
```
no child with platform linux/amd64 in index
```

La imagen sigue el esquema de nombres: `<loginServer>/azure-gpt-rag/<componente>:<git-hash>`

### 3.5 — Sube la imagen al ACR

```bash
docker push crlceaba747tjgw.azurecr.io/azure-gpt-rag/mcp:bba88fb
```

Empuja todas las capas de la imagen al Azure Container Registry.

### 3.6 — Actualiza el Azure Container App

```bash
az containerapp update \
  --name ca-lceaba747tjgw-mcp \
  --resource-group GPT-RAG-001 \
  --image crlceaba747tjgw.azurecr.io/azure-gpt-rag/mcp:bba88fb
```

Crea una nueva revisión del Container App apuntando a la nueva imagen. Azure Container Apps hace el rolling update automáticamente.

---

## Los 4 componentes y su función

| Componente           | Tag    | Azure Container App               | Función en la solución                        |
|----------------------|--------|-----------------------------------|-----------------------------------------------|
| `gpt-rag-ui`         | v2.2.1 | `ca-...-ui`                       | Frontend web (React/SPA) para el usuario final |
| `gpt-rag-mcp`        | v0.3.5 | `ca-...-mcp`                      | Servidor MCP — expone herramientas (tools) al orchestrator |
| `gpt-rag-orchestrator` | v2.4.1 | `ca-...-orchestrator`           | Motor central: recibe preguntas, orquesta RAG + MCP + LLM |
| `gpt-rag-ingestion`  | v2.2.2 | `ca-...-ingestion`                | Indexa documentos en Azure AI Search          |

---

## Flujo completo con tiempos aproximados

```
azd deploy
  │
  ├─ [~1s]   Lee azure.yaml → dispara scripts/preDeploy.sh
  │
  ├─ [~10s]  Verificaciones: Docker, Azure CLI, Resource Group
  │
  ├─ Por cada componente (x4):
  │   ├─ [~5s]   git clone --depth 1 + checkout tag
  │   ├─ [~2s]   App Config: lee 4 valores vía az CLI
  │   ├─ [~1s]   az acr login
  │   ├─ [~3-8min] docker build --platform linux/amd64  ← más lento en Apple Silicon (emulación QEMU)
  │   ├─ [~30s]  docker push → ACR
  │   └─ [~15s]  az containerapp update → nueva revisión en Azure
  │
  └─ [Total: ~20-35 minutos] para los 4 componentes en Apple Silicon
```

---

## Cómo ejecutar deploy de un solo componente

Si solo quieres redesplegar el MCP sin tocar los otros:

```bash
# Desde el directorio del componente directamente:
cd /Users/gerardoreyes/Repos/ai-demos/gpt-rag-mcp
bash scripts/deploy.sh
```

O si `preDeploy.sh` admite filtrado (actualmente no), la única forma es correr el deploy script del componente directamente.

---

## Problemas conocidos

### ⚠️ Fix de `--platform` se pierde en cada deploy

**Síntoma:** `gpt-rag-mcp` falla con `no child with platform linux/amd64 in index`

**Causa:** `preDeploy.sh` hace `rm -rf` del directorio y lo re-clona desde el tag `v0.3.5` de GitHub en **cada** ejecución de `azd deploy`. El tag oficial no tiene `--platform linux/amd64`, así que cualquier fix local se sobreescribe.

**Workaround actual:** Después de que `preDeploy.sh` clone el repo (o antes de que ejecute el deploy script), volver a agregar la línea manualmente. O ejecutar `scripts/deploy.sh` directamente desde el directorio del componente (que no se re-clona si ya existe).

**Solución definitiva:** El fix debe mergearse en el upstream: `https://github.com/azure/gpt-rag-mcp` (issue pendiente de reportar).

### ⚠️ Build lento en Apple Silicon

El flag `--platform linux/amd64` activa emulación QEMU en Apple Silicon (M1/M2/M3). El build puede tardar 5-8 minutos por componente en lugar de ~1 minuto. Es normal.

---

## Variables de entorno relevantes

| Variable                  | Dónde vive                          | Qué controla                              |
|---------------------------|-------------------------------------|-------------------------------------------|
| `AZURE_RESOURCE_GROUP`    | `.azure/<env>/.env`                 | Resource group donde están los Container Apps |
| `AZURE_SUBSCRIPTION_ID`   | `.azure/<env>/.env`                 | Subscripción de Azure                     |
| `APP_CONFIG_ENDPOINT`     | `.azure/<env>/.env` o `az env set`  | URL del Azure App Configuration           |
| `AZURE_ZERO_TRUST`        | Shell env                           | Si es `TRUE`, pide confirmación manual antes de deploy |
| `tag`                     | Shell env (opcional)               | Sobreescribe el git hash como tag de imagen |
| `DEBUG`                   | Shell env (opcional)               | Si es `true`, activa `set -x` en deploy.sh |
