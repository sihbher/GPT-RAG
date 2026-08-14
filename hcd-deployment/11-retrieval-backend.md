# Retrieval Backend en GPT-RAG: `foundry_iq` vs `ai_search`

| Campo             | Valor                                                        |
| ----------------- | ----------------------------------------------------------- |
| Versión           | v1                                                          |
| Fecha             | 2026-08-13                                                  |
| Autor             | Gerardo Reyes                                               |
| Contexto          | Aclaración surgida durante el post-provision HCD ([01-azd-postprovision.md](01-azd-postprovision.md)) |
| Aplica a          | Entorno `gptrag-bot01` (`RETRIEVAL_BACKEND=foundry_iq`)     |
```toc
```

## TL;DR

- **`RETRIEVAL_BACKEND`** es el interruptor que decide **cómo recupera GPT-RAG el
  contexto** para responder (la "R" de RAG).
- Tiene **dos valores**: **`foundry_iq`** (nuevo, **default**) y **`ai_search`**
  (clásico/legacy).
- En este despliegue está en **`foundry_iq`**, por eso el post-provision crea un
  **knowledge source** y una **knowledge base** (y por eso apareció el tema del
  shared private link Search→Storage).
- No es opcional "de adorno": con `foundry_iq`, **la knowledge base ES el motor de
  recuperación**. Sin ella, no hay retrieval.

---

## 1. Qué es `RETRIEVAL_BACKEND`

Es un parámetro de infraestructura (`retrievalBackend` en
[infra/main.bicep](infra/main.bicep)) que se sella en App Configuration como
`RETRIEVAL_BACKEND` (label `gpt-rag`) y que el **orquestador** lee en runtime para
decidir su estrategia de recuperación.

```bicep
@allowed([
  'ai_search'
  'foundry_iq'
])
param retrievalBackend string = 'foundry_iq'
```

> Importante: `retrievalBackend` **no es solo configuración** — *gatea
> infraestructura real*. Con `foundry_iq`, el Bicep crea la **conexión
> knowledge-base** de AI Foundry y los **shared private links** de AI Search hacia
> Foundry / Azure OpenAI / Cognitive Services. Cambiarlo después del provision no
> es un simple flip de una key.

---

## 2. Los dos valores

### `foundry_iq` (nuevo, default)

Usa **Foundry IQ / Azure AI Search "knowledge retrieval"**: una capa de
recuperación *agéntica* servida por AI Search a través de la **Knowledge Base API**
(`2026-05-01-preview`). En vez de que el orquestador arme queries de búsqueda a
mano, delega a una **knowledge base** que orquesta la recuperación sobre uno o más
**knowledge sources**.

Piezas que provisiona:

- **Knowledge source** (`knowledge-base-blob-ks`): *de dónde* salen los documentos.
- **Knowledge base** (`knowledge-base`): el objeto que el orquestador consulta;
  referencia a los knowledge sources.
- **Conexión de Foundry** (`KNOWLEDGE_BASE_CONNECTION_ID`) + **shared private
  links** (en ZTA) para que Search llegue a Foundry/OpenAI/Storage de forma privada.

### `ai_search` (clásico / legacy)

El patrón histórico de GPT-RAG: el orquestador consulta **directamente el índice de
Azure AI Search** (búsqueda híbrida: vectorial + keyword + semantic), opcionalmente
con **agentic retrieval** vía la flag `ENABLE_AGENTIC_RETRIEVAL`.

- **No** crea knowledge sources ni knowledge bases.
- **No** requiere la conexión knowledge-base ni los SPL específicos de Foundry IQ.
- `ENABLE_AGENTIC_RETRIEVAL` quedó **deprecado** (se mantiene una release por
  compatibilidad) — su rol lo absorbe `retrievalBackend`.

```bicep
@description('Deprecated. Kept for one release for compatibility ... Use retrievalBackend ... instead.')
param enableAgenticRetrieval bool = false
```

---

## 3. Por qué `foundry_iq` es el default (y desde cuándo)

- **Introducido en AI Landing Zone `v2.1.1` (2026-06-26)**: *"Foundry IQ runtime
  configuration groundwork for GPT-RAG"* ([Azure/GPT-RAG#526](https://github.com/Azure/GPT-RAG/issues/526)).
  Ahí se agregaron `retrievalBackend`, los parámetros Pattern A/B, el stamping de
  `KNOWLEDGE_BASE_CONNECTION_ID`, el billing plan `knowledgeRetrieval`, los
  preflights y el helper de post-provision que crea el knowledge source/base.
