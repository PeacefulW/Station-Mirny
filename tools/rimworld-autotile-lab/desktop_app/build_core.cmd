@echo off
setlocal

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo vswhere.exe not found
  exit /b 1
)

for /f "usebackq delims=" %%I in (`"%VSWHERE%" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
  set "VSINSTALL=%%I"
)

if not defined VSINSTALL (
  echo Visual Studio C++ toolchain not found
  exit /b 1
)

call "%VSINSTALL%\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 1

set "CARGO=%USERPROFILE%\.cargo\bin\cargo.exe"
if not exist "%CARGO%" (
  echo cargo.exe not found at "%CARGO%"
  exit /b 1
)

pushd "%~dp0core"
"%CARGO%" build --release
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
