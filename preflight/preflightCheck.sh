#!/usr/bin/env bash
# =============================================================================
# preflight/preflightCheck.sh
#
# Pre-deployment capacity and availability checker for azure-gpt-rag
#
# This script reads your azd environment variables and infra/main.parameters.json
# to validate that the target Azure regions have sufficient quota and service
# availability BEFORE running `azd provision`, helping you avoid mid-deployment
# failures caused by capacity constraints or unsupported regions.
#
# Usage:
#   chmod +x preflight/preflightCheck.sh
#   ./preflight/preflightCheck.sh [--location <region>] [--fail-fast] [--help]
#   ./preflight/preflightCheck.sh --location eastus2
#
# See preflight/README.md for full documentation.
# =============================================================================

# ---------------------------------------------------------------------------
# Shell options — do NOT use set -e here; we handle errors per-check
# ---------------------------------------------------------------------------
set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARAMS_FILE="$REPO_ROOT/infra/main.parameters.json"

# ---------------------------------------------------------------------------
# ANSI color codes
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------
FAIL_FAST=false
OVERRIDE_LOCATION=""
OVERRIDE_SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fail-fast)         FAIL_FAST=true; shift ;;
    --location|-l)       OVERRIDE_LOCATION="$2"; shift 2 ;;
    --subscription|-s)   OVERRIDE_SUBSCRIPTION="$2"; shift 2 ;;
    -h|--help)
      echo ""
      echo -e "  Usage: $0 [OPTIONS]"
      echo ""
      echo "  Options:"
      echo "    -l, --location <region>        Azure region slug to validate (e.g. eastus, westeurope)"
      echo "                                   Overrides AZURE_LOCATION for this run."
      echo "                                   If not provided, the script will prompt you."
      echo "    -s, --subscription <id|name>   Subscription ID or name to use."
      echo "                                   Defaults to the current az CLI context."
      echo "    --fail-fast                    Stop immediately on the first FAIL result."
      echo "    -h, --help                     Show this help message."
      echo ""
      echo "  Examples:"
      echo "    $0 --location eastus"
      echo "    $0 -l swedencentral -s 'My Subscription'"
      echo "    $0 --fail-fast"
      echo ""
      exit 0
      ;;
    *) echo "Unknown option: $1"; echo "Run '$0 --help' for usage."; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Results tracking
# ---------------------------------------------------------------------------
RESULTS=()       # Each entry: "STATUS|CHECK_NAME|DETAIL"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
INFO_COUNT=0
COSMOS_ACCESS_BLOCKED=false   # set to true if Cosmos DB region access is denied
SEARCH_QUOTA_BLOCKED=false    # set to true if AI Search quota/capacity is exhausted

add_result() {
  local status="$1" name="$2" detail="${3:-}"
  RESULTS+=("${status}|${name}|${detail}")
  case "$status" in
    PASS) (( PASS_COUNT++ )) ;;
    FAIL) (( FAIL_COUNT++ )); [[ "$FAIL_FAST" == "true" ]] && { print_summary; exit 1; } ;;
    WARN) (( WARN_COUNT++ )) ;;
    SKIP) (( SKIP_COUNT++ )) ;;
    INFO) (( INFO_COUNT++ )) ;;
  esac
}

pass() { add_result "PASS" "$1" "${2:-}"; }
fail() { add_result "FAIL" "$1" "${2:-}"; }
warn() { add_result "WARN" "$1" "${2:-}"; }
skip() {
  printf "  ${DIM}%-58s${NC}" "$1 ..."
  echo -e " ${DIM}[SKIP]${NC}"
  [[ -n "${2:-}" ]] && echo -e "  ${DIM}  ↳ ${2}${NC}"
  add_result "SKIP" "$1" "${2:-}"
}
info() { add_result "INFO" "$1" "${2:-}"; }

# ---------------------------------------------------------------------------
# Printing helpers
# ---------------------------------------------------------------------------
banner() {
  echo
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║         azure-gpt-rag  •  Pre-Deployment Preflight Checker           ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  echo
}

section() {
  echo
  echo -e "${BLUE}${BOLD}──────────────────────────────────────────────────────────────────────${NC}"
  echo -e "${BLUE}${BOLD}  $1${NC}"
  echo -e "${BLUE}${BOLD}──────────────────────────────────────────────────────────────────────${NC}"
}

log_check() {
  # Live feedback while running a check
  printf "  ${DIM}%-58s${NC}" "$1 ..."
}

log_done() {
  local status="$1"
  case "$status" in
    PASS) echo -e " ${GREEN}[PASS]${NC}" ;;
    FAIL) echo -e " ${RED}[FAIL]${NC}" ;;
    WARN) echo -e " ${YELLOW}[WARN]${NC}" ;;
    SKIP) echo -e " ${DIM}[SKIP]${NC}" ;;
    INFO) echo -e " ${MAGENTA}[INFO]${NC}" ;;
  esac
}

# ---------------------------------------------------------------------------
# Parameter parsing helpers
# ---------------------------------------------------------------------------

# Get a value from main.parameters.json. Handles ${VAR} substitution.
get_param() {
  local key="$1"
  local raw
  raw=$(jq -r ".parameters[\"${key}\"].value // empty" "$PARAMS_FILE" 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    echo ""
    return 0
  fi
  # Resolve ${VAR} references using current shell environment
  if [[ "$raw" =~ ^\$\{([A-Z_0-9]+)\}$ ]]; then
    local varname="${BASH_REMATCH[1]}"
    echo "${!varname:-}"
  else
    echo "$raw"
  fi
}

# Normalize bool: "true", "1", "t" (case-insensitive) → returns 0 (true); else 1 (false)
is_true() {
  local val
  val=$(echo "${1:-false}" | tr '[:upper:]' '[:lower:]' | xargs)
  [[ "$val" == "true" || "$val" == "1" || "$val" == "t" ]]
}

# Map a VM size to its vCPU count (best-effort from name)
vcpus_from_size() {
  local size="$1"
  # Extract the numeric digits after the series letter (e.g., Standard_D8s_v5 → 8)
  echo "$size" | grep -oE '[0-9]+' | head -1
}

# Map a VM size to its Azure quota family name (best-effort)
family_from_size() {
  local size="$1"
  case "$size" in
    Standard_D*s_v5*) echo "standardDSv5Family" ;;
    Standard_D*s_v4*) echo "standardDDSv4Family" ;;
    Standard_D*s_v3*) echo "standardDSv3Family" ;;
    Standard_D*_v4*)  echo "standardDv4Family"  ;;
    Standard_D*_v5*)  echo "standardDv5Family"  ;;
    Standard_E*s_v5*) echo "standardESv5Family" ;;
    Standard_E*s_v4*) echo "standardESv4Family" ;;
    Standard_F*s_v2*) echo "standardFSv2Family" ;;
    Standard_B*)      echo "standardBSFamily"   ;;
    Standard_NC*)     echo "standardNCFamily"   ;;
    *) echo "" ;;
  esac
}

