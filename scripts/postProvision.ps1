# postProvision.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[INFO] Running post-provision steps..."
Write-Host ""

#-------------------------------------------------------------------------------
# Mirror azd environment variables into process environment
# This avoids persisting secrets in the User environment (registry)
#-------------------------------------------------------------------------------
& azd env get-values | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') {
    $k = $matches[1]
    $v = $matches[2] -replace '^"|"$', ''
    Set-Item -Path Env:$k -Value $v
  }
}

#-------------------------------------------------------------------------------
# Zero Trust Information
#-------------------------------------------------------------------------------
Write-Host ""
if ($env:NETWORK_ISOLATION -and $env:NETWORK_ISOLATION.ToLower() -eq 'true') {
    Write-Host "[INFO] Zero Trust enabled."
    Write-Host "[NOTE] If app config failed, run azd provision again due to token timeout restrictions."
    Write-Host "Access to Azure resources is restricted to the VNet."
    Write-Host "Ensure you run scripts/postProvision.ps1 from within the VNet."
    Write-Host "If you are using a local machine, make sure you have a VPN connection to the VNet."
    Write-Host "You can also use the Test VM to access the environment and complete the setup."
    $answer = Read-Host "Are you running this script from inside the VNet or via VPN? [Y/n]"
    if ($answer.ToLower() -notmatch '^(y|yes)$') {
        Write-Host "[ERROR] Please run this script from inside the VNet or with VPN access. Exiting."
        exit 0
    }
} else {
    Write-Host "[INFO] Provisioning basic architecture."
}

#-------------------------------------------------------------------------------
# Container APP API Keys Warning
#-------------------------------------------------------------------------------
Write-Host ""
if ($env:USE_CAPP_API_KEY -and $env:USE_CAPP_API_KEY.ToLower() -eq 'true') {
    Write-Host "[INFO] Using API Key for Container Apps access."
    Write-Host "[WARN] IMPORTANT: Each App API Key was initialized with resourceToken."
    Write-Host "    Please update to a custom API key ASAP."
}

#-------------------------------------------------------------------------------
# Check required environment variable
#-------------------------------------------------------------------------------
Write-Host "[INFO] Checking required environment variables..."
$requiredVars = @('APP_CONFIG_ENDPOINT')
$missing = @()
foreach ($v in $requiredVars) {
    $val = [Environment]::GetEnvironmentVariable($v)
    if (-not $val) { $missing += $v; Write-Host "  $v=<missing>" -ForegroundColor Yellow } else { Write-Host "  $v=$val" }
}
if ($missing.Count -gt 0) {
    Write-Host "[WARN] Missing required variables: $($missing -join ', '). Skipping configuration steps that depend on them." -ForegroundColor Yellow
}

#-------------------------------------------------------------------------------
# Setup Python environment
#-------------------------------------------------------------------------------
Write-Host "[INFO] Creating temporary venv..."

$pythonExe = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    # Resolve the actual Python 3 interpreter path via the py launcher
    $pythonExe = & py -3 -c "import sys; print(sys.executable)"
    $pythonExe = $pythonExe.Trim()
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonExe = (Get-Command python).Source
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $pythonExe = (Get-Command python3).Source
} else {
    Write-Host "[ERROR] Python was not found in PATH." -ForegroundColor Red
    Write-Host "Install Python 3.10+ and ensure it is available as 'py' or 'python'."
    Write-Host "Windows: https://www.python.org/downloads/windows/"
    exit 1
}

Write-Host "Using Python: $pythonExe"
& $pythonExe -m venv --without-pip config/.venv_temp

if (-not (Test-Path "config/.venv_temp/Scripts/Activate.ps1")) {
    Write-Host "[ERROR] Failed to create virtual environment at config/.venv_temp." -ForegroundColor Red
    exit 1
}

# Activate the venv
& config/.venv_temp/Scripts/Activate.ps1

