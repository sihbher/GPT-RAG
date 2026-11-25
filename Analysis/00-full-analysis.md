# GPT-RAG Solution Accelerator — Documento de Referencia Completo para LLMs y Desarrolladores

> **Versión analizada:** v2.4.2 | **Fecha del documento:** Marzo 2026  
> **Repositorio origen:** https://github.com/azure/gpt-rag  
> **Licencia:** MIT  
> **Documentación oficial:** https://azure.github.io/GPT-RAG/ | https://aka.ms/gpt-rag-docs

---

## Tabla de Contenidos

1. [¿Qué es GPT-RAG?](#1-qué-es-gpt-rag)
2. [Conceptos Clave](#2-conceptos-clave)
3. [Capacidades Completas](#3-capacidades-completas)
4. [Prerrequisitos](#4-prerrequisitos)
5. [Arquitectura Final](#5-arquitectura-final)
6. [Fuera de Alcance](#6-fuera-de-alcance)
7. [Escenarios de Ejemplo](#7-escenarios-de-ejemplo)
8. [Índice de Samples Incluidos](#8-índice-de-samples-incluidos)

---

## 1. ¿Qué es GPT-RAG?

### Descripción en una frase

**GPT-RAG es un acelerador de soluciones empresariales de código abierto de Microsoft que despliega un sistema completo de Retrieval-Augmented Generation (RAG) con agentes AI sobre Azure, aplicando Zero Trust, IA Responsable y observabilidad desde el primer despliegue.**

### Propuesta de valor principal

GPT-RAG elimina las semanas de arquitectura, código base y configuración de seguridad que normalmente requiere construir un sistema de RAG empresarial en Azure. Con dos comandos (`azd provision` y `azd deploy`) aprovisiona toda la infraestructura, despliega cuatro aplicaciones de producción y configura automáticamente los servicios de IA.

El sistema permite a las organizaciones:
- Responder preguntas en lenguaje natural sobre sus propios documentos corporativos (PDFs, Word, Excel, SharePoint).
- Operar con seguridad de nivel empresarial: Zero Trust, ACL por documento, sin contraseñas en código.
- Extender el chatbot a un **agente AI capaz de actuar**: consultar bases de datos en SQL, llamar APIs externas, razonar en múltiples pasos.
- Desplegar en producción con observabilidad completa (Application Insights + Log Analytics).

### Metadatos del proyecto

| Campo | Valor |
|---|---|
| **Repositorio** | https://github.com/azure/gpt-rag |
| **Licencia** | MIT |
| **Runtime de IaC** | Azure Developer CLI (azd) + Bicep |
| **Versión actual** | v2.4.2 (2026-02-04) |
| **Modelo de chat** | gpt-5-mini (2025-08-07) |
| **Modelo de embeddings** | text-embedding-3-large (v1) |
| **Plataforma** | Azure (soporte multi-cloud: Gov `.azurecr.us`, China `.azurecr.cn`) |
| **Patrón** | Multi-repositorio: 1 orquestador + 4 repositorios de componentes |

---

## 2. Conceptos Clave

### 2.1 RAG (Retrieval-Augmented Generation)

RAG es el patrón central del sistema. Combina dos fases:

1. **Retrieval (Recuperación):** Dada una pregunta del usuario, se buscan los fragmentos de documentos más semánticamente similares usando vectores (embeddings).
2. **Augmented Generation (Generación Aumentada):** Se pasan esos fragmentos + la pregunta al LLM para que genere una respuesta fundamentada en texto real, incluyendo citas.

**¿Por qué importa?** Elimina las alucinaciones del LLM al anclar la respuesta en documentos reales y privados del cliente, sin enviar datos fuera de Azure.

```
Pregunta usuario → Vector embedding → AI Search (top-k chunks) → LLM prompt → Respuesta con citas
```

### 2.2 Azure AI Foundry

Servicio de Azure que aloja y gestiona los modelos de IA (LLM y embeddings). Provee:
- **Hub**: Recurso padre compartible entre proyectos.
- **Project**: Unidad de trabajo que agrupa modelos, conexiones y evaluaciones.
- **Deployments**: Instancias de modelos con SKU y capacidad configurables.

En GPT-RAG se despliegan dos modelos:
- `chat` → `gpt-5-mini` (GlobalStandard, 40 TPM) — para generación de respuestas.
- `text-embedding` → `text-embedding-3-large` (Standard, 40 TPM) — para vectorización.

```json
// Fragmento de main.parameters.json
{
  "name": "chat",
  "model": { "format": "OpenAI", "name": "gpt-5-mini", "version": "2025-08-07" },
  "sku": { "name": "GlobalStandard", "capacity": 40 },
  "canonical_name": "CHAT_DEPLOYMENT_NAME"
}
```

### 2.3 Azure AI Search (Cognitive Search)

Motor de búsqueda vectorial e híbrida de Azure. En GPT-RAG actúa como:
- **Índice vectorial**: Almacena embeddings de los chunks de documentos.
- **Motor de búsqueda híbrida**: Combina búsqueda de texto completo (BM25) con búsqueda semántica (vectores).
- **Agentic Retrieval**: Modo avanzado donde el LLM genera múltiples queries de búsqueda automáticamente para mejorar el recall.

Se configura con indexers, skillsets y datasources definidos en Jinja2 (`config/search/search.j2`).

### 2.4 Model Context Protocol (MCP)

Estándar abierto (similar a "USB para herramientas de AI") que permite a los LLM conectarse con sistemas externos. El componente `gpt-rag-mcp` implementa un servidor MCP que expone herramientas al orquestador:

```python
# Patrón conceptual de herramienta MCP
@tool
def consultar_base_datos(query_sql: str) -> dict:
    """Ejecuta una consulta SQL sobre la base de datos corporativa."""
    ...
```

El orquestador puede invocar estas herramientas para completar tareas que requieren acceder a datos en tiempo real, APIs externas o sistemas internos.

### 2.5 Zero Trust / Network Isolation

Modo de seguridad (activado con `NETWORK_ISOLATION=true`) donde:
- Todo el tráfico entre servicios fluye por Private Endpoints dentro de una VNet privada.
- El acceso público a todos los servicios de backend está deshabilitado.
- El único punto de entrada es Azure Bastion + VM de prueba.
- NSGs protegen cada subred.

```
Internet → [BLOQUEADO] → Azure Storage / Cosmos DB / AI Search
Jumpbox VM → Bastion → VNet → Private Endpoints → Servicios Azure
```

### 2.6 Azure Verified Modules (AVM)

Módulos Bicep estándar de Microsoft con controles de seguridad, naming y observabilidad predefinidos. GPT-RAG usa `br/public:avm/ptn/ai-ml/ai-foundry:0.6.0` para el recurso más complejo (AI Foundry), garantizando alineación con las prácticas actuales de Microsoft.

### 2.7 Managed Identity

Identidades de Azure AD que Azure gestiona automáticamente, sin necesidad de contraseñas ni claves API. Cada Container App tiene su propia Managed Identity con los permisos mínimos necesarios (RBAC de mínimo privilegio).

```
Container App "orchestrator"
├── CognitiveServicesOpenAIUser → AI Foundry (invocar modelos)
├── SearchIndexDataReader → AI Search (leer índice)
├── CosmosDBBuiltInDataContributor → Cosmos DB (leer/escribir historial)
├── AppConfigurationDataReader → App Config (leer settings)
└── KeyVaultSecretsUser → Key Vault (leer secretos)
```

### 2.8 Azure App Configuration

Servicio centralizado de configuración. Todas las variables de entorno de todas las aplicaciones se almacenan aquí con la etiqueta `gpt-rag`. Las apps leen su configuración al arrancar usando su Managed Identity.

### 2.9 Embeddings y Vectores

Un **embedding** es una representación numérica (vector de dimensiones altas) de texto. Documentos con significado similar tienen vectores similares en el espacio vectorial. El modelo `text-embedding-3-large` convierte tanto los documentos (en ingesta) como las preguntas del usuario (en consulta) en vectores para comparar su similitud.

### 2.10 Agentic Retrieval

Función de Azure AI Search (`ENABLE_AGENTIC_RETRIEVAL=true`) donde el LLM actúa como agente de recuperación:
1. Analiza la pregunta del usuario.
2. Genera múltiples sub-queries de búsqueda automáticamente.
3. Combina los resultados para un recall significativamente mayor.

Requiere un **Knowledge Agent** configurado en AI Search con acceso al deployment de chat.

---

## 3. Capacidades Completas

### 3.1 Componentes de Aplicación (Multi-Repo)

El sistema está formado por cuatro repositorios de aplicaciones que GPT-RAG clona, construye y despliega automáticamente desde `infra/manifest.json`:

| Componente | Versión | Repositorio | Rol en el sistema |
|---|---|---|---|
| **gpt-rag-ui** | v2.2.1 | github.com/azure/gpt-rag-ui | Frontend web — interfaz de chat |
| **gpt-rag-orchestrator** | v2.4.1 | github.com/azure/gpt-rag-orchestrator | Motor de orquestación RAG + agentes |
| **gpt-rag-ingestion** | v2.2.2 | github.com/azure/gpt-rag-ingestion | Pipeline de ingesta de documentos |
| **gpt-rag-mcp** | v0.3.5 | github.com/azure/gpt-rag-mcp | Servidor MCP para agentes AI |

#### 3.1.1 gpt-rag-ui (Frontend)

- **Tecnología**: TypeScript/React (aplicación web).
- **Función**: Interfaz de chat que el usuario final usa para hacer preguntas y ver respuestas con citas.
- **Container App**: `frontend` | Externa | Perfil `main` | 1 réplica.
- **Características UI**:
  - Chat conversacional con historial.
  - Visualización de citas con enlaces a documentos originales.
  - User Feedback Loop (para recopilar retroalimentación sobre respuestas).
  - Soporte para respuestas con citas a fragmentos específicos de documentos.

**Roles RBAC asignados a su Managed Identity:**

| Rol | Recurso destino |
|---|---|
| AppConfigurationDataReader | App Configuration |
| AcrPull | Container Registry |
| StorageBlobDataReader | Storage Account |
| StorageBlobDelegator | Storage Account |
| KeyVaultSecretsUser | Key Vault |

#### 3.1.2 gpt-rag-orchestrator (Motor de Orquestación)

- **Tecnología**: Python.
- **Función**: Núcleo del sistema. Recibe la pregunta del usuario, coordina la búsqueda en AI Search, gestiona el historial de conversación y genera la respuesta final usando el LLM.
- **Container App**: `orchestrator` | Externa | Perfil `main` | 1 réplica.
- **Estrategias de orquestación disponibles**:
  - **Single Agent Strategy**: Agente único que combina búsqueda y síntesis. Simplificado en v2.3.0 para mejor manejo de citas.
  - **MCP Strategy**: Delega a herramientas del servidor MCP para escenarios agénticos avanzados. Simplificado en v2.3.0.
- **Características del API**:
  - Endpoint REST `POST /api/orc` para integración con sistemas externos.
  - Soporte para autenticación por API Key (`USE_CAPP_API_KEY=true`).
  - Header `x-ms-query-source-authorization` para propagación de identidad del usuario (seguridad por documento v2.4.0).
  - Soporte para compatibilidad con modelos directos de Azure para inferencia (v2.3.0).

**Roles RBAC asignados:**

| Rol | Recurso destino |
|---|---|
| AppConfigurationDataReader | App Configuration |
| CognitiveServicesUser | AI Foundry |
| CognitiveServicesOpenAIUser | AI Foundry |
| AcrPull | Container Registry |
| CosmosDBBuiltInDataContributor | Cosmos DB |
| SearchIndexDataReader | AI Search |
| StorageBlobDataReader | Storage Account |
| KeyVaultSecretsUser | Key Vault |

#### 3.1.3 gpt-rag-ingestion (Pipeline de Ingesta)

- **Tecnología**: Python.
- **Función**: Procesa documentos, los fragmenta, genera embeddings y los indexa en Azure AI Search.
- **Container App**: `dataingest` | Externa | Perfil `main` | 1 réplica.
- **Fuentes de ingesta soportadas**:
  - Azure Blob Storage (contenedor `documents`) — PDFs, Word, Excel, imágenes, etc.
  - SharePoint Lists (v2.3.0).
  - SharePoint Documents.
  - Imágenes (OCR a través del skillset de AI Search).
- **Pipeline de ingesta**:
  1. Detección de documentos nuevos/modificados.
  2. Extracción de texto (OCR para imágenes).
  3. Fragmentación (chunking) en piezas semánticamente coherentes.
  4. Generación de embeddings con `text-embedding-3-large`.
  5. Indexación en Azure AI Search con metadatos de seguridad.
- **Mejoras de fiabilidad**: Ingesta de hojas de cálculo grandes mejorada en v2.4.1. Índices con más de 1.000 chunks sin re-indexación innecesaria desde v2.2.4.

**Roles RBAC asignados:**

| Rol | Recurso destino |
|---|---|
| AppConfigurationDataReader | App Configuration |
| CognitiveServicesUser | AI Foundry |
| CognitiveServicesOpenAIUser | AI Foundry |
| CosmosDBBuiltInDataContributor | Cosmos DB |
| AcrPull | Container Registry |
| SearchIndexDataContributor | AI Search |
| StorageBlobDataContributor | Storage Account |
| KeyVaultSecretsUser | Key Vault |

#### 3.1.4 gpt-rag-mcp (Servidor MCP)

- **Tecnología**: Python.
- **Función**: Implementa el Model Context Protocol para exponer herramientas al orquestador, habilitando escenarios de agentes AI que pueden actuar más allá de la búsqueda documental.
- **Container App**: `mcp` | Externa | Perfil `main` | 1 réplica.
- **Capacidades principales**:
  - Expone herramientas siguiendo el estándar MCP para que el LLM las invoque.
  - Soporte para NL2SQL: el agente puede traducir lenguaje natural a SQL.
  - Extensible: se pueden añadir nuevas herramientas Python decoradas con `@tool`.
- **Almacenamiento**: Contenedor `mcp` en Cosmos DB para estado de herramientas.

**Roles RBAC asignados (más amplios por mayores capacidades):**

| Rol | Recurso destino |
|---|---|
| AppConfigurationDataReader | App Configuration |
| CognitiveServicesUser | AI Foundry |
| CognitiveServicesOpenAIUser | AI Foundry |
| CosmosDBBuiltInDataContributor | Cosmos DB |
| AcrPull | Container Registry |
| SearchIndexDataContributor | AI Search |
| StorageBlobDataContributor | Storage Account |
| StorageQueueDataContributor | Storage Account (colas) |
| KeyVaultSecretsUser | Key Vault |

---

### 3.2 Servicios de Infraestructura

Tabla completa de todos los recursos Azure desplegados, con sus feature flags y propósito:

| Recurso Azure | Feature Flag | Default | Propósito en GPT-RAG |
|---|---|---|---|
| **Azure AI Foundry Hub** | `deployAiFoundry` | true | Aloja modelos de IA (gpt-5-mini, text-embedding-3-large) |
| **Azure AI Foundry Project** | `deployAfProject` | true | Proyecto de trabajo que agrupa conexiones y deployments |
| **Azure AI Foundry Agent Svc** | `deployAAfAgentSvc` | true | Servicio de agentes de AI Foundry |
| **Azure AI Search** | `deploySearchService` | true | Índice vectorial e híbrido de documentos |
| **Azure Cosmos DB** | `deployCosmosDb` | true | Historial de conversaciones, prompts, config MCP, datasources |
| **Azure Container Apps Env** | `deployContainerEnv` | true | Entorno de ejecución de los 4 Container Apps |
| **Azure Container Apps (×4)** | `deployContainerApps` | true | Frontend, Orchestrator, DataIngest, MCP |
| **Azure Container Registry** | `deployContainerRegistry` | true | Imágenes Docker de los 4 componentes |
| **Azure Storage Account** | `deployStorageAccount` | true | Documentos, imágenes, datos NL2SQL |
| **Azure Key Vault** | `deployKeyVault` | true | Secretos, API keys, contraseñas de VM |
| **Azure Key Vault (VM)** | `deployVmKeyVault` | configurable | Secretos específicos de la VM de prueba |
| **Azure App Configuration** | `deployAppConfig` | true | Configuración centralizada (etiqueta: gpt-rag) |
| **Application Insights** | `deployAppInsights` | true | Telemetría y trazas de aplicación |
| **Log Analytics Workspace** | `deployLogAnalytics` | true | Logs centralizados de todos los servicios |
| **Azure Virtual Network** | `networkIsolation` | false | Aislamiento de red (Zero Trust) |
| **Subredes (10 subredes)** | `deploySubnets` | configurable | Segmentación de red |
| **Network Security Groups** | `deployNsgs` | true | Control de tráfico entre subredes |
| **Private Endpoints** | `networkIsolation` | false | Comunicación privada con servicios Azure |
| **Private DNS Zones** | `networkIsolation` | false | Resolución de nombres internos |
| **Azure Bastion** | `networkIsolation` | false | Acceso seguro a la VM |
| **VM de prueba (jumpbox)** | `deployVM` | true | Acceso a entorno Zero Trust |
| **Bing Search** | `deployGroundingWithBing` | false | Grounding con información web en tiempo real |
| **PostgreSQL Flexible Server** | `deployPostgres` | false | Base de datos relacional opcional |
| **API Management** | `deployApim` | false | Gateway de API opcional |

---

### 3.3 Modelos de IA Desplegados

| Nombre canónico | Nombre del deployment | Modelo | Versión | SKU | Capacidad |
|---|---|---|---|---|---|
| `CHAT_DEPLOYMENT_NAME` | `chat` | gpt-5-mini | 2025-08-07 | GlobalStandard | 40 TPM |
| `EMBEDDING_DEPLOYMENT_NAME` | `text-embedding` | text-embedding-3-large | 1 | Standard | 40 TPM |

---

### 3.4 Almacenamiento: Contenedores y Colecciones

#### Storage Account (Azure Blob)

| Contenedor | Canónico | Propósito |
|---|---|---|
| `documents` | `DOCUMENTS_STORAGE_CONTAINER` | Documentos corporativos para ingesta |
| `documents-images` | `DOCUMENTS_IMAGES_STORAGE_CONTAINER` | Imágenes procesadas por OCR |
| `nl2sql` | `NL2SQL_STORAGE_CONTAINER` | Metadatos de esquemas de BD para NL2SQL |

#### Cosmos DB (NoSQL)

| Colección | Canónico | Propósito |
|---|---|---|
| `conversations` | `CONVERSATIONS_DATABASE_CONTAINER` | Historial de conversaciones |
| `datasources` | `DATASOURCES_DATABASE_CONTAINER` | Configuración de fuentes de datos |
| `prompts` | `PROMPTS_CONTAINER` | Plantillas de prompts configurables |
| `mcp` | `MCP_CONTAINER` | Estado de herramientas del servidor MCP |

---

### 3.5 Perfiles de Carga de Trabajo de Container Apps

| Perfil | Tipo | Min | Max | Propósito |
|---|---|---|---|---|
| `Consumption` | Consumption | — | — | Cargas esporádicas (no crítico) |
| `main` | D4 | 0 | 1 | Todos los Container Apps en producción |

El perfil `D4` provee 4 vCPU y 8 GB RAM por instancia para cargas de trabajo estables.

---

### 3.6 Capacidades de IA Responsable (RAI)

#### Blocklist (`raiblocklist.json`)
- **Nombre**: `gptragBlocklist`
- Lista configurable de términos bloqueados (patrones exactos o regex).
- Se aplica tanto a prompts como a completions.

#### Política de Filtros de Contenido (`raipolicies.json`)
- **Nombre**: `gptragRAIPolicy`
- **Base**: `Microsoft.Default` (tipo `UserManaged`)

| Categoría | Fuente | Umbral | Bloqueo activo |
|---|---|---|---|
| hate | prompt | medium | ✅ |
| hate | completion | medium | ✅ |
| sexual | prompt | medium | ✅ |
| sexual | completion | medium | ✅ |
| selfharm | prompt | medium | ✅ |
| selfharm | completion | medium | ✅ |
| violence | prompt | medium | ✅ |
| violence | completion | medium | ✅ |
| jailbreak | prompt | — | ❌ (deshabilitado) |
| protected_material_text | completion | — | ❌ (deshabilitado) |
| protected_material_code | completion | — | ❌ (deshabilitado) |

> **Nota de seguridad**: `jailbreak` está deshabilitado por defecto. Se recomienda habilitarlo en entornos de producción.

---

### 3.7 Capacidades de Seguridad por Documento (v2.4.0)

Sistema de control de acceso a nivel de documento usando Azure AI Search con trimming nativo de ACL/RBAC:

- **Metadatos de indexación**: Cada documento indexado puede incluir `userIds`, `groupIds`, `rbacScope`.
- **Propagación de identidad**: Header `x-ms-query-source-authorization` propaga el token del usuario final al Search.
- **Comportamiento seguro por defecto**: Peticiones sin token válido son rechazadas.
- **Soporte para debug**: Opción de `elevated-read` para admins.

---

### 3.8 Capacidades de Configuración del Índice de Búsqueda

El índice de AI Search se configura via plantillas Jinja2 en `config/search/`:

| Archivo | Propósito |
|---|---|
| `search.j2` | Definición completa del índice (campos, skillsets, indexers, datasources) |
| `search.settings.j2` | Variables derivadas que se escriben de vuelta a App Configuration |
| `setup.py` | Orquesta el render de plantillas y las llamadas REST a la Search API |

**Versión configurada de la API**: `2025-11-01-preview` (con soporte de Agentic Retrieval).

**Recursos que se crean/actualizan**:
1. **Datasources**: Conexiones a Azure Blob Storage, Cosmos DB, SharePoint.
2. **Indexes**: Índice vectorial con campos de texto, embeddings y metadatos de seguridad.
3. **Skillsets**: Pipeline de enriquecimiento: OCR → chunking → embedding.
4. **Indexers**: Combinan datasource + skillset → index (orquestadores de ingesta).

---

### 3.9 Extensibilidad del Sistema

| Punto de extensión | Mecanismo | Dificultad |
|---|---|---|
| Añadir nuevo componente | Agregar repo en `manifest.json` + entrada en `containerAppsList` | Media |
| Añadir nuevo modelo LLM | Entrada en `modelDeploymentList` de `main.parameters.json` | Baja |
| Añadir nueva fuente de datos | Datasource en `search.j2` + conector en `gpt-rag-ingestion` | Media |
| Añadir herramienta MCP | Función `@tool` en `gpt-rag-mcp` | Baja |
| Personalizar índice de búsqueda | Editar `config/search/search.j2` | Media |
| Añadir feature flag nuevo | Parámetro en `main.bicep` + entrada en `main.parameters.json` | Baja |
| Usar VNet existente | `USE_EXISTING_VNET=true` + `EXISTING_VNET_RESOURCE_ID` | Baja |
| Soporte multi-región | Parámetros `aiFoundryLocation`, `cosmosLocation`, `psqlLocation` | Baja |

---

### 3.10 Hooks del Ciclo de Vida AZD

| Hook | Script (POSIX) | Script (Windows) | Momento de ejecución |
|---|---|---|---|
| `preprovision` | `scripts/preDeploy.ps1` | `scripts/preProvision.ps1` | Antes de `azd provision` |
| `postprovision` | `scripts/preDeploy.ps1` | `scripts/postProvision.ps1` | Después de `azd provision` |
| `predeploy` | `scripts/preDeploy.ps1` | `scripts/preDeploy.ps1` | Antes de `azd deploy` |

**Flujo de ejecución completo**:

```
azd provision
  ├─ preProvision.sh  → Warning Zero Trust, confirmación usuario
  ├─ [Bicep deploy]   → Crea/actualiza todos los recursos Azure
  └─ postProvision.sh → 1) AI Foundry (RAI) 2) Container Apps (ACR) 3) AI Search (índices)

azd deploy
  ├─ preDeploy.sh     → Clona 4 repos, build Docker, push a ACR
  └─ [ACA update]     → Actualiza imágenes en Container Apps
```

---

## 4. Prerrequisitos

### 4.1 Servicios Cloud Requeridos

| Servicio Azure | SKU Recomendado | Notas |
|---|---|---|
| **Azure AI Foundry** | — | Necesita quota de modelos en la región |
| **Azure AI Search** | Standard S1 | Free tier no soporta vectores ni Agentic Retrieval |
| **Azure Cosmos DB** | Serverless o Provisioned | Verificar disponibilidad en región con `util/prereqs.py` |
| **Azure Container Apps** | Consumption + D4 | D4 para cargas de trabajo estables |
| **Azure Container Registry** | Basic | Solo para dev; Standard para prod |
| **Azure Storage Account** | StorageV2 LRS | GRS para prod con HA |
| **Azure Key Vault** | Standard | Sin requisitos especiales |
| **Azure App Configuration** | Free o Standard | Standard para alta disponibilidad |
| **Application Insights** | — | Vinculado a Log Analytics Workspace |
| **Log Analytics** | — | Retención 90 días por defecto |
| **Azure Virtual Network** | — | Solo si `networkIsolation=true` |
| **Azure Bastion** | Basic | Solo si `networkIsolation=true` |

### 4.2 Cuotas de Modelos de IA Requeridas

| Modelo | Región recomendada | Capacidad mínima | Canónico |
|---|---|---|---|
| gpt-5-mini | eastus / eastus2 / swedencentral | 40 TPM | `CHAT_DEPLOYMENT_NAME` |
| text-embedding-3-large | Mismo que AI Foundry | 40 TPM | `EMBEDDING_DEPLOYMENT_NAME` |

> Verificar cuota disponible antes de desplegar: `cd util && python prereqs.py`
> Solicitar incremento: https://aka.ms/oai/quotaincrease

### 4.3 Toolchain de Desarrollo

| Herramienta | Versión mínima | Propósito | Instalación |
|---|---|---|---|
| **Azure Developer CLI (azd)** | Latest | Orquestación de despliegue | https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd |
| **Azure CLI (az)** | ≥ 2.x | Autenticación y operaciones ARM | https://docs.microsoft.com/cli/azure/install-azure-cli |
| **Docker Desktop** | Latest (activo) | Build y push de imágenes | https://www.docker.com/products/docker-desktop/ |
| **Python** | ≥ 3.9 | Scripts de configuración post-provisión | https://www.python.org/downloads/ |
| **Git** | Cualquiera | Clonar repos de componentes | https://git-scm.com/ |
| **jq** | Cualquiera | Parsear manifest.json en preDeploy.sh | `brew install jq` / `apt install jq` |
| **PowerShell** | ≥ 7 (pwsh) | Solo Windows — hooks AZD | https://github.com/PowerShell/PowerShell |
| **rsync** | Cualquiera | Copia de .azure/ a componentes (POSIX) | Incluido en macOS/Linux |

### 4.4 Permisos y Roles Necesarios

El usuario que ejecuta `azd provision` necesita en el Resource Group de destino:

- **Owner** — o los permisos equivalentes para:
  - Crear todos los recursos Azure listados.
  - Realizar **asignaciones de roles RBAC** (critical: sin este permiso, las Managed Identities no funcionarán).
  - El `principalId` en `main.parameters.json` debe ser el Object ID del usuario/servicio principal.

### 4.5 Variables de Entorno Requeridas

| Variable | Descripción | Cómo configurar |
|---|---|---|
| `AZURE_ENV_NAME` | Nombre del entorno AZD | `azd env new <nombre>` |
| `AZURE_LOCATION` | Región principal Azure | `azd env set AZURE_LOCATION eastus2` |
| `AZURE_PRINCIPAL_ID` | Object ID del usuario desplegador | Auto-detectado o `azd env set ...` |
| `APP_CONFIG_ENDPOINT` | URL del App Configuration | Generado por Bicep |
| `NETWORK_ISOLATION` | `true` para Zero Trust | `azd env set NETWORK_ISOLATION false` |
| `ENABLE_AGENTIC_RETRIEVAL` | Agentic Retrieval en AI Search | `azd env set ENABLE_AGENTIC_RETRIEVAL false` |
| `USE_UAI` | User-Assigned Identity | `azd env set USE_UAI false` |
| `USE_CAPP_API_KEY` | Autenticación por API Key entre apps | `azd env set USE_CAPP_API_KEY false` |

### 4.6 Cuotas y Límites Relevantes

| Recurso | Límite relevante | Impacto |
|---|---|---|
| gpt-5-mini | 40K TPM (default) | Cuello de botella en uso intensivo |
| text-embedding-3-large | 40K TPM (default) | Cuello de botella en ingesta masiva |
| Container Apps (D4) | 4 vCPU, 8 GB RAM, máx 1 réplica | Sin auto-escalado en config default |
| Cosmos DB | RU según SKU | Verificar con `util/prereqs.py` |
| AI Search | 10K documentos (Free) / ilimitado (Standard) | Free no viable para prod |
| Private Endpoints | pe-subnet /26 = 64 IPs | Suficiente para ~20 PEs en paralelo |

---

## 5. Arquitectura Final

### 5.1 Diagrama de Componentes en ASCII Art

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                          USUARIO FINAL                                       ║
║                    (navegador web / API REST)                                ║
╚══════════════════════════════╤═════════════════════════════════════════════╝
                               │ HTTPS
                               ▼
╔══════════════════════════════════════════════════════════════════════════════╗
║              AZURE CONTAINER APPS ENVIRONMENT                                ║
║                (VNet: aca-environment-subnet /24)                            ║
║                                                                              ║
║  ┌───────────────────┐  REST  ┌──────────────────────┐  MCP  ┌───────────┐ ║
║  │   gpt-rag-ui      │──────►│  gpt-rag-orchestrator │──────►│gpt-rag-mcp║ ║
║  │   (Frontend)      │◄──────│  (Orquestador RAG)    │       │(Servidor  ║ ║
║  │   v2.2.1          │       │  v2.4.1               │       │ MCP)      ║ ║
║  └───────────────────┘       └──────────┬────────────┘       │ v0.3.5    ║ ║
║                                         │                     └───────────┘ ║
║  ┌───────────────────┐                  │                                   ║
║  │  gpt-rag-ingestion│                  │ (búsqueda + LLM)                 ║
║  │  (Data Ingest)    │──────────────────┤                                   ║
║  │  v2.2.2           │ (indexa docs)    │                                   ║
║  └────────┬──────────┘                  │                                   ║
╚═══════════╪═════════════════════════════╪═════════════════════════════════╝
            │                             │
            ▼  indexa                     ▼  busca documentos
┌───────────────────┐         ┌───────────────────────┐
│  Azure AI Search  │◄────────│  Azure AI Foundry     │
│  - Índice vectorial         │  - gpt-5-mini         │
│  - Agentic Retrieval        │  - text-embedding-3-  │
│  - Seguridad ACL  │         │    large              │
└───────────────────┘         └───────────────────────┘
            │                             │
            └──────────────┬──────────────┘
                           ▼
            ┌──────────────────────────────┐
            │     Servicios de Soporte     │
            │                              │
            │  Azure Cosmos DB             │
            │  ├── conversations           │
            │  ├── datasources             │
            │  ├── prompts                 │
            │  └── mcp                    │
            │                              │
            │  Azure Storage Account       │
            │  ├── documents               │
            │  ├── documents-images        │
            │  └── nl2sql                 │
            │                              │
            │  Azure Key Vault             │
            │  Azure App Configuration     │
            │  Application Insights        │
            │  Log Analytics Workspace     │
            └──────────────────────────────┘

[MODO ZERO TRUST adicional]
Internet ──►[BLOQUEADO]──► Servicios Backend
Jumpbox VM ──► Azure Bastion ──► VNet ──► Private Endpoints ──► Servicios
```

### 5.2 Mapa de Comunicación Entre Servicios

| Origen | Destino | Protocolo | Puerto | Propósito |
|---|---|---|---|---|
| Usuario final | gpt-rag-ui | HTTPS | 443 | Interfaz de chat |
| gpt-rag-ui | gpt-rag-orchestrator | REST/HTTPS | 8080 | Envío de preguntas |
| gpt-rag-orchestrator | Azure AI Foundry | REST/HTTPS | 443 | Invocar LLM y embeddings |
| gpt-rag-orchestrator | Azure AI Search | REST/HTTPS | 443 | Búsqueda vectorial/semántica |
| gpt-rag-orchestrator | Azure Cosmos DB | REST/HTTPS | 443 | Historial conversación |
| gpt-rag-orchestrator | Azure App Configuration | REST/HTTPS | 443 | Leer configuración |
| gpt-rag-orchestrator | gpt-rag-mcp | MCP/HTTPS | 8080 | Invocar herramientas |
| gpt-rag-ingestion | Azure AI Foundry | REST/HTTPS | 443 | Generar embeddings |
| gpt-rag-ingestion | Azure AI Search | REST/HTTPS | 443 | Escribir índice |
| gpt-rag-ingestion | Azure Storage Account | REST/HTTPS | 443 | Leer documentos |
| gpt-rag-mcp | Azure Cosmos DB | REST/HTTPS | 443 | Estado de herramientas |
| Scripts Python | Azure App Configuration | REST/HTTPS | 443 | Leer/escribir config |
| Scripts Python | Azure AI Search | REST/HTTPS | 443 | Crear recursos Search |
| Scripts Python | Azure AI Foundry | ARM/HTTPS | 443 | Configurar RAI |
| Scripts Python | Azure Key Vault | REST/HTTPS | 443 | Escribir secretos |
| Container Apps | Azure Container Registry | HTTPS | 443 | Pull de imágenes Docker |

### 5.3 Flujo de Datos de Extremo a Extremo

#### Flujo A: Ingesta de documentos

```
1. El usuario sube un PDF a Azure Blob Storage (contenedor: documents)
   └──► Azure Storage Blob REST API

2. El Indexer de AI Search detecta el nuevo blob (trigger periódico o manual)
   └──► Polling al datasource de Blob Storage

3. El Skillset procesa el documento:
   a. Extracción de texto (PDF parser / OCR para imágenes con Azure AI Vision)
   b. Chunking: divide el texto en fragmentos semánticamente coherentes
   c. Embedding: llama a text-embedding-3-large en AI Foundry para cada chunk
   d. Metadata: añade campos de seguridad (userIds, groupIds) si están configurados

4. Los chunks vectorizados se escriben al índice de Azure AI Search
   └──► REST API AI Search (index documents)

5. El índice queda disponible para búsqueda semántica en segundos
```

#### Flujo B: Consulta del usuario (RAG estándar)

```
1. Usuario escribe: "¿Cuántos días de vacaciones tengo?"
   └──► gpt-rag-ui (React/TypeScript)

2. Frontend envía POST /api/orc a gpt-rag-orchestrator:
   { "conversation_id": "abc123", "question": "¿Cuántos días de vacaciones tengo?" }

3. Orchestrator carga configuración desde Azure App Configuration (label: gpt-rag)

4. Orchestrator genera embedding de la pregunta:
   └──► POST /openai/deployments/text-embedding/embeddings (AI Foundry)
   ←── vector[3072 dimensiones]

5. Orchestrator busca en Azure AI Search:
   └──► POST /indexes/knowledge-base/docs/search (híbrido: vector + texto)
   ←── top-5 chunks con score de relevancia y citas

6. Orchestrator construye el prompt RAG:
   "Responde usando solo la siguiente información: [chunks]. Pregunta: ¿Cuántos días...?"

7. Orchestrator llama al LLM:
   └──► POST /openai/deployments/chat/completions (AI Foundry / gpt-5-mini)
   ←── "Según el documento 'política-RRHH-2025.pdf', tienes 20 días..."

8. Orchestrator guarda la conversación en Cosmos DB (contenedor: conversations)

9. Respuesta con citas llega al usuario via gpt-rag-ui
```

#### Flujo C: Consulta agéntica (con MCP)

```
1-4. Igual al Flujo B

5. Orchestrator usa estrategia MCP — invoca herramientas del servidor gpt-rag-mcp:
   └──► POST /tools/invoke { "tool": "consultar_bd_sql", "args": { "schema": "hr" } }

6. gpt-rag-mcp ejecuta la herramienta (NL2SQL u otras)
   └──► Conecta a base de datos / API externa / AI Search

7. El resultado de la herramienta se integra en el contexto del LLM

8. gpt-5-mini genera respuesta multi-paso con información estructurada

9. Respuesta con datos estructurados y citas llega al usuario
```

#### Flujo D: Agentic Retrieval (modo avanzado)

```
1-3. Igual al Flujo B

4. En lugar de una búsqueda simple, el AI Search Knowledge Agent:
   a. Llama a gpt-5-mini para analizar la pregunta
   b. Genera múltiples sub-queries semánticamente distintas:
      - "política de vacaciones empleados"
      - "días libres remunerados por año"
      - "beneficios tiempo libre"
   c. Ejecuta las 3 búsquedas en paralelo
   d. Combina y deduplica resultados (mejor recall)

5-9. Igual al Flujo B pero con contexto más completo y preciso
```

### 5.4 Ciclo de Vida de una Tarea (Trigger a Resultado)

```
PROVISIONING (una vez)
│
├─ azd provision
│   ├─ preProvision.sh → Confirmación Zero Trust
│   ├─ Bicep deploy    → 30-35 min: todos los recursos Azure
│   └─ postProvision.sh
│       ├─ AI Foundry Setup  → RAI blocklist + política + API key en KV
│       ├─ Container Apps    → Asocia ACR con identidades
│       └─ AI Search Setup   → Datasources + index + skillset + indexers
│
├─ azd deploy
│   ├─ preDeploy.sh    → Clona 4 repos, build Docker, push ACR
│   └─ ACA update      → Container Apps usan nuevas imágenes
│
RUNTIME (continuo)
│
├─ INGESTA (batch/trigger)
│   └─ Blob Storage → Indexer → Skillset → Index → AI Search
│
└─ QUERY (por request)
    └─ Usuario → UI → Orchestrator → AI Search + AI Foundry → Respuesta
```

### 5.5 Esquema de Base de Datos (Cosmos DB)

Cosmos DB usa el modelo NoSQL de documentos:

```
Database: gpt-rag-db
├── conversations (partitionKey: /conversation_id)
│   └── { id, conversation_id, messages: [...], timestamp, user_id }
│
├── datasources (partitionKey: /id)
│   └── { id, type, connection_string, index_name, ... }
│
├── prompts (partitionKey: /id)
│   └── { id, name, template, variables: [...], version }
│
└── mcp (partitionKey: /id)
    └── { id, tool_name, state, last_updated }
```

### 5.6 Modos de Despliegue Comparados

| Modo | `networkIsolation` | Acceso | Seguridad | Complejidad | Costo adicional |
|---|---|---|---|---|---|
| **Básico** | `false` | Internet público | Alta (RBAC + Managed Identity) | Baja | — |
| **Zero Trust** | `true` | Solo desde VNet/VPN | Máxima | Alta | +VM, Bastion, PEs, NSGs |
| **BYO VNet** | `true` + `useExistingVNet=true` | VNet enterprise existente | Máxima | Media | Solo PEs y NSGs |

### 5.7 Modelo de Seguridad

#### Autenticación

| Tipo | Mecanismo | Dónde se usa |
|---|---|---|
| **LLM a Azure** | Managed Identity (ChainedTokenCredential) | Todos los Container Apps |
| **Scripts Python** | AzureCliCredential + ManagedIdentityCredential (chain) | postProvision.sh |
| **Entre Container Apps** | API Key opcional (`USE_CAPP_API_KEY`) | gpt-rag-ui → orchestrator |
| **Usuario a Backend** | `x-ms-query-source-authorization` (JWT) | Para seguridad por doc |

#### Autorización (RBAC de mínimo privilegio)

```
Principio: cada componente tiene SOLO los roles que necesita

gpt-rag-ui        → Lee docs de Storage, config, secretos
gpt-rag-orchestrator → Lee todo + escribe en Cosmos (historial)
gpt-rag-ingestion → Escribe en AI Search + Storage
gpt-rag-mcp       → Permisos más amplios (acceso a colas, Search write)
```

#### Gestión de Secretos

```
Key Vault → [secreto: evaluationsModelApiKey] = API key del modelo AI Foundry
App Configuration (label: gpt-rag) → Todas las variables de configuración
No hay secretos en código fuente ni en variables de entorno sin cifrar
```

---

## 6. Fuera de Alcance

Lo que GPT-RAG **no hace nativamente** y requiere implementación personalizada:

| Gap | Descripción | Esfuerzo estimado | Solución sugerida |
|---|---|---|---|
| **Fine-tuning de modelos** | No hay pipelines para entrenar modelos customizados | Alto (2-4 semanas) | Azure AI Foundry Fine-tuning API |
| **Búsqueda en tiempo real web** | Solo documentos indexados; Bing Search es opcional y no siempre habilitado | Bajo (días) | Activar `deployGroundingWithBing=true` + config en orchestrator |
| **Multi-idioma con traducción automática** | No traduce documentos o respuestas entre idiomas | Medio (1 semana) | Azure Cognitive Services Translator integrado como skill |
| **Interfaz de administración** | No hay UI para gestionar documentos, prompts o usuarios | Alto (3-5 semanas) | Desarrollar admin panel personalizado o usar Azure Portal |
| **Gestión de usuarios y autenticación** | No incluye sistema de usuarios (login, registro, roles de negocio) | Medio (1-2 semanas) | Integrar con Azure AD B2C o Microsoft Entra ID |
| **Pipelines CI/CD** | No incluye GitHub Actions ni Azure DevOps para updates automáticos | Bajo (días) | Configurar GitHub Actions que ejecuten `azd deploy` |
| **Tests automatizados** | No incluye test suite para los componentes | Alto (3-6 semanas) | Tests unitarios + integración por componente |
| **Monitoreo de calidad de respuestas** | Application Insights captura telemetría pero no evalúa calidad de RAG | Medio (1-2 semanas) | Azure AI Foundry Evaluation workflows |
| **Rate limiting y throttling** | No incluye control de tasa de peticiones por usuario | Bajo (días) | Activar `deployApim=true` o middleware en orchestrator |
| **Export/Import de conversaciones** | No hay feature para exportar historial de conversaciones | Bajo (días) | Script Python contra Cosmos DB API |
| **Soporte multi-tenant** | Un despliegue sirve a una organización; multi-tenant requiere adaptación | Alto (4-8 semanas) | Particionamiento por tenant en AI Search y Cosmos |
| **Versionado de documentos** | No se gestiona versionado de documentos; se reindexan al actualizar | Medio (1 semana) | Añadir campo de versión en metadata del índice |
| **Notificaciones proactivas** | El sistema es reactivo (pregunta → respuesta); no envía alertas | Medio (1 semana) | Azure Event Grid + Logic Apps |
| **Soporte para audio/video** | Solo procesa texto e imágenes estáticas (con OCR) | Alto (3-5 semanas) | Azure Speech Services + Video Indexer como skills |
| **Respuestas en streaming** | No hay streaming token por token en la respuesta | Bajo-Medio (días-semana) | Implementar SSE/WebSocket en orchestrator y UI |
| **Caché de respuestas** | Cada pregunta hace llamadas completas al LLM y Search | Bajo (días) | Azure Cache for Redis como capa de caché semántica |

---

## 7. Escenarios de Ejemplo

> **Nota**: Los flujos de configuración de infraestructura son idénticos para todos los escenarios. La variación está en los documentos que se indexan, los prompts configurados en la colección `prompts` de Cosmos DB, y las herramientas del servidor MCP.

---

### Escenario 1: Asistente de RRHH para Políticas Corporativas

**Sector**: Cualquier empresa | **Complejidad**: Básica

**Descripción**: Empleados preguntan sobre políticas de vacaciones, código de conducta, beneficios y procesos de onboarding.

**Configuración**:
```bash
# Paso 1: Provisionar infraestructura (modo básico, sin Zero Trust)
azd env set AZURE_ENV_NAME gpt-rag-rrhh
azd env set AZURE_LOCATION eastus2
azd env set NETWORK_ISOLATION false
azd provision
azd deploy

# Paso 2: Subir documentos RRHH al Blob Storage
az storage blob upload-batch \
  --source ./documentos-rrhh/ \
  --destination documents \
  --account-name <storage_account> \
  --auth-mode login

# Paso 3: Disparar la indexación manualmente (o esperar el ciclo automático)
az search indexer run --name knowledge-base-indexer \
  --service-name <search_service> \
  --resource-group <resource_group>
```

**Prompt de sistema** (a guardar en Cosmos DB, colección `prompts`):
```json
{
  "id": "rrhh-system-prompt",
  "name": "RRHH Assistant",
  "template": "Eres un asistente de Recursos Humanos para {{company_name}}. Responde ÚNICAMENTE en base a los documentos corporativos proporcionados. Si la información no está en los documentos, indica que el empleado debe contactar directamente con RRHH. Sé empático y profesional. Proporciona siempre la fuente exacta del documento."
}
```

**Flujo de consulta**:
```
Empleado: "¿Cuántos días de vacaciones tengo en mi primer año?"
  → AI Search busca en: manual-empleados-2025.pdf, politica-vacaciones.pdf
  → Chunks: "Los empleados tienen derecho a 15 días laborables en el primer año..."
  → gpt-5-mini genera: "Según la Política de Vacaciones (sección 3.2), en tu primer año 
     tienes derecho a 15 días laborables. Esta política está en vigor desde enero 2025."
```

---

### Escenario 2: Asistente Legal de Contratos

**Sector**: Legal / Jurídico | **Complejidad**: Media

**Descripción**: Abogados analizan miles de contratos para extraer cláusulas específicas, comparar términos y detectar riesgos.

**Configuración especial**: Activar `NETWORK_ISOLATION=true` para garantizar que los contratos no salen de la VNet.

```bash
# Modo Zero Trust para datos sensibles
azd env set NETWORK_ISOLATION true
azd env set ENABLE_AGENTIC_RETRIEVAL true  # Para mejor búsqueda en documentos complejos
azd provision

# Conectar desde la VM jumpbox via Bastion para ejecutar postProvision
# Acceder a Azure Portal → Bastion → VM de prueba
# Dentro de la VM:
bash /path/to/scripts/postProvision.sh

# Subir contratos (desde dentro de la VNet)
az storage blob upload-batch \
  --source ./contratos/ \
  --destination documents \
  --account-name <storage_account> \
  --auth-mode login
```

**Herramienta MCP personalizada para análisis de contratos**:
```python
# En gpt-rag-mcp, añadir herramienta personalizada:
@tool
def extraer_clausulas_riesgo(tipo_clausula: str, nivel_riesgo: str) -> dict:
    """
    Extrae cláusulas de contratos por tipo y nivel de riesgo.
    
    Args:
        tipo_clausula: 'penalty', 'liability', 'termination', 'confidentiality'
        nivel_riesgo: 'alto', 'medio', 'bajo'
    
    Returns:
        Lista de contratos con las cláusulas identificadas
    """
    # Búsqueda en AI Search con filtros de metadata
    results = search_client.search(
        search_text=f"cláusula {tipo_clausula}",
        filter=f"risk_level eq '{nivel_riesgo}'",
        top=20
    )
    return [{"contract": r["title"], "clause": r["content"]} for r in results]
```

**Caso de uso real**:
```
Abogado: "¿Cuáles son los contratos con cláusulas de penalidad superiores a 100.000€?"
  → Orchestrator usa MCP Strategy
  → gpt-rag-mcp invoca: extraer_clausulas_riesgo("penalty", "alto")
  → Resultado: [ { "contract": "Contrato-Proveedor-XYZ.pdf", "clause": "§12.3..." } ... ]
  → gpt-5-mini sintetiza una tabla con los contratos y cláusulas de riesgo
```

---

### Escenario 3: Q&A Técnico para Soporte de Producto

**Sector**: Tecnología / SaaS | **Complejidad**: Media

**Descripción**: Agentes de soporte técnico responden preguntas de clientes sobre manuales, release notes y bases de conocimiento técnico.

**Fuentes de datos**:
- Blob Storage: manuales de producto (PDF)
- SharePoint: artículos de base de conocimiento (actualización continua)

**Configuración de múltiples fuentes**:
```bash
# Configurar SharePoint como fuente adicional
# Esto se hace en config/search/search.j2 — añadir datasource de SharePoint:
```

```jinja
{# En search.j2, añadir datasource de SharePoint #}
{% set sharepoint_datasource = {
  "name": "knowledge-base-sharepoint",
  "type": "sharepoint",
  "credentials": {
    "connectionString": "{{ SHAREPOINT_CONNECTION_STRING }}"
  },
  "container": {
    "name": "{{ SHAREPOINT_SITE_URL }}"
  }
} %}
```

**Escenario de escalada multi-etapa**:
```
Cliente: "El error 'ERR_CONNECTION_RESET' aparece solo cuando uso HTTPS con proxy corporativo"

1. AI Search busca en manuales: "ERR_CONNECTION_RESET HTTPS proxy" → 3 chunks relevantes
2. Orchestrator detecta que la respuesta puede requerir diagnóstico activo
3. Invoca herramienta MCP: verificar_estado_servicio(servicio="proxy-gateway")
4. MCP retorna: { "status": "degraded", "last_incident": "2026-03-20" }
5. gpt-5-mini genera respuesta:
   "Según nuestro manual técnico (§4.7), este error en HTTPS con proxy suele 
    deberse a [explicación]. ADEMÁS: Detectamos un incidente activo en nuestro 
    proxy gateway el 20/03. ¿Esto coincide con cuándo empezaste a ver el error?"
```

---

### Escenario 4: Análisis Financiero NL2SQL

**Sector**: Banca / Finanzas | **Complejidad**: Alta

**Descripción**: Analistas financieros hacen preguntas en lenguaje natural sobre datos de bases de datos relacionales (reportes de ventas, P&L, flujo de caja).

**Configuración NL2SQL**:
```bash
# Habilitar contenedor NL2SQL en Storage (ya incluido por defecto)
# Subir el esquema de la base de datos al contenedor nl2sql
az storage blob upload \
  --file ./schema/financial_db_schema.json \
  --container-name nl2sql \
  --name schema.json \
  --account-name <storage_account> \
  --auth-mode login
```

**Esquema de base de datos para contexto**:
```json
{
  "database": "FinancialDB",
  "tables": [
    {
      "name": "ventas_mensuales",
      "columns": [
        { "name": "mes", "type": "DATE" },
        { "name": "producto", "type": "VARCHAR(100)" },
        { "name": "region", "type": "VARCHAR(50)" },
        { "name": "revenue", "type": "DECIMAL(15,2)" },
        { "name": "unidades", "type": "INT" }
      ]
    },
    {
      "name": "gastos_operativos",
      "columns": [
        { "name": "trimestre", "type": "VARCHAR(10)" },
        { "name": "categoria", "type": "VARCHAR(100)" },
        { "name": "monto", "type": "DECIMAL(15,2)" },
        { "name": "centro_costo", "type": "VARCHAR(50)" }
      ]
    }
  ]
}
```

**Herramienta MCP para NL2SQL**:
```python
@tool
def ejecutar_query_financiero(pregunta_natural: str) -> dict:
    """
    Traduce una pregunta en lenguaje natural a SQL y ejecuta en la BD financiera.
    
    Args:
        pregunta_natural: Pregunta del analista en español
    
    Returns:
        Resultado de la query SQL con datos estructurados
    """
    # 1. Cargar esquema desde Storage Account (nl2sql container)
    schema = load_schema_from_blob("schema.json")
    
    # 2. Usar gpt-5-mini para generar SQL
    sql_query = llm.generate(
        prompt=f"Dado este esquema: {schema}\nGenera SQL para: {pregunta_natural}\nSQL:"
    )
    
    # 3. Validar y ejecutar
    result = db.execute(sql_query)
    return { "sql": sql_query, "data": result, "rows": len(result) }
```

**Consulta real**:
```
Analista: "¿Cuál fue el revenue del producto X en Q3 2025 comparado con Q3 2024?"

→ Orchestrator detecta intención de datos estructurados
→ Invoca herramienta MCP: ejecutar_query_financiero(pregunta)
→ SQL generado:
  SELECT trimestre, SUM(revenue) as total
  FROM ventas_mensuales
  WHERE producto = 'Producto X'
    AND YEAR(mes) IN (2024, 2025)
    AND QUARTER(mes) = 3
  GROUP BY trimestre

→ Resultado: { "Q3 2024": 1250000, "Q3 2025": 1480000 }
→ gpt-5-mini genera narrativa:
  "El Producto X generó €1.48M en Q3 2025, un crecimiento del 18.4% respecto a 
   Q3 2024 (€1.25M). [Tabla: Q3 2024 vs Q3 2025]"
```

---

### Escenario 5: Asistente Médico para Protocolos Clínicos

**Sector**: Salud | **Complejidad**: Alta (con Zero Trust obligatorio)

**Descripción**: Personal médico consulta protocolos clínicos, guías de medicación y estudios internos de forma segura.

**Configuración de seguridad máxima con ACL por documento**:
```bash
# Zero Trust + Seguridad por documento (HIPAA-ready)
azd env set NETWORK_ISOLATION true
azd env set ENABLE_AGENTIC_RETRIEVAL true
azd provision && azd deploy
```

**Indexación con control de acceso por rol médico**:
```python
# Script de ingesta con metadatos de seguridad (personalización de gpt-rag-ingestion)
def index_protocol(file_path: str, allowed_roles: list, department: str):
    """Indexa un protocolo médico con restricciones de acceso."""
    document = {
        "id": generate_id(file_path),
        "content": extract_text(file_path),
        "title": os.path.basename(file_path),
        "department": department,
        # Campos de seguridad (v2.4.0)
        "groupIds": allowed_roles,  # ["medicos-urgencias", "residentes"]
        "rbacScope": f"hospital/departamentos/{department}"
    }
    search_client.upload_documents([document])

# Solo médicos de urgencias y residentes ven protocolos de urgencias
index_protocol(
    "protocolo-iam-urgencias.pdf",
    allowed_roles=["medicos-urgencias", "residentes"],
    department="urgencias"
)
```

**Consulta con propagación de identidad**:
```python
# Desde el orchestrator, se propaga el token del médico logueado
response = requests.post(
    f"{SEARCH_ENDPOINT}/indexes/clinical-protocols/docs/search",
    headers={
        "x-ms-query-source-authorization": f"Bearer {user_token}"
    },
    json={"search": "protocolo infarto agudo de miocardio"}
)
# AI Search aplica trimming automático: solo devuelve resultados permitidos para este médico
```

---

### Escenario 6: Asistente de Manufactura con Manuales de Mantenimiento

**Sector**: Manufactura / Industria | **Complejidad**: Media

**Descripción**: Técnicos de campo consultan manuales de mantenimiento de maquinaria, procedimientos de seguridad y listas de piezas de repuesto.

**Tipos de documentos indexados**:
- Manuales técnicos PDF con diagramas (OCR habilitado).
- Listas de materiales (BOM) en Excel.
- Procedimientos de seguridad en Word.

**Integración con sistema ERP** (via MCP):
```python
@tool
def consultar_inventario_piezas(codigo_pieza: str) -> dict:
    """Consulta el stock actual de una pieza en el ERP."""
    erp_response = requests.get(
        f"{ERP_URL}/api/inventory/{codigo_pieza}",
        headers={"Authorization": f"Bearer {ERP_TOKEN}"}
    )
    return erp_response.json()

@tool
def crear_orden_compra(codigo_pieza: str, cantidad: int, prioridad: str) -> dict:
    """Crea una orden de compra en el ERP para piezas de repuesto."""
    return erp_client.create_purchase_order(codigo_pieza, cantidad, prioridad)
```

**Consulta multi-etapa**:
```
Técnico: "La fresadora FX-2000 tiene fallo en el eje principal. ¿Qué necesito y cuánto hay en stock?"

1. AI Search busca en manuales: "FX-2000 eje principal mantenimiento" → Procedimiento §7.3
2. Extrae: "Requiere rodamientos SKF 6205 (×2) y sello de aceite NOK-3210"
3. Invoca: consultar_inventario_piezas("SKF-6205") → { "stock": 3, "almacen": "A-12" }
4. Invoca: consultar_inventario_piezas("NOK-3210") → { "stock": 0, "plazo": "5 días" }
5. Respuesta:
   "Para reparar el eje de la FX-2000 (Manual §7.3) necesitas:
    - Rodamientos SKF 6205 (×2): DISPONIBLE - Almacén A-12 (3 unidades)
    - Sello NOK-3210 (×1): SIN STOCK - Plazo de entrega 5 días
    ¿Deseas crear una orden de compra urgente para el sello?"
```

---

### Escenario 7: Atención al Cliente en Retail con Historial Personalizado

**Sector**: Retail / E-commerce | **Complejidad**: Media

**Descripción**: El chatbot de atención al cliente tiene acceso a políticas de devolución, catálogo de productos y el historial de pedidos del cliente actual.

**Personalización del historial de conversación con contexto de cliente**:
```python
# Orchestrator personalizado (fork de gpt-rag-orchestrator)
async def handle_customer_query(question: str, customer_id: str, conversation_id: str):
    # Cargar historial de conversación desde Cosmos DB
    history = await cosmos_client.get_conversation(conversation_id)
    
    # Cargar contexto del cliente (sistema externo via MCP)
    customer_context = await mcp_client.invoke_tool(
        "obtener_perfil_cliente",
        { "customer_id": customer_id }
    )
    
    # Búsqueda RAG en catálogo y políticas
    search_results = await search_client.search(
        question,
        filter=f"category in ('returns', 'products', 'shipping')"
    )
    
    # Prompt enriquecido con contexto personal
    prompt = f"""
    Cliente: {customer_context['nombre']}
    Pedidos recientes: {customer_context['pedidos_ultimos_30_dias']}
    Historial de conversación: {history}
    
    Información de la empresa: {search_results}
    
    Pregunta: {question}
    Responde de forma personalizada usando el nombre del cliente.
    """
    
    return await llm_client.complete(prompt)
```

---

### Escenario 8: Sistema de Q&A para Investigación Académica

**Sector**: Educación / Investigación | **Complejidad**: Media

**Descripción**: Investigadores consultan corpus de papers académicos, tesis y reportes internos del instituto.

**Pipeline de ingesta para papers académicos**:
```python
# Metadata enriquecida para papers académicos
def process_academic_paper(pdf_path: str, metadata: dict):
    chunks = chunk_document(pdf_path)
    
    for chunk in chunks:
        document = {
            "id": f"{metadata['doi']}_{chunk['index']}",
            "content": chunk["text"],
            "title": metadata["title"],
            "authors": metadata["authors"],  # ["García, J.", "López, M."]
            "year": metadata["year"],
            "doi": metadata["doi"],
            "keywords": metadata["keywords"],
            "journal": metadata["journal"],
            "section": chunk["section"]  # "Abstract", "Methods", "Results"
        }
        search_client.upload_documents([document])
```

**Búsqueda con filtros académicos**:
```
Investigador: "¿Qué estudios del 2023-2025 analizan el impacto de los LLMs en diagnóstico médico?"

→ Agentic Retrieval genera sub-queries:
  - "LLM diagnóstico médico resultados clínicos"
  - "inteligencia artificial radiología diagnóstico"  
  - "NLP medicina precisión diagnosis"
→ AI Search filtra: year >= 2023 AND keywords contains "LLM" OR "large language model"
→ Resultado: 12 papers relevantes con secciones de resultados citadas

Respuesta: "Según 8 estudios publicados entre 2023-2025:
- Smith et al. (2024, NEJM): Precisión del 94% en diagnóstico de neumonía con GPT-4
- García et al. (2025, Radiology): ..."
```

---

### Escenario 9: Flujo de Ingesta Paralela para Migraciones Masivas

**Sector**: Cualquiera | **Complejidad**: Alta (operacional)

**Descripción**: Migrar 50.000 documentos históricos al nuevo sistema GPT-RAG en paralelo.

**Arquitectura de ingesta paralela**:
```python
# Script de carga masiva con paralelización
import asyncio
from azure.storage.blob.aio import BlobServiceClient
from concurrent.futures import ThreadPoolExecutor

async def upload_batch(files: list, container_client, batch_id: int):
    """Sube un lote de archivos en paralelo."""
    tasks = []
    for file_path in files:
        blob_name = f"migración-{batch_id}/{os.path.basename(file_path)}"
        tasks.append(container_client.upload_blob(blob_name, open(file_path, "rb")))
    
    results = await asyncio.gather(*tasks, return_exceptions=True)
    return sum(1 for r in results if not isinstance(r, Exception))

async def migrate_documents(source_dir: str, batch_size: int = 100):
    """Migra documentos en lotes paralelos."""
    files = list(Path(source_dir).rglob("*.pdf"))
    batches = [files[i:i+batch_size] for i in range(0, len(files), batch_size)]
    
    async with BlobServiceClient.from_connection_string(CONN_STR) as client:
        container = client.get_container_client("documents")
        
        # Procesar 5 lotes en paralelo
        for i in range(0, len(batches), 5):
            parallel_batches = batches[i:i+5]
            results = await asyncio.gather(*[
                upload_batch(batch, container, i+j)
                for j, batch in enumerate(parallel_batches)
            ])
            print(f"Lote {i}: {sum(results)} documentos subidos")

# Disparar indexación masiva (el indexer procesa en orden)
az search indexer run --name knowledge-base-indexer \
  --service-name <search_service> -g <rg>
```

---

### Escenario 10: Asistente de Compliance y Auditoría

**Sector**: Finanzas / Regulatorio | **Complejidad**: Alta

**Descripción**: Auditores verifican cumplimiento de políticas regulatorias (GDPR, SOX, IFRS) contra documentos internos de la empresa.

**Flujo multi-step condicional**:
```
Auditor: "¿Nuestros contratos con proveedores de la UE cumplen con GDPR Art. 28 
          (sub-procesadores de datos)?"

Paso 1 — Buscar en normativa:
→ AI Search busca "GDPR artículo 28 sub-procesadores" en corpus de regulaciones
→ Extrae: requisitos de cláusulas obligatorias

Paso 2 — Buscar en contratos internos:
→ AI Search busca "sub-procesadores datos procesamiento" en contratos de proveedores UE

Paso 3 — Comparación condicional:
Si hay contratos sin las cláusulas requeridas:
  → Herramienta MCP: generar_reporte_gaps_compliance(contratos_incumplidos, articulo="GDPR_28")
  → Resultado: lista de contratos que requieren enmienda + plantilla de cláusula

Respuesta final:
"Revisé 47 contratos con proveedores UE.
✅ 43 contratos cumplen con GDPR Art. 28
❌ 4 contratos incumplen:
  - Contrato-TechProvider-2023.pdf: Falta cláusula de notificación de brechas (72h)
  - [...]
He generado las cláusulas de enmienda necesarias en ./gdpr_amendments/"
```

---

## 8. Índice de Samples Incluidos

El repositorio orquestador `gpt-rag` no incluye samples de código de aplicación directamente — estos viven en los 4 repositorios de componentes. Sin embargo, incluye los siguientes **archivos de referencia, plantillas y scripts** documentados:

### Archivos de Infraestructura y Configuración

| Nombre | Ruta | Descripción |
|---|---|---|
| `main.bicep` | `infra/main.bicep` | Plantilla principal Bicep con todos los recursos Azure (~400 líneas de parámetros + lógica) |
| `main.parameters.json` | `infra/main.parameters.json` | Parámetros de despliegue con feature flags, modelos de IA, contenedores y workload profiles |
| `manifest.json` | `infra/manifest.json` | Versiones de los 4 componentes de aplicación (fuente de verdad del despliegue) |
| `azure.yaml` | `azure.yaml` | Definición del proyecto AZD con hooks de ciclo de vida |
| `constants.bicep` | `infra/constants/constants.bicep` | Tipos y constantes compartidas (abreviaturas, roles RBAC) |
| `abbreviations.json` | `infra/constants/abbreviations.json` | Prefijos de nombres de recursos Azure (ej. `kv-` para Key Vault) |
| `roles.json` | `infra/constants/roles.json` | IDs GUID de todos los roles RBAC de Azure |

### Módulos Bicep Reutilizables

| Módulo | Ruta | Descripción |
|---|---|---|
| AI Foundry | `infra/modules/ai-foundry/main.bicep` | Wrapper de AVM para Azure AI Foundry Hub + Project + conexiones |
| AI Foundry Conexiones | `infra/modules/ai-foundry/connection-*.bicep` | Conexiones AI Foundry a AI Search, App Insights, Storage, Bing |
| App Configuration | `infra/modules/app-configuration/app-configuration.bicep` | Módulo de Azure App Configuration |
| Bing Search | `infra/modules/bing-search/main.bicep` | Módulo de Bing Search para grounding web |
| Container Apps List | `infra/modules/container-apps/container-apps-list.bicep` | Despliega la lista de Container Apps desde parámetros |
| Networking | `infra/modules/networking/` | VNet, subredes, NSGs, DNS privado, Private Endpoints |
| Security RBAC | `infra/modules/security/resource-role-assignment.bicep` | Asignación de roles RBAC sobre recursos individuales |
| Cosmos RBAC | `infra/modules/security/cosmos-data-plane-role-assignment.bicep` | Roles de plano de datos de Cosmos DB |

### Plantillas de Configuración de AI Search (Jinja2)

| Nombre | Ruta | Descripción |
|---|---|---|
| Definición de índice | `config/search/search.j2` | Plantilla completa del índice vectorial con campos, skillsets, indexers y datasources |
| Variables de configuración | `config/search/search.settings.j2` | Variables derivadas que se escriben de vuelta a App Configuration |

### Scripts de Automatización

| Nombre | Ruta | Descripción |
|---|---|---|
| `preProvision.sh` | `scripts/preProvision.sh` | Warning de Zero Trust con confirmación interactiva del usuario |
| `postProvision.sh` | `scripts/postProvision.sh` | Configura AI Foundry (RAI), Container Apps (ACR) y AI Search (índices) |
| `preDeploy.sh` | `scripts/preDeploy.sh` | Clona repos de componentes desde manifest.json, build Docker, push a ACR |

### Scripts de Configuración Python

| Nombre | Ruta | Descripción |
|---|---|---|
| AI Foundry Setup | `config/aifoundry/setup.py` | Configura RAI blocklist + política de filtros + guarda API key en Key Vault |
| Key Vault Helper | `config/aifoundry/keyvault.py` | Cliente para escribir secretos en Azure Key Vault |
| Container Apps Setup | `config/containerapps/setup.py` | Asocia ACR con cada Container App via Managed Identity (paralelizado) |
| AI Search Setup | `config/search/setup.py` | Renderiza plantillas Jinja2 y crea todos los recursos de AI Search via API REST |
| Prerequisitos | `util/prereqs.py` | Verifica cuota de Cosmos DB y Azure OpenAI en la región destino |

### Archivos de Política de IA Responsable

| Nombre | Ruta | Descripción |
|---|---|---|
| RAI Policies | `config/aifoundry/raipolicies.json` | Política de filtros de contenido (hate, sexual, selfharm, violence en umbral medium) |
| RAI Blocklist | `config/aifoundry/raiblocklist.json` | Plantilla de blocklist de términos prohibidos |

### Documentación de Análisis

| Nombre | Ruta | Descripción |
|---|---|---|
| **Este documento** | `analysis/00-full-analysis.md` | Referencia completa para LLMs y desarrolladores |
| Análisis completo | `analysis/analisis-completo.md` | Análisis técnico profundo del repositorio |
| FAQ | `analysis/faq.md` | Preguntas frecuentes sobre operación |
| Guía junior | `analysis/guia-junior.md` | Introducción para ingenieros con conocimientos básicos de Azure |
| Arquitectura drawio | `analysis/gpt-rag-architecture.drawio` | Diagrama de arquitectura editable |
| Despliegue AZD | `analysis/azd-deploy-explicado.md` | Explicación detallada del ciclo de despliegue AZD |

### Archivos de Preflight

| Nombre | Ruta | Descripción |
|---|---|---|
| Preflight Check | `preflight/preflightCheck.sh` | Script de verificación pre-despliegue |
| README Preflight | `preflight/README.md` | Instrucciones del proceso de preflight |

---

## Referencias y Recursos Adicionales

| Recurso | URL |
|---|---|
| Documentación oficial GPT-RAG | https://azure.github.io/GPT-RAG/ |
| Repositorio principal | https://github.com/azure/gpt-rag |
| gpt-rag-ui | https://github.com/azure/gpt-rag-ui |
| gpt-rag-orchestrator | https://github.com/azure/gpt-rag-orchestrator |
| gpt-rag-ingestion | https://github.com/azure/gpt-rag-ingestion |
| gpt-rag-mcp | https://github.com/azure/gpt-rag-mcp |
| Azure Developer CLI | https://learn.microsoft.com/azure/developer/azure-developer-cli/ |
| Azure Verified Modules (AVM) | https://azure.github.io/Azure-Verified-Modules/ |
| Azure AI Search Agentic Retrieval | https://learn.microsoft.com/azure/search/agentic-retrieval-concept |
| Model Context Protocol | https://modelcontextprotocol.io/ |
| Solicitar cuota OpenAI | https://aka.ms/oai/quotaincrease |
| Documentación alternativa | https://aka.ms/gpt-rag-docs |

---

*Documento generado como referencia única para agentes de IA y desarrolladores técnicos. Última actualización: Marzo 2026. Versión del repositorio analizada: v2.4.2.*
