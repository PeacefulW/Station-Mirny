param(
    [string] $GodotBin = "",
    [string] $TestPath = "res://tests/unit",
    [string] $ReportDirectory = "res://test-results/gdunit4",
    [int] $ReportCount = 3,
    [switch] $ContinueOnFailure,
    [switch] $NoHeadless
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")).Path

function Resolve-GodotBinary {
    param([string] $Requested)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $candidates += $Requested
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        $candidates += $env:GODOT_BIN
    }

    $candidates += (Join-Path $repoRoot "Godot_v4.6.2-stable_win64_console.exe")
    $candidates += (Join-Path $repoRoot "Godot_v4.6.2-stable_win64.exe")
    $candidates += "godot"
    $candidates += "godot4"

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "Godot binary was not found. Pass -GodotBin or set GODOT_BIN."
}

$godot = Resolve-GodotBinary -Requested $GodotBin
Set-Location $repoRoot

$gdUnitArgs = @(
    "-a", $TestPath,
    "-rd", $ReportDirectory,
    "-rc", [string] $ReportCount
)

if ($ContinueOnFailure) {
    $gdUnitArgs += "-c"
}
if (-not $NoHeadless) {
    $gdUnitArgs += "--ignoreHeadlessMode"
}

$godotArgs = @("--path", ".", "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd") + $gdUnitArgs
if (-not $NoHeadless) {
    $godotArgs = @("--headless") + $godotArgs
}

Write-Host "Running GdUnit4: $TestPath"
& $godot @godotArgs
$testExitCode = $LASTEXITCODE

$copyLogArgs = @("--path", ".", "--quiet", "-s", "res://addons/gdUnit4/bin/GdUnitCopyLog.gd", "-rd", $ReportDirectory)
if (-not $NoHeadless) {
    $copyLogArgs = @("--headless") + $copyLogArgs
}

& $godot @copyLogArgs | Out-Null

exit $testExitCode
