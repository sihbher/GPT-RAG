# Prueba de Despliegue GPT RAG para HCD

| Campo             | Valor                                                                       |
| ----------------- | --------------------------------------------------------------------------- |
| Versión           | v9                                                                          |
| Fecha inicio      | 2026-08-07                                                                  |
| Autor             | Gerardo Reyes                                                               |
| Suscripción       | HCD-NON-PROD (`*******`)                       |
| Tenant            | CA Housing & Community Development (`*******`) |
| Dominio tenant    | *******                                                       |
| Repositorio local | `/Users/gerardoreyes/Repos/ai-forks/april06/GPT-RAG`                        |
| Template          | [Azure/gpt-rag](https://github.com/azure/gpt-rag)                           |
```toc
```

## Objetivo

Documentar paso a paso la prueba de despliegue del acelerador GPT RAG en el entorno aislado de HCD, usando un contexto de Azure separado (`AZURE_CONFIG_DIR` y `AZD_CONFIG_DIR` dedicados) para no interferir con otros clientes.

## Historial de versiones

| Versión | Fecha      | Cambios                                                                                                                                                                                                    |
| ------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| v1      | 2026-08-07 | Documentación inicial: aislamiento de contexto, login, clonado del repo, actualización de azd, creación y configuración del entorno azd.                                                                   |
| v2      | 2026-08-11 | Parametrización del SKU de los modelos (residencia US) con backward compatibility, parche al preflight regional, y ejecución del preflight (PASS). Cambio de repo de trabajo a `ai-forks/april06/GPT-RAG`. |
| v3      | 2026-08-11 | Primer `azd provision`: fallo de compilación de Bicep por submódulo `infra` en checkout roto (v1.1.4, archivos borrados). Reparación al pin correcto **v2.3.0**; Bicep compila sin errores.                |
| v4      | 2026-08-11 | Segundo `azd provision`: el preflight de AILZ rechazaba el token de SKU anidado. Helper `Resolve-ModelDeploymentSkus.ps1` en `preProvision` materializa el SKU concreto en `infra/main.parameters.json`. Ambos preflights pasan. |
| v5      | 2026-08-11 | Tercer `azd provision`: aprovisiona casi todo pero falla en el shared private link del AI Search (nombre de 64 chars > 60). Fix en `infra/main.bicep` con `cafTrim(..., 60)`. Cambios de AILZ registrados en `ailz-improvements.md` para PR upstream. |
| v6      | 2026-08-12 | Cuarto `azd provision`: **SUCCESS** (12m40s), todos los recursos creados. Post-provision pendiente (Zero Trust → debe correr dentro de la VNet vía la Test VM/Bastion). Datos de conexión a la VM. Archivo de contexto para Copilot en `hcd-deployment/README.md` dentro del repo. |
| v7      | 2026-08-12 | Acceso a la Test VM (saga Bastion): password no estaba en KV → reset; Bastion timeout desde toda red por NSG con `bastionAllowedSourceIPs` vacío (no era GSA/Defender); write de NSG bloqueado por PIM expirado. Fix con `BASTION_ALLOWED_SOURCE_IPS`. Change 3 en `ailz-improvements.md`. Sección de parámetros al final. |
| v8      | 2026-08-12 | Root cause del KV vacío (el password de la VM nunca se persiste en el Bicep) y paso alternativo: cliente nativo de Bastion (túnel + RDP) desde la Mac. |
| v9      | 2026-08-12 | Deploy sin Docker: ACR Tasks agent pool **no disponible en westus** (falla `azd provision`). Revertido `DEPLOY_ACR_TASK_AGENT_POOL=false`; opciones (abrir ACR temporal + `azd deploy`, o cambiar región). Change 4 en `ailz-improvements.md`. |

---

## Paso 1: Aislar el contexto de Azure para HCD

Se definen directorios de configuración dedicados para mantener el contexto de HCD separado del resto de credenciales y entornos.

```bash
export AZURE_CONFIG_DIR="$HOME/.azure-hcd"
export AZD_CONFIG_DIR="$HOME/.azd-hcd"
```

## Paso 2: Login en el tenant de HCD

```bash
az login --tenant *******
```

Selección de suscripción:

```
No     Subscription name    Subscription ID                       Tenant
-----  -------------------  ------------------------------------  ------------------------------------
[1] *  HCD-NON-PROD         *******  *******
```

Verificación del contexto activo:

```bash
az account show -o table
```

```
EnvironmentName    HomeTenantId                          IsDefault    Name          State    TenantId
-----------------  ------------------------------------  -----------  ------------  -------  ------------------------------------
AzureCloud         *******  True         HCD-NON-PROD  Enabled  *******
```

## Paso 3: Cargar el script de entorno HCD

El script `hcd-env.sh` configura el contexto aislado. Debe cargarse con `source` (no ejecutarse directamente, ya que ejecutarlo da `permission denied`).

```bash
source "/Users/gerardoreyes/Microsoft/AI-Factory/Factory-Work/projects/HCD/Deploy/tools/hcd-env.sh"
```

Salida:

```
Azure context: HCD (aislado). Suscripción activa:
Name          Tenant
------------  ------------------------------------
HCD-NON-PROD  *******
```

> Nota: intentar ejecutar el script directamente (`/Users/.../hcd-env.sh`) devuelve `zsh: permission denied`. Hay que usar `source`.

## Paso 4: Clonar el repositorio GPT RAG

```bash
cd /Users/gerardoreyes/Repos/hcd-tests/gpt001
git clone https://github.com/azure/gpt-rag .
code .
```

Volver a cargar el contexto HCD dentro del nuevo workspace:

```bash
source "/Users/gerardoreyes/Microsoft/AI-Factory/Factory-Work/projects/HCD/Deploy/tools/hcd-env.sh"
```

```
Contexto Azure activo (HCD, aislado):
Name          Tenant
------------  ------------------------------------
HCD-NON-PROD  *******
```

## Paso 5: Actualizar Azure Developer CLI (azd)

La versión instalada (1.24.2) no reconocía algunos comandos y pedía actualización a 1.30.0.

```bash
# Confiar en el tap de azure/azd
brew trust azure/azd

# Reinstalar como cask
brew uninstall azd && brew install --cask azure/azd/azd
```

Resultado: `azd` actualizado correctamente a la versión 1.30.0.

```
🍺  azd was successfully installed!
```

> Observación: `azd status` no existe como comando. Los comandos válidos incluyen `azd up`, `azd provision`, `azd deploy`, `azd env`, `azd show`, entre otros.

## Paso 6: Re-login para confirmar tenant con nombre resuelto

```bash
az login
```

```
Tenant: CA Housing & Community Development
Subscription: HCD-NON-PROD (*******)
```

Verificación final:

```bash
az account show -o table
```

```
EnvironmentName    HomeTenantId                          IsDefault    Name          State    TenantDefaultDomain    TenantDisplayName                   TenantId
-----------------  ------------------------------------  -----------  ------------  -------  ---------------------  ----------------------------------  ------------------------------------
AzureCloud         *******  True         HCD-NON-PROD  Enabled  *******  CA Housing & Community Development  *******
```

## Paso 7: Crear y configurar el entorno azd

### 7.1 Definir variables de shell

> Nota: en zsh la asignación de variables no lleva `$` ni espacios. `$deployName = "..."` da `command not found: =`. La forma correcta es `variable="valor"` (sin espacios).

```bash
deployName="gptrag-bot01"
echo $deployName
# gptrag-bot01

resourceGroup="*******"
```

### 7.2 Crear el entorno azd

```bash
azd env new $deployName --no-prompt
```

```
New environment 'gptrag-bot01' was set as default
```

### 7.3 Configurar las variables del entorno

> Nota: cada `azd env set` acepta un solo par `clave valor`. Pegar varias líneas juntas provoca `ERROR: invalid key=value format`. Ejecutar cada comando por separado.

```bash
# Suscripción y grupo de recursos
azd env set AZURE_SUBSCRIPTION_ID $HCD_SUBSCRIPTION_ID
azd env set AZURE_RESOURCE_GROUP $resourceGroup

# Aislamiento de red (modo Zero Trust)
azd env set NETWORK_ISOLATION true

# VM de acceso y firewall
azd env set DEPLOY_VM true
azd env set DEPLOY_AZURE_FIREWALL false
```

### 7.4 Verificar los valores del entorno

```bash
azd env get-values
```

```
AZURE_ENV_NAME="gptrag-bot01"
AZURE_RESOURCE_GROUP="*******"
AZURE_SUBSCRIPTION_ID="*******"
DEPLOY_AZURE_FIREWALL="false"
DEPLOY_VM="true"
NETWORK_ISOLATION="true"
```

| Variable | Valor | Propósito |
|----------|-------|-----------|
| `AZURE_ENV_NAME` | `gptrag-bot01` | Nombre del entorno azd |
| `AZURE_RESOURCE_GROUP` | `*******` | Grupo de recursos destino |
| `AZURE_SUBSCRIPTION_ID` | `*******` | Suscripción HCD-NON-PROD |
| `NETWORK_ISOLATION` | `true` | Despliegue en modo Zero Trust (red aislada) |
| `DEPLOY_VM` | `true` | Crea una VM de acceso dentro de la red aislada |
| `DEPLOY_AZURE_FIREWALL` | `false` | No se aprovisiona Azure Firewall |

---

## Paso 8: Parametrizar el tipo de despliegue (SKU) de los modelos

> A partir de aquí el repo de trabajo es `/Users/gerardoreyes/Repos/ai-forks/april06/GPT-RAG` (fork con el entorno azd `gptrag-bot01`).

Contexto: HCD exige residencia de datos en EE. UU. (US-geofencing). Para Azure OpenAI eso significa **no** usar tipos `Global*` (`GlobalStandard`, `GlobalProvisioned`, `GlobalBatch`); solo `Standard` (una geografía) o `DataZoneStandard` (zona de datos US).

En lugar de codificar el SKU directamente en `main.parameters.json`, se **parametrizó** vía variables de entorno de `azd`, manteniendo **backward compatibility** con el repo base (defaults originales) para poder proponer el cambio upstream.

### 8.1 Tokens en `main.parameters.json` (`modelDeploymentList`)

```jsonc
// chat
"sku": { "name": "${CHAT_DEPLOYMENT_SKU=GlobalStandard}", "capacity": 100 }
// text-embedding
"sku": { "name": "${EMBEDDING_DEPLOYMENT_SKU=Standard}", "capacity": 100 }
```

- Sin variables → comportamiento idéntico al repo base (`GlobalStandard` / `Standard`).
- HCD las sobreescribe con `DataZoneStandard` (ver Paso 9).
- `capacity` se deja como número (no token) para no romper la validación de tipo `int` en Bicep.

### 8.2 Parche al preflight regional

El preflight `scripts/Invoke-RegionalPreflight.ps1` solo resolvía tokens `${VAR=default}` en parámetros de primer nivel; leía `modelDeploymentList[].sku.name` de forma literal. Se ajustó `Test-ModelReadiness` para resolver los tokens anidados con el helper existente `Resolve-TemplateValue`:

```powershell
$modelName    = Resolve-TemplateValue $model.name
$modelVersion = Resolve-TemplateValue $model.version
$skuName      = Resolve-TemplateValue $deployment.sku.name
$capacity     = [double](Resolve-TemplateValue $deployment.sku.capacity)
```

Así el preflight y `azd provision` usan el mismo valor (ambos leen el entorno de `azd`).

## Paso 9: Configurar los SKUs para residencia US

```bash
azd env set CHAT_DEPLOYMENT_SKU DataZoneStandard
azd env set EMBEDDING_DEPLOYMENT_SKU DataZoneStandard
```

Verificación:

```bash
azd env get-values | grep -E "CHAT_DEPLOYMENT_SKU|EMBEDDING_DEPLOYMENT_SKU"
```

```
CHAT_DEPLOYMENT_SKU="DataZoneStandard"
EMBEDDING_DEPLOYMENT_SKU="DataZoneStandard"
```

> `DataZoneStandard` usa un pool de cuota distinto a `GlobalStandard`. En `westus` hay cuota suficiente (chat 50000, embedding 10000; cada uno pide 100).

## Paso 10: Ejecutar el preflight regional

```bash
export AZURE_CONFIG_DIR="$HOME/.azure-hcd"
export AZD_CONFIG_DIR="$HOME/.azd-hcd"
./scripts/preProvision.sh
```

### 10.1 Primer intento: FAIL por credenciales

El primer intento falló con **25 FAIL**, todos `AuthorizationFailed` en llamadas ARM — incluso al leer el propio grupo de recursos (`*******`), sobre el que sí se tiene Contributor:

```
FAIL provider:Microsoft.Compute - ... (AuthorizationFailed) ... does not have authorization to perform action
'Microsoft.Resources/subscriptions/providers/read' ... If access was recently granted, please refresh your credentials.
Result: FAIL (25 fail, 9 warn)
```

Diagnóstico: **no era falta de rol** (el RG propio también fallaba) sino **permisos/PIM sin activar** (el token no traía los roles de suscripción).

### 10.2 Tras activar permisos: PASS

Después de activar los permisos (PIM) el preflight pasa:

```
PASS provider:Microsoft.Compute - registered.
PASS quota:compute:vm-sku - Standard_D2s_v3 is available in westus.
PASS model:gpt-5-nano - DataZoneStandard deployment is listed in westus.
PASS model:gpt-5-nano:quota - 50000 quota units remaining; deployment requests 100.
PASS model:text-embedding-3-large - DataZoneStandard deployment is listed in westus.
PASS model:text-embedding-3-large:quota - 10000 quota units remaining; deployment requests 100.
Result: WARN (0 fail, 8 warn)
```

> Justo tras activar PIM, el namespace `Microsoft.Compute` / `Microsoft.Quota` tardó ~1–2 min en propagar; una segunda corrida lo resolvió.

Los 8 WARN son benignos: ítems de cuota "not found" (la Quota API responde, pero esos ítems no se exponen para esta suscripción/región) y las advertencias genéricas de capacidad de AI Search / Cosmos.

> En esta corrida el preflight de AI Landing Zone (`infra/scripts/Invoke-PreflightChecks.ps1`) **no** corrió porque el submódulo `infra` estaba en un checkout roto (v1.1.4) que no incluía ese script. Tras reparar el submódulo al pin correcto **v2.3.0** (ver Paso 11), el script **sí** existe y correrá en la siguiente ejecución.

---

## Paso 11: `azd provision` — fallo de Bicep y reparación del submódulo `infra`

Al ejecutar `azd provision`, el preflight regional pasó (`0 fail, 8 warn`) pero la compilación de Bicep falló:

```
infra/main.bicep(54,24) : Error BCP091: ... Could not find ... 'infra/constants/constants.bicep'.
infra/main.bicep(320,40) : Error BCP063: The name "const" is not a parameter, variable, resource or module.
... (decenas de BCP063 iguales + _testVmRoles / _peList / _executorRoles no válidos)
deployment failed: failed to compile bicep template
```

### 11.1 Causa

El submódulo `infra/` estaba en un **checkout roto**: versión **v1.1.4** (`5b45518`) con 12 archivos borrados —incluido `constants/constants.bicep`— y `main.bicep` modificado. Como `main.bicep` hace `import * as const from 'constants/constants.bicep'`, al faltar el archivo se dispara `BCP091` y toda la cascada de `BCP063 "const" is not...`.

`git submodule update` (sin `--force`) no pudo corregirlo porque los cambios locales bloqueaban el checkout.

El pin correcto (superproyecto + `.gitmodules` + `manifest.json` `ailz_tag`) es **v2.3.0** (`1616ddd`):

```bash
git ls-tree HEAD infra        # 1616ddd... (v2.3.0) — lo que fija el superproyecto
git -C infra rev-parse HEAD   # 5b45518... (v1.1.4) — lo que había en disco (roto)
```

### 11.2 Reparación

```bash
# respaldo del working tree roto (por si acaso)
git -C infra diff HEAD > "$TMPDIR/infra_worktree_v114_backup.patch"

# resetear el submódulo al pin correcto, descartando el estado roto
git submodule sync --recursive
git submodule update --init --recursive --force
```

Verificación:

```bash
git -C infra describe --tags   # v2.3.0
git -C infra status --short    # (limpio)
ls infra/constants/            # abbreviations.json  constants.bicep  roles.json
```

El Bicep language server reporta **0 errores** en `infra/main.bicep`.

> `infra/` es un submódulo vendorizado que se reemplaza durante el aprovisionamiento; no debe editarse a mano. El estado roto probablemente venía de un `git submodule update` previo interrumpido.

> En v2.3.0 sí existe `infra/scripts/Invoke-PreflightChecks.ps1`, así que la **siguiente** corrida de `azd provision` ejecutará también el preflight de AI Landing Zone (además del regional).

---

## Paso 12: Segundo `azd provision` — el preflight de AILZ rechaza el token de SKU anidado

El deploy volvió a fallar, ahora en el **preflight de AI Landing Zone**:

```
[FAIL] MODEL_QUOTA_INSUFFICIENT  Insufficient AI model quota in 'westus':
  No quota entry 'OpenAI.${CHAT_DEPLOYMENT_SKU=GlobalStandard}.gpt-5-nano' in westus.
  No quota entry 'OpenAI.${EMBEDDING_DEPLOYMENT_SKU=Standard}.text-embedding-3-large' in westus.
Summary: 1 fail, 4 warn, 1 info
```

### 12.1 Causa

El preflight de AILZ (`infra/scripts/Invoke-PreflightChecks.ps1`) **no resuelve tokens `${VAR=default}` anidados** dentro de `modelDeploymentList`. Su función `Get-EffectiveParameters` → `Expand-ParamValue` solo resuelve valores **string de primer nivel** (`if ($Raw -isnot [string]) { return $Raw }`); los arrays/objetos se pasan tal cual. Por eso arma el nombre de cuota con el token literal → entrada inexistente → FAIL.

Es el mismo patrón que el preflight regional (ya parcheado), pero AILZ es **vendorizado** (no se debe editar). El patrón del framework es: tokens `${VAR=default}` **solo en parámetros escalares de primer nivel**; en el `main.parameters.json` original de GPT-RAG los SKU de `modelDeploymentList` son **concretos**.

Además se confirmó que el WARN `SEARCH_SKU_UNAVAILABLE` es benigno: la API `Microsoft.Search/locations/westus/usages` devuelve `{"value": []}` (sin renglones de cuota), igual que los "quota item not found".

### 12.2 Solución (materializar el SKU en el paso de copia)

Se sigue el mismo patrón del framework (`${VAR=default}`), pero resolviéndolo en el paso que sí controlamos: al copiar `main.parameters.json` → `infra/main.parameters.json` en el hook `preProvision`.

- **Nuevo** `scripts/Resolve-ModelDeploymentSkus.ps1`: resuelve los tokens de `modelDeploymentList[].sku.name` con reemplazo **textual puntual** (no re-serializa el JSON). Precedencia: env de azd → env de proceso → default del token.
- **`scripts/preProvision.sh`** y **`scripts/preProvision.ps1`** llaman al helper tras copiar a `infra/` (paridad mantenida).

Resultado: tanto el preflight de AILZ como azd ven `DataZoneStandard` **concreto**; el `main.parameters.json` del root **conserva los tokens** (backward compatible, apto para PR upstream). No se toca nada vendorizado.

Verificación:

```
Resolved model deployment SKU tokens in infra parameters:
  ${CHAT_DEPLOYMENT_SKU=GlobalStandard} -> DataZoneStandard;
  ${EMBEDDING_DEPLOYMENT_SKU=Standard} -> DataZoneStandard
...
  Summary: 0 fail, 4 warn, 1 info    (preflight de AILZ)
```

- Con env seteada → `DataZoneStandard`. Sin env → default (`GlobalStandard`/`Standard`) = idéntico al upstream.
- `preProvision` sale con código 0 (ambos preflights pasan).

---

## Paso 13: Tercer `azd provision` — falla el nombre del shared private link del AI Search (>60 chars)

Esta vez el aprovisionamiento avanzó muchísimo: creó Container Registry, Key Vault, Log Analytics, Storage, VNet, App Insights, Cosmos, Container Apps Environment, ambos Search, Foundry, los model deployments `chat`/`text-embedding`, y casi todos los private endpoints. Falló casi al final:

```
ERROR: deployment failed: error deploying infrastructure: deploying to resource group:
BadRequest: 'name' is allowed to only have alphanumeric characters, underscores, hyphens
and periods; and must be between 1-60 characters in length
```

### 13.1 Cómo se obtuvo el detalle

El error de `azd` es genérico; el recurso exacto sale de las operaciones del deployment:

```bash
az deployment operation group list -g ******* \
  -n gptrag-bot01-<timestamp> \
  --query "[?properties.provisioningState=='Failed'].{type:properties.targetResource.resourceType, name:properties.targetResource.resourceName, code:properties.statusMessage.error.code, msg:properties.statusMessage.error.message}" -o json
```

(el nombre del deployment `gptrag-bot01-<timestamp>` sale de la URL del portal que imprime `azd`).

### 13.2 Causa

Recurso: `Microsoft.Search/searchServices/sharedPrivateLinkResources`, nombre
`spl-srch-iunaos-gptrag-bot01-wus-001-cognitiveservices_account-1` = **64 chars** (límite 60).

Se construye en `infra/main.bicep` (variable `searchFoundrySharedPrivateLinkResources`) como
`spl-${searchServiceName}-cognitiveservices_account-1`. Con `searchServiceName` = `srch-iunaos-gptrag-bot01-wus-001` (32 chars) + prefijo `spl-` (4) + sufijo `-cognitiveservices_account-1` (28) = 64. **AILZ no trunca el nombre del SPL a 60** (a diferencia del search name, que sí usa `cafTrim(..., 60)`). Es un **bug de AILZ**, no del SKU; el nombre de entorno largo (`gptrag-bot01`) lo dispara.

### 13.3 Fix (Opción 1)

Se envolvieron los tres nombres de SPL en el helper existente `cafTrim(..., 60)` en `infra/main.bicep`:

```bicep
name: cafTrim('spl-${resourceNames.searchServiceName}-openai_account-1', 60)
name: cafTrim('spl-${resourceNames.searchServiceName}-foundry_account-1', 60)
name: cafTrim('spl-${resourceNames.searchServiceName}-cognitiveservices_account-1', 60)
```

- Los nombres cortos (`openai` 53, `foundry` 54) quedan **sin cambio** → no se orfanan los SPL ya creados.
- Solo el que desbordaba (`cognitiveservices` 64) se trunca a 60.
- Bicep compila sin errores nuevos.

> `infra/` es vendorizado; este edit es local (persiste porque `preProvision` hace `git submodule update` sin `--force`, pero se perdería con un reset forzado). El fix se registró en **`ailz-improvements.md`** para abrirlo como PR en `Azure/bicep-ptn-aiml-landing-zone` desde un clon directo.

---

## Paso 14: `azd provision` exitoso — mover el post-provision a la Test VM (Zero Trust)

El cuarto `azd provision` terminó en **SUCCESS (12m40s)**; se crearon todos los recursos
(Container Registry, Key Vaults, Log Analytics, App Insights, Storage, VNet + Private
Endpoints, Cosmos workload + Foundry, Container Apps Environment + 3 apps, 2 Search,
Foundry account/project/connections, y los model deployments `chat`/`text-embedding`
en `DataZoneStandard`).

Como es Zero Trust, el post-provision (config de plano de datos + build/deploy de apps)
**debe correr dentro de la VNet**. Al correrlo desde la laptop salió:

```
Ensure you run scripts/postProvision.sh from within the VNet ...
Are you running this script from inside the VNet or via VPN? [Y/n]: n
❌ Please run this script from inside the VNet or with VPN access. Exiting.
```

### 14.1 Datos de la Test VM / conexión

| Item | Valor |
|---|---|
| VM | `testvmiunaoskcf` (**Windows**, `Standard_D2s_v3`) |
| Usuario admin | `testvmuser` |
| Password | aleatorio → Key Vault `kv-iunaos-gptrag-bot01-w` (obtener con el comando de abajo) |
| Acceso | Azure **Bastion** (sin IP pública) |
| Key Vaults | `kv-iunaos-gptrag-bot01-w` (principal), `kv-ai-iunaoskcfg3y2` (AI) |

**Obtener el password** (correr local, con el contexto aislado):

```bash
export AZURE_CONFIG_DIR=$HOME/.azure-hcd AZD_CONFIG_DIR=$HOME/.azd-hcd
az keyvault secret list --vault-name kv-iunaos-gptrag-bot01-w --query "[].name" -o tsv
az keyvault secret show  --vault-name kv-iunaos-gptrag-bot01-w --name <secret-name> --query value -o tsv
```

Password de la VM (pegar aquí el valor tras obtenerlo, este archivo es privado):

```
testvmuser / <PEGAR-PASSWORD-AQUI>
```

**Conectar:** Portal → RG `*******` → VM `testvmiunaoskcf` →
Connect → Bastion → RDP con `testvmuser` + password.

### 14.2 En la VM (Windows) — completar

```powershell
git clone <fork-url> gpt-rag; cd gpt-rag
git checkout hcd/test01
git submodule update --init --recursive
# re-hidratar el env azd apuntando al RG ya aprovisionado
azd env new gptrag-bot01
azd env set AZURE_SUBSCRIPTION_ID *******
azd env set AZURE_RESOURCE_GROUP  *******
azd env set AZURE_LOCATION        westus
azd env set NETWORK_ISOLATION     true
azd env set CHAT_DEPLOYMENT_SKU       DataZoneStandard
azd env set EMBEDDING_DEPLOYMENT_SKU  DataZoneStandard
azd env set RUN_FROM_JUMPBOX      true
azd env refresh
azd provision   # postProvision corre dentro de la VNet
azd deploy      # build + deploy de las container apps
```

> El contexto completo para Copilot en la VM quedó en el repo: `hcd-deployment/README.md`
> (sin secretos, viaja con el push). Si el fix del SPL (`cafTrim`) no está tras el
> `submodule update`, re-aplicarlo en `infra/main.bicep`.

---

## Paso 15: Acceso a la Test VM — la saga de Bastion (password, NSG, PIM)

Conectarse a la Test VM fue lo más laborioso. Resumen en orden de lo que se encontró y resolvió:

### 15.1 El password no estaba en ningún Key Vault → reset

Con `DEPLOY_VM_KEY_VAULT=false`, el `vmAdminPassword = $(secretOrRandomPassword)` se generó
en el deploy pero **no se guardó** (ni KV ni env). El KV `kv-iunaos-gptrag-bot01-w` está **vacío**
(esto corrige la suposición del Paso 14 de sacarlo del KV). Se reseó por management plane:

```bash
az vm user update -g ******* -n testvmiunaoskcf -u testvmuser -p '<password-elegido>'
```

En Bastion, usar **Authentication Type = "Password"** (no "from Key Vault").

### 15.2 Bastion daba timeout desde cualquier red — NO era GSA/Defender

Descartes con pruebas:
- `management.azure.com`, `portal.azure.com`, `login`, internet → OK. **Solo** la IP del Bastion (`52.225.20.172`) hacía timeout.
- Falla igual en navegador **y** CLI, y **desde una VM limpia en otra suscripción** → no era el cliente/GSA/Defender (fue un falso positivo, aunque GSA y Defender NP sí están activos en la Mac).
- **Causa real:** el NSG del `AzureBastionSubnet` **no tenía la regla `AllowHttps*` inbound** (solo `DenyAllInternetInbound`), porque **`bastionAllowedSourceIPs` estaba vacío**. `bastion-nsg.bicep` genera una regla de allow **por cada IP** de esa lista; lista vacía → cero reglas → Bastion cerrado para todos. (Registrado como **Change 3** en `ailz-improvements.md`.)

### 15.3 No podía crear la regla NSG — PIM expirado

`az network nsg rule create` daba `AuthorizationFailed` en `networkSecurityGroups/securityRules/write`,
aunque los reads funcionaban. Causa: el rol Contributor es **PIM-elegible** y la **ventana de activación
había expirado** (por eso `az role assignment list` salía vacío y el error decía *"refresh your credentials"*).
→ **Reactivar PIM** y refrescar token (`az account get-access-token`).

### 15.4 Fix aplicado (reproducible)

Con PIM activo, se seteó el **parámetro** (en vez de regla manual) para que sea reproducible:

```bash
azd env set BASTION_ALLOWED_SOURCE_IPS '["*******"]'   # tu IP pública
```

Se aplica en el próximo `azd provision` (crea `AllowHttpsFromTrustedIP-0`, 443 desde tu IP).
Para acceso inmediato sin re-provision, la regla manual equivalente (requiere PIM activo):

```bash
az network nsg rule create -g ******* \
  --nsg-name nsg-vnet-iunaos-gptrag-bot01-wus-001-AzureBastionSubnet \
  -n AllowHttpsInbound --priority 200 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes ******* --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 443
```

### 15.5 Root cause del KV vacío: el password de la VM nunca se persiste

En `infra/main.bicep`, `vmAdminPassword` aparece **solo** en dos líneas:

```bicep
param vmAdminPassword string     // (901) viene de $(secretOrRandomPassword)
...
adminPassword: vmAdminPassword   // (1524) se aplica DIRECTO al recurso VM
```

- `$(secretOrRandomPassword)` **sin argumentos de KV** → azd genera un password aleatorio en cada deploy pero **no lo persiste** (ni KV ni `.env`).
- El Bicep aplica `vmAdminPassword` **directo** a la VM y **nunca lo escribe a un Key Vault**.
- `deployVmKeyVault` (param 266, default `false`) **no está cableado** para guardar el password: solo existe como parámetro y output (3844); no crea KV ni secreto. Ponerlo en `true` **tampoco** lo hubiera guardado.

**Neto:** el password se genera → se aplica → **se descarta**. El KV está vacío porque **nada** escribe el password ahí; la opción "Password from Azure Key Vault" del Bastion es **engañosa** en esta plantilla. Por eso el único camino es resetear (15.1). **Qué faltó:** un paso que persista el password (`$(secretOrRandomPassword <kv> <secret>)`, que el Bicep escriba el secreto, o que `deployVmKeyVault` realmente lo cablee). Candidato a Change 4 en `ailz-improvements.md`.

### 15.6 Alternativa: cliente nativo de Bastion (túnel + RDP) desde la Mac

La experiencia web del Bastion es mala; con **PIM activo** y la **regla NSG** puesta (443 desde tu IP), se puede usar el **cliente nativo** (túnel local + RDP):

```bash
# extensión de Bastion para az
az extension add -n bastion

# 1) habilitar tunneling (management-plane, reversible; SKU Standard lo soporta)
az network bastion update -n bas-testvm-iunaoskcfg3y2 -g ******* --enable-tunneling true

# 2) abrir túnel local al RDP de la VM
az network bastion tunnel -n bas-testvm-iunaoskcfg3y2 -g ******* \
  --target-resource-id /subscriptions/*******/resourceGroups/*******/providers/Microsoft.Compute/virtualMachines/testvmiunaoskcf \
  --resource-port 3389 --port 13389
```

Luego en la Mac: **Windows App** (Microsoft Remote Desktop) → PC `localhost:13389` → `testvmuser` + password.

> Notas:
> - El túnel va al **mismo** endpoint/NSG del Bastion, así que **necesita la regla NSG** (443 desde tu IP) igual que el web.
> - Si tu Mac enruta por **GSA** y cambia tu IP de egreso, la regla para `*******` podría no coincidir; verifica tu IP efectiva (`curl ifconfig.me`) o amplía la regla.
> - `--enable-tunneling true` es reversible (`--enable-tunneling false`).

✅ **Confirmado (2026-08-12):** túnel + RDP con **Windows App** a `localhost:13389` (usuario `testvmuser`) **funcionó** — se entró al escritorio de la Test VM. Es el método recomendado (la experiencia web del Bastion es mala). Dejar la terminal del túnel abierta mientras dure la sesión.

---

## Paso 16: Deploy sin Docker — ACR Tasks agent pool NO disponible en westus

Objetivo: desplegar las imágenes de las apps **sin Docker**. GPT-RAG construye en ACR
(`az acr build`) en vez de Docker local (`BUILD_MODE=acr-task` / `USE_DOCKER=false`), y en
ZTA (`NETWORK_ISOLATION=true`) los scripts de deploy **ya lo auto-seleccionan**. La jumpbox
**no trae Docker** a propósito.

**Requisito en red aislada:** el ACR es Premium con acceso público deshabilitado, así que
`az acr build` contra el builder compartido de Microsoft falla → se necesita un builder
**dentro de la VNet** = el **ACR Tasks agent pool** (`DEPLOY_ACR_TASK_AGENT_POOL`, default `false`).

### 16.1 El problema: agent pools no existen en westus

Al setear `DEPLOY_ACR_TASK_AGENT_POOL=true` y `azd provision`, falla la validación:

```
LocationNotAvailableForResourceType: The provided location 'westus' is not available for
resource type 'Microsoft.ContainerRegistry/registries/agentPools'.
Available: eastus, westeurope, westus2, southcentralus, australiaeast, canadacentral,
centralus, eastasia, eastus2, northeurope, francecentral, switzerlandnorth, swedencentral, ...
```

**`westus` no está en la lista** → el path "sin Docker vía agent pool en la VNet" **no está
disponible en esta región**.

### 16.2 Desbloquear

```bash
azd env set DEPLOY_ACR_TASK_AGENT_POOL false   # la validación falló antes de tocar nada
```

### 16.3 Opciones para "sin Docker" en westus

- **A (recomendada):** abrir el ACR temporalmente + `azd deploy` (usa `az acr build` con el
  builder compartido) + volver a cerrar:
  ```bash
  ACR=criunaosgptragbot01wus001
  az acr update -n $ACR --public-network-access Enabled     # requiere PIM (Network write)
  azd deploy
  az acr update -n $ACR --public-network-access Disabled
  ```
  Ventana breve de exposición del ACR (el push igual requiere auth).
- **B:** cambiar la región a una con agent pools (`westus2`, `eastus2`, `southcentralus`) →
  redeploy completo + re-verificar `DataZoneStandard` de los modelos (eastus2/southcentralus sí lo tienen).
- **C:** Docker dentro de la VNet (instalar Docker en la jumpbox/otra VM) → **es** usar Docker.

Registrado como **Change 4** en `ailz-improvements.md` (el path no-Docker de ZTA asume agent
pools, que no están en todas las regiones; falta warning en preflight).

---

## Estado actual

- Contexto Azure aislado para HCD; rol de escritura vía **PIM** (recordar reactivar cuando expire).
- Repo de trabajo: `/Users/gerardoreyes/Repos/ai-forks/april06/GPT-RAG`; submódulo `infra` **v2.3.0** (con fix local del SPL).
- Entorno azd `gptrag-bot01` (Zero Trust, VM de acceso, sin Azure Firewall).
- `azd provision` = **SUCCESS**; acceso al Bastion resuelto (RDP por túnel confirmado).
- Deploy sin Docker: agent pool **no disponible en westus** → `DEPLOY_ACR_TASK_AGENT_POOL=false`; para deploy usar Opción A (abrir ACR temporal + `azd deploy`).
- Contexto para el Bastion: `hcd-deployment/README.md` (repo). Fixes de AILZ: `ailz-improvements.md` (Changes 1–4).

## Próximos pasos

- [x] Crear y configurar el entorno azd `gptrag-bot01`.
- [x] Parametrizar el SKU de los modelos (`DataZoneStandard`, residencia US).
- [x] Preflight regional + AILZ en verde.
- [x] Reparar el submódulo `infra` (v2.3.0) y el nombre del SPL (`cafTrim`).
- [x] `azd provision` completo (SUCCESS).
- [x] Resolver el acceso al Bastion (password reset + `BASTION_ALLOWED_SOURCE_IPS` + PIM) y RDP por túnel.
- [ ] Desplegar las apps **sin Docker**: Opción A (abrir ACR temporal + `azd deploy`) o decidir región/agent pool.
- [ ] Completar post-provision (`RUN_FROM_JUMPBOX=true`) y validar apps (orchestrator/frontend/dataingest) + endpoint.
- [ ] Abrir el PR a `Azure/bicep-ptn-aiml-landing-zone` (ver `ailz-improvements.md`, Changes 1–4).

---

## Parámetros del entorno azd (todos los que se agregaron)

`azd env set` aplicados sobre los defaults del template (además de los que azd rellena solo):

| Variable | Valor | Por qué |
|---|---|---|
| `AZURE_SUBSCRIPTION_ID` | `*******` | Suscripción destino |
| `AZURE_RESOURCE_GROUP` | `*******` | RG destino |
| `AZURE_LOCATION` | `westus` | Región |
| `NETWORK_ISOLATION` | `true` | Zero Trust (red aislada) |
| `DEPLOY_VM` | `true` | Test VM / jumpbox |
| `DEPLOY_AZURE_FIREWALL` | `false` | Sin Azure Firewall |
| `CHAT_DEPLOYMENT_SKU` | `DataZoneStandard` | Residencia US (chat) — **no obvio** |
| `EMBEDDING_DEPLOYMENT_SKU` | `DataZoneStandard` | Residencia US (embedding) — **no obvio** |
| `BASTION_ALLOWED_SOURCE_IPS` | `["*******"]` | Permitir acceso al Bastion desde tu IP — **sin esto el Bastion queda inservible** |
| `RUN_FROM_JUMPBOX` | `true` (pendiente, en la VM) | Correr post-provision dentro de la VNet |

> Los tres marcados (`CHAT_DEPLOYMENT_SKU`, `EMBEDDING_DEPLOYMENT_SKU`, `BASTION_ALLOWED_SOURCE_IPS`)
> son los que causaron fricción: sin ellos, o violas la residencia US, o el Bastion queda inalcanzable.
> `BASTION_ALLOWED_SOURCE_IPS` aplica en el próximo `azd provision`; para HCD conviene documentarlo como
> parámetro obligatorio cuando se despliega la Test VM.

