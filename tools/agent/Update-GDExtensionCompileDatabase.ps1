param(
    [string] $Scons = "",
    [string] $Platform = "",
    [string] $Target = "template_debug",
    [switch] $Build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")).Path
$gdextensionRoot = Join-Path $repoRoot "gdextension"

if (-not (Test-Path -LiteralPath (Join-Path $gdextensionRoot "SConstruct"))) {
    throw "GDExtension SConstruct was not found at $gdextensionRoot."
}

function Resolve-SConsInvocation {
    param([string] $Requested)

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $requestedCommand = Get-Command $Requested -ErrorAction SilentlyContinue
        if ($null -eq $requestedCommand) {
            throw "Requested SCons command was not found: $Requested"
        }
        return @{
            Command = $requestedCommand.Source
            Prefix = @()
        }
    }

    foreach ($pythonCommandName in @("python", "py")) {
        $pythonCommand = Get-Command $pythonCommandName -ErrorAction SilentlyContinue
        if ($null -eq $pythonCommand) {
            continue
        }

        & $pythonCommand.Source "-m" "SCons" "--version" | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return @{
                Command = $pythonCommand.Source
                Prefix = @("-m", "SCons")
            }
        }
    }

    $pathSCons = Get-Command "scons" -ErrorAction SilentlyContinue
    if ($null -ne $pathSCons) {
        return @{
            Command = $pathSCons.Source
            Prefix = @()
        }
    }

    throw "SCons was not found. Install scons or pass -Scons with the executable path."
}

$sconsArgs = @(
    "target=$Target",
    "compiledb=yes",
    "compiledb_file=compile_commands.json"
)

if (-not [string]::IsNullOrWhiteSpace($Platform)) {
    $sconsArgs += "platform=$Platform"
}

if (-not $Build) {
    $sconsArgs += "compiledb"
}

Set-Location $gdextensionRoot
Write-Host "Updating GDExtension compile database."
$sconsInvocation = Resolve-SConsInvocation -Requested $Scons
$fullSconsArgs = @($sconsInvocation.Prefix) + $sconsArgs
& $sconsInvocation.Command @fullSconsArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$compileDbPath = Join-Path $gdextensionRoot "compile_commands.json"
if (-not (Test-Path -LiteralPath $compileDbPath)) {
    throw "SCons completed but compile_commands.json was not created."
}

Write-Host "Updated $compileDbPath"
exit 0
