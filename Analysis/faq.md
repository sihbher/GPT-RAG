# FAQ — GPT-RAG Solution Accelerator

> Preguntas frecuentes para entender y operar este repositorio. Haz clic en cualquier pregunta del índice para ir directamente a la respuesta.

---

## Índice

### 🔰 Conceptos Generales
- [¿Qué es GPT-RAG y para qué sirve?](#qué-es-gpt-rag-y-para-qué-sirve)
- [¿Qué es RAG y por qué es importante?](#qué-es-rag-y-por-qué-es-importante)
- [¿Cuál es la diferencia entre este repo y usar ChatGPT directamente?](#cuál-es-la-diferencia-entre-este-repo-y-usar-chatgpt-directamente)
- [¿Este repositorio es una aplicación completa o solo infraestructura?](#este-repositorio-es-una-aplicación-completa-o-solo-infraestructura)
- [¿Qué es MCP (Model Context Protocol) en este contexto?](#qué-es-mcp-model-context-protocol-en-este-contexto)
- [¿Qué es Agentic Retrieval?](#qué-es-agentic-retrieval)

### ⚙️ Prerrequisitos y Configuración
- [¿Qué herramientas necesito instalar antes de empezar?](#qué-herramientas-necesito-instalar-antes-de-empezar)
- [¿Cómo verifico si mi suscripción de Azure tiene cuota disponible?](#cómo-verifico-si-mi-suscripción-de-azure-tiene-cuota-disponible)
- [¿En qué regiones de Azure funciona mejor?](#en-qué-regiones-de-azure-funciona-mejor)
- [¿Necesito tener Docker instalado?](#necesito-tener-docker-instalado)
- [¿Qué permisos de Azure necesito para desplegar?](#qué-permisos-de-azure-necesito-para-desplegar)

### 🚀 Despliegue
- [¿Cuáles son los comandos básicos para desplegar?](#cuáles-son-los-comandos-básicos-para-desplegar)
- [¿Cuánto tiempo tarda el despliegue completo?](#cuánto-tiempo-tarda-el-despliegue-completo)
- [¿Qué hace `azd provision` vs `azd deploy`?](#qué-hace-azd-provision-vs-azd-deploy)
- [¿Qué son los hooks preProvision, postProvision y preDeploy?](#qué-son-los-hooks-preprovision-postprovision-y-predeploy)
- [¿Puedo desplegar solo algunos componentes y no todos?](#puedo-desplegar-solo-algunos-componentes-y-no-todos)
- [¿Cómo configuro parámetros antes de desplegar?](#cómo-configuro-parámetros-antes-de-desplegar)
- [¿Cómo se forman los nombres de los recursos de Azure?](#cómo-se-forman-los-nombres-de-los-recursos-de-azure)
- [¿Puedo reutilizar un Azure AI Search existente en lugar de crear uno nuevo?](#puedo-reutilizar-un-azure-ai-search-existente-en-lugar-de-crear-uno-nuevo)
- [¿Qué es el `manifest.json` y para qué se usa?](#qué-es-el-manifestjson-y-para-qué-se-usa)

### 🔒 Seguridad y Zero Trust
- [¿Qué es el modo Zero Trust / Network Isolation?](#qué-es-el-modo-zero-trust--network-isolation)
- [¿Cómo accedo a los recursos una vez activado Zero Trust?](#cómo-accedo-a-los-recursos-una-vez-activado-zero-trust)
- [¿Puedo usar mi propia VNet existente?](#puedo-usar-mi-propia-vnet-existente)
- [¿Cómo se manejan los secretos y las contraseñas?](#cómo-se-manejan-los-secretos-y-las-contraseñas)
- [¿Qué es Managed Identity y por qué el sistema la usa?](#qué-es-managed-identity-y-por-qué-el-sistema-la-usa)
- [¿Cómo funciona la seguridad a nivel de documento?](#cómo-funciona-la-seguridad-a-nivel-de-documento)

### 📄 Ingesta de Documentos
- [¿Dónde subo los documentos para que el sistema los procese?](#dónde-subo-los-documentos-para-que-el-sistema-los-procese)
- [¿Qué formatos de documentos soporta el sistema?](#qué-formatos-de-documentos-soporta-el-sistema)
- [¿Cómo funciona el proceso de indexación de documentos?](#cómo-funciona-el-proceso-de-indexación-de-documentos)
- [¿Cada cuánto tiempo se actualizan los documentos en el índice?](#cada-cuánto-tiempo-se-actualizan-los-documentos-en-el-índice)
- [¿Qué modelo de embeddings se usa para vectorizar documentos?](#qué-modelo-de-embeddings-se-usa-para-vectorizar-documentos)

### 🤖 Modelos de IA
- [¿Qué modelos de IA están configurados por defecto?](#qué-modelos-de-ia-están-configurados-por-defecto)
- [¿Cómo cambio el modelo de lenguaje que se usa?](#cómo-cambio-el-modelo-de-lenguaje-que-se-usa)
- [¿Puedo usar modelos de otros proveedores que no sean OpenAI?](#puedo-usar-modelos-de-otros-proveedores-que-no-sean-openai)
- [¿Qué políticas de IA Responsable (RAI) están configuradas?](#qué-políticas-de-ia-responsable-rai-están-configuradas)
- [¿Cómo personalizo los filtros de contenido?](#cómo-personalizo-los-filtros-de-contenido)

### 🔧 Personalización e Integración
- [¿Cómo integro este sistema con mi propia aplicación?](#cómo-integro-este-sistema-con-mi-propia-aplicación)
- [¿Cómo agrego nuevas herramientas al agente AI (MCP)?](#cómo-agrego-nuevas-herramientas-al-agente-ai-mcp)
- [¿Cómo personalizo el índice de búsqueda?](#cómo-personalizo-el-índice-de-búsqueda)
- [¿Cómo agrego soporte para SharePoint?](#cómo-agrego-soporte-para-sharepoint)
- [¿Cómo funciona el feature de NL2SQL?](#cómo-funciona-el-feature-de-nl2sql)
- [¿Puedo usar Bing Search para buscar en internet además de mis documentos?](#puedo-usar-bing-search-para-buscar-en-internet-además-de-mis-documentos)

### 💰 Costos
- [¿Cuánto cuesta desplegar este sistema en Azure?](#cuánto-cuesta-desplegar-este-sistema-en-azure)
- [¿Cuáles son los recursos más costosos?](#cuáles-son-los-recursos-más-costosos)
- [¿Cómo puedo reducir costos en un entorno de desarrollo o pruebas?](#cómo-puedo-reducir-costos-en-un-entorno-de-desarrollo-o-pruebas)

### 🛠️ Solución de Problemas
- [El `postProvision.sh` falla con un error de autenticación. ¿Qué hago?](#el-postprovisionsh-falla-con-un-error-de-autenticación-qué-hago)
- [El `preDeploy.sh` falla porque Docker no está corriendo. ¿Cómo lo soluciono?](#el-predeploysh-falla-porque-docker-no-está-corriendo-cómo-lo-soluciono)
- [El script de App Configuration falla con timeout. ¿Qué hago?](#el-script-de-app-configuration-falla-con-timeout-qué-hago)
- [Cosmos DB da error `cosmos_vnet_blocked`. ¿Cómo lo resuelvo?](#cosmos-db-da-error-cosmos_vnet_blocked-cómo-lo-resuelvo)
- [Las Container Apps arrancan con una imagen de prueba (hello world). ¿Es normal?](#las-container-apps-arrancan-con-una-imagen-de-prueba-hello-world-es-normal)
- [¿Cómo actualizo a una versión más nueva del sistema?](#cómo-actualizo-a-una-versión-más-nueva-del-sistema)

---

## 🔰 Conceptos Generales

---

### ¿Qué es GPT-RAG y para qué sirve?

GPT-RAG (Generative Pre-trained Transformer — Retrieval-Augmented Generation) es un **acelerador de soluciones de código abierto de Microsoft** que te permite desplegar un sistema de chatbot empresarial completo en Azure. Permite a las organizaciones:

- Hacer preguntas en lenguaje natural sobre sus propios documentos internos.
- Obtener respuestas fundamentadas en información real (no alucinaciones).
- Operar con seguridad empresarial (Zero Trust, RBAC, privacidad de datos).
- Integrar agentes AI que pueden razonar y actuar sobre múltiples fuentes de datos.

**Documentación oficial**: https://azure.github.io/GPT-RAG/

---

### ¿Qué es RAG y por qué es importante?

RAG es un patrón arquitectónico que combina dos cosas:

1. **Retrieval (Recuperación)**: Buscar los fragmentos de documentos más relevantes para una pregunta.
2. **Augmented Generation (Generación Aumentada)**: Pasar esos fragmentos al LLM junto con la pregunta para que genere una respuesta informada.

**¿Por qué es importante?**
- Sin RAG, el LLM solo sabe lo que aprendió en su entrenamiento (corte de conocimiento).
- Con RAG, el LLM puede responder sobre tus documentos específicos, actualizados y privados.
- Reduce drásticamente las alucinaciones al anclar la respuesta en texto real.
- Cumple con requisitos de privacidad: tus documentos no salen de tu Azure.

---

### ¿Cuál es la diferencia entre este repo y usar ChatGPT directamente?

| Aspecto | ChatGPT Directo | GPT-RAG |
|---|---|---|
| Conocimiento | Solo entrenamiento del modelo | Tus documentos corporativos |
| Privacidad | Datos van a servidores de OpenAI | Todo dentro de tu Azure |
| Actualización | Limitado por fecha de corte | Actualiza con tus nuevos docs |
| Seguridad | Sin control de acceso a nivel doc | Zero Trust + ACL por documento |
| Citas | No cita fuentes | Cita el documento y fragmento exacto |
| Agentes | Capacidad básica | MCP + herramientas personalizadas |
| Costo | Por uso (pay-per-query) | Azure OpenAI managed (tu suscripción) |

---

### ¿Este repositorio es una aplicación completa o solo infraestructura?

Ambas cosas. Es un **repositorio orquestador** que:
- Contiene la **infraestructura como código** (Bicep) para crear los recursos Azure.
- Referencia **4 repositorios de aplicaciones** en `infra/manifest.json` que se clonan y despliegan automáticamente.
- Contiene **scripts de configuración** (Python) que ajustan AI Foundry, AI Search y Container Apps después de crearlos.

Los 4 repos de aplicación son:
- `github.com/azure/gpt-rag-ui` — Frontend web
- `github.com/azure/gpt-rag-orchestrator` — Motor de orquestación RAG
- `github.com/azure/gpt-rag-ingestion` — Pipeline de ingesta de documentos
- `github.com/azure/gpt-rag-mcp` — Servidor MCP para agentes AI

---

### ¿Qué es MCP (Model Context Protocol) en este contexto?

MCP es un **protocolo estándar abierto** (similar a un "USB para herramientas de AI") que permite a los modelos de lenguaje conectarse con sistemas externos. En GPT-RAG:

- El componente `gpt-rag-mcp` es un **servidor MCP** que expone herramientas al orquestador.
- El orquestador puede usar esas herramientas para completar tareas: consultar bases de datos, llamar APIs, acceder a información en tiempo real.
- Añadir tus propias herramientas convierte el chatbot en un **agente AI** capaz de actuar.

---

### ¿Qué es Agentic Retrieval?

Agentic Retrieval es una función de **Azure AI Search** que usa el LLM para mejorar las búsquedas automáticamente. En lugar de hacer una búsqueda simple, el sistema:

1. Analiza la pregunta del usuario con el LLM.
2. Genera múltiples queries de búsqueda alternativas.
3. Las combina para obtener resultados más completos y precisos.

Se activa con `ENABLE_AGENTIC_RETRIEVAL=true` en las variables AZD. Requiere Azure AI Search con Knowledge Agent habilitado.

---

## ⚙️ Prerrequisitos y Configuración

---

### ¿Qué herramientas necesito instalar antes de empezar?

| Herramienta | Instalación | Verificación |
|---|---|---|
| Azure Developer CLI | https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd | `azd version` |
| Azure CLI | https://docs.microsoft.com/cli/azure/install-azure-cli | `az version` |
| Docker Desktop | https://www.docker.com/products/docker-desktop/ | `docker info` |
| Python 3.9+ | https://www.python.org/downloads/ | `python3 --version` |
| Git | https://git-scm.com/ | `git --version` |

En Windows, también necesitas **PowerShell 7+** (`pwsh`).

---

### ¿Cómo verifico si mi suscripción de Azure tiene cuota disponible?

Usa el script incluido en el repo:

```bash
cd util
pip install -r requirements.txt
python prereqs.py
# Te pedirá la región (default: eastus2)
```

Esto verifica:
- Si tu suscripción tiene habilitado Cosmos DB en esa región.
- El uso actual de cuota de Azure OpenAI (TPM disponibles).

Si la cuota es insuficiente, pide incremento en: https://aka.ms/oai/quotaincrease

---

### ¿En qué regiones de Azure funciona mejor?

Las regiones con mejor disponibilidad de modelos OpenAI y servicios AI son:

- `eastus` / `eastus2` (recomendado para América)
- `westeurope` / `swedencentral` (Europa)
- `australiaeast` (Asia-Pacífico)

Puedes usar regiones distintas por componente:
- `AZURE_LOCATION` — región principal
- `AZURE_AI_FOUNDRY_LOCATION` — para modelos de IA (si quieres una región con mejor capacidad)
- `AZURE_COSMOS_LOCATION` — para Cosmos DB

---

### ¿Necesito tener Docker instalado?

**Sí, es obligatorio** para `azd deploy`. El script `preDeploy.sh` hace build de las imágenes Docker de los 4 componentes y las sube al Azure Container Registry.

Si Docker no está corriendo al ejecutar `azd deploy`, el script fallará inmediatamente con el mensaje:
```
Docker daemon is not running. Start Docker Desktop and try again
```

---

### ¿Qué permisos de Azure necesito para desplegar?

Necesitas ser **Owner** o tener los permisos equivalentes en el Resource Group donde vas a desplegar. Específicamente:

- Permiso para crear todos los recursos listados en el despliegue.
- Permiso para hacer **asignaciones de roles RBAC** (necesario porque el script asigna roles a las Managed Identities de las Container Apps).

El `principalId` en `main.parameters.json` debe ser tu Object ID de Azure AD.

---

## 🚀 Despliegue

---

### ¿Cuáles son los comandos básicos para desplegar?

```bash
# Login
az login
azd auth login

# Crear entorno (una sola vez)
azd env new <nombre-entorno>

# Configurar variables mínimas
azd env set AZURE_LOCATION eastus2

# Provisionar infraestructura (crea recursos Azure)
azd provision

# Desplegar aplicaciones (build Docker + push + actualiza Container Apps)
azd deploy
```

---

### ¿Cuánto tiempo tarda el despliegue completo?

| Fase | Tiempo Aproximado |
|---|---|
| `azd provision` (primer despliegue) | 20–35 minutos |
| `azd provision` (actualizaciones) | 10–15 minutos |
| `postProvision.sh` (scripts Python) | 5–10 minutos |
| `azd deploy` (build + push + update) | 10–20 minutos |
| **Total primera vez** | **~45–65 minutos** |

---

### ¿Qué hace `azd provision` vs `azd deploy`?

| Comando | Qué hace |
|---|---|
| `azd provision` | Crea/actualiza todos los recursos de Azure usando Bicep (IaC). También ejecuta `preProvision` y `postProvision` hooks. |
| `azd deploy` | Construye las imágenes Docker de los 4 componentes, las sube al ACR y actualiza las Container Apps. Ejecuta el hook `preDeploy`. |

**Regla general**: `azd provision` para cambios de infraestructura; `azd deploy` para cambios de código de aplicación.

---

### ¿Qué son los hooks preProvision, postProvision y preDeploy?

Son scripts que AZD ejecuta automáticamente en momentos clave del ciclo de vida. Están definidos en `azure.yaml`:

| Hook | Script | Propósito |
|---|---|---|
| `preProvision` | `scripts/preProvision.sh` | Advierte sobre Zero Trust, pide confirmación |
| `postProvision` | `scripts/postProvision.sh` | Configura AI Foundry (RAI), Container Apps (ACR), AI Search (índices) |
| `preDeploy` | `scripts/preDeploy.sh` | Clona repos de componentes, hace build Docker y sube imágenes a ACR |

---

### ¿Puedo desplegar solo algunos componentes y no todos?

Sí. El `main.bicep` tiene **feature flags** que se configuran en `main.parameters.json`. Para desactivar un recurso, cambia su valor a `"false"`:

```json
"deployPostgres":   { "value": "false" },
"deployGroundingWithBing": { "value": "false" },
"deployVM":         { "value": "false" }
```

O vía CLI antes de provisionar:
```bash
azd env set DEPLOY_VM false
```

---

### ¿Cómo configuro parámetros antes de desplegar?

Tienes dos métodos:

**Método 1: Variables de entorno AZD**
```bash
azd env set NETWORK_ISOLATION false
azd env set ENABLE_AGENTIC_RETRIEVAL true
azd env set USE_UAI false
```

**Método 2: Editar `main.parameters.json`** directamente para valores que no cambian entre entornos.

Los parámetros con formato `"${VARIABLE}"` en `main.parameters.json` se sustituyen automáticamente con las variables AZD.

---

### ¿Cómo se forman los nombres de los recursos de Azure?

Cada recurso recibe un nombre con el patrón `<abreviatura> + <resourceToken>`. El `resourceToken` es un hash determinista de 13 caracteres calculado en `main.bicep`:

```bicep
param resourceToken string = toLower(uniqueString(subscription().id, environmentName, location))
```

Los tres inputs son:

| Input | Ejemplo |
|---|---|
| `subscription().id` | `d12d19a9-0636-4951-90a4-339158fd57d8` |
| `environmentName` | `gpt-rag-dev` |
| `location` | `eastus2` |

Ejemplos de nombres resultantes:

| Recurso | Patrón | Ejemplo |
|---|---|---|
| AI Search | `srch-<token>` | `srch-g5rp2aievnncc` |
| Key Vault | `kv-<token>` | `kv-g5rp2aievnncc` |
| App Config | `appcs-<token>` | `appcs-g5rp2aievnncc` |
| Storage Account | `st<token>` | `stg5rp2aievnncc` (sin guiones) |

El token resultante también se guarda en el `.env` como `RESOURCE_TOKEN`. Como `uniqueString()` es determinista, si vuelves a ejecutar `azd provision` con los mismos parámetros, obtienes los mismos nombres — garantizando idempotencia. Si cambias la región o el nombre del entorno, el token cambia y se crean recursos nuevos.

---

### ¿Puedo reutilizar un Azure AI Search existente en lugar de crear uno nuevo?

Sí. Configura dos cosas:

**1. En `main.parameters.json`** (o vía variable de ambiente):
```json
"deploySearchService":  { "value": "false" },
"aiSearchResourceId":   { "value": "${AI_SEARCH_RESOURCE_ID}" }
```

**2. En tu `.azure/<env>/.env`**:
```dotenv
DEPLOY_SEARCH_SERVICE="false"
AI_SEARCH_RESOURCE_ID="/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/<nombre>"
```

Para obtener el ARM resource ID de tu servicio existente:
```bash
az search service show \
  --name <nombre> \
  --resource-group <rg> \
  --query id -o tsv
```

**Advertencia sobre tiers**: El repo asume por defecto AI Search **Standard** (necesario para Semantic Search y Agentic Retrieval). Si tu servicio existente es tier **Basic**, desactiva Agentic Retrieval:
```bash
azd env set ENABLE_AGENTIC_RETRIEVAL false
```

> El despliegue **no modifica ni escala** un AI Search existente — solo lo referencia para crear la conexión con AI Foundry y escribir su endpoint en App Configuration.

---

### ¿Qué es el `manifest.json` y para qué se usa?

El archivo `infra/manifest.json` define exactamente qué versiones de los 4 componentes de aplicación se van a desplegar:

```json
{
  "tag": "v2.4.2",
  "components": [
    { "name": "gpt-rag-ui",           "tag": "v2.2.1" },
    { "name": "gpt-rag-mcp",          "tag": "v0.3.5" },
    { "name": "gpt-rag-orchestrator", "tag": "v2.4.1" },
    { "name": "gpt-rag-ingestion",    "tag": "v2.2.2" }
  ]
}
```

El script `preDeploy.sh` lee este archivo para saber qué tag de Git clonar de cada repositorio de componente antes de hacer el build Docker.

---

## 🔒 Seguridad y Zero Trust

---

### ¿Qué es el modo Zero Trust / Network Isolation?

Es un modo de alta seguridad donde **todos los recursos Azure tienen acceso público deshabilitado**. La comunicación ocurre solo dentro de una VNet privada mediante **Private Endpoints**.

Para activarlo:
```bash
azd env set NETWORK_ISOLATION true
azd provision
```

Implica:
- Se crea una VNet con subredes dedicadas.
- Se crean Private Endpoints para cada servicio (Storage, Cosmos, AI Search, etc.).
- Se crean Private DNS Zones para resolución de nombres.
- Se despliega Azure Bastion + VM de prueba para acceso remoto seguro.
- NSGs en todas las subredes.

---

### ¿Cómo accedo a los recursos una vez activado Zero Trust?

1. En Azure Portal, accede a **Azure Bastion** del resource group del despliegue.
2. Conecta a la **VM de prueba** (jumpbox) via Bastion.
3. Desde la VM, puedes acceder a todos los recursos privados.
4. El `postProvision.sh` también debe ejecutarse desde dentro de la VNet (o con VPN).

Las URLs de las Container Apps aún son públicas (si se configuraron como `external: true`), pero los servicios backend (AI Search, Cosmos, Storage) solo son alcanzables desde dentro de la VNet.

---

### ¿Puedo usar mi propia VNet existente?

Sí. Activa la opción y proporciona el Resource ID de tu VNet:

```bash
azd env set USE_EXISTING_VNET true
azd env set EXISTING_VNET_RESOURCE_ID "/subscriptions/.../virtualNetworks/mi-vnet"
```

Asegúrate de que tu VNet tiene las subredes necesarias con los prefijos correctos.

---

### ¿Cómo se manejan los secretos y las contraseñas?

- Todos los secretos se almacenan en **Azure Key Vault**.
- Las apps acceden a secretos via **Managed Identity** (no necesitan contraseñas).
- La contraseña de la VM se genera aleatoriamente con `$(secretOrRandomPassword)` y se guarda en Key Vault.
- La API key del modelo de IA se almacena en Key Vault como `evaluationsModelApiKey`.
- **No hay credenciales hardcodeadas** en ningún archivo del repositorio.

---

### ¿Qué es Managed Identity y por qué el sistema la usa?

Una **Managed Identity** es una identidad automática que Azure asigna a un recurso (en este caso, a cada Container App). Las ventajas:

- Azure gestiona el ciclo de vida de las credenciales automáticamente.
- No necesitas contraseñas ni claves de acceso en tu código.
- Las apps se autentican ante otros servicios Azure sin secrets.

GPT-RAG asigna roles RBAC específicos a cada Managed Identity según lo que necesita:
- El **Orchestrator** tiene `SearchIndexDataReader` pero no `SearchIndexDataContributor`.
- El **DataIngest** tiene `SearchIndexDataContributor` para poder escribir en el índice.

---

### ¿Cómo funciona la seguridad a nivel de documento?

Desde v2.4.0, GPT-RAG soporta **ACL/RBAC trimming** en Azure AI Search:

- Cada documento indexado lleva metadatos de quién puede acceder: `userIds`, `groupIds`, `rbacScope`.
- El usuario final debe pasar un token Azure AD en el header `x-ms-query-source-authorization`.
- Azure AI Search filtra los resultados para devolver solo documentos que el usuario tiene permiso de ver.
- Comportamiento seguro por defecto: sin token válido, no se devuelven resultados.

---

## 📄 Ingesta de Documentos

---

### ¿Dónde subo los documentos para que el sistema los procese?

Sube los documentos al **contenedor `documents`** del Azure Storage Account creado por el despliegue:

Puedes usar:
- **Azure Portal → Storage Account → Blob Storage → contenedor `documents`**
- **Azure Storage Explorer** (herramienta de escritorio)
- **Azure CLI**: `az storage blob upload --container-name documents --file mi.pdf --name mi.pdf`
- **Python SDK**: `BlobServiceClient.get_container_client("documents").upload_blob(...)`

---

### ¿Qué formatos de documentos soporta el sistema?

El pipeline de ingesta soporta:
- **PDF** (con OCR para PDFs escaneados)
- **Word** (.docx)
- **Excel** (.xlsx)
- **PowerPoint** (.pptx)
- **Texto plano** (.txt, .md)
- **HTML**
- **Imágenes** (via contenedor `documents-images` con OCR)
- **SharePoint** (listas y bibliotecas de documentos) — configuración adicional requerida

---

### ¿Cómo funciona el proceso de indexación de documentos?

```
1. Documento sube al Blob Storage (contenedor: documents)
        ↓
2. Azure AI Search Indexer detecta el nuevo archivo
        ↓
3. Skillset procesa el documento:
   - Divide en fragmentos (chunking)
   - Aplica OCR si es imagen o PDF escaneado
   - Genera embedding con text-embedding-3-large
        ↓
4. Cada fragmento se guarda en el índice con:
   - El texto del fragmento
   - Su vector (embedding)
   - Metadatos (nombre de archivo, URL, página, etc.)
        ↓
5. El documento ya es consultable via búsqueda semántica
```

---

### ¿Cada cuánto tiempo se actualizan los documentos en el índice?

Depende de la configuración del **Indexer** definida en la plantilla `config/search/search.j2`. Por defecto, los indexers de Azure AI Search pueden configurarse con:

- **Schedules**: Cada N minutos/horas.
- **On-demand**: Ejecutar manualmente via API REST o Azure Portal.
- **Change detection**: Detectar automáticamente nuevos blobs en Storage.

Para forzar una reindexación inmediata, ejecuta el indexer manualmente desde Azure Portal → AI Search → Indexers → Run.

---

### ¿Qué modelo de embeddings se usa para vectorizar documentos?

El modelo configurado por defecto es **`text-embedding-3-large`** de OpenAI, desplegado en Azure AI Foundry.

- Dimensión del vector: 3072 por defecto.
- SKU: Standard con 40K TPM.
- API Version: 2025-01-01-preview.

Puedes cambiar el modelo modificando la entrada `EMBEDDING_DEPLOYMENT_NAME` en `modelDeploymentList` de `main.parameters.json`.

---

## 🤖 Modelos de IA

---

### ¿Qué modelos de IA están configurados por defecto?

| Tipo | Modelo | Versión | Capacidad |
|---|---|---|---|
| **Chat / LLM** | `gpt-5-mini` | 2025-08-07 | 40K TPM (GlobalStandard) |
| **Embeddings** | `text-embedding-3-large` | v1 | 40K TPM (Standard) |

Ambos se despliegan en **Azure AI Foundry** dentro de tu propia suscripción.

---

### ¿Cómo cambio el modelo de lenguaje que se usa?

Edita la sección `modelDeploymentList` en `main.parameters.json`:

```json
{
  "name": "chat",
  "model": {
    "format": "OpenAI",
    "name": "gpt-4o",          ← Cambia aquí el nombre del modelo
    "version": "2024-11-20"    ← Cambia aquí la versión
  },
  "sku": { "name": "GlobalStandard", "capacity": 20 },
  "canonical_name": "CHAT_DEPLOYMENT_NAME"
}
```

Luego ejecuta `azd provision` para actualizar el despliegue del modelo.

---

### ¿Puedo usar modelos de otros proveedores que no sean OpenAI?

Azure AI Foundry soporta múltiples proveedores de modelos (Meta Llama, Mistral, Cohere, etc.) desde el **Model Catalog**. Sin embargo, la configuración por defecto del orchestrator está optimizada para modelos OpenAI.

Para usar modelos alternativos:
- Comprueba compatibilidad con el API de chat completions OpenAI (la mayoría los soporta).
- Actualiza `modelDeploymentList` con el formato del modelo alternativo.
- Puede requerir ajustes en el código del orchestrator.

---

### ¿Qué políticas de IA Responsable (RAI) están configuradas?

Las políticas en `config/aifoundry/raipolicies.json` aplican filtros de contenido con umbral **medium** para:
- **Hate speech** (prompt + completion): Bloqueado.
- **Sexual content** (prompt + completion): Bloqueado.
- **Self-harm** (prompt + completion): Bloqueado.
- **Violence** (prompt + completion): Bloqueado.
- **Jailbreak** (prompt): Deshabilitado por defecto.
- **Protected material text/code** (completion): Deshabilitado por defecto.

---

### ¿Cómo personalizo los filtros de contenido?

Edita `config/aifoundry/raipolicies.json`. Por ejemplo, para habilitar la detección de jailbreak:

```json
{
  "name": "jailbreak",
  "blocking": true,
  "source": "prompt",
  "enabled": true   ← Cambiar a true
}
```

También puedes agregar términos bloqueados editando `config/aifoundry/raiblocklist.json`.

Luego vuelve a ejecutar `python -m config.aifoundry.setup` para aplicar los cambios.

---

## 🔧 Personalización e Integración

---

### ¿Cómo integro este sistema con mi propia aplicación?

El **orchestrator** expone una API REST. Ejemplo de llamada:

```python
import requests

url = "https://<tu-orchestrator>.azurecontainerapps.io/api/orc"
headers = {
    "Content-Type": "application/json",
    "x-api-key": "<tu-api-key>"  # Si USE_CAPP_API_KEY=true
}
payload = {
    "conversation_id": "conv-001",
    "question": "¿Cuál es el procedimiento de onboarding?"
}

response = requests.post(url, json=payload, headers=headers)
data = response.json()
print(data["answer"])         # Respuesta generada
print(data["data_points"])    # Fragmentos de documentos usados como contexto
```

---

### ¿Cómo agrego nuevas herramientas al agente AI (MCP)?

1. Clona el repo `gpt-rag-mcp`.
2. Agrega tu función como una herramienta registrada en el servidor MCP.
3. Haz build y push de la nueva imagen a ACR.

```python
# Ejemplo simplificado de una nueva herramienta MCP
@tool(name="consultar_inventario", description="Consulta el inventario actual de productos")
async def consultar_inventario(producto: str) -> str:
    # Tu lógica de consulta aquí
    resultado = mi_api_inventario.consultar(producto)
    return f"Stock de {producto}: {resultado.cantidad} unidades"
```

---

### ¿Cómo personalizo el índice de búsqueda?

Edita `config/search/search.j2` (plantilla Jinja2) para añadir nuevos campos al índice:

```json
{
  "name": "departamento",
  "type": "Edm.String",
  "searchable": true,
  "filterable": true,
  "facetable": true
}
```

Luego vuelve a ejecutar:
```bash
python -m config.search.setup
```

Esto recreará el índice con el nuevo esquema (¡se perderán los datos indexados, habrá que re-indexar!).

---

### ¿Cómo agrego soporte para SharePoint?

SharePoint es soportado desde v2.3.0. Para habilitarlo:

1. Configura las credenciales de SharePoint en Azure App Configuration.
2. El datasource de AI Search debe apuntarse al sitio de SharePoint.
3. Edita la plantilla `search.j2` para incluir el datasource de SharePoint.

Consulta la documentación oficial para los pasos detallados de autenticación OAuth con SharePoint.

---

### ¿Cómo funciona el feature de NL2SQL?

NL2SQL (Natural Language to SQL) permite hacer preguntas en lenguaje natural sobre bases de datos:

1. Los metadatos del esquema de base de datos se almacenan en el contenedor `nl2sql` de Storage Account.
2. El orchestrator identifica intenciones NL2SQL.
3. Usa el LLM para generar el SQL apropiado.
4. Ejecuta la query y devuelve resultados tabulares.

Requiere configuración adicional del datasource en la plantilla de AI Search.

---

### ¿Puedo usar Bing Search para buscar en internet además de mis documentos?

Sí, está soportado pero **desactivado por defecto**. Para activarlo:

```bash
azd env set DEPLOY_GROUNDING_WITH_BING true
# O editar main.parameters.json:
"deployGroundingWithBing": { "value": "true" }
```

Luego `azd provision` creará un recurso de Bing Search API y lo conectará a AI Foundry mediante `connection-bing-search-tool.bicep`.

---

## 💰 Costos

---

### ¿Cuánto cuesta desplegar este sistema en Azure?

El costo varía significativamente por región, escala y uso. Los componentes más relevantes:

| Servicio | Costo Estimado (mensual, bajo uso) |
|---|---|
| Azure AI Foundry + OpenAI | Variable por tokens consumidos |
| Azure Container Apps (4 apps, perfil D4) | ~$150–$300 |
| Azure AI Search (Standard S1) | ~$250 |
| Azure Cosmos DB | ~$25–$50 (serverless o provisioned) |
| Azure Container Registry (Basic) | ~$5 |
| Azure Key Vault + App Config | ~$5–$10 |
| Azure Bastion + VM (si Zero Trust) | ~$150–$250 adicional |

**Estimación total sin Zero Trust**: ~$500–800/mes para un entorno básico con uso moderado.

Use la [Calculadora de Azure](https://azure.microsoft.com/pricing/calculator/) para estimaciones precisas.

---

### ¿Cuáles son los recursos más costosos?

1. **Azure AI Search (Standard S1)**: ~$250/mes fijo. Es el más caro pero necesario para índices de producción.
2. **Azure Container Apps** con perfil D4: Cada Container App con perfil `D4` (4 vCPU, 8 GB RAM) tiene costo por tiempo activo.
3. **Azure OpenAI** (tokens): Varía con el volumen de queries. `gpt-5-mini` es más económico que GPT-4.
4. **Azure Bastion** (si Zero Trust): ~$140/mes por tener el servicio activo.

---

### ¿Cómo puedo reducir costos en un entorno de desarrollo o pruebas?

- **Desactivar Zero Trust** (`NETWORK_ISOLATION=false`): Elimina Bastion, VM y algunos networking costs.
- **Desactivar VM** (`deployVM=false`): Elimina costo de jumpbox.
- **Usar Azure AI Search Basic** en lugar de Standard: Reduce capacidad pero baja el costo fijo.
- **Reducir réplicas de Container Apps** a `min_replicas: 0` para escalar a cero cuando no hay tráfico.
- **Usar SKU Consumption** para Container Apps: Paga solo por tiempo de ejecución.
- **Apagar el entorno** cuando no se use: `az group delete` o usa el flag para escalar a cero.

---

## 🛠️ Solución de Problemas

---

### El `postProvision.sh` falla con un error de autenticación. ¿Qué hago?

Este es el error más común. Causas y soluciones:

**Causa 1: Token expirado de Azure CLI**
```bash
az login --use-device-code
azd auth login
```

**Causa 2: Timeout de Managed Identity** (mencionado en v2.2.3)
El timeout se aumentó a 30 segundos en `config/aifoundry/setup.py`. Si persiste, vuelve a correr:
```bash
azd provision  # Vuelve a ejecutar postProvision automáticamente
```

**Causa 3: Zero Trust activo** — debes ejecutar desde dentro de la VNet. Conéctate via Bastion y ejecuta manualmente:
```bash
source scripts/postProvision.sh
```

---

### El `preDeploy.sh` falla porque Docker no está corriendo. ¿Cómo lo soluciono?

1. Abre **Docker Desktop** y espera a que diga "Docker Desktop is running".
2. Verifica: `docker info` debe responder sin errores.
3. Vuelve a ejecutar `azd deploy`.

En Linux (sin Docker Desktop):
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

---

### El script de App Configuration falla con timeout. ¿Qué hago?

El `postProvision.sh` puede fallar si App Configuration tarda en responder (conocido en modo Zero Trust). Solución:

```bash
# Volver a ejecutar azd provision (re-ejecuta postProvision.sh)
azd provision

# O ejecutar el script de configuración directamente
export APP_CONFIG_ENDPOINT=$(azd env get-value APP_CONFIG_ENDPOINT)
python -m config.aifoundry.setup
python -m config.containerapps.setup
python -m config.search.setup
```

---

### Cosmos DB da error `cosmos_vnet_blocked`. ¿Cómo lo resuelvo?

Esto ocurre cuando Cosmos DB está en modo red privada pero intentas acceder desde fuera. Soluciones:

1. **Accede desde dentro de la VNet** (via Bastion + VM).
2. **Verifica** que los private endpoints de Cosmos DB estén correctamente creados en Azure Portal.
3. Si persiste, re-ejecuta `azd provision` — fue corregido en v2.2.5.

---

### Las Container Apps arrancan con una imagen de prueba (hello world). ¿Es normal?

**Sí, es completamente normal** después de `azd provision`. El `main.bicep` despliega una imagen placeholder (`mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`) para que los recursos existan.

Las imágenes reales se despliegan cuando ejecutas `azd deploy`, que hace build y push de los repositorios reales de los componentes.

---

### ¿Cómo actualizo a una versión más nueva del sistema?

1. Actualiza el `manifest.json` con los nuevos tags de los componentes.
2. Revisa el `CHANGELOG.md` para cambios de infraestructura (pueden requerir `azd provision`).
3. Si hay cambios de infraestructura: `azd provision`.
4. Siempre termina con: `azd deploy` para actualizar las imágenes.

```bash
# Ejemplo: Actualizar solo el orchestrator
# Editar manifest.json: "tag": "v2.5.0" en gpt-rag-orchestrator
azd deploy
```

---

*¿Tienes una pregunta que no está aquí? Consulta la [documentación oficial](https://azure.github.io/GPT-RAG/) o abre un issue en [GitHub](https://github.com/azure/gpt-rag/issues).*