# Load environment variables from azd if available; otherwise rely on shell env
load_azd_env() {
  if command -v azd &>/dev/null; then
    local azd_env_output
    azd_env_output=$(azd env get-values 2>/dev/null || true)
    if [[ -n "$azd_env_output" ]]; then
      while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        value="${value%\"}"
        value="${value#\"}"
        # Only export if not already set in the shell
        if [[ -z "${!key:-}" ]]; then
          export "$key=$value" 2>/dev/null || true
        fi
      done <<< "$azd_env_output"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Summary and recommendations
# ---------------------------------------------------------------------------
print_summary() {
  section "PREFLIGHT CHECK RESULTS"

  # Header
  printf "\n  ${BOLD}%-4s  %-8s  %-55s${NC}\n" "#" "STATUS" "CHECK"
  echo "  $(printf '─%.0s' {1..70})"

  local idx=1
  # Declare arrays outside of local to avoid bash 3.2 set -u unbound variable bug
  # Use safe expansion pattern "${arr[@]+${arr[@]}}" throughout
  local -a failed_checks
  local -a warned_checks
  failed_checks=()
  warned_checks=()

  for entry in "${RESULTS[@]+${RESULTS[@]}}"; do
    local status name detail
    IFS='|' read -r status name detail <<< "$entry"

    local color="$NC"
    case "$status" in
      PASS) color="$GREEN" ;;
      FAIL) color="$RED";    failed_checks+=("$name: $detail") ;;
      WARN) color="$YELLOW"; warned_checks+=("$name: $detail") ;;
      SKIP) color="$DIM"   ;;
      INFO) color="$MAGENTA" ;;
    esac

    printf "  %-4s  ${color}%-8s${NC}  %-55s\n" "$idx" "$status" "$name"
    if [[ -n "${detail:-}" ]]; then
      printf "        ${DIM}%-8s  %s${NC}\n" "" "$detail"
    fi
    (( idx++ ))
  done

  echo "  $(printf '─%.0s' {1..70})"
  echo
  echo -e "  ${GREEN}${BOLD}PASS: $PASS_COUNT${NC}  ${RED}${BOLD}FAIL: $FAIL_COUNT${NC}  ${YELLOW}${BOLD}WARN: $WARN_COUNT${NC}  ${DIM}SKIP: $SKIP_COUNT${NC}"
  echo

  # Recommendations block — use safe expansion to avoid unbound variable on empty arrays
  local fc_count=${#failed_checks[@]:-0}
  local wc_count=${#warned_checks[@]:-0}
  if [[ $fc_count -gt 0 || $wc_count -gt 0 ]]; then
    echo -e "${BOLD}  RECOMMENDATIONS${NC}"
    echo "  $(printf '─%.0s' {1..70})"

    for fc in "${failed_checks[@]+${failed_checks[@]}}"; do
      echo -e "  ${RED}✖${NC} ${fc}"
    done

    for wc in "${warned_checks[@]+${warned_checks[@]}}"; do
      echo -e "  ${YELLOW}⚠${NC} ${wc}"
    done

    echo
    echo -e "  ${BOLD}Suggested actions:${NC}"

    if [[ $fc_count -gt 0 ]]; then
      echo -e "  • For FAIL items, resolve each issue before running ${BOLD}azd provision${NC}."
    fi
    echo -e "  • To change the deployment region: ${BOLD}azd env set AZURE_LOCATION <new-region>${NC}"
    echo -e "  • To change the AI Foundry region:  ${BOLD}azd env set AZURE_AI_FOUNDRY_LOCATION <new-region>${NC}"
    echo -e "  • To change the Cosmos DB region:   ${BOLD}azd env set AZURE_COSMOS_LOCATION <new-region>${NC}"
    echo -e "  • Request OpenAI quota increases at: ${BLUE}https://aka.ms/oai/quotaincrease${NC}"
    echo -e "  • Request VM quota increases at:     ${BLUE}https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade${NC}"
    echo -e "  • Check resource provider availability: ${BOLD}az provider register --namespace <namespace>${NC}"
    if [[ "${COSMOS_ACCESS_BLOCKED:-}" == "true" ]]; then
      echo
      echo -e "  ${YELLOW}${BOLD}Cosmos DB region access is blocked:${NC}"
      echo -e "  • Option 1 — Request region access:     ${BLUE}https://aka.ms/cosmosdbquota${NC}"
      echo -e "  • Option 2 — Use a different region:    ${BOLD}azd env set AZURE_COSMOS_LOCATION eastus2${NC}"
      echo -e "               (other options: westus2, westeurope, northeurope, southeastasia)"
    fi
    if [[ "${SEARCH_QUOTA_BLOCKED:-}" == "true" ]]; then
      echo
      echo -e "  ${YELLOW}${BOLD}AI Search quota or capacity is insufficient in the target region:${NC}"
      echo -e "  • Option 1 — Request quota increase:    ${BLUE}https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade${NC}"
      echo -e "  • Option 2 — Use a different region:    ${BOLD}azd env set AZURE_LOCATION <region>${NC}"
      echo -e "               (options with known capacity: eastus, westus2, westeurope, northeurope, swedencentral)"
      echo -e "  ${DIM}  Note: 'InsufficientResourcesAvailable' can also indicate regional physical capacity${NC}"
      echo -e "  ${DIM}  constraints on Azure's side. If quota shows available, try a different region.${NC}"
    fi
    echo
  fi

  # Final verdict
  if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}✖  PREFLIGHT FAILED — $FAIL_COUNT issue(s) must be resolved before provisioning.${NC}"
    echo
  elif [[ $WARN_COUNT -gt 0 ]]; then
    echo -e "  ${YELLOW}${BOLD}⚠  PREFLIGHT PASSED WITH WARNINGS — review the items above before provisioning.${NC}"
    echo
  else
    echo -e "  ${GREEN}${BOLD}✔  PREFLIGHT PASSED — your environment looks ready for azd provision.${NC}"
    echo
  fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
banner

# ---------------------------------------------------------------------------
# Load azd environment variables early so get_param substitutions resolve
# ---------------------------------------------------------------------------
load_azd_env

# =============================================================================
# SECTION 1 — PREREQUISITES
# =============================================================================
section "1 · Prerequisites"

# --- az CLI ------------------------------------------------------------------
log_check "Azure CLI (az) installed"
if command -v az &>/dev/null; then
  AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  pass "Azure CLI installed" "Version: $AZ_VERSION"
  log_done "PASS"
else
  fail "Azure CLI installed" "Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  log_done "FAIL"
  echo -e "\n  ${RED}Azure CLI is required. Cannot continue without it.${NC}\n"
  exit 1
fi

# --- jq ----------------------------------------------------------------------
log_check "jq (JSON processor) installed"
if command -v jq &>/dev/null; then
  JQ_VERSION=$(jq --version 2>/dev/null || echo "unknown")
  pass "jq installed" "Version: $JQ_VERSION"
  log_done "PASS"
else
  fail "jq installed" "Install: brew install jq  |  apt-get install jq  |  https://jqlang.github.io/jq/"
  log_done "FAIL"
  echo -e "\n  ${RED}jq is required to parse main.parameters.json. Cannot continue.${NC}\n"
  exit 1
fi

# --- parameters file ---------------------------------------------------------
log_check "infra/main.parameters.json exists"
if [[ -f "$PARAMS_FILE" ]]; then
  pass "Parameters file found" "$PARAMS_FILE"
  log_done "PASS"
else
  fail "Parameters file not found" "Expected at: $PARAMS_FILE"
  log_done "FAIL"
  echo -e "\n  ${RED}Cannot find main.parameters.json. Verify REPO_ROOT: $REPO_ROOT${NC}\n"
  exit 1
fi

# =============================================================================
# SECTION 2 — AUTHENTICATION & SUBSCRIPTION
# =============================================================================
section "2 · Authentication & Subscription"

# --- az login ----------------------------------------------------------------
log_check "Azure CLI authenticated"
ACCOUNT_JSON=$(az account show -o json 2>/dev/null || true)
if [[ -n "$ACCOUNT_JSON" && "$ACCOUNT_JSON" != "null" ]]; then
  CURRENT_SUB=$(echo "$ACCOUNT_JSON" | jq -r '.id')
  CURRENT_SUB_NAME=$(echo "$ACCOUNT_JSON" | jq -r '.name')
  CURRENT_USER=$(echo "$ACCOUNT_JSON" | jq -r '.user.name // .user.type')
  pass "Azure CLI authenticated" "User: $CURRENT_USER"
  log_done "PASS"
else
  fail "Azure CLI authenticated" "Run: az login"
  log_done "FAIL"
  print_summary
  exit 1
fi

# --- Subscription ------------------------------------------------------------
# Resolution priority: --subscription flag > AZURE_SUBSCRIPTION_ID env var > current az context
log_check "Target subscription accessible"
if [[ -n "$OVERRIDE_SUBSCRIPTION" ]]; then
  PARAM_SUB="$OVERRIDE_SUBSCRIPTION"
  SUB_SOURCE="--subscription flag"
elif [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  PARAM_SUB="$AZURE_SUBSCRIPTION_ID"
  SUB_SOURCE="AZURE_SUBSCRIPTION_ID env var"
else
  PARAM_SUB="$CURRENT_SUB"
  SUB_SOURCE="current az CLI context"
fi

SUB_CHECK=$(az account show --subscription "$PARAM_SUB" -o json 2>/dev/null || true)
if [[ -n "$SUB_CHECK" && "$SUB_CHECK" != "null" ]]; then
  SUB_NAME=$(echo "$SUB_CHECK" | jq -r '.name')
  AZURE_SUBSCRIPTION_ID=$(echo "$SUB_CHECK" | jq -r '.id')
  pass "Subscription accessible" "Name: $SUB_NAME  ID: $AZURE_SUBSCRIPTION_ID  (source: $SUB_SOURCE)"
  log_done "PASS"
else
  fail "Subscription accessible" "Subscription '$PARAM_SUB' not found or no access (source: $SUB_SOURCE)"
  log_done "FAIL"
  AZURE_SUBSCRIPTION_ID="$CURRENT_SUB"
fi

# =============================================================================
# SECTION 3 — ENVIRONMENT & REGION CONFIGURATION
# =============================================================================
section "3 · Region Configuration"

# Resolve regions — priority: --location flag > env var > azd env > interactive prompt
if [[ -n "$OVERRIDE_LOCATION" ]]; then
  AZURE_LOCATION="$OVERRIDE_LOCATION"
  LOCATION_SOURCE="--location flag"
elif [[ -n "${AZURE_LOCATION:-}" ]]; then
  LOCATION_SOURCE="AZURE_LOCATION env var"
else
  # No region set anywhere — prompt the user interactively
  echo
  echo -e "  ${YELLOW}${BOLD}AZURE_LOCATION is not set.${NC}"
  echo -e "  ${BOLD}Please enter the Azure region you want to validate.${NC}"
  echo -e "  ${DIM}Common options: eastus, eastus2, westus2, westeurope, northeurope,${NC}"
  echo -e "  ${DIM}               swedencentral, australiaeast, southeastasia${NC}"
  echo
  while true; do
    printf "  ${CYAN}>${NC} Enter region (e.g. eastus): "
    read -r AZURE_LOCATION </dev/tty
    AZURE_LOCATION=$(echo "$AZURE_LOCATION" | tr '[:upper:]' '[:lower:]' | xargs)
    if [[ -n "$AZURE_LOCATION" ]]; then
      break
    fi
    echo -e "  ${RED}Region cannot be empty. Try again.${NC}"
  done
  LOCATION_SOURCE="interactive prompt"
  echo
fi

AZURE_AI_FOUNDRY_LOCATION="${AZURE_AI_FOUNDRY_LOCATION:-$AZURE_LOCATION}"
AZURE_COSMOS_LOCATION="${AZURE_COSMOS_LOCATION:-$AZURE_LOCATION}"
AZURE_PSQL_LOCATION="${AZURE_PSQL_LOCATION:-$AZURE_LOCATION}"

# Print resolved locations
echo
echo -e "  ${BOLD}Resolved locations:${NC}  ${DIM}(source: ${LOCATION_SOURCE})${NC}"
echo -e "  AZURE_LOCATION            = ${BOLD}${AZURE_LOCATION:-<not set>}${NC}"
if [[ -n "${AZURE_AI_FOUNDRY_LOCATION:-}" && "$AZURE_AI_FOUNDRY_LOCATION" != "$AZURE_LOCATION" ]]; then
  echo -e "  AZURE_AI_FOUNDRY_LOCATION = ${BOLD}${AZURE_AI_FOUNDRY_LOCATION}${NC}"
elif [[ -n "${AZURE_LOCATION:-}" ]]; then
  echo -e "  AZURE_AI_FOUNDRY_LOCATION = ${DIM}<same as AZURE_LOCATION: $AZURE_LOCATION>${NC}"
else
  echo -e "  AZURE_AI_FOUNDRY_LOCATION = ${DIM}<not set>${NC}"
fi
if [[ -n "${AZURE_COSMOS_LOCATION:-}" && "$AZURE_COSMOS_LOCATION" != "$AZURE_LOCATION" ]]; then
  echo -e "  AZURE_COSMOS_LOCATION     = ${BOLD}${AZURE_COSMOS_LOCATION}${NC}"
elif [[ -n "${AZURE_LOCATION:-}" ]]; then
  echo -e "  AZURE_COSMOS_LOCATION     = ${DIM}<same as AZURE_LOCATION: $AZURE_LOCATION>${NC}"
else
  echo -e "  AZURE_COSMOS_LOCATION     = ${DIM}<not set>${NC}"
fi
if [[ -n "${AZURE_PSQL_LOCATION:-}" && "$AZURE_PSQL_LOCATION" != "$AZURE_LOCATION" ]]; then
  echo -e "  AZURE_PSQL_LOCATION       = ${BOLD}${AZURE_PSQL_LOCATION}${NC}"
elif [[ -n "${AZURE_LOCATION:-}" ]]; then
  echo -e "  AZURE_PSQL_LOCATION       = ${DIM}<same as AZURE_LOCATION: $AZURE_LOCATION>${NC}"
else
  echo -e "  AZURE_PSQL_LOCATION       = ${DIM}<not set>${NC}"
fi
echo

# Fetch list of valid Azure region slugs once (cached)
log_check "Fetching Azure region list"
VALID_LOCATIONS_JSON=$(az account list-locations --query "[].{name:name, display:displayName}" -o json 2>/dev/null || echo "[]")
VALID_LOCATION_NAMES=$(echo "$VALID_LOCATIONS_JSON" | jq -r '.[].name' 2>/dev/null || true)
if [[ -n "$VALID_LOCATION_NAMES" ]]; then
  info "Azure region list fetched" "$(echo "$VALID_LOCATION_NAMES" | wc -l | xargs) regions available"
  log_done "INFO"
else
  warn "Azure region list fetch failed" "Region validation may be skipped"
  log_done "WARN"
fi

# Helper: validate a region
validate_region() {
  local region="$1"
  local label="$2"
  local required="${3:-true}"

  # Check emptiness BEFORE printing the log line to avoid confusing "Region '' ..." messages
  if [[ -z "$region" ]]; then
    if is_true "$required"; then
      log_check "Region $label is set"
      fail "Region $label not set" "Run: azd env set $label <region>  (e.g. eastus, westeurope)"
      log_done "FAIL"
    else
      log_check "Region $label is set (optional)"
      skip "Region $label not set" "Not required for current configuration"
      log_done "SKIP"
    fi
    return
  fi

  log_check "Region '$region' ($label) is a valid Azure region"
  if echo "$VALID_LOCATION_NAMES" | grep -qx "$region" 2>/dev/null; then
    DISPLAY=$(echo "$VALID_LOCATIONS_JSON" | jq -r --arg n "$region" '.[] | select(.name==$n) | .display' 2>/dev/null || echo "")
    pass "Region '$region' is valid" "Display name: $DISPLAY"
    log_done "PASS"
  else
    fail "Region '$region' is invalid" "Run 'az account list-locations -o table' to see valid slugs"
    log_done "FAIL"
  fi
}

validate_region "${AZURE_LOCATION}"             "AZURE_LOCATION"            "true"
validate_region "${AZURE_AI_FOUNDRY_LOCATION}"  "AZURE_AI_FOUNDRY_LOCATION" "false"
validate_region "${AZURE_COSMOS_LOCATION}"      "AZURE_COSMOS_LOCATION"     "false"

# Parse feature flags from parameters.json
DEPLOY_POSTGRES=$(get_param "deployPostgres")
if is_true "$DEPLOY_POSTGRES"; then
  validate_region "${AZURE_PSQL_LOCATION}" "AZURE_PSQL_LOCATION" "false"
fi

# =============================================================================
# SECTION 4 — RESOURCE PROVIDER REGISTRATION
# =============================================================================
section "4 · Resource Provider Registration"

check_provider() {
  local namespace="$1"
  local purpose="$2"

  log_check "Provider $namespace ($purpose)"
  local state
  state=$(az provider show --namespace "$namespace" --query "registrationState" -o tsv 2>/dev/null || echo "NotFound")

  case "$state" in
    Registered)
      pass "Provider $namespace" "State: Registered"
      log_done "PASS"
      ;;
    Registering)
      warn "Provider $namespace" "State: Registering (still in progress — may not be ready)"
      log_done "WARN"
      ;;
    NotRegistered|Unregistered)
      fail "Provider $namespace" "Not registered. Run: az provider register --namespace $namespace"
      log_done "FAIL"
      ;;
    NotFound)
      warn "Provider $namespace" "Could not determine state (check permissions)"
      log_done "WARN"
      ;;
    *)
      warn "Provider $namespace" "Unexpected state: $state"
      log_done "WARN"
      ;;
  esac
}