Write-Host "[INFO] Bootstrapping pip..."
try {
    & $pythonExe -m ensurepip --upgrade
} catch {
    Write-Host "[WARN] ensurepip failed; falling back to get-pip.py download."
    $getPipPath = Join-Path $env:TEMP "get-pip.py"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPipPath -UseBasicParsing
    & $pythonExe $getPipPath
    if (Test-Path $getPipPath) {
        Remove-Item $getPipPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[INFO] Installing requirements..."
& $pythonExe -m pip install --upgrade pip
& $pythonExe -m pip install -r config/requirements.txt

#-------------------------------------------------------------------------------
# 1) AI Foundry Setup
#-------------------------------------------------------------------------------
if (-not $missing.Contains('APP_CONFIG_ENDPOINT')) {
    Write-Host "`n[INFO] AI Foundry Setup..."
    try {
        Write-Host "[INFO] Running config.aifoundry.setup..."
        & $pythonExe -m config.aifoundry.setup
        Write-Host "[OK] AI Foundry setup script finished."
    } catch {
        Write-Host "[WARN] Error during AI Foundry setup. Skipping it."
    }
} else {
    Write-Host "[SKIP] Skipping AI Foundry setup (missing APP_CONFIG_ENDPOINT)."
}

#-------------------------------------------------------------------------------
# 2) Container Apps Setup
#-------------------------------------------------------------------------------
if (-not $missing.Contains('APP_CONFIG_ENDPOINT')) {
    Write-Host "`n[INFO] ContainerApp setup..."
    try {
        Write-Host "[INFO] Running config.containerapps.setup..."
        & $pythonExe -m config.containerapps.setup
        Write-Host "[OK] Container Apps setup script finished."
    } catch {
        Write-Host "[WARN] Error during Container Apps setup. Skipping it."
    }
} else {
    Write-Host "[SKIP] Skipping Container Apps setup (missing APP_CONFIG_ENDPOINT)."
}

#-------------------------------------------------------------------------------
# 3) AI Search Setup
#-------------------------------------------------------------------------------
if (-not $missing.Contains('APP_CONFIG_ENDPOINT')) {
    Write-Host "[INFO] AI Search setup..."
    try {
        Write-Host "[INFO] Running config.search.setup..."
        & $pythonExe -m config.search.setup
        Write-Host "[OK] Search setup script finished."
    } catch {
        Write-Host "[WARN] Error during Search setup. Skipping it."
    }
} else {
    Write-Host "[SKIP] Skipping Search setup (missing APP_CONFIG_ENDPOINT)."
}

#-------------------------------------------------------------------------------
# Cleaning up
#-------------------------------------------------------------------------------
# Write-Host "`n[INFO] Cleaning Python environment up..."
# if (Get-Command deactivate -ErrorAction SilentlyContinue) { deactivate }
# # Try to stop any python processes that reference the temporary venv to avoid file locks
# $venvPattern = "config\\.venv_temp"
# try {
#     $procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and ($_.CommandLine -match $venvPattern) }
# } catch {
#     # Fallback if Get-CimInstance isn't available for some reason
#     $procs = @()
# }

# if ($procs -and $procs.Count -gt 0) {
#     Write-Host "Stopping processes referencing venv:"
#     foreach ($p in $procs) {
#         Write-Host "  Stopping pid $($p.ProcessId) - $($p.Name)"
#         try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
#     }
#     Start-Sleep -Seconds 1
# }

# # Retry removal with exponential backoff to handle transient locks
# $maxRetries = 5
# for ($i = 1; $i -le $maxRetries; $i++) {
#     try {
#         Remove-Item -Recurse -Force config/.venv_temp -ErrorAction Stop
#         Write-Host "Removed venv directory."
#         break
#     } catch {
#         if ($i -eq $maxRetries) {
#             Write-Host "[WARN] Failed to remove venv after $maxRetries attempts: $($_.Exception.Message)"
#         } else {
#             Write-Host ("Retry {0}/{1}: waiting and retrying..." -f $i, $maxRetries)
#             Start-Sleep -Seconds (2 * $i)
#         }
#     }
# }

Write-Host "`n[OK] postProvisioning completed."
