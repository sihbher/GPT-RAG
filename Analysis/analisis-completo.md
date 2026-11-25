# Análisis Completo del Repositorio GPT-RAG Solution Accelerator

> **Versión analizada:** v2.4.2 (fecha de tag: 2026-02-04)  
> **Repositorio origen:** https://github.com/azure/gpt-rag  
> **Fecha de análisis:** Marzo 2026

---

## Tabla de Contenidos

1. [Visión General](#1-visión-general)
2. [Propósito y Casos de Uso](#2-propósito-y-casos-de-uso)
3. [Arquitectura del Sistema](#3-arquitectura-del-sistema)
4. [Estructura del Repositorio](#4-estructura-del-repositorio)
5. [Componentes Principales (Multi-Repo)](#5-componentes-principales-multi-repo)
6. [Infraestructura como Código (IaC)](#6-infraestructura-como-código-iac)
7. [Scripts de Automatización](#7-scripts-de-automatización)
8. [Configuración Post-Provisión (Python)](#8-configuración-post-provisión-python)
9. [Seguridad y Zero Trust](#9-seguridad-y-zero-trust)
10. [IA Responsable (RAI)](#10-ia-responsable-rai)
11. [Observabilidad y Monitoreo](#11-observabilidad-y-monitoreo)
12. [Flujo de Datos End-to-End](#12-flujo-de-datos-end-to-end)
13. [Patrones de Extensibilidad](#13-patrones-de-extensibilidad)
14. [Herramientas y Prerequisitos](#14-herramientas-y-prerequisitos)
15. [Historial de Versiones Relevante](#15-historial-de-versiones-relevante)
16. [Análisis de Riesgos y Consideraciones](#16-análisis-de-riesgos-y-consideraciones)

---

## 1. Visión General

**GPT-RAG Solution Accelerator** es un acelerador de soluciones empresariales para desplegar un sistema completo de **Retrieval-Augmented Generation (RAG)** sobre Azure. No es una aplicación única, sino un **repositorio orquestador** (landing zone) que:

- Provisiona toda la infraestructura de Azure necesaria mediante **Bicep + Azure Verified Modules (AVM)**.
- Coordina el despliegue de **cuatro componentes de aplicación** alojados en repositorios GitHub separados.
- Aplica principios de **Zero Trust**, **Responsible AI** y **observabilidad end-to-end** desde el primer día.
- Permite a equipos empresariales operacionalizar IA Generativa con confianza y en producción.

El patrón RAG combina un **modelo de lenguaje grande (LLM)** con un **motor de búsqueda vectorial** para que las respuestas del modelo estén fundamentadas en información corporativa real, reduciendo alucinaciones y cumpliendo con requisitos de privacidad de datos.

---

## 2. Propósito y Casos de Uso

### Casos de Uso Soportados

| Caso de Uso | Descripción |
|---|---|
| **Q&A Empresarial** | Preguntas y respuestas sobre documentos corporativos (PDFs, Word, SharePoint, etc.) |
| **Atención al Cliente** | Chatbot inteligente con acceso a bases de conocimiento internas |
| **NL2SQL** | Generación de consultas SQL a partir de lenguaje natural sobre bases de datos |
| **Automatización de Decisiones** | Agentes AI que procesan consultas complejas sobre grandes colecciones de datos |
| **Integración con SharePoint** | Indexación y consulta de listas y documentos de SharePoint |
| **Búsqueda Semántica** | Búsqueda vectorial y semántica sobre repositorios de conocimiento |

### Principios de Diseño

- **Seguridad primero**: Arquitectura Zero Trust con aislamiento de red, endpoints privados y principio de mínimo privilegio.
- **Modularidad**: Feature flags permiten activar/desactivar componentes según necesidades.
- **Escalabilidad**: Azure Container Apps con perfiles de carga de trabajo escalables.
- **Repetibilidad**: Despliegue totalmente automatizable vía `azd provision` + `azd deploy`.
- **Observabilidad**: Application Insights + Log Analytics integrados desde el inicio.

---

## 3. Arquitectura del Sistema

### Diagrama Conceptual

```
┌─────────────────────────────────────────────────────────────────────┐
│                     USUARIO FINAL                                   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTPS
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  AZURE CONTAINER APPS ENVIRONMENT                    │
│                                                                      │
│  ┌─────────────┐   REST    ┌──────────────────┐    ┌─────────────┐  │
│  │  Frontend   │ ────────► │  Orchestrator    │    │  DataIngest │  │
│  │  (gpt-rag-  │           │  (gpt-rag-       │    │  (gpt-rag-  │  │
│  │   ui)       │           │   orchestrator)  │    │  ingestion) │  │
│  └─────────────┘           └────────┬─────────┘    └──────┬──────┘  │
│                                     │                     │         │
│                      ┌──────────────┘                     │         │
│                      ▼                                     ▼         │
│               ┌─────────────┐                    ┌──────────────┐   │
│               │  MCP Server │                    │  AI Search   │   │
│               │  (gpt-rag-  │                    │  (Indexer)   │   │
│               │   mcp)      │                    └──────────────┘   │
│               └─────────────┘                                        │
└──────────────────────────────────────────────────────────────────────┘
         │                     │                       │
         ▼                     ▼                       ▼
┌──────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│  Azure AI    │    │  Azure Cosmos DB │    │  Azure Storage      │
│  Foundry     │    │  (conversaciones,│    │  (documentos,       │
│  (LLM+       │    │   prompts, mcp,  │    │   imágenes, NL2SQL) │
│  Embeddings) │    │   datasources)   │    └─────────────────────┘
└──────────────┘    └──────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Azure AI Search             │
│  (índices vectoriales,       │
│   skillsets, agentic         │
│   retrieval)                 │
└──────────────────────────────┘
```

### Servicios de Soporte

```
Azure Key Vault          → Secretos, claves de API, contraseñas de VM
Azure App Configuration  → Configuración centralizada (etiqueta: gpt-rag)
Azure Container Registry → Imágenes Docker de los 4 componentes
Azure App Insights       → Telemetría y trazas de aplicación
Azure Log Analytics      → Logs centralizados y queries KQL
Azure VNet + NSGs        → Aislamiento de red (modo Zero Trust)
Azure Bastion + VM       → Acceso seguro en modo aislado
Bing Search (opcional)   → Grounding con información web en tiempo real
```

---

## 4. Estructura del Repositorio

```
gpt-rag/ (repositorio orquestador)
│
├── azure.yaml              → Definición AZD: hooks, proveedor Bicep, nombre
├── infra/
│   ├── main.bicep          → Plantilla principal (3092 líneas) con todos los recursos
│   ├── main.parameters.json→ Parámetros de despliegue con substitución de variables AZD
│   ├── manifest.json       → Versiones y repos de los 4 componentes de aplicación
│   ├── constants/
│   │   ├── constants.bicep → Tipos y constantes compartidas (abbrs, roles, tipos ACA)
│   │   ├── abbreviations.json → Prefijos de nombres de recursos Azure
│   │   └── roles.json      → IDs de roles RBAC de Azure
│   └── modules/
│       ├── ai-foundry/     → Módulo AI Foundry (wrapper de AVM)
│       ├── app-configuration/ → App Config Bicep
│       ├── bing-search/    → Bing Search Grounding (opcional)
│       ├── container-apps/ → Lista de Container Apps
│       ├── networking/     → VNet, subnets, NSGs, DNS privado, endpoints privados
│       └── security/       → Asignaciones de roles RBAC (Cosmos, recursos generales)
│
├── config/
│   ├── requirements.txt    → Dependencias Python (azure-*, jinja2, requests)
│   ├── aifoundry/
│   │   ├── setup.py        → Configura RAI, blocklists y Key Vault para AI Foundry
│   │   ├── raipolicies.json→ Definición de filtros de contenido RAI
│   │   ├── raiblocklist.json→ Términos bloqueados (blocklist)
│   │   └── keyvault.py     → Helper para escribir secretos en Key Vault
│   ├── containerapps/
│   │   └── setup.py        → Asocia ACR con Container Apps via identidad
│   └── search/
│       ├── setup.py        → Crea datasources, indexes, skillsets e indexers en AI Search
│       ├── search.j2       → Plantilla Jinja2 para definición del índice de búsqueda
│       └── search.settings.j2 → Plantilla de variables para App Configuration
│
├── scripts/
│   ├── preProvision.sh/.ps1  → Warning de Zero Trust antes de provisionar
│   ├── postProvision.sh/.ps1 → Configura AI Foundry, Container Apps y AI Search
│   └── preDeploy.sh/.ps1     → Build y push de imágenes Docker a ACR
│
├── util/
│   └── prereqs.py          → Verificación de cuota Cosmos DB y OpenAI por región
│
└── media/                  → Imágenes (logo, arquitectura, homepage)
```

---

## 5. Componentes Principales (Multi-Repo)

El archivo `infra/manifest.json` define exactamente cuatro componentes de aplicación que se clonan y despliegan durante `azd deploy`:

### 5.1 gpt-rag-ui (v2.2.1)
- **Rol**: Frontend web — la interfaz de chat que ve el usuario final.
- **Tecnología**: Aplicación web (probablemente React/TypeScript).
- **Container App**: `frontend` (externa, perfil `main`, 1 réplica).
- **RBAC asignado**: AppConfigurationDataReader, AcrPull, StorageBlobDataReader, StorageBlobDelegator, KeyVaultSecretsUser.

### 5.2 gpt-rag-orchestrator (v2.4.1)
- **Rol**: Orquestador de IA — recibe preguntas del frontend, coordina la búsqueda y genera respuestas usando el LLM.
- **Estrategias de orquestación**: Single Agent, MCP Strategy, y otras personalizables.
- **Container App**: `orchestrator` (externa, perfil `main`, 1 réplica).
- **RBAC asignado**: AppConfigurationDataReader, CognitiveServicesUser, CognitiveServicesOpenAIUser, AcrPull, CosmosDBBuiltInDataContributor, SearchIndexDataReader, StorageBlobDataReader, KeyVaultSecretsUser.

### 5.3 gpt-rag-ingestion (v2.2.2)
- **Rol**: Pipeline de ingesta de documentos — procesa y vectoriza documentos para el índice de búsqueda.
- **Fuentes soportadas**: Azure Blob Storage, SharePoint (listas y documentos), Excel, imágenes.
- **Container App**: `dataingest` (externa, perfil `main`, 1 réplica).
- **RBAC asignado**: AppConfigurationDataReader, CognitiveServicesUser, CognitiveServicesOpenAIUser, CosmosDBBuiltInDataContributor, AcrPull, SearchIndexDataContributor, StorageBlobDataContributor, KeyVaultSecretsUser.

### 5.4 gpt-rag-mcp (v0.3.5)
- **Rol**: Servidor MCP (Model Context Protocol) — expone herramientas y capacidades al orquestador para escenarios agénticos avanzados.
- **Container App**: `mcp` (externa, perfil `main`, 1 réplica).
- **RBAC asignado**: AppConfigurationDataReader, CognitiveServicesUser, CognitiveServicesOpenAIUser, CosmosDBBuiltInDataContributor, AcrPull, SearchIndexDataContributor, StorageBlobDataContributor, StorageQueueDataContributor, KeyVaultSecretsUser.

---

## 6. Infraestructura como Código (IaC)

### 6.1 Modelos de IA Desplegados

Definidos en `main.parameters.json` → sección `modelDeploymentList`:

| Nombre Canónico | Modelo | SKU | Capacidad |
|---|---|---|---|
| `CHAT_DEPLOYMENT_NAME` | `gpt-5-mini` (2025-08-07) | GlobalStandard | 40 TPM |
| `EMBEDDING_DEPLOYMENT_NAME` | `text-embedding-3-large` (v1) | Standard | 40 TPM |

### 6.2 Contenedores de Storage Account

| Nombre | Canónico |
|---|---|
| `documents-images` | `DOCUMENTS_IMAGES_STORAGE_CONTAINER` |
| `documents` | `DOCUMENTS_STORAGE_CONTAINER` |
| `nl2sql` | `NL2SQL_STORAGE_CONTAINER` |

### 6.3 Contenedores de Cosmos DB

| Nombre | Canónico |
|---|---|
| `conversations` | `CONVERSATIONS_DATABASE_CONTAINER` |
| `datasources` | `DATASOURCES_DATABASE_CONTAINER` |
| `prompts` | `PROMPTS_CONTAINER` |
| `mcp` | `MCP_CONTAINER` |

### 6.4 Feature Flags de Infraestructura

El `main.bicep` expone parámetros booleanos para activar/desactivar recursos individuales:

| Flag | Default | Recurso |
|---|---|---|
| `deployAiFoundry` | true | Azure AI Foundry Hub + Project |
| `deployAppConfig` | true | Azure App Configuration |
| `deployAppInsights` | true | Application Insights |
| `deployCosmosDb` | true | Cosmos DB |
| `deployContainerApps` | true | Azure Container Apps |
| `deployContainerRegistry` | true | Azure Container Registry |
| `deployKeyVault` | true | Key Vault |
| `deployLogAnalytics` | true | Log Analytics Workspace |
| `deploySearchService` | true | Azure AI Search |
| `deployStorageAccount` | true | Storage Account |
| `deployVM` | true | VM de prueba (jumpbox) |
| `deployMcp` | true | Servidor MCP |
| `deployGroundingWithBing` | false | Bing Search Grounding |
| `deployPostgres` | false | Azure Database for PostgreSQL |
| `networkIsolation` | false | Zero Trust (red aislada) |
| `enableAgenticRetrieval` | configurable | Agentic Retrieval en AI Search |

### 6.5 Esquema de Red (Zero Trust)

Cuando `networkIsolation = true`, el despliegue crea una VNet con el esquema `192.168.0.0/21` y las siguientes subredes:

| Subred | Prefijo | Tamaño | Propósito |
|---|---|---|---|
| agent-subnet | 192.168.0.0/24 | 256 IPs | AI Foundry Agents |
| aca-environment-subnet | 192.168.1.0/24 | 256 IPs | Azure Container Apps |
| pe-subnet | 192.168.2.0/26 | 64 IPs | Private Endpoints |
| AzureBastionSubnet | 192.168.2.64/26 | 64 IPs | Azure Bastion |
| AzureFirewallSubnet | 192.168.2.128/26 | 64 IPs | Azure Firewall |
| gateway-subnet | 192.168.2.192/26 | 64 IPs | VPN Gateway |
| AppGatewaySubnet | 192.168.3.0/27 | 32 IPs | Application Gateway |
| api-management-subnet | 192.168.3.32/27 | 32 IPs | API Management |
| jumpbox-subnet | 192.168.3.64/27 | 32 IPs | Jumpbox VM |
| devops-build-agents-subnet | 192.168.3.96/27 | 32 IPs | Agentes DevOps |

### 6.6 Azure Verified Modules (AVM)

El módulo AI Foundry usa el AVM público: `br/public:avm/ptn/ai-ml/ai-foundry:0.6.0`. Esto garantiza alineación con estándares Microsoft y mantenibilidad a largo plazo.

---

## 7. Scripts de Automatización

El ciclo de vida de despliegue de `azd` ejecuta hooks en orden:

```
azd provision
  └─► preProvision.sh   → Advertencia Zero Trust (sale si usuario cancela)
  └─► [Bicep deploy]    → Crea/actualiza recursos Azure
  └─► postProvision.sh  → Configura AI Foundry, Container Apps, AI Search

azd deploy
  └─► preDeploy.sh      → Clona repos de componentes, build Docker, push a ACR
  └─► [ACA image update]→ Actualiza imágenes en Container Apps
```

### 7.1 preProvision.sh
- Lee la variable `AZURE_NETWORK_ISOLATION`.
- Si está habilitada, muestra una advertencia y pide confirmación explicando que tras la provisión sólo se podrá acceder desde la VM+Bastion.
- Puede omitirse con `AZURE_SKIP_NETWORK_ISOLATION_WARNING=true`.

### 7.2 postProvision.sh
1. **Carga variables AZD** en el entorno del proceso (sin persistir en el SO).
2. **Verifica** si `NETWORK_ISOLATION` está habilitada y si el script corre dentro de la VNet.
3. **Verifica** `APP_CONFIG_ENDPOINT` (obligatorio).
4. **Crea venv temporal Python** y lo activa.
5. **Ejecuta** en secuencia:
   - `python -m config.aifoundry.setup` → RAI + Key Vault
   - `python -m config.containerapps.setup` → ACR asociación
   - `python -m config.search.setup` → AI Search completo
6. **Limpia** el venv temporal.

### 7.3 preDeploy.sh
- Verifica que Docker esté corriendo (falla con código 11 si no).
- Localiza el root del repositorio (`gpt-rag`).
- Lee ubicación del entorno AZD desde `.azure/<env>/.env`.
- Clona los 4 repositorios de componentes usando versiones del `manifest.json`.
- Copia el `.azure/` folder a cada componente.
- Ejecuta `scripts/deploy.sh` en cada componente (build + push a ACR).

---

## 8. Configuración Post-Provisión (Python)

### 8.1 config/aifoundry/setup.py

**Patrón de autenticación**: `ChainedTokenCredential(AzureCliCredential, ManagedIdentityCredential)`

**Flujo de ejecución**:
1. Carga configuración desde Azure App Configuration (label: `gpt-rag`).
2. Lee `config/aifoundry/raiblocklist.json` y `config/aifoundry/raipolicies.json`.
3. Aplica/actualiza la **blocklist RAI** (`gptragBlocklist`) con sus items.
4. Aplica/actualiza la **política RAI** (`gptragRAIPolicy`) asociada al deployment de chat.
5. Obtiene la **API key del modelo** de AI Foundry y la guarda como secreto `evaluationsModelApiKey` en Key Vault.

**Variables requeridas en App Config** (label: `gpt-rag`):
- `SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AI_FOUNDRY_ACCOUNT_NAME`
- `MODEL_DEPLOYMENTS` (JSON), `KEY_VAULT_URI`

### 8.2 config/containerapps/setup.py

**Flujo**:
1. Lee `CONTAINER_APPS` (JSON) de App Configuration.
2. Para cada Container App, determina si usa **System-Assigned Identity** o **User-Assigned Identity** (`USE_UAI`).
3. Verifica si ACR ya está asociado; si no, lo actualiza.
4. Ejecuta hasta `MAX_WORKERS=2` operaciones en paralelo con `ThreadPoolExecutor`.

### 8.3 config/search/setup.py

**Flujo**:
1. Carga **todas** las configuraciones de App Config (label: `gpt-rag`).
2. Extrae info del modelo de embedding (`EMBEDDING_DEPLOYMENT_NAME`) y chat (`CHAT_DEPLOYMENT_NAME`) de `MODEL_DEPLOYMENTS`.
3. Renderiza plantillas Jinja2 (`search.j2`, `search.settings.j2`) con esos contextos.
4. Escribe variables derivadas de vuelta a App Configuration.
5. Crea/actualiza via API REST:
   - **Datasources**: Conexiones a fuentes de datos (Azure Blob, Cosmos, SharePoint)
   - **Indexes**: Índice vectorial con campos para embeddings y metadatos
   - **Skillsets**: Pipeline de enriquecimiento cognitivo (chunking, embedding, OCR)
   - **Indexers**: Orquestadores que unen datasource → skillset → index
6. Gestiona dependencias: borra indexer/skillset antes de recrear si hay cambios.

---

## 9. Seguridad y Zero Trust

### Modelo de Identidad
- **Managed Identity** (System-Assigned o User-Assigned) para cada Container App.
- **RBAC de Azure** con roles de mínimo privilegio asignados explícitamente en `main.parameters.json` por componente.
- **No hay secrets hardcodeados** en código: todo via App Configuration + Key Vault.

### Network Isolation (Zero Trust)
Cuando se activa:
- Todos los servicios Azure tienen **public network access = Disabled**.
- Comunicación via **Private Endpoints** en la subred `pe-subnet`.
- Acceso a la red via **Azure Bastion** + VM de prueba.
- NSGs en todas las subredes.
- Private DNS zones para resolución de nombres internos.

### Seguridad de Documentos (v2.4.0)
- **ACL/RBAC trimming** en Azure AI Search con propagación de identidad del usuario final.
- Header `x-ms-query-source-authorization` para pasar tokens de usuario.
- Metadatos de indexación con `userIds`/`groupIds`/`rbacScope` por documento.
- Comportamiento seguro por defecto: peticiones sin token válido son rechazadas.

### Autenticación de Container Apps
- Opción `USE_CAPP_API_KEY`: usa claves API para autenticar llamadas entre Container Apps.
- Si se activa, se advierte para cambiar la clave inicial (`resourceToken`) por una personalizada.

---

## 10. IA Responsable (RAI)

### Blocklist (`raiblocklist.json`)
Lista configurable de términos bloqueados (`BLOCKLIST_NAME = "gptragBlocklist"`). Impide que ciertos términos aparezcan en prompts o completions.

### Política de Filtros de Contenido (`raipolicies.json`)
Política `UserManaged` basada en `Microsoft.Default` con los siguientes filtros configurados en umbral **medium**, habilitados para **prompt** y **completion**:

| Categoría | Origen | Umbral | Bloqueo |
|---|---|---|---|
| hate | prompt + completion | medium | ✅ |
| sexual | prompt + completion | medium | ✅ |
| selfharm | prompt + completion | medium | ✅ |
| violence | prompt + completion | medium | ✅ |
| jailbreak | prompt | — | ❌ (disabled) |
| protected_material_text | completion | — | ❌ (disabled) |
| protected_material_code | completion | — | ❌ (disabled) |

---

## 11. Observabilidad y Monitoreo

- **Azure Application Insights**: Telemetría automática de Container Apps. Conexión definida en AI Foundry (`connection-application-insights.bicep`).
- **Azure Log Analytics Workspace**: Centraliza logs de todos los servicios. Container Apps environment lo usa como backend de logs.
- **AI Foundry connections**: Se crean conexiones explícitas entre el proyecto AI Foundry y Application Insights, AI Search, Storage Account y Bing Search.
- **Logging en scripts Python**: Configurado con `logging.basicConfig` a nivel INFO; SDKs de Azure suprimidos a WARNING para reducir ruido.

---

## 12. Flujo de Datos End-to-End

### Flujo de Ingesta de Documentos
```
Usuario sube documento
  → Azure Blob Storage (contenedor: documents)
  → AI Search Indexer (trigger periódico o manual)
  → Skillset: OCR + chunking + embedding (text-embedding-3-large)
  → Índice vectorial en Azure AI Search
```

### Flujo de Consulta del Usuario
```
Usuario escribe pregunta en gpt-rag-ui
  → REST a gpt-rag-orchestrator
  → App Configuration: carga configuración y prompts
  → Azure AI Search: búsqueda vectorial/semántica/agéntica
  → gpt-rag-mcp (si estrategia MCP): herramientas adicionales
  → Azure AI Foundry (gpt-5-mini): generación de respuesta RAG
  → Cosmos DB: guarda historial de conversación
  → Respuesta con citas al usuario
```

### Flujo de Consulta NL2SQL
```
Usuario hace pregunta en lenguaje natural sobre datos estructurados
  → Orchestrator identifica intención NL2SQL
  → Storage Account (contenedor: nl2sql): metadatos del esquema de BD
  → AI Foundry: genera SQL desde lenguaje natural
  → Ejecuta query y devuelve resultado
```

---

## 13. Patrones de Extensibilidad

### Añadir un Nuevo Componente
1. Crear nuevo repo de componente con `scripts/deploy.sh`.
2. Agregar entrada en `infra/manifest.json`.
3. Añadir entrada en `containerAppsList` de `main.parameters.json` con roles RBAC.
4. El hook `preDeploy.sh` lo clonará y desplegará automáticamente.

### Añadir un Nuevo Modelo
1. Añadir entrada en `modelDeploymentList` de `main.parameters.json`.
2. Incluir `canonical_name` para que los scripts de configuración lo detecten.
3. Volver a ejecutar `azd provision`.

### Personalizar el Índice de Búsqueda
1. Editar `config/search/search.j2` (plantilla Jinja2 con variables de App Config).
2. Editar `config/search/search.settings.j2` para nuevas variables.
3. Volver a ejecutar `python -m config.search.setup`.

### Añadir Nuevos Feature Flags
1. Declarar parámetro en `main.bicep` con `@description`.
2. Añadir al `main.parameters.json` con formato `{ "value": "${ENV_VARIABLE}" }`.
3. Usar `azd env set VARIABLE_NAME value` para configurar.

### Soporte Multi-Cloud / Multi-Región
- El ACR DNS suffix se detecta automáticamente: `.azurecr.io`, `.azurecr.us` (Government), `.azurecr.cn` (China).
- Los parámetros `aiFoundryLocation`, `psqlLocation`, `cosmosLocation` permiten despliegue multi-región de componentes específicos.

---

## 14. Herramientas y Prerequisitos

### Herramientas Requeridas

| Herramienta | Versión | Propósito |
|---|---|---|
| Azure Developer CLI (`azd`) | Últama | Orquestación de despliegue |
| Azure CLI (`az`) | ≥2.x | Autenticación y operaciones ARM |
| Docker Desktop | Activo | Build y push de imágenes |
| Python 3.x | ≥3.9 | Scripts de configuración |
| Git | Cualquiera | Clonar repos de componentes |
| PowerShell (Windows) | 7+ (pwsh) | Scripts en Windows |

### Verificación de Prerequisitos

El script `util/prereqs.py` verifica:
1. **Provisión de Cosmos DB** en la región destino: consulta la API de Azure para confirmar que la suscripción tiene acceso.
2. **Uso de cuota de Azure OpenAI** en la región: muestra tabla con recursos actuales vs límite para detectar posibles bloqueos de capacidad.

```bash
# Uso
cd util
pip install -r requirements.txt
python prereqs.py
# Ingresa región cuando se solicite (default: eastus2)
```

### Variables de Entorno Clave

| Variable | Descripción |
|---|---|
| `AZURE_ENV_NAME` | Nombre del entorno AZD |
| `AZURE_LOCATION` | Región principal de despliegue |
| `AZURE_PRINCIPAL_ID` | Object ID del usuario/SP que despliega |
| `NETWORK_ISOLATION` | `true` para Zero Trust |
| `ENABLE_AGENTIC_RETRIEVAL` | `true` para Agentic Retrieval en AI Search |
| `USE_UAI` | `true` para User-Assigned Identity |
| `USE_CAPP_API_KEY` | `true` para autenticación por API key entre Container Apps |
| `APP_CONFIG_ENDPOINT` | URL del App Configuration (requerida en scripts Python) |

---

## 15. Historial de Versiones Relevante

| Versión | Fecha | Cambios Key |
|---|---|---|
| v2.4.2 | 2026-02-04 | Fix Docker ARM64, clave pública Microsoft, puerto no privilegiado (8080) |
| v2.4.1 | 2026-01-20 | Mejoras ingesta de Excel en gpt-rag-ingestion |
| v2.4.0 | 2026-01-15 | Seguridad a nivel de documento con ACL/RBAC en AI Search; gpt-5-mini |
| v2.3.0 | 2025-12-15 | Soporte SharePoint Lists; Single Agent refactorizado; MCP Strategy simplificado |
| v2.2.6 | 2025-12-05 | Fix SEARCH_CONNECTION_ID en App Configuration |
| v2.2.5 | 2025-12-02 | Fix Cosmos DB en redes privadas |
| v2.2.0 | 2025-10-16 | Bring Your Own VNet; Agentic Retrieval |

---

## 16. Análisis de Riesgos y Consideraciones

### Complejidad de Despliegue
- La arquitectura multi-repo requiere que Docker esté activo durante `azd deploy`.
- El modo Zero Trust aumenta significativamente la complejidad operacional: todos los scripts post-provisión deben ejecutarse desde dentro de la VNet.
- El `postProvision.sh` descarga pip durante la ejecución (`bootstrap.pypa.io`), lo que puede fallar en redes muy cerradas.

### Cuotas y Capacidades
- El modelo `gpt-5-mini` con 40K TPM puede ser insuficiente en cargas de trabajo intensivas. Verificar con `util/prereqs.py` antes de desplegar.
- `text-embedding-3-large` en SKU Standard con 40K TPM puede convertirse en cuello de botella durante ingesta masiva.
- Cosmos DB puede no estar disponible en todas las regiones. Verificar con `util/prereqs.py`.

### Seguridad Operacional
- El script `postProvision.sh` advierte que las API Keys de Container Apps se inicializan con `resourceToken` y deben cambiarse.
- Las políticas RAI tienen `jailbreak` **deshabilitado** por defecto. Considerar habilitarlo en producción.
- El `vmAdminPassword` usa `$(secretOrRandomPassword)` — se genera aleatoriamente, pero debe rotarse y guardarse en Key Vault.

### Mantenimiento
- El repositorio depende de AVM `0.6.0` para AI Foundry. Actualizaciones de AVM pueden requerir adaptaciones.
- Los 4 componentes tienen versionado independiente; actualizar `manifest.json` requiere pruebas de compatibilidad.
- La plantilla Jinja2 `search.j2` es la pieza más personalizable pero también la más sensible a cambios en el esquema del índice.

---

*Documento generado como análisis técnico profundo del repositorio GPT-RAG Solution Accelerator v2.4.2.*
