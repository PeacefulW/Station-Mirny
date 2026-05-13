param(
    [switch] $SkipGdUnit,
    [switch] $SkipFormat,
    [switch] $UpdateCompileDatabase,
    [string] $GodotBin = "",
    [string[]] $FormatPaths = @(),
    [string] $TestPath = "res://tests/unit"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")).Path
Set-Location $repoRoot

if (-not $SkipFormat) {
    $formatScript = Join-Path $scriptDir "Invoke-GDScriptFormatCheck.ps1"
    & $formatScript -Paths $FormatPaths
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not $SkipGdUnit) {
    $gdUnitScript = Join-Path $scriptDir "Invoke-GdUnit4.ps1"
    & $gdUnitScript -GodotBin $GodotBin -TestPath $TestPath
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if ($UpdateCompileDatabase) {
    $compileDbScript = Join-Path $scriptDir "Update-GDExtensionCompileDatabase.ps1"
    & $compileDbScript
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Host "Agent validation completed."
exit 0
