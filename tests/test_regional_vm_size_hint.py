"""An unusable VM_SIZE fails with actionable alternatives, without Azure access."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")
DRIVER = r"""
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SubscriptionId = 'workload-sub'
$SkipAzureCliChecks = $false
$script:FailureCount = 0
$script:WarningCount = 0
$script:Calls = @()
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:VM_SOURCE, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Regional preflight did not parse.' }
$names = @('Write-PreflightCheck', 'Get-VmSizeAlternatives', 'Get-VmSizeHint', 'Test-ComputeQuota')
foreach ($node in $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names
}, $false)) { Invoke-Expression $node.Extent.Text }
$catalog = Get-Content $env:VM_CATALOG -Raw | ConvertFrom-Json
function Get-QuotaData { return $null }
function Test-QuotaRemaining { }
function Invoke-AzJson {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $script:Calls += ($Arguments -join ' ')
    if (($Arguments[0..1] -join ' ') -ne 'vm list-skus') { throw 'Unexpected Azure operation.' }
    if ($env:VM_LIST_FAILS -eq 'true' -and $Arguments -notcontains '--size') { return @{ failed = $true; error = 'denied' } }
    $size = if ($Arguments -contains '--size') { $Arguments[[array]::IndexOf($Arguments, '--size') + 1] } else { $null }
    return @($catalog | Where-Object { -not $size -or $_.name -eq $size })
}
$output = Test-ComputeQuota -Location 'swedencentral' -VmSize $env:VM_SIZE 6>&1 | Out-String
Write-Output ('RESULT:' + (@{ failures = $script:FailureCount; output = $output.Trim(); calls = @($script:Calls) } | ConvertTo-Json -Compress))
"""


def sku(name, vcpus="2", memory="8", arch="x64", controllers="SCSI", premium="True", restricted=False):
    return {
        "name": name,
        "family": "testFamily",
        "restrictions": [{"reasonCode": "NotAvailableForSubscription", "type": "Location"}] if restricted else [],
        "capabilities": [
            {"name": "vCPUs", "value": vcpus}, {"name": "MemoryGB", "value": memory},
            {"name": "CpuArchitectureType", "value": arch}, {"name": "DiskControllerTypes", "value": controllers},
            {"name": "PremiumIO", "value": premium},
        ],
    }


CATALOG = [
    sku("Standard_D2s_v3", restricted=True),
    sku("Standard_D2s_v5"),
    sku("Standard_D2as_v5"),
    sku("Standard_B2s_v2"),
    sku("Standard_B2ats_v2", memory="1"),          # too little memory for the jumpbox
    sku("Standard_D2lds_v5", memory="4"),          # too little memory
    sku("Standard_D2ps_v5", arch="Arm64"),         # image is x64
    sku("Standard_D2s_v6", controllers="NVMe"),    # Bicep does not configure NVMe
    sku("Standard_D2_v5", premium="False"),        # Premium SSD required
    sku("Standard_D4s_v5", vcpus="4", memory="16"),  # different vCPU count
    sku("Standard_D2ds_v5", restricted=True),      # restricted
]


@unittest.skipUnless(PWSH, "PowerShell is required for regional preflight checks")
class RegionalVmSizeHintTests(unittest.TestCase):
    def run_check(self, vm_size: str, *, list_fails: bool = False) -> dict:
        with tempfile.TemporaryDirectory(prefix="vm size hint ") as directory:
            folder = Path(directory)
            (folder / "catalog.json").write_text(json.dumps(CATALOG), encoding="utf-8")
            (folder / "run.ps1").write_text(DRIVER, encoding="utf-8")
            environment = dict(
                os.environ,
                VM_SOURCE=str(ROOT / "scripts" / "Invoke-RegionalPreflight.ps1"),
                VM_CATALOG=str(folder / "catalog.json"),
                VM_SIZE=vm_size,
                VM_LIST_FAILS=str(list_fails).lower(),
            )
            result = subprocess.run(
                [PWSH, "-NoProfile", "-NonInteractive", "-File", str(folder / "run.ps1")],
                env=environment, capture_output=True, text=True, timeout=60,
            )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        row = next(line for line in result.stdout.splitlines() if line.startswith("RESULT:"))
        return json.loads(row.removeprefix("RESULT:"))

    def test_restricted_size_fails_with_compatible_alternatives(self) -> None:
        result = self.run_check("Standard_D2s_v3")
        self.assertEqual(1, result["failures"])
        self.assertIn("Standard_D2s_v3 has restrictions in swedencentral.", result["output"])
        self.assertIn(
            "Available 2-vCPU alternatives: Standard_D2as_v5, Standard_D2s_v5, Standard_B2s_v2.",
            result["output"],
        )
        self.assertIn("Run: azd env set VM_SIZE Standard_D2as_v5", result["output"])
        for excluded in ("B2ats_v2", "D2lds_v5", "D2ps_v5", "D2s_v6", "D2_v5", "D4s_v5", "D2ds_v5"):
            self.assertNotIn(excluded, result["output"])

    def test_unknown_size_fails_with_default_two_vcpu_alternatives(self) -> None:
        result = self.run_check("Standard_Unknown_v9")
        self.assertEqual(1, result["failures"])
        self.assertIn("Standard_Unknown_v9 is not available in swedencentral.", result["output"])
        self.assertIn("Standard_D2as_v5", result["output"])

    def test_available_size_passes_without_listing_the_catalog(self) -> None:
        result = self.run_check("Standard_D2s_v5")
        self.assertEqual(0, result["failures"])
        self.assertIn("Standard_D2s_v5 is available in swedencentral.", result["output"])
        self.assertEqual(1, len(result["calls"]))
        self.assertIn("--size Standard_D2s_v5", result["calls"][0])

    def test_catalog_failure_still_fails_closed_with_generic_hint(self) -> None:
        result = self.run_check("Standard_D2s_v3", list_fails=True)
        self.assertEqual(1, result["failures"])
        self.assertIn("Choose another size with 'azd env set VM_SIZE <size>'.", result["output"])

    def test_hint_queries_are_read_only(self) -> None:
        result = self.run_check("Standard_D2s_v3")
        self.assertTrue(all(call.startswith("vm list-skus") for call in result["calls"]))
        self.assertTrue(all("--subscription workload-sub" in call for call in result["calls"]))


if __name__ == "__main__":
    unittest.main()
