# Preflight Checker — azure-gpt-rag

A pre-deployment validation script that reads your `azd` environment variables and `infra/main.parameters.json` to verify that the target Azure regions have sufficient **quota**, **service availability**, and **resource provider registration** before you run `azd provision`.

Running this check can save you from mid-deployment failures caused by capacity limits or unsupported regions.

---

## Contents

| File | Description |
|---|---|
| `preflightCheck.sh` | Bash script for macOS / Linux |
| `README.md` | This file |

> A PowerShell version (`preflightCheck.ps1`) for Windows is planned for a future release.

---

## What It Checks

| Section | Checks |
|---|---|
| **1 · Prerequisites** | `az` CLI installed, `jq` installed, `main.parameters.json` found |
| **2 · Authentication** | Active `az login` session, target subscription accessible |
| **3 · Region Configuration** | `AZURE_LOCATION`, `AZURE_AI_FOUNDRY_LOCATION`, `AZURE_COSMOS_LOCATION`, `AZURE_PSQL_LOCATION` are valid Azure region slugs |
| **4 · Resource Providers** | `Microsoft.App`, `Microsoft.CognitiveServices`, `Microsoft.Search`, `Microsoft.ContainerRegistry`, `Microsoft.DocumentDB`, `Microsoft.KeyVault`, `Microsoft.Storage`, `Microsoft.Insights`, `Microsoft.OperationalInsights` are registered |
| **5 · Regional Availability** | Container Apps, AI Search, AI Foundry, Container Registry are available in the target regions |
| **6 · VM Quota** | Sufficient vCPU quota for `vmSize` (e.g. `Standard_D8s_v5`) when `deployVM=true` and `networkIsolation=true` |
| **7 · OpenAI Models** | Each model in `modelDeploymentList` (name + version) is listed as available in `AZURE_AI_FOUNDRY_LOCATION`; warns about TPM capacity |
| **8 · PostgreSQL** | PostgreSQL Flexible Server SKUs available in `AZURE_PSQL_LOCATION` when `deployPostgres=true` |

The script reads feature flags (`deployVM`, `deployAiFoundry`, `deploySearchService`, `deployContainerApps`, `deployPostgres`, `networkIsolation`) directly from `main.parameters.json`, so checks for disabled services are automatically skipped.

---

## Requirements

