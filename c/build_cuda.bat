@echo off
rem ---------------------------------------------------------------------------
rem build_cuda.bat - one-shot build of coli_cuda.dll (Windows, nvcc + MSVC).
rem
rem Mirrors the Makefile's `cuda-dll` recipe so it can be double-clicked or run
rem from a plain shell: it locates vcvars64.bat and the CUDA toolkit itself
rem rather than hardcoding install paths. The same four sources, the same
rem flags - keep the two in step (the source list is spelled out at the build).
rem
rem Overrides (set before calling):
rem   CUDA_ARCH   GPU compute capability (sm_NNN). Auto-detected from the
rem               installed GPU via nvidia-smi; set to override or to
rem               cross-compile. sm_120 = Blackwell / RTX 50xx, sm_89 = Ada /
rem               RTX 40xx, sm_86 = Ampere / RTX 30xx.
rem   CUDA_PATH   CUDA toolkit root. Normally set by the CUDA installer.
rem   CCBIN       Directory containing the cl.exe nvcc should use as host
rem               compiler. Set this to force a specific toolset.
rem   ALLOW_UNSUPPORTED  =1 adds -allow-unsupported-compiler.
rem ---------------------------------------------------------------------------
setlocal

rem --- GPU arch: detect from the installed GPU unless overridden ------------
rem nvidia-smi reports compute capability as e.g. "12.0"; strip the dot for the
rem sm_NNN suffix (12.0 -> sm_120, 8.9 -> sm_89). The value is validated as
rem <digits>.<digits>; anything else falls back to sm_120.
if not "%CUDA_ARCH%"=="" goto have_arch
for /f "usebackq skip=1 delims=" %%c in (`nvidia-smi -i 0 --query-gpu=compute_cap --format=csv 2^>nul`) do set "CC=%%c"
echo(%CC%| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 goto arch_default
for /f "tokens=1,2 delims=." %%a in ("%CC%") do set "CUDA_ARCH=sm_%%a%%b"
if not "%CUDA_ARCH%"=="" goto have_arch
:arch_default
echo WARNING: could not detect GPU compute capability; defaulting to sm_120.>&2
set "CUDA_ARCH=sm_120"
:have_arch
set "CC="

rem --- MSVC: nvcc needs cl.exe as its host compiler -------------------------
rem msvc_env.bat finds a Visual Studio and calls its vcvars64.bat; the
rem environment it sets up stays for this script (same process).
if not "%CCBIN%"=="" goto have_msvc
call "%~dp0msvc_env.bat"
if %ERRORLEVEL%==0 goto have_msvc
goto no_msvc
:have_msvc

rem -ccbin pins the host compiler explicitly.
set "CCBIN_FLAG="
if not "%CCBIN%"=="" set "CCBIN_FLAG=-ccbin "%CCBIN%""
set "UNSUPPORTED_FLAG="
if "%ALLOW_UNSUPPORTED%"=="1" set "UNSUPPORTED_FLAG=-allow-unsupported-compiler"

rem --- CUDA -----------------------------------------------------------------
set "NVCC=nvcc"
where nvcc.exe >nul 2>&1
if %ERRORLEVEL%==0 goto have_nvcc
if "%CUDA_PATH%"=="" goto no_cuda
if not exist "%CUDA_PATH%\bin\nvcc.exe" goto no_cuda
set "NVCC=%CUDA_PATH%\bin\nvcc.exe"
:have_nvcc

rem Add -L<cuda>\lib\x64 for cudart only when CUDA_PATH is known.
set "CUDA_LIB="
if not "%CUDA_PATH%"=="" set "CUDA_LIB=-L"%CUDA_PATH%\lib\x64""

rem --- Build ----------------------------------------------------------------
rem Build in the script's own directory so backend_cuda.cu resolves and the DLL
rem lands next to colibri.exe.
pushd "%~dp0"

echo Building coli_cuda.dll for %CUDA_ARCH% ...
rem The SAME four sources as the Makefile's `cuda-dll` target (c/Makefile), and
rem the same flags (-ftz=false keeps the denormals the CPU path keeps). The
rem source list must match: backend_cuda.cu alone builds and links fine, but
rem the DLL is then missing the three OPTIONAL entry points the loader resolves
rem with RESOLVE_OPT -- coli_cuda_chain_ops (cuda_chain.cu), coli_cuda_tier_ops
rem (cu_xb.cu) and coli_cuda_ink_ops (backend_cuda_ink.cu). A missing one does
rem not fail the load: the CUDA chain, the GPU expert tier and Inkling's bf16
rem path turn themselves off, silently, and the engine runs on a smaller GPU
rem footprint than it should. If a source is added to the Makefile's target,
rem add it here too.
rem -Xcompiler=-W3 sets the MSVC host-compiler warning level.
"%NVCC%" -O3 -std=c++17 -ftz=false -arch=%CUDA_ARCH% -Xcompiler=-W3 -shared ^
    %CCBIN_FLAG% %UNSUPPORTED_FLAG% ^
    -DCOLI_CUDA_BUILDING_DLL %CUDA_LIB% -lcudart ^
    backend_cuda.cu cuda_chain.cu cu_xb.cu backend_cuda_ink.cu -o coli_cuda.dll
set "RC=%ERRORLEVEL%"

popd
if not "%RC%"=="0" goto failed
rem The marker: this DLL was built here, for the arch above. The setup reads it to
rem know the card the DLL was made for: a local build runs on that card and on
rem the newer ones, where the release's portable DLL (sm_80 and newer) cannot.
rem It goes beside the DLL, which is in this script's own directory.
>"%~dp0coli_cuda.local" echo %CUDA_ARCH%
echo.
echo OK: %~dp0coli_cuda.dll
echo Now build the host with the runtime loader:
echo     make colibri.exe CUDA_DLL=1 ARCH=native
exit /b 0

:no_msvc
echo ERROR: cl.exe (MSVC) not found.>&2
echo Install "Desktop development with C++":>&2
echo     winget install Microsoft.VisualStudio.2022.BuildTools>&2
echo ...or run this from the "x64 Native Tools Command Prompt for VS 2022".>&2
exit /b 1

:no_cuda
echo ERROR: nvcc not found, and CUDA_PATH is unset or has no bin\nvcc.exe.>&2
echo CUDA 12.8+ is required for sm_120 (Blackwell / RTX 50xx):>&2
echo     winget install Nvidia.CUDA>&2
exit /b 1

:failed
echo.>&2
echo FAILED: nvcc exited with %RC%.>&2
echo.>&2
echo "unsupported gpu architecture" - CUDA older than the target.>&2
echo     sm_120 needs CUDA 12.8+.  Override: set CUDA_ARCH=sm_89>&2
echo.>&2
echo "unsupported Microsoft Visual Studio version" - your VS is NEWER than>&2
echo CUDA supports (it accepts 2017-2022 only). Install the 2022 toolset>&2
echo side by side; it coexists with newer VS and this script prefers it:>&2
echo     winget install Microsoft.VisualStudio.2022.BuildTools>&2
echo     (then add the "Desktop development with C++" workload)>&2
echo Or point at a specific cl.exe directory:>&2
echo     set CCBIN=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\<ver>\bin\Hostx64\x64>&2
exit /b %RC%
