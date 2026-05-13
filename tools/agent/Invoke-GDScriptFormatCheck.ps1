param(
    [string] $FormatterBin = "",
    [string[]] $Paths = @(),
    [switch] $NoLint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")).Path

function Resolve-FormatterBinary {
    param([string] $Requested)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $candidates += $Requested
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GDSCRIPT_FORMATTER_BIN)) {
        $candidates += $env:GDSCRIPT_FORMATTER_BIN
    }

    $candidates += (Join-Path $repoRoot ".tools\agent\gdscript-formatter\gdscript-formatter.exe")
    $candidates += "gdscript-formatter"

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

    throw "gdscript-formatter was not found. Pass -FormatterBin or set GDSCRIPT_FORMATTER_BIN."
}

function Get-ChangedGDScriptPaths {
    $diff = & git -C $repoRoot diff --name-only -- "*.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "git diff failed while discovering changed GDScript files."
    }

    $cached = & git -C $repoRoot diff --cached --name-only -- "*.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached failed while discovering changed GDScript files."
    }

    $untracked = & git -C $repoRoot ls-files --others --exclude-standard -- "*.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while discovering untracked GDScript files."
    }

    return @($diff) + @($cached) + @($untracked)
}

function Resolve-ExistingPaths {
    param([string[]] $InputPaths)

    $resolved = @()
    foreach ($item in $InputPaths) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        $path = $item
        if (-not [System.IO.Path]::IsPathRooted($path)) {
            $path = Join-Path $repoRoot $path
        }

        if (Test-Path -LiteralPath $path) {
            $resolved += (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $resolved | Sort-Object -Unique
}

$formatter = Resolve-FormatterBinary -Requested $FormatterBin
$candidatePaths = $Paths
if ($candidatePaths.Count -eq 0) {
    $candidatePaths = Get-ChangedGDScriptPaths
}

$gdscriptPaths = @(Resolve-ExistingPaths -InputPaths $candidatePaths)
if ($gdscriptPaths.Count -eq 0) {
    Write-Host "No GDScript files to check."
    exit 0
}

Write-Host "Checking GDScript formatting on $($gdscriptPaths.Count) path(s)."
& $formatter "--check" "--safe" @gdscriptPaths
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not $NoLint) {
    Write-Host "Linting GDScript on $($gdscriptPaths.Count) path(s)."
    & $formatter "lint" @gdscriptPaths
    exit $LASTEXITCODE
}

exit 0