| Tool | Install |
|---|---|
| [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | `brew install azure-cli` |
| [jq](https://jqlang.github.io/jq/) | `brew install jq` |
| Bash ≥ 4.0 | Pre-installed on Linux; `brew install bash` on macOS if needed |

---

## Quick Start

### 1. Make the script executable

```bash
chmod +x preflight/preflightCheck.sh
```

### 2. Authenticate with Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 3. Set your azd environment variables

If you have already run `azd env new` or `azd env select`, the script will automatically load your environment variables via `azd env get-values`.

You can also pass the region and subscription directly as arguments — the script will prompt you for a region if neither is provided:

```bash
# Will prompt: "> Enter region (e.g. eastus):"
./preflight/preflightCheck.sh

# Pass region directly (no prompt)
./preflight/preflightCheck.sh -l eastus

# Pass both region and subscription
./preflight/preflightCheck.sh -l eastus -s "My Subscription"
```

Or export them manually:

```bash
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_LOCATION="eastus"
export AZURE_AI_FOUNDRY_LOCATION="eastus"
export AZURE_COSMOS_LOCATION="eastus"
```

### 4. Run the script from the repository root

```bash
./preflight/preflightCheck.sh
```

---

## CLI Options

```
Usage: ./preflight/preflightCheck.sh [OPTIONS]

  -l, --location <region>       Azure region slug to validate (e.g. eastus, westeurope)
                                Overrides AZURE_LOCATION for this run.
                                If not provided, the script will prompt you interactively.
  -s, --subscription <id|name>  Subscription ID or display name to validate against.
                                Defaults to the current az CLI context subscription.
  --fail-fast                   Stop immediately on the first FAIL result.
  -h, --help                    Show this help message.
```

**Region resolution priority:**
1. `--location` / `-l` flag (this run only, does not modify your azd env)
2. `AZURE_LOCATION` environment variable (or loaded via `azd env get-values`)
3. **Interactive prompt** — if neither is set, the script asks you to type a region

**Subscription resolution priority:**
1. `--subscription` / `-s` flag
2. `AZURE_SUBSCRIPTION_ID` environment variable
3. Current `az` CLI context (the active subscription from `az account show`)

**Examples:**

```bash
# Prompted interactively for region, uses current az context subscription
./preflight/preflightCheck.sh

# Specify region directly
./preflight/preflightCheck.sh --location eastus
./preflight/preflightCheck.sh -l westeurope

# Specify both region and subscription
./preflight/preflightCheck.sh -l swedencentral -s 'My Dev Subscription'
./preflight/preflightCheck.sh --location eastus --subscription xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Stop at the first failure (useful in CI pipelines)
./preflight/preflightCheck.sh -l eastus --fail-fast
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed (PASS or WARN only) |
| `1` | One or more FAIL results — resolve before provisioning |

---

## Sample Output

```
╔══════════════════════════════════════════════════════════════════════╗
║         azure-gpt-rag  •  Pre-Deployment Preflight Checker          ║
╚══════════════════════════════════════════════════════════════════════╝

──────────────────────────────────────────────────────────────────────
  1 · Prerequisites
──────────────────────────────────────────────────────────────────────
  Azure CLI (az) installed ...                                [PASS]
  jq (JSON processor) installed ...                          [PASS]
  infra/main.parameters.json exists ...                      [PASS]

...

──────────────────────────────────────────────────────────────────────
  PREFLIGHT CHECK RESULTS
──────────────────────────────────────────────────────────────────────

  #    STATUS    CHECK
  ──────────────────────────────────────────────────────────────────────
  1    PASS      Azure CLI installed
  2    PASS      Azure CLI authenticated
  3    PASS      Subscription accessible
                 Name: My Subscription  ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  4    PASS      Region 'eastus' is valid
  5    PASS      Provider Microsoft.App
  ...
  12   FAIL      Model 'gpt-5-mini' not available in 'eastus'
                 Change AZURE_AI_FOUNDRY_LOCATION or update the model.
  13   WARN      OpenAI quota for 'gpt-5-mini' (GlobalStandard)
                 Requesting 40K TPM. Visit https://aka.ms/oai/quotaincrease
  ──────────────────────────────────────────────────────────────────────

  PASS: 10  FAIL: 1  WARN: 2  SKIP: 3

  RECOMMENDATIONS
  ──────────────────────────────────────────────────────────────────────
  ✖ Model 'gpt-5-mini' not available in 'eastus': ...
  ⚠ OpenAI quota for 'gpt-5-mini': Requesting 40K TPM

  Suggested actions:
  • For FAIL items, resolve each issue before running azd provision.
  • To change the AI Foundry region:  azd env set AZURE_AI_FOUNDRY_LOCATION <new-region>
  • Request OpenAI quota increases at: https://aka.ms/oai/quotaincrease
  • Request VM quota increases at:     https://portal.azure.com/#view/Microsoft_Azure_Capacity/...

  ✖  PREFLIGHT FAILED — 1 issue(s) must be resolved before provisioning.
```

---

## Integration with azd Hooks

You can run the preflight check automatically as part of `azd provision` by adding it to the `preprovision` hook in `azure.yaml`:

```yaml
hooks:
  preprovision:
    posix:
      shell: sh
      run: |
        ./preflight/preflightCheck.sh
      interactive: true
```

> **Note:** This will block provisioning if the script exits with code `1`. Remove the hook if you want to run the preflight check manually only.

---

## Common Failures and Fixes

| Failure | Fix |
|---|---|
| **Region not valid** | Run `az account list-locations --query "[].name" -o tsv` to find valid slugs |
| **Resource provider not registered** | `az provider register --namespace <namespace> --wait` |
| **Container Apps not available in region** | Change `AZURE_LOCATION` to `eastus`, `westeurope`, or `australiaeast` |
| **Model not available in AI Foundry region** | Change `AZURE_AI_FOUNDRY_LOCATION` — check [OpenAI model availability by region](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models) |
| **Insufficient VM vCPU quota** | Request quota increase at [Azure Portal — Quotas](https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade) |
| **OpenAI TPM quota exceeded** | Request increase at [https://aka.ms/oai/quotaincrease](https://aka.ms/oai/quotaincrease) |
| **PostgreSQL not available** | Check [PostgreSQL Flexible Server regional availability](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/?products=postgresql) |

---

## How Regions Are Resolved

The script resolves regions in this priority order:

1. `--location` CLI flag (overrides only `AZURE_LOCATION` for this run)
2. Environment variables already exported in your shell
3. `azd env get-values` (loaded automatically if `azd` is installed)
4. Falls back to the value in `main.parameters.json` for hardcoded entries

Regions not set default to `AZURE_LOCATION` (e.g., `AZURE_AI_FOUNDRY_LOCATION` defaults to `AZURE_LOCATION` if not explicitly set).

---

## Limitations

- **OpenAI quota** (TPM/RPM) cannot be precisely checked pre-deployment because it depends on existing account usage. The script checks model *availability* in the region and emits a `WARN` for capacity — review your quota in the [Azure OpenAI Studio](https://oai.azure.com/portal) if you see `QuotaExceeded` errors.
- **Cosmos DB** and **Storage Account** availability checks are not included since these services have very broad regional coverage.
- The script requires `Contributor` or `Reader` role on the subscription to query quotas and provider metadata.
