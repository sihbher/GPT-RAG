# GPT-RAG: Guía para Ingenieros Junior

> **Para quién es este documento**: Ingenieros de software con conocimientos básicos de Azure que quieren entender rápidamente qué hace este repositorio y cómo pueden integrarlo con soluciones de Inteligencia Artificial.

---

## ¿Qué hace este repositorio en una línea?

**GPT-RAG despliega automáticamente en Azure todo lo necesario para que una empresa tenga un chatbot inteligente que responde preguntas basándose en sus propios documentos.**

---

## El problema que resuelve

Imagina que tu empresa tiene miles de documentos internos: manuales, políticas, contratos, reportes. Un empleado quiere encontrar información rápidamente. Sin AI, tendría que buscar manualmente. Con un LLM normal (como ChatGPT), el modelo inventaría respuestas porque no conoce tus documentos.

**RAG (Retrieval-Augmented Generation)** resuelve esto en dos pasos:
1. **Primero busca** en tus documentos los fragmentos más relevantes a la pregunta.
2. **Luego genera** una respuesta usando un LLM, pero fundamentada en esos fragmentos reales.

GPT-RAG automatiza todo el proceso para que funcione en producción, con seguridad empresarial.

---

## Los 4 bloques de construcción

El sistema está compuesto por **4 aplicaciones independientes** que trabajan juntas:

```
┌──────────────┐     pregunta      ┌──────────────────┐
│   Frontend   │ ───────────────►  │  Orchestrator    │
│  (la UI web) │ ◄───────────────  │  (el cerebro)    │
└──────────────┘    respuesta       └────────┬─────────┘
                                             │
                            busca ▼          ▼ genera texto
                     ┌──────────────┐  ┌──────────────────┐
                     │  AI Search   │  │  Azure OpenAI    │
                     │ (índice de   │  │  (gpt-5-mini)    │
                     │  documentos) │  └──────────────────┘
                     └──────┬───────┘
                            ▲
                    indexa  │
               ┌────────────┘
               │
        ┌──────────────┐
        │   DataIngest │
        │ (sube y      │
        │  vectoriza   │
        │  documentos) │
        └──────────────┘
```

| Componente | ¿Qué hace? | Lenguaje |
|---|---|---|
| **gpt-rag-ui** | La página web que ve el usuario | TypeScript/React |
| **gpt-rag-orchestrator** | Coordina búsqueda + LLM + historial | Python |
| **gpt-rag-ingestion** | Procesa y vectoriza documentos | Python |
| **gpt-rag-mcp** | Expone herramientas extra para agentes AI | Python |

---

## ¿Qué quiere decir "vectorizar documentos"?

Cuando el **DataIngest** procesa un documento, lo transforma en números (vectores matemáticos) usando el modelo `text-embedding-3-large`. Esto permite hacer **búsqueda semántica**: encontrar documentos por significado, no solo por palabras exactas.

**Ejemplo**: Si preguntas *"¿Cuál es la política de vacaciones?"*, el sistema encontrará el documento aunque diga *"días libres remunerados"* — porque semánticamente es lo mismo.

---

## ¿Qué infraestructura crea en Azure?

Con un solo comando (`azd provision`), este repo crea automáticamente:

| Servicio Azure | Para qué sirve en GPT-RAG |
|---|---|
| **Azure AI Foundry** | Aloja los modelos de IA (gpt-5-mini + embeddings) |
| **Azure AI Search** | Almacena y consulta el índice vectorial de documentos |
| **Azure Cosmos DB** | Guarda historial de conversaciones y configuraciones |
| **Azure Container Apps** | Ejecuta las 4 aplicaciones como contenedores Docker |
| **Azure Container Registry** | Almacena las imágenes Docker de las 4 apps |
| **Azure Storage Account** | Almacena los documentos originales y datos NL2SQL |
| **Azure Key Vault** | Guarda secretos (contraseñas, API keys) de forma segura |
| **Azure App Configuration** | Configuración centralizada para todas las apps |
| **Application Insights** | Monitoreo y telemetría de las apps |
| **Log Analytics** | Logs centralizados de todos los servicios |

---

## El flujo completo paso a paso

### Paso 1: Subir documentos
```
Tú subes PDFs/Word/Excel al Blob Storage (contenedor: documents)
        ↓
El Indexer de AI Search lo detecta automáticamente
        ↓
El Skillset lo divide en fragmentos, le aplica OCR si hace falta,
y genera vectores con text-embedding-3-large
        ↓
Los vectores se almacenan en el índice de Azure AI Search
```

### Paso 2: El usuario hace una pregunta
```
Usuario escribe: "¿Cuántos días de vacaciones tengo?"
        ↓
gpt-rag-ui envía la pregunta al gpt-rag-orchestrator
        ↓
El orchestrator convierte la pregunta en un vector (embedding)
        ↓
Azure AI Search compara ese vector con todos los documentos
y devuelve los 5 fragmentos más similares
        ↓
El orchestrator pasa esos fragmentos + la pregunta a gpt-5-mini:
"Responde esta pregunta usando SOLO esta información: [fragmentos]"
        ↓
gpt-5-mini genera una respuesta con citas a los documentos originales
        ↓
La respuesta aparece en la UI con referencias
```

---

## ¿Qué es MCP y por qué importa para AI?

**MCP (Model Context Protocol)** es un estándar abierto que permite a los modelos de IA conectarse con herramientas externas. El componente `gpt-rag-mcp` actúa como un servidor que expone **herramientas** al orquestador.