- En esa misma versión, **`foundryIqPattern` pasó a default `azureBlob`** (ingesta
  nativa de Blob/ADLS) y `ENABLE_AGENTIC_RETRIEVAL` se documentó como deprecado.
- El default de `retrievalBackend` es **`foundry_iq` para despliegues nuevos**; los
  existentes pueden **mantener `ai_search`** hasta que migren explícitamente (lo dice
  la propia descripción del parámetro).

Motivación (por qué Microsoft lo hizo default): mueve la lógica de recuperación
—híbrido, semantic ranking, extracción de contenido (OCR/layout), permisos a nivel
documento— a un servicio gestionado (Foundry IQ) en lugar de mantenerla en el
código del orquestador. Menos código propio, más capacidades "de fábrica".

---

## 4. `foundry_iq` en detalle

### 4.1 Patrones (`FOUNDRY_IQ_PATTERN`)

| Patrón | Valor | Qué hace |
|---|---|---|
| **A — nativo Blob/ADLS** (default) | `azureBlob` | Foundry IQ **ingiere directamente** los archivos del contenedor de Storage (`documents`). Es lo que usa este despliegue. `managed` es un alias de compatibilidad de `azureBlob`. |
| **B — índice existente** | `searchIndex` | Registra un **índice de AI Search ya existente** (`gpt-rag-index`) como knowledge source. Opt-in legacy, para quien ya tenía su índice. |

### 4.2 Opciones clave (App Config, label `gpt-rag`)

| Key | Default | Significado |
|---|---|---|
| `FOUNDRY_IQ_API_VERSION` | `2026-05-01-preview` | API de data-plane para knowledge source/base. |
| `FOUNDRY_IQ_KNOWLEDGE_SOURCE_KIND` | `azureBlob` | Tipo del source (blob nativo). |
| `FOUNDRY_IQ_STORAGE_CONTAINER_NAME` | `documents` | Contenedor de origen. |
| `FOUNDRY_IQ_CONTENT_EXTRACTION_MODE` | `standard` | `standard` = Content Understanding (OCR/layout, necesario para PDFs escaneados/imagen). `minimal` = solo texto ya presente. |
| `FOUNDRY_IQ_KNOWLEDGE_RETRIEVAL_BILLING_PLAN` | `free` | `free` = allowance incluida; `standard` = pay-as-you-go tras el free. |
| `FOUNDRY_IQ_INGESTION_PERMISSION_OPTIONS` | `["rbacScope"]` | Metadata de permisos ingerida. ADLS Gen2 puede añadir `userIds`/`groupIds`; blob soporta `rbacScope` y `sensitivityLabels`. |
| `FOUNDRY_IQ_IS_ADLS_GEN2` | `false` | `true` si el origen es ADLS Gen2 (namespace jerárquico). |

> **Nota sobre `standard` extraction:** requiere Foundry en región soportada por
> Content Understanding, puede requerir un `PATCH /contentunderstanding/defaults`
> la primera vez, tiene límites por documento (300 páginas / 5 min) y se factura por
> medidores de Content Understanding además del plan `knowledgeRetrieval`. Es
> **inmutable** en un knowledge source existente: cambiarlo obliga a **recrear** el
> knowledge source y la knowledge base.

### 4.3 Infraestructura que gatea (en ZTA)

- Conexión `KNOWLEDGE_BASE_CONNECTION_ID` (AI Foundry → AI Search).
- Shared private links Search → **Foundry / OpenAI / Cognitive Services** (para
  embeddings y extracción) y Search → **Storage blob** (para ingesta nativa).
- **Estos SPL nacen `Pending` y hay que aprobarlos** — justo el paso que resolvimos
  en [01-azd-postprovision.md](01-azd-postprovision.md) (el 403 "Public access is disabled").

---

## 5. `ai_search` en detalle

- El orquestador consulta el **índice de AI Search** directamente (híbrido:
  vectorial + BM25 + semantic).
- `ENABLE_AGENTIC_RETRIEVAL=true` habilitaba una capa agéntica sobre ese índice
  (ahora deprecada en favor de `foundry_iq`).
