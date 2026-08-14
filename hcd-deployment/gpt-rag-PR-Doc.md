# GPT-RAG — Cambios del repo para PR upstream

> Documento de preparación para abrir una PR a **`Azure/GPT-RAG`** con los ajustes
> hechos en este repo durante el despliegue HCD. Contiene el **inventario de
> cambios, el porqué, los diffs y notas de compatibilidad**.

| Campo        | Valor                                             |
| ------------ | ------------------------------------------------- |
| Fecha        | 2026-08-14                                        |
| Autor        | Gerardo Reyes                                     |
| Rama actual  | `hcd/test01` (fork `sihbher/GPT-RAG`)             |
| Base upstream| `Azure/GPT-RAG` (`main` / `develop`)              |
```toc
```

## Alcance

**En alcance de esta PR (cambios a este repo, `Azure/GPT-RAG`):**

1. Parametrizar el SKU de los model deployments (backward-compatible).
2. Preflight regional: resolver tokens `${VAR=default}` anidados en `modelDeploymentList`.
3. Helper nuevo `Resolve-ModelDeploymentSkus.ps1` + cableado en `preProvision.ps1`/`.sh`.
4. `postProvision.ps1`: robustez del resolver de storage (evitar falso match con storage BYO).

**Fuera de alcance (NO van en esta PR):**

- **Cambios al submódulo `infra/` (AI Landing Zone).** Van a
  `Azure/bicep-ptn-aiml-landing-zone` y están registrados en `ailz-improvements.md`
  (p. ej. el `cafTrim(..., 60)` del shared private link, y los SPL que nacen
  `Pending` sin auto-aprobar). No editar `infra/` en esta PR: es vendorizado.
- **Documentos de la interacción HCD** (`hcd-deployment/*.md`). Son notas del
  engagement, no material upstream.

---

## Cambio 1 — Parametrizar el SKU de los model deployments

**Archivo:** [main.parameters.json](../main.parameters.json)

**Qué:** los `sku.name` de `modelDeploymentList` (chat y embedding) pasan de valores
fijos a **tokens `${VAR=default}`**, con los defaults originales.

```diff
   "sku": {
-    "name": "GlobalStandard",
+    "name": "${CHAT_DEPLOYMENT_SKU=GlobalStandard}",
     "capacity": 100
   },
...
   "sku": {
-    "name": "Standard",
+    "name": "${EMBEDDING_DEPLOYMENT_SKU=Standard}",
     "capacity": 100
   },
```

**Por qué:** permite a un operador elegir el *deployment type* del modelo (por
ejemplo `DataZoneStandard` por **residencia de datos US**) vía
`azd env set CHAT_DEPLOYMENT_SKU ...` sin editar el archivo de parámetros.

**Compatibilidad:** sin variables de entorno, los tokens resuelven a
`GlobalStandard` / `Standard` → **comportamiento idéntico** al actual. `capacity`
se deja como número (no token) para no romper la validación de tipo `int` en Bicep.

---

## Cambio 2 — Preflight regional resuelve tokens anidados de SKU

**Archivo:** [scripts/Invoke-RegionalPreflight.ps1](../scripts/Invoke-RegionalPreflight.ps1)

**Qué:** `Test-ModelReadiness` leía `modelDeploymentList[].sku.name` literal; ahora
resuelve los tokens con el helper existente `Resolve-TemplateValue`.

```diff
 foreach ($deployment in @($Models)) {
     $model = $deployment.model
-    $modelName = $model.name
-    $modelVersion = $model.version
-    $skuName = $deployment.sku.name
-    $capacity = [double]$deployment.sku.capacity
+    $modelName = Resolve-TemplateValue $model.name
+    $modelVersion = Resolve-TemplateValue $model.version
+    $skuName = Resolve-TemplateValue $deployment.sku.name
+    $capacity = [double](Resolve-TemplateValue $deployment.sku.capacity)
```

**Por qué:** tras el Cambio 1, sin este parche el preflight validaría el token
literal (`${CHAT_DEPLOYMENT_SKU=...}`) como si fuera un SKU, y no coincidiría con la
cuota. Con la resolución, el preflight y `azd` usan el **mismo valor efectivo**.

