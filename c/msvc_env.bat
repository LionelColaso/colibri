@echo off
rem ---------------------------------------------------------------------------
rem msvc_env.bat - puts cl.exe (MSVC) on the PATH for the caller.
rem
rem nvcc needs cl.exe as its host compiler, and the Makefile's Windows recipes
rem need it on the PATH. This finds a Visual Studio with vswhere and calls its
rem vcvars64.bat; the environment stays for the caller (a 'call', in the same
rem process), so the caller can build right after.
rem
rem Use:
rem     call "%~dp0msvc_env.bat" || goto no_msvc
rem
rem Returns 0 when cl.exe is on the PATH afterwards, 1 when no MSVC was found
rem (the caller says so and stops).
rem
rem Overrides (set before calling):
rem   VSWHERE  the vswhere.exe to use (default: the Visual Studio Installer's).
rem ---------------------------------------------------------------------------

rem cl.exe already on the PATH (a Native Tools prompt): nothing to do.
where cl.exe >nul 2>&1
if %ERRORLEVEL%==0 exit /b 0

set "VSINSTALLER=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"
if not defined VSWHERE set "VSWHERE=%VSINSTALLER%\vswhere.exe"
if not exist "%VSWHERE%" exit /b 1

rem Invoke vswhere by bare name from its own directory: a quoted path in a
rem for /f body loses its quotes to cmd /c ("C:\Program" is not recognized).
rem The version range: VS 2017 (15.x) through VS 18, the versions nvcc's host
rem compiler works with; -latest picks the newest of them. A Visual Studio
rem newer than that is still found by the fallback below.
set "VSDIR="
pushd "%VSINSTALLER%"
for /f "usebackq delims=" %%i in (`vswhere.exe -latest -products * -version "[15.0,19.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not "%VSDIR%"=="" goto found_vs
echo WARNING: no Visual Studio 15.x-18.x found; falling back to the newest install.>&2
for /f "usebackq delims=" %%i in (`vswhere.exe -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
:found_vs
popd
if "%VSDIR%"=="" exit /b 1
if not exist "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" exit /b 1

call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
where cl.exe >nul 2>&1
if %ERRORLEVEL%==0 exit /b 0
exit /b 1
