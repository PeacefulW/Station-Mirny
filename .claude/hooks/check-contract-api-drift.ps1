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
    Write-Report "## Station Mirny Canonical Doc Drift Precheck`nCould not resolve a base ref. Skipping advisory precheck."
    exit 0
}

$changedFiles = @(git diff --name-only "$base...HEAD")
if ($LASTEXITCODE -ne 0 -or $changedFiles.Count -eq 0) {
    $changedFiles = @(git diff --name-only "$base")
}

$sourcePattern = '^(core|scenes|data|gdextension)/.*\.(gd|tscn|tres|res|cpp|hpp|h|c)$'
$sourceChanges = @($changedFiles | Where-Object { ($_ -replace '\\','/') -match $sourcePattern })
$canonicalDocsChanged = @($changedFiles | Where-Object {
    $normalized = ($_ -replace '\\','/')
    $normalized -eq 'AGENTS.md' -or $normalized -match '^docs/.+\.md$'
})

$report = @()
$report += "## Station Mirny Canonical Doc Drift Precheck"
$report += ""
$report += "- Base ref: $base"
$report += "- Source/runtime/data files changed: $($sourceChanges.Count)"
$report += "- Canonical docs changed: $([bool]$canonicalDocsChanged.Count)"

if ($sourceChanges.Count -gt 0 -and $canonicalDocsChanged.Count -eq 0) {
    $report += ""
    $report += "WARNING: Source/data files changed, but no living canonical docs changed in this diff."
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
$report += "OK: no immediate canonical-doc drift warning from static precheck."
Write-Report ($report -join "`n")
exit 0
