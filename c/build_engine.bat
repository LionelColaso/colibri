@echo off
rem ---------------------------------------------------------------------------
rem build_engine.bat - one-shot build of the colibri engine (Windows).
rem
rem Mirrors the Makefile's engine build recipes so it can be double-clicked or
rem run from a plain shell: for CUDA it locates vcvars64.bat (nvcc needs
rem cl.exe as its host compiler) and runs make.
rem
rem Usage:
rem   build_engine.bat [backend] [target]
rem     backend: cuda (default), vulkan, cpu
rem     target:  the engine to build (default: colibri)
rem
rem The CUDA build is TWO make targets, not one: the host engine, which links
rem the runtime loader (make <target> CUDA_DLL=1), and coli_cuda.dll, which
rem carries the backend (make CUDA_DLL=1 cuda-dll). The engine alone carries
rem no backend: built without the loader it stays a CPU-only binary that cannot
rem use the card, however complete the DLL beside it is. Both need CUDA_DLL=1,
rem or make rebuilds a CPU-only host over the CUDA one (see .build-config).
rem
rem The DLL is built for this machine's card (CUDA_ARCH=sm_XX, detected here),
rem the way a Linux build is: the setup reads it as this machine's own backend,
rem where the release's portable one (compute 8.0 and newer) cannot run. The
rem marker beside it names the arch it was built for.
rem
rem Overrides (set before calling):
rem   ARCH        CPU architecture (default: native)
rem   CUDA_ARCH   GPU compute capability (default: native)
rem   COLI_MAKE   the make executable (default: MSYS2's, else make on PATH)
rem   COLI_MSYS2  the MSYS2 root, for make and sh (default: on PATH)
rem ---------------------------------------------------------------------------
setlocal

rem --- Build here: the script's own directory, so the Makefile and its sources
rem --- are found and the engine and the DLL land next to each other. This is
rem --- the FIRST pushd: a pushd/popd pair over a drive change (the Visual
rem --- Studio installer is on C:) leaves the directory stack unable to take the
rem --- next pushd, and the build would run in the wrong directory.
pushd "%~dp0"

rem --- Backend ---
if "%~1"=="" goto default_backend
set "BACKEND=%~1"
shift
goto backend_done
:default_backend
set "BACKEND=cuda"
:backend_done

rem --- Target ---
if "%~1"=="" goto default_target
set "TARGET=%~1"
goto target_done
:default_target
set "TARGET=colibri"
:target_done

rem --- MSVC: only the CUDA build needs it (nvcc's host compiler) ---------
rem msvc_env.bat finds a Visual Studio and calls its vcvars64.bat; the
rem environment it sets up stays for this script (same process).
if "%BACKEND%"=="cuda" goto find_msvc
goto have_msvc
:find_msvc
call "%~dp0msvc_env.bat"
if %ERRORLEVEL%==0 goto have_msvc
:no_msvc
echo ERROR: cl.exe (MSVC) not found.>&2
echo Install "Desktop development with C++":>&2
echo     winget install Microsoft.VisualStudio.2022.BuildTools>&2
echo ...or run this from the "x64 Native Tools Command Prompt for VS 2022".>&2
exit /b 1
:have_msvc

rem --- make and sh: MSYS2's, which the recipes need (sh, grep) ---------
rem The Makefile's recipes are POSIX shell; GNU make finds sh.exe beside
rem make.exe, but make and the compiler have to be reachable from here.
if not "%COLI_MSYS2%"=="" if exist "%COLI_MSYS2%\usr\bin\make.exe" set "PATH=%COLI_MSYS2%\ucrt64\bin;%COLI_MSYS2%\usr\bin;%PATH%"
if not "%COLI_MAKE%"=="" goto have_make
if not "%COLI_MSYS2%"=="" if exist "%COLI_MSYS2%\usr\bin\make.exe" (
    set "COLI_MAKE=%COLI_MSYS2%\usr\bin\make.exe"
    goto have_make
)
for /f "delims=" %%m in ('where make.exe 2^>nul') do if not defined COLI_MAKE set "COLI_MAKE=%%m"
if not "%COLI_MAKE%"=="" goto have_make
echo ERROR: make not found.>&2
echo Install MSYS2 (its make and sh build the engine):>&2
echo     winget install MSYS2.MSYS2>&2
echo ...or set COLI_MAKE to the make.exe to use.>&2
exit /b 1
:have_make

rem --- ARCH: native, as the setup passes it (the Makefile's own Windows default
rem --- is the portable x86-64-v3); an ARCH in the environment wins.
if "%ARCH%"=="" set "ARCH=native"

rem --- CUDA_ARCH: this card's own arch, as the setup passes it; a CUDA_ARCH in the
rem --- environment wins. An explicit arch (not "native") makes nvcc put the PTX
rem --- of that arch in the DLL beside its SASS, so the driver JITs it on the
rem --- newer cards: the DLL runs on the card it was built for and on the newer
rem --- ones, which is what the setup tells the user.
if "%CUDA_ARCH%"=="" goto detect_arch
rem A CUDA_ARCH in the environment wins, and the marker records it as it is
rem ("portable" is the release's own rule: compute 8.0 and newer).
set "LOCAL_ARCH=%CUDA_ARCH%"
goto have_arch
:detect_arch
set "LOCAL_ARCH="
set "CC="
for /f "usebackq skip=1 delims=" %%c in (`nvidia-smi -i 0 --query-gpu=compute_cap --format=csv 2^>nul`) do set "CC=%%c"
echo(%CC%| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 goto arch_unknown
for /f "tokens=1,2 delims=." %%a in ("%CC%") do set "LOCAL_ARCH=sm_%%a%%b"
if not "%LOCAL_ARCH%"=="" (
    set "CUDA_ARCH=%LOCAL_ARCH%"
    goto have_arch
)
:arch_unknown
set "CC="
set "CUDA_ARCH=native"
set "LOCAL_ARCH=native"
:have_arch

rem --- Build ---
echo Building %TARGET% for %BACKEND% ...
if "%BACKEND%"=="cuda" goto build_cuda
if "%BACKEND%"=="vulkan" goto build_vulkan
goto build_cpu

rem The host links the runtime loader and the DLL carries the backend: both
rem are needed, and the host alone is a CPU-only binary.
:build_cuda
"%COLI_MAKE%" -C . CUDA_DLL=1 ARCH=%ARCH% %TARGET%
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto failed
"%COLI_MAKE%" -C . CUDA_DLL=1 ARCH=%ARCH% cuda-dll
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto failed
rem The marker: this DLL was built here, for the arch above. The setup reads it to
rem know the card the DLL was made for: a local build runs on that card and on
rem the newer ones, where the release's portable DLL (sm_80 and newer) cannot.
>coli_cuda.local echo %LOCAL_ARCH%
goto build_done

:build_vulkan
"%COLI_MAKE%" -C . VK=1 ARCH=%ARCH% %TARGET%
set "RC=%ERRORLEVEL%"
goto build_done

:build_cpu
"%COLI_MAKE%" -C . ARCH=%ARCH% %TARGET%
set "RC=%ERRORLEVEL%"
goto build_done

:build_done
popd
if not "%RC%"=="0" goto failed
echo.
echo OK: engine built successfully.
exit /b 0

:failed
echo.>&2
echo FAILED: make exited with %RC%.>&2
echo.>&2
exit /b %RC%