check_provider "Microsoft.App"                 "Container Apps"
check_provider "Microsoft.CognitiveServices"   "AI Foundry / OpenAI"
check_provider "Microsoft.Search"              "Azure AI Search"
check_provider "Microsoft.ContainerRegistry"   "Azure Container Registry"
check_provider "Microsoft.DocumentDB"          "Cosmos DB"
check_provider "Microsoft.KeyVault"            "Key Vault"
check_provider "Microsoft.Storage"             "Storage Account"
check_provider "Microsoft.Insights"            "Application Insights"
check_provider "Microsoft.OperationalInsights" "Log Analytics"

# =============================================================================
# SECTION 5 — SERVICE REGIONAL AVAILABILITY
# =============================================================================
section "5 · Service Regional Availability"

# Helper: check if a location name (slug) appears in a provider's location list
# Azure lists locations as display names in provider metadata, so we map them
check_service_in_region() {
  local namespace="$1"
  local resource_type="$2"
  local region="$3"
  local service_label="$4"

  [[ -z "$region" ]] && { skip "$service_label in region (region not set)" ""; return; }

  log_check "$service_label availability in '$region'"

  # Provider returns display names; build a reverse map slug→display for the target region
  local display_name
  display_name=$(echo "$VALID_LOCATIONS_JSON" | jq -r --arg n "$region" '.[] | select(.name==$n) | .display' 2>/dev/null || echo "")

  local provider_locations
  provider_locations=$(az provider show --namespace "$namespace" \
    --query "resourceTypes[?resourceType=='${resource_type}'].locations[]" \
    -o tsv 2>/dev/null || true)

  if [[ -z "$provider_locations" ]]; then
    warn "$service_label availability in '$region'" "Could not retrieve location list for $namespace/$resource_type"
    log_done "WARN"
    return
  fi

  # Match by display name (case-insensitive) or region slug
  if echo "$provider_locations" | grep -qi "^${display_name}$" 2>/dev/null || \
     echo "$provider_locations" | grep -qi "^${region}$" 2>/dev/null; then
    pass "$service_label available in '$region'" ""
    log_done "PASS"
  else
    fail "$service_label not available in '$region'" \
      "Choose a different region. Try: eastus, westeurope, southeastasia"
    log_done "FAIL"
  fi
}