**Compatibilidad:** `Resolve-TemplateValue` sobre un string sin token devuelve el
string tal cual → sin cambios para parámetros no tokenizados.

---

## Cambio 3 — Helper `Resolve-ModelDeploymentSkus.ps1` + cableado en preProvision

**Archivos:**
- **Nuevo:** [scripts/Resolve-ModelDeploymentSkus.ps1](../scripts/Resolve-ModelDeploymentSkus.ps1)
- [scripts/preProvision.ps1](../scripts/preProvision.ps1)
- [scripts/preProvision.sh](../scripts/preProvision.sh)

**Qué:** tras copiar `main.parameters.json` → `infra/main.parameters.json`, el helper
**materializa** los tokens de `modelDeploymentList[].sku.name` a valores concretos
en la copia de `infra/` (reemplazo textual puntual, sin re-serializar el JSON).
Precedencia: **env de azd → env de proceso → default del token**.

```diff
 # scripts/preProvision.ps1
+# Resolve azd env tokens nested in modelDeploymentList[].sku.name in the copied
+# infra parameters, so the landing-zone preflight and azd see concrete SKUs.
+$resolveSkusScript = Join-Path $PSScriptRoot "Resolve-ModelDeploymentSkus.ps1"
+if (Test-Path $resolveSkusScript) {
+    & pwsh -NoProfile -File $resolveSkusScript -ParameterFile (Join-Path $infraDir "main.parameters.json")
+}
```

```diff
 # scripts/preProvision.sh
+# Resolve azd env tokens nested in modelDeploymentList[].sku.name in the copied
+# infra parameters, so the landing-zone preflight and azd see concrete SKUs.
+RESOLVE_SKUS_SCRIPT="$SCRIPT_DIR/Resolve-ModelDeploymentSkus.ps1"
+if [ -f "$RESOLVE_SKUS_SCRIPT" ] && command -v pwsh >/dev/null 2>&1; then
+    pwsh -NoProfile -File "$RESOLVE_SKUS_SCRIPT" -ParameterFile "$INFRA_DIR/main.parameters.json"
+fi
```

**Por qué:** el preflight del AI Landing Zone (vendorizado) **no resuelve** tokens
`${VAR=default}` anidados dentro de `modelDeploymentList`; arma el nombre de cuota
con el token literal y falla (`MODEL_QUOTA_INSUFFICIENT`). Materializar el SKU en la
copia de `infra/` hace que **tanto el preflight de AILZ como `azd`** vean el SKU
concreto, sin tocar nada vendorizado.

**Compatibilidad:** el `main.parameters.json` de la raíz **conserva los tokens**
(apto para upstream). Sin env, el helper resuelve al default → idéntico al actual.
Paridad PowerShell/shell mantenida (ambos `preProvision` invocan el mismo helper).

---

## Cambio 4 — `postProvision.ps1`: resolver de storage robusto ante cuentas BYO

**Archivo:** [scripts/postProvision.ps1](../scripts/postProvision.ps1)

**Qué:** el descubrimiento del storage principal exige el prefijo `st` (además de
excluir `staif`), para no confundirse con cuentas de storage ajenas presentes en el
mismo grupo de recursos.

```diff
 # Storage: main workload vs AI Foundry storage (prefix "staif")
+# Require the "st" prefix so unrelated BYO storage accounts in the RG don't create an ambiguous match that forces the legacy-name fallback.
 $storageName = _resolveResource `
     -Type 'Microsoft.Storage/storageAccounts' `
     -Fallback "st$nameSuffix" `
