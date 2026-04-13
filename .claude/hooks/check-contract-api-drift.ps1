param(
    [string]$BaseRef = "main"
)

$ErrorActionPreference = "Stop"

function Write-Report {
    param([string]$Text)

    Write-Host $Text
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $Text
    }
}

$baseCandidates = @(
    "origin/$BaseRef",
    $BaseRef,
    "HEAD~1"
)

$base = $null
foreach ($candidate in $baseCandidates) {
    git rev-parse --verify $candidate *> $null
    if ($LASTEXITCODE -eq 0) {
        $base = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($base)) {
    Write-Report "## Station Mirny Contract/API Drift Precheck`nCould not resolve a base ref. Skipping advisory precheck."
    exit 0
}

$changedFiles = @(git diff --name-only "$base...HEAD")
if ($LASTEXITCODE -ne 0 -or $changedFiles.Count -eq 0) {
    $changedFiles = @(git diff --name-only "$base")
}

$sourcePattern = '^(core|scenes|data|gdextension)/.*\.(gd|tscn|tres|res|cpp|hpp|h|c)$'
$sourceChanges = @($changedFiles | Where-Object { ($_ -replace '\\','/') -match $sourcePattern })
$dataContractsChanged = @($changedFiles | Where-Object { ($_ -replace '\\','/') -eq 'docs/02_system_specs/world/DATA_CONTRACTS.md' })
$publicApiChanged = @($changedFiles | Where-Object { ($_ -replace '\\','/') -eq 'docs/00_governance/PUBLIC_API.md' })

$report = @()
$report += "## Station Mirny Contract/API Drift Precheck"
$report += ""
$report += "- Base ref: $base"
$report += "- Source/runtime/data files changed: $($sourceChanges.Count)"
$report += "- DATA_CONTRACTS.md changed: $([bool]$dataContractsChanged.Count)"
$report += "- PUBLIC_API.md changed: $([bool]$publicApiChanged.Count)"

if ($sourceChanges.Count -gt 0 -and $dataContractsChanged.Count -eq 0 -and $publicApiChanged.Count -eq 0) {
    $report += ""
    $report += "WARNING: Source/data files changed, but neither canonical contract doc changed in this diff."
    $report += "This is advisory by default. Set STRICT_CONTRACT_CHECK=1 to make this a blocking CI check."
    $report += ""
    $report += "Changed source/data files:"
    foreach ($file in $sourceChanges | Select-Object -First 25) {
        $report += "- $file"
    }
    if ($sourceChanges.Count -gt 25) {
        $report += "- ... and $($sourceChanges.Count - 25) more"
    }

    Write-Report ($report -join "`n")
    if ($env:STRICT_CONTRACT_CHECK -eq "1") {
        exit 1
    }
    exit 0
}

$report += ""
$report += "OK: no immediate contract/API drift warning from static precheck."
Write-Report ($report -join "`n")
exit 0