- No hay knowledge base/source; la ingesta la maneja el pipeline de ingestion de
  GPT-RAG (dataingest) hacia el índice.
- Menos piezas nuevas (sin conexión knowledge-base ni SPL de Foundry IQ), pero
  también sin las capacidades gestionadas de Foundry IQ (extracción avanzada,
  permisos a nivel documento vía knowledge source, billing plan gestionado).

---

## 6. Diferencias lado a lado

| Aspecto | `foundry_iq` (default) | `ai_search` (legacy) |
|---|---|---|
| Introducido | AILZ **v2.1.1** (2026-06-26) | Patrón histórico de GPT-RAG |
| Estado | **Default para nuevos deploys** | Compatibilidad para deploys existentes |
| Cómo recupera | Knowledge base (agéntico gestionado) sobre knowledge sources | Query directo al índice de AI Search |
| Crea knowledge source/base | **Sí** | No |
| Extracción de contenido | Content Understanding (`standard`, OCR/layout) | La del pipeline de ingestion |
| Permisos a nivel doc | Sí (permission options del knowledge source) | Vía filtros/seguridad del índice |
| Infra extra (ZTA) | Conexión Foundry + SPL Search→Foundry/OpenAI/CogSvc/Storage | Menos SPL (sin los de Foundry IQ) |
| Flag agéntico | `retrievalBackend` | `ENABLE_AGENTIC_RETRIEVAL` (deprecado) |
| API data-plane | `2026-05-01-preview` (knowledge*) | API de índices/consultas de AI Search |
| Facturación específica | Plan `knowledgeRetrieval` (+ Content Understanding si `standard`) | Solo AI Search |

---

## 7. Cambiar de backend = decisión de arquitectura

Cambiar `RETRIEVAL_BACKEND` **no es reversible con un solo flip** porque el valor
gatea infraestructura:

- **De `foundry_iq` a `ai_search`:** habría que dejar de depender de la knowledge
  base, reconfigurar el orquestador para consultar el índice directamente, y aceptar
  que la conexión knowledge-base y los SPL de Foundry IQ quedan sin uso. La ingesta
  debe garantizar que el índice de AI Search está poblado como espera `ai_search`.
- **De `ai_search` a `foundry_iq`:** hay que aprovisionar la conexión knowledge-base,
  los SPL, y crear el knowledge source/base (el paso de post-provision que ya
  hicimos aquí).

Para **HCD**, dado que **toda la infra ya se aprovisionó con `foundry_iq`**
(conexión knowledge-base, SPL, índices), **lo natural es quedarse en `foundry_iq`**
y completar la knowledge base — que es exactamente lo que estamos haciendo. Migrar a
`ai_search` implicaría re-aprovisionar y reconfigurar sin un beneficio claro para
este caso.

---

## 8. Relación con lo que vimos en el deploy

- El post-provision falló al crear `knowledge-base-blob-ks` con **403 "Public access
  is disabled"** → causa: el **shared private link Search→Storage `blob`** estaba
  `Pending`. Esto **solo aplica** porque `RETRIEVAL_BACKEND=foundry_iq` (patrón
  `azureBlob`): Foundry IQ ingiere el blob directamente y necesita ruta privada al
  Storage.
- Con `ai_search` ese knowledge source **no existiría** y no habría chocado con ese
  SPL — pero tampoco tendrías las capacidades de Foundry IQ. Ver el detalle y el fix
  en [01-azd-postprovision.md](01-azd-postprovision.md) (Paso 2).

---

## 9. Referencias en el repo

- Parámetro y valores: [infra/main.bicep](infra/main.bicep) (`retrievalBackend`,
  `foundryIqPattern`, familia `foundryIq*`).
- Defaults de despliegue: [main.parameters.json](main.parameters.json)
  (`RETRIEVAL_BACKEND=foundry_iq`, `FOUNDRY_IQ_PATTERN=azureBlob`, …).
- Creación de knowledge source/base: `config/search/setup.py` y `config/search/search.j2`.
- Historial: [infra/CHANGELOG.md](infra/CHANGELOG.md) (v2.1.1 introduce Foundry IQ;
  v2.1.3 default `standard` extraction; v2.3.0 passthrough de App Config).