-    -Filter { -not $_.name.StartsWith('staif') }
+    -Filter { $_.name.StartsWith('st') -and -not $_.name.StartsWith('staif') }
```

**Por qué (bug real):** `_resolveResource` solo descartaba `staif*`. Si el RG tiene
una cuenta de storage no relacionada (p. ej. una BYO `hcdgenai`), quedaban **dos**
matches → cae al **fallback legacy** `st$RESOURCE_TOKEN`, que **no existe** con
naming CAF. Ese nombre se sella en `STORAGE_ACCOUNT_RESOURCE_ID` y el knowledge
source de Foundry IQ falla con **401** (`Unable to retrieve blob container for
account '...'`). Exigir el prefijo `st` deja **un solo** match (el storage real de
GPT-RAG, `st...`; Foundry es `staif...`; las BYO no empiezan por `st`).

**Compatibilidad:** los storage de GPT-RAG siempre usan el prefijo `st` (abreviatura
`st` en `constants`, tanto en naming CAF como legacy), así que el filtro no excluye
ninguna cuenta legítima; solo elimina el falso match con cuentas ajenas.

**Nota de paridad:** `postProvision.sh` **no** implementa este descubrimiento de
nombres (solo el `.ps1` puebla App Configuration con nombres resueltos). Es una
asimetría **preexistente**; este cambio no la introduce. Si se quiere paridad total,
sería un cambio aparte que porte la lógica de App Config al `.sh`.

---

## Agrupación sugerida de PR(s)

- **PR A — "Parameterize model deployment SKUs":** Cambios 1 + 2 + 3 (van juntos;
  el 2 y 3 existen para soportar el 1 en ambos preflights). Título sugerido:
  *"Allow overriding model deployment SKU via azd env (backward-compatible)"*.
- **PR B — "Fix storage discovery with BYO storage in the RG":** Cambio 4 (bug fix
  independiente). Título sugerido:
  *"postProvision: require 'st' prefix when resolving the workload storage account"*.

Se pueden enviar como **dos PRs** (más fáciles de revisar) o una sola con dos commits.

---

## Validación realizada

- **Cambios 1–3:** con `CHAT_DEPLOYMENT_SKU=DataZoneStandard` /
  `EMBEDDING_DEPLOYMENT_SKU=DataZoneStandard`, el preflight regional y el de AILZ
  pasan (`0 fail`), y `azd provision` desplegó ambos modelos en `DataZoneStandard`
  en `westus`. Sin env, los defaults (`GlobalStandard`/`Standard`) se mantienen.
- **Cambio 4:** en un RG con una cuenta de storage BYO adicional, el resolver
  pasaba de un nombre inexistente (`st$RESOURCE_TOKEN`) al storage real; se validó
  reintentando el post-provision tras el fix: **exit 0 (2026-08-14)**, con
  `PUT knowledgesources/knowledge-base-blob-ks` (201) y
  `PUT knowledgebases/knowledge-base` (201) sobre el storage correcto
  (`stiunaosgptragbot01wus00`).

---

## Checklist para abrir la PR (reglas del repo)

- [ ] Partir de `develop` y crear rama `feature/<desc>` (el flujo del repo exige
      features → `develop`, no `main`).
- [ ] Rebasar/cherry-pick **solo** los cambios en alcance (Cambios 1–4); **excluir**
      `hcd-deployment/*` y cualquier edición de `infra/`.
- [ ] Actualizar `CHANGELOG.md` (Keep a Changelog / SemVer) con los cambios.
- [ ] Verificar paridad `preProvision.ps1` ↔ `preProvision.sh` (Cambio 3).
- [ ] Abrir la(s) PR(s) contra `develop` con descripción y notas de compatibilidad.
- [ ] Cross-referenciar la PR de AILZ (`ailz-improvements.md`) para los cambios de
      `infra/` relacionados (SPL `cafTrim`, auto-aprobación de shared private links).

---

## Referencia rápida (archivos tocados)

| Archivo | Tipo | Cambio |
|---|---|---|
| [main.parameters.json](../main.parameters.json) | mod | Tokens de SKU en `modelDeploymentList` |
| [scripts/Invoke-RegionalPreflight.ps1](../scripts/Invoke-RegionalPreflight.ps1) | mod | Resolver tokens anidados de SKU |
| [scripts/Resolve-ModelDeploymentSkus.ps1](../scripts/Resolve-ModelDeploymentSkus.ps1) | **nuevo** | Materializa SKU en `infra/main.parameters.json` |
| [scripts/preProvision.ps1](../scripts/preProvision.ps1) | mod | Invoca el helper |
| [scripts/preProvision.sh](../scripts/preProvision.sh) | mod | Invoca el helper (paridad) |
| [scripts/postProvision.ps1](../scripts/postProvision.ps1) | mod | Resolver de storage exige prefijo `st` |