**¿Por qué es importante para soluciones de AI?**
- Permite crear **Agentes AI** que no solo responden, sino que también **actúan**: consultan bases de datos, llaman APIs externas, generan reportes.
- Es el núcleo de la tendencia hacia **AI Agentic**: modelos que completan tareas complejas de múltiples pasos.
- Puedes agregar tus propias herramientas al servidor MCP para extender lo que el agente puede hacer.

---

## Cómo integrarte con este sistema

### Opción 1: Agregar tus propios documentos
Es la integración más simple. Solo sube documentos al contenedor `documents` de Azure Blob Storage y el indexer los procesará automáticamente.

```python
# Ejemplo con Python SDK
from azure.storage.blob import BlobServiceClient

client = BlobServiceClient.from_connection_string("...")
container = client.get_container_client("documents")
with open("mi_manual.pdf", "rb") as f:
    container.upload_blob("mi_manual.pdf", f)
# El indexer lo procesará automáticamente en el siguiente ciclo
```

### Opción 2: Llamar al Orchestrator como API
El orchestrator expone una API REST. Puedes integrarlo en tu propia aplicación:

```python
import requests

response = requests.post(
    "https://<tu-orchestrator>.azurecontainerapps.io/api/orc",
    json={
        "conversation_id": "123",
        "question": "¿Cuál es la política de gastos de viaje?"
    },
    headers={"x-api-key": "<tu-api-key>"}
)
print(response.json()["answer"])
```

### Opción 3: Añadir una herramienta al servidor MCP
Si quieres que el agente AI tenga acceso a tu sistema interno (base de datos, CRM, ERP):

1. Clona `gpt-rag-mcp`.
2. Agrega tu herramienta como función Python decorada con `@tool`.
3. El agente AI podrá usarla automáticamente al orquestar respuestas.

### Opción 4: Personalizar el Índice de Búsqueda
Si tus documentos tienen estructura especial (metadatos, categorías, departamentos), puedes editar `config/search/search.j2` para añadir campos personalizados al índice.

---

## Seguridad: ¿qué necesito saber?

**Zero Trust**: El modo de alta seguridad (`NETWORK_ISOLATION=true`) aísla completamente los recursos en una red privada. Solo se puede acceder desde una VM dentro de la red. Ideal para datos sensibles.

**Sin contraseñas en código**: Todas las credenciales se almacenan en Azure Key Vault. Cada app tiene una **Managed Identity** (identidad propia) que Azure gestiona — no se necesitan contraseñas.

**RBAC**: Cada componente solo tiene acceso a lo que necesita. Por ejemplo, el **frontend** no puede escribir en el índice de búsqueda, pero el **dataingest** sí puede.

---

## Cómo desplegar el sistema (resumen)

```bash
# 1. Instalar herramientas
# - Azure Developer CLI (azd)
# - Azure CLI (az)
# - Docker Desktop (asegúrate de que esté corriendo)
# - Python 3.9+

# 2. Clonar este repositorio
git clone https://github.com/azure/gpt-rag.git
cd gpt-rag

# 3. Login en Azure
az login
azd auth login

# 4. Inicializar entorno AZD
azd env new mi-entorno-gpt-rag

# 5. Configurar región y opciones
azd env set AZURE_LOCATION eastus2

# 6. Provisionar infraestructura (~20-30 min)
azd provision

# 7. Desplegar aplicaciones (~10-15 min)
azd deploy

# ¡Listo! La URL del frontend aparecerá al final
```

---

## Conceptos clave que debes conocer

| Término | Definición Simple |
|---|---|
| **RAG** | Sistema que busca info relevante antes de pedirle al LLM que responda |
| **Embedding / Vector** | Representación matemática del significado de un texto |
| **Vectorización** | Convertir texto a vectores para poder hacer búsqueda semántica |
| **Skillset** | Pipeline de transformaciones que AI Search aplica a los documentos |
| **Indexer** | Proceso que lee documentos, aplica el skillset y carga el índice |
| **Azure AI Foundry** | Plataforma Azure para gestionar y desplegar modelos de IA |
| **MCP** | Protocolo estándar para conectar LLMs con herramientas externas |
| **Agentic Retrieval** | AI Search usa el LLM para reformular queries y obtener mejores resultados |
| **Zero Trust** | Modelo de seguridad donde nada se confía por defecto; todo se verifica |
| **Managed Identity** | Identidad automática de Azure; no necesitas manejar contraseñas |
| **RBAC** | Control de acceso basado en roles: cada app solo accede a lo que necesita |
| **AZD (azd)** | Azure Developer CLI: herramienta que automatiza provision + deploy |

---

## Próximos pasos recomendados

1. **Explora el README oficial**: https://azure.github.io/GPT-RAG/
2. **Ejecuta `util/prereqs.py`** para verificar que tu suscripción tiene cuota disponible antes de desplegar.
3. **Empieza sin Zero Trust** (`NETWORK_ISOLATION=false`) para entender el sistema antes de añadir la complejidad de red.
4. **Sube 2-3 documentos de prueba** y haz preguntas para validar que el RAG funciona.
5. **Revisa Application Insights** para entender el flujo de una query end-to-end.
6. **Explora `config/search/search.j2`** para entender cómo está construido el índice vectorial.

---

*¿Tienes dudas? Revisa el [FAQ](./faq.md) o la [documentación oficial](https://azure.github.io/GPT-RAG/).*