DEPLOY_CONTAINER_APPS=$(get_param "deployContainerApps")
DEPLOY_SEARCH=$(get_param "deploySearchService")
DEPLOY_AI_FOUNDRY=$(get_param "deployAiFoundry")
DEPLOY_ACR=$(get_param "deployContainerRegistry")
DEPLOY_COSMOS=$(get_param "deployCosmosDb")

if is_true "$DEPLOY_CONTAINER_APPS"; then
  check_service_in_region "Microsoft.App" "containerApps" \
    "$AZURE_LOCATION" "Container Apps"
else
  skip "Container Apps availability" "deployContainerApps=false"
fi

if is_true "$DEPLOY_SEARCH"; then
  check_service_in_region "Microsoft.Search" "searchServices" \
    "$AZURE_LOCATION" "AI Search"

  # AI Search quota — subscription-level capacity check for the Standard SKU
  # (SKU is hardcoded as 'standard' in infra/main.bicep)
  if [[ -n "$AZURE_LOCATION" && -n "$AZURE_SUBSCRIPTION_ID" ]]; then
    log_check "Fetching AI Search quota in '$AZURE_LOCATION'"
    SEARCH_USAGES_JSON=$(az rest \
      --method GET \
      --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Search/locations/${AZURE_LOCATION}/usages?api-version=2023-11-01" \
      -o json 2>/dev/null || echo '{"value":[]}')

    SEARCH_USAGES_ERR=$(echo "$SEARCH_USAGES_JSON" | jq -r '.error.code // ""' 2>/dev/null || echo "")
    if [[ -n "$SEARCH_USAGES_ERR" ]]; then
      warn "AI Search quota check failed" \
        "Could not query quota (code: $SEARCH_USAGES_ERR). Verify capacity at portal.azure.com"
      log_done "WARN"
    else
      SEARCH_QUOTA_ENTRY=$(echo "$SEARCH_USAGES_JSON" | jq -c \
        '.value[] | select(.name.value == "searchServices.Standard")' 2>/dev/null | head -1 || true)

      if [[ -z "$SEARCH_QUOTA_ENTRY" ]]; then
        warn "AI Search quota data not found for Standard SKU in '$AZURE_LOCATION'" \
          "Usage entry 'searchServices.Standard' missing — verify capacity at portal.azure.com"
        log_done "WARN"
      else
        SQ_CURRENT=$(echo "$SEARCH_QUOTA_ENTRY" | jq -r '.currentValue // 0' 2>/dev/null || echo 0)
        SQ_LIMIT=$(echo   "$SEARCH_QUOTA_ENTRY" | jq -r '.limit // 0'        2>/dev/null || echo 0)
        SQ_AVAILABLE=$(( SQ_LIMIT - SQ_CURRENT ))

        echo -e "  ${DIM}  AI Search quota — Used: $SQ_CURRENT  Limit: $SQ_LIMIT  Available: $SQ_AVAILABLE${NC}"
        log_done "INFO"

        log_check "AI Search Standard quota available in '$AZURE_LOCATION'"
        if [[ "$SQ_LIMIT" -eq 0 ]]; then
          SEARCH_QUOTA_BLOCKED=true
          fail "AI Search quota limit is 0 in '$AZURE_LOCATION'" \
            "No Standard Search quota allocated. Request increase or choose another region."
          log_done "FAIL"
        elif [[ "$SQ_AVAILABLE" -le 0 ]]; then
          SEARCH_QUOTA_BLOCKED=true
          fail "AI Search Standard quota exhausted in '$AZURE_LOCATION'" \
            "Used: $SQ_CURRENT / Limit: $SQ_LIMIT. Request increase or use a different region."
          log_done "FAIL"
        elif [[ "$SQ_AVAILABLE" -eq 1 ]]; then
          warn "AI Search Standard quota nearly exhausted in '$AZURE_LOCATION'" \
            "Only 1 slot left (Used: $SQ_CURRENT / Limit: $SQ_LIMIT). Consider a different region."
          log_done "WARN"
        else
          pass "AI Search Standard quota available in '$AZURE_LOCATION'" \
            "Used: $SQ_CURRENT / Limit: $SQ_LIMIT  (Available: $SQ_AVAILABLE)"
          log_done "PASS"
        fi
      fi
    fi
  fi
else
  skip "AI Search availability" "deploySearchService=false"
fi

if is_true "$DEPLOY_AI_FOUNDRY"; then
  check_service_in_region "Microsoft.CognitiveServices" "accounts" \
    "$AZURE_AI_FOUNDRY_LOCATION" "AI Foundry (CognitiveServices)"
else
  skip "AI Foundry availability" "deployAiFoundry=false"
fi

if is_true "$DEPLOY_ACR"; then
  check_service_in_region "Microsoft.ContainerRegistry" "registries" \
    "$AZURE_LOCATION" "Container Registry"
else
  skip "Container Registry availability" "deployContainerRegistry=false"
fi

if is_true "$DEPLOY_COSMOS"; then
  COSMOS_REGION="${AZURE_COSMOS_LOCATION:-$AZURE_LOCATION}"
  USE_ZONE_REDUNDANCY=$(get_param "useZoneRedundancy")

  check_service_in_region "Microsoft.DocumentDB" "databaseAccounts" \
    "$COSMOS_REGION" "Cosmos DB"

  # Subscription region access check — the EXACT signal that predicts the
  # "high demand for zonal redundant accounts" / ServiceUnavailable failure.
  # API: providers/Microsoft.DocumentDB/locations/{region}
  # Returns isSubscriptionRegionAccessAllowedForRegular (non-AZ accounts)
  #        isSubscriptionRegionAccessAllowedForAz       (zone-redundant accounts)
  if [[ -n "$COSMOS_REGION" && -n "$AZURE_SUBSCRIPTION_ID" ]]; then
    log_check "Cosmos DB subscription region access in '$COSMOS_REGION'"
    COSMOS_LOC_JSON=$(az rest \
      --method GET \
      --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.DocumentDB/locations/${COSMOS_REGION}?api-version=2023-04-15" \
      -o json 2>/dev/null || echo "{}")

    COSMOS_LOC_ERR=$(echo "$COSMOS_LOC_JSON" | jq -r '.error.code // ""' 2>/dev/null || echo "")
    if [[ -n "$COSMOS_LOC_ERR" ]]; then
      warn "Cosmos DB region access check failed" \
        "Could not query location metadata (code: $COSMOS_LOC_ERR). Verify at portal.azure.com"
      log_done "WARN"
    else
      ACCESS_REGULAR=$(echo "$COSMOS_LOC_JSON" | jq -r '.properties.isSubscriptionRegionAccessAllowedForRegular // "unknown"' 2>/dev/null || echo "unknown")
      ACCESS_AZ=$(echo      "$COSMOS_LOC_JSON" | jq -r '.properties.isSubscriptionRegionAccessAllowedForAz      // "unknown"' 2>/dev/null || echo "unknown")
      SUPPORTS_AZ=$(echo    "$COSMOS_LOC_JSON" | jq -r '.properties.supportsAvailabilityZone                   // "unknown"' 2>/dev/null || echo "unknown")

      echo -e "  ${DIM}  Region access — Regular: $ACCESS_REGULAR  |  AZ: $ACCESS_AZ  |  Supports AZ: $SUPPORTS_AZ${NC}"
      log_done "INFO"

      # Check regular (non-AZ) access — always required
      log_check "Cosmos DB regular account access allowed in '$COSMOS_REGION'"
      if [[ "$ACCESS_REGULAR" == "true" ]]; then
        pass "Cosmos DB regular account access allowed in '$COSMOS_REGION'" ""
        log_done "PASS"
      elif [[ "$ACCESS_REGULAR" == "false" ]]; then
        COSMOS_ACCESS_BLOCKED=true
        fail "Cosmos DB regular access BLOCKED in '$COSMOS_REGION'" \
          "Subscription requires region access. See https://aka.ms/cosmosdbquota"
        log_done "FAIL"
      else
        warn "Cosmos DB regular access unknown for '$COSMOS_REGION'" \
          "Could not determine access status. Proceed with caution."
        log_done "WARN"
      fi

      # Check AZ access only when useZoneRedundancy=true
      if is_true "$USE_ZONE_REDUNDANCY"; then
        log_check "Cosmos DB zone-redundant (AZ) access allowed in '$COSMOS_REGION'"
        if [[ "$ACCESS_AZ" == "true" ]]; then
          pass "Cosmos DB AZ account access allowed in '$COSMOS_REGION'" ""
          log_done "PASS"
        elif [[ "$ACCESS_AZ" == "false" ]]; then
          COSMOS_ACCESS_BLOCKED=true
          fail "Cosmos DB AZ access BLOCKED in '$COSMOS_REGION'" \
            "useZoneRedundancy=true but subscription lacks AZ access. See https://aka.ms/cosmosdbquota"
          log_done "FAIL"
        else
          warn "Cosmos DB AZ access unknown for '$COSMOS_REGION'" \
            "useZoneRedundancy=true — verify AZ access in Azure portal before deploying."
          log_done "WARN"
        fi
      fi
    fi
  fi
else
  skip "Cosmos DB availability" "deployCosmosDb=false"
fi

# =============================================================================
# SECTION 6 — VM QUOTA CHECK
# =============================================================================
section "6 · Virtual Machine Quota"

DEPLOY_VM=$(get_param "deployVM")
NETWORK_ISOLATION_RAW=$(get_param "networkIsolation")

# VM is only deployed when both deployVM=true and networkIsolation=true
if is_true "$DEPLOY_VM" && is_true "$NETWORK_ISOLATION_RAW"; then
  VM_SIZE=$(get_param "vmSize")
  VM_SIZE="${VM_SIZE:-Standard_D8s_v5}"
  VM_VCPUS=$(vcpus_from_size "$VM_SIZE")
  VM_FAMILY=$(family_from_size "$VM_SIZE")

  echo -e "  ${DIM}VM size: $VM_SIZE  |  vCPUs needed: ${VM_VCPUS:-unknown}  |  Family: ${VM_FAMILY:-unknown}${NC}"

  if [[ -n "$VM_FAMILY" && -n "$AZURE_LOCATION" ]]; then
    log_check "vCPU quota for $VM_FAMILY in '$AZURE_LOCATION'"
    QUOTA_JSON=$(az vm list-usage --location "$AZURE_LOCATION" \
      --query "[?name.value=='${VM_FAMILY}']" \
      -o json 2>/dev/null || echo "[]")

    CURRENT=$(echo "$QUOTA_JSON" | jq -r '.[0].currentValue // "N/A"' 2>/dev/null || echo "N/A")
    LIMIT=$(echo   "$QUOTA_JSON" | jq -r '.[0].limit // "N/A"'        2>/dev/null || echo "N/A")

    if [[ "$CURRENT" == "N/A" || "$LIMIT" == "N/A" ]]; then
      warn "VM quota for $VM_FAMILY" "Could not retrieve quota (check permissions). Current: $CURRENT / Limit: $LIMIT"
      log_done "WARN"
    else
      AVAILABLE=$(( LIMIT - CURRENT ))
      NEEDED="${VM_VCPUS:-0}"
      info "VM quota details" "Used: $CURRENT  Limit: $LIMIT  Available: $AVAILABLE  Needed: $NEEDED"
      log_done "INFO"
      log_check "Available vCPUs >= needed ($NEEDED) for $VM_SIZE"
      if [[ "$AVAILABLE" -ge "${NEEDED:-0}" ]] 2>/dev/null; then
        pass "Sufficient vCPU quota for $VM_SIZE" "Available: $AVAILABLE  Needed: $NEEDED"
        log_done "PASS"
      else
        fail "Insufficient vCPU quota for $VM_SIZE" \
          "Available: $AVAILABLE  Needed: $NEEDED. Request increase at portal.azure.com"
        log_done "FAIL"
      fi
    fi
  else
    warn "VM quota check skipped" "Could not determine VM family from size '$VM_SIZE' or location is empty"
    log_done "WARN"
  fi
else
  if is_true "$DEPLOY_VM" && ! is_true "$NETWORK_ISOLATION_RAW"; then
    skip "VM quota check" "VM is only deployed when networkIsolation=true"
  else
    skip "VM quota check" "deployVM=false"
  fi
fi

# =============================================================================
# SECTION 7 — OPENAI MODEL AVAILABILITY
# =============================================================================
section "7 · OpenAI Model Availability (AI Foundry)"

if is_true "$DEPLOY_AI_FOUNDRY" && [[ -n "$AZURE_AI_FOUNDRY_LOCATION" ]]; then

  # Parse modelDeploymentList from parameters.json
  MODEL_COUNT=$(jq -r '.parameters.modelDeploymentList.value | length' "$PARAMS_FILE" 2>/dev/null || echo 0)
  echo -e "  ${DIM}Checking $MODEL_COUNT model deployment(s) in region: $AZURE_AI_FOUNDRY_LOCATION${NC}"

  # Fetch available models in the target region via REST
  log_check "Fetching available OpenAI models in '$AZURE_AI_FOUNDRY_LOCATION'"
  MODELS_JSON=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.CognitiveServices/locations/${AZURE_AI_FOUNDRY_LOCATION}/models?api-version=2024-04-01-preview" \
    -o json 2>/dev/null || echo '{"value":[]}')

  MODELS_AVAILABLE_COUNT=$(echo "$MODELS_JSON" | jq '.value | length' 2>/dev/null || echo 0)

  if [[ "$MODELS_AVAILABLE_COUNT" -gt 0 ]]; then
    info "Available models fetched" "$MODELS_AVAILABLE_COUNT model variant(s) found in $AZURE_AI_FOUNDRY_LOCATION"
    log_done "INFO"
  else
    warn "Could not fetch model list" "REST call failed or no models returned. Manual verification needed."
    log_done "WARN"
  fi

  # Fetch current quota usage for OpenAI in this region (subscription-level)
  # API: Microsoft.CognitiveServices/locations/{loc}/usages
  # Returns TPM limits and current usage per model+SKU combination
  log_check "Fetching OpenAI quota usage in '$AZURE_AI_FOUNDRY_LOCATION'"
  QUOTA_USAGE_JSON=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.CognitiveServices/locations/${AZURE_AI_FOUNDRY_LOCATION}/usages?api-version=2024-10-01" \
    -o json 2>/dev/null || echo '{"value":[]}')

  QUOTA_ENTRY_COUNT=$(echo "$QUOTA_USAGE_JSON" | jq '.value | length' 2>/dev/null || echo 0)
  if [[ "$QUOTA_ENTRY_COUNT" -gt 0 ]]; then
    info "OpenAI quota data fetched" "$QUOTA_ENTRY_COUNT quota entries found for region $AZURE_AI_FOUNDRY_LOCATION"
    log_done "INFO"
  else
    warn "Could not fetch OpenAI quota data" "Quota comparison will be skipped. Check permissions (Cognitive Services Contributor or Reader)"
    log_done "WARN"
  fi

  # Check each model in modelDeploymentList
  for (( i=0; i<MODEL_COUNT; i++ )); do
    MODEL_NAME=$(jq -r ".parameters.modelDeploymentList.value[$i].model.name"    "$PARAMS_FILE" 2>/dev/null || echo "unknown")
    MODEL_VER=$(jq  -r ".parameters.modelDeploymentList.value[$i].model.version" "$PARAMS_FILE" 2>/dev/null || echo "")
    SKU_NAME=$(jq   -r ".parameters.modelDeploymentList.value[$i].sku.name"      "$PARAMS_FILE" 2>/dev/null || echo "")
    CAPACITY=$(jq   -r ".parameters.modelDeploymentList.value[$i].sku.capacity"  "$PARAMS_FILE" 2>/dev/null || echo 0)
    DEPLOY_NAME=$(jq -r ".parameters.modelDeploymentList.value[$i].name"         "$PARAMS_FILE" 2>/dev/null || echo "$i")

    # ── 7a · Model regional availability ──────────────────────────────────
    log_check "Model '$MODEL_NAME' v$MODEL_VER ($SKU_NAME) available in region"

    if [[ "$MODELS_AVAILABLE_COUNT" -eq 0 ]]; then
      skip "Model '$MODEL_NAME' availability" "Model list unavailable — skipping"
      log_done "SKIP"
    else
      MATCH=$(echo "$MODELS_JSON" | jq -r \
        --arg name "$MODEL_NAME" \
        '.value[] | select(.model.name == $name) | .model.name' \
        2>/dev/null | head -1 || true)

      if [[ -n "$MATCH" ]]; then
        VER_MATCH=$(echo "$MODELS_JSON" | jq -r \
          --arg name "$MODEL_NAME" --arg ver "$MODEL_VER" \
          '.value[] | select(.model.name == $name and .model.version == $ver) | .model.version' \
          2>/dev/null | head -1 || true)
        if [[ -n "$VER_MATCH" ]]; then
          pass "Model '$MODEL_NAME' v$MODEL_VER available in '$AZURE_AI_FOUNDRY_LOCATION'" "SKU: $SKU_NAME"
          log_done "PASS"
        else
          warn "Model '$MODEL_NAME' v$MODEL_VER not confirmed in '$AZURE_AI_FOUNDRY_LOCATION'" \
            "Model name found but version '$MODEL_VER' not listed — may still deploy"
          log_done "WARN"
        fi
      else
        fail "Model '$MODEL_NAME' not available in '$AZURE_AI_FOUNDRY_LOCATION'" \
          "Change AZURE_AI_FOUNDRY_LOCATION or update the model in main.parameters.json"
        log_done "FAIL"
      fi
    fi

    # ── 7b · Quota availability (available TPM vs requested capacity) ──────
    # Quota name format used by Azure: OpenAI.{SkuName}.{model-name}
    # currentValue = already allocated TPM (in thousands) across all deployments
    # limit        = subscription-level maximum TPM (in thousands)
    # available    = limit - currentValue  →  must be >= CAPACITY requested
    log_check "OpenAI quota for '$MODEL_NAME' ($SKU_NAME): need ${CAPACITY}K TPM"

    if [[ "$QUOTA_ENTRY_COUNT" -eq 0 ]]; then
      skip "Quota check for '$MODEL_NAME' ($SKU_NAME)" "Quota data unavailable"
      log_done "SKIP"
    else
      # Try primary format: OpenAI.{SkuName}.{model-name}
      QUOTA_NAME="OpenAI.${SKU_NAME}.${MODEL_NAME}"
      QUOTA_ENTRY=$(echo "$QUOTA_USAGE_JSON" | jq \
        --arg qn "$QUOTA_NAME" \
        '.value[] | select(.name.value == $qn)' 2>/dev/null || true)

      # Fallback: case-insensitive partial match on model name + SKU name
      if [[ -z "$QUOTA_ENTRY" ]]; then
        _model_lower=$(echo "$MODEL_NAME" | tr '[:upper:]' '[:lower:]')
        _sku_lower=$(echo "$SKU_NAME" | tr '[:upper:]' '[:lower:]')
        QUOTA_ENTRY=$(echo "$QUOTA_USAGE_JSON" | jq -c \
          --arg model "$_model_lower" --arg sku "$_sku_lower" \
          '.value[] | select(
            (.name.value | ascii_downcase | contains($model)) and
            (.name.value | ascii_downcase | contains($sku))
          )' 2>/dev/null | head -1 || true)
      fi

      if [[ -z "$QUOTA_ENTRY" ]]; then
        warn "Quota entry not found for '$MODEL_NAME' ($SKU_NAME)" \
          "Key 'OpenAI.${SKU_NAME}.${MODEL_NAME}' not in usages response — model may be new or quota not yet allocated"
        log_done "WARN"
      else
        Q_CURRENT=$(echo "$QUOTA_ENTRY" | jq -r '.currentValue // 0' 2>/dev/null || echo 0)
        Q_LIMIT=$(echo   "$QUOTA_ENTRY" | jq -r '.limit       // 0' 2>/dev/null || echo 0)
        Q_UNIT=$(echo    "$QUOTA_ENTRY" | jq -r '.unit        // ""' 2>/dev/null || true)
        Q_AVAILABLE=$(( Q_LIMIT - Q_CURRENT ))

        # Capacity in parameters is in thousands of tokens; limit/currentValue are also in K TPM
        if [[ "$Q_LIMIT" -eq 0 ]]; then
          warn "Quota limit is 0 for '$MODEL_NAME' ($SKU_NAME)" \
            "Subscription has no quota allocated for this model. Request at https://aka.ms/oai/quotaincrease"
          log_done "WARN"
        elif [[ "$Q_AVAILABLE" -ge "$CAPACITY" ]]; then
          pass "Sufficient quota for '$MODEL_NAME' ($SKU_NAME)" \
            "Available: ${Q_AVAILABLE}K TPM  Requested: ${CAPACITY}K TPM  (Used: ${Q_CURRENT}K / Limit: ${Q_LIMIT}K  Unit: $Q_UNIT)"
          log_done "PASS"
        else
          fail "Insufficient quota for '$MODEL_NAME' ($SKU_NAME)" \
            "Available: ${Q_AVAILABLE}K TPM  Requested: ${CAPACITY}K TPM  (Used: ${Q_CURRENT}K / Limit: ${Q_LIMIT}K). Request increase: https://aka.ms/oai/quotaincrease"
          log_done "FAIL"
        fi
      fi
    fi
  done

elif is_true "$DEPLOY_AI_FOUNDRY" && [[ -z "$AZURE_AI_FOUNDRY_LOCATION" ]]; then
  warn "OpenAI model check skipped" "AZURE_AI_FOUNDRY_LOCATION is not set"
else
  skip "OpenAI model availability" "deployAiFoundry=false"
fi

# =============================================================================
# SECTION 8 — POSTGRESQL FLEXIBLE SERVER
# =============================================================================
section "8 · PostgreSQL Flexible Server"

if is_true "$DEPLOY_POSTGRES"; then
  PSQL_REGION="${AZURE_PSQL_LOCATION:-$AZURE_LOCATION}"

  log_check "PostgreSQL Flexible Server available in '$PSQL_REGION'"
  PSQL_SKUS=$(az postgres flexible-server list-skus --location "$PSQL_REGION" -o json 2>/dev/null || echo "[]")
  PSQL_SKU_COUNT=$(echo "$PSQL_SKUS" | jq 'length' 2>/dev/null || echo 0)

  if [[ "$PSQL_SKU_COUNT" -gt 0 ]]; then
    pass "PostgreSQL Flexible Server available in '$PSQL_REGION'" "$PSQL_SKU_COUNT SKU(s) found"
    log_done "PASS"

    # Check vCore quota
    log_check "PostgreSQL vCore quota in '$PSQL_REGION'"
    PSQL_QUOTA=$(az postgres flexible-server list-skus --location "$PSQL_REGION" \
      --query "[0].supportedFlexibleServerEditions[0].supportedServerVersions[0].supportedVcores" \
      -o json 2>/dev/null || echo "[]")

    if [[ -n "$PSQL_QUOTA" && "$PSQL_QUOTA" != "[]" ]]; then
      info "PostgreSQL SKUs available" "vCore options found in $PSQL_REGION"
      log_done "INFO"
    else
      warn "PostgreSQL vCore details unavailable" "Verify quota manually in the Azure portal"
      log_done "WARN"
    fi
  else
    fail "PostgreSQL Flexible Server not available in '$PSQL_REGION'" \
      "Choose a region where PostgreSQL Flexible Server is supported"
    log_done "FAIL"
  fi
else
  skip "PostgreSQL availability" "deployPostgres=false in main.parameters.json"
fi

# =============================================================================
# SUMMARY
# =============================================================================
print_summary

# ---------------------------------------------------------------------------
# Exit code: 0 = success/warnings only, 1 = failures exist
# ---------------------------------------------------------------------------
if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
else
  exit 0
fi
