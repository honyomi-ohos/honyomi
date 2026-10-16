@echo off
rem ============================================================================
rem One-click rebuild of the prebuilt libaom binaries (AV1 decoder-only) for
rem the vendored libavif in this directory.
rem
rem Usage:
rem   build-aom.cmd            rebuild arm64-v8a + x86_64
rem   build-aom.cmd arm64      rebuild arm64-v8a only
rem   build-aom.cmd x64        rebuild x86_64 only
rem
rem Requirements:
rem   - DevEco Studio OHOS SDK, located via standard env vars in this order:
rem     OHOS_SDK (native SDK dir) / DEVECO_SDK_HOME (SDK root) /
rem     OHOS_SDK_HOME (SDK root), falling back to the standard install dir
rem   - Git for Windows (provides perl, needed by the aom build)
rem   - curl + tar (built into Windows 10 1803+)
rem
rem macOS / Linux: use build-aom.sh instead (same behavior).
rem
rem Downloads (cached in %TEMP%\mihon-aom):
rem   - libaom v3.15.2 source tarball (GitHub mirror of aomedia.googlesource.com)
rem   - nasm 2.16.03 (x86_64 assembly, only for the x64 target)
rem
rem Outputs are copied to: prebuilt\<abi>\libaom.a
rem See README.md in this directory for full provenance.
rem ============================================================================
setlocal EnableExtensions

set "VENDORDIR=%~dp0"
set "WORK=%TEMP%\mihon-aom"
rem libaom source comes from the git submodule in this directory (see README.md).
set "SRC=%VENDORDIR%aom"
set "NASM_DIR=%WORK%\nasm-2.16.03"
set "NASM_ZIP=%WORK%\nasm-2.16.03-win64.zip"
set "NASM_URL=https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-win64.zip"

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=all"

rem ---- 1. Locate the OHOS native SDK ----------------------------------------
rem Resolution order (standard DevEco conventions, no machine-specific paths):
rem   1. OHOS_SDK        - native SDK dir (contains build\cmake\ohos.toolchain.cmake)
rem   2. DEVECO_SDK_HOME - DevEco Studio SDK root (contains default\openharmony)
rem   3. OHOS_SDK_HOME   - same layout as DEVECO_SDK_HOME
rem   4. Standard install: %ProgramFiles%\Huawei\DevEco Studio\sdk
set "SDK_REAL="
if defined OHOS_SDK set "SDK_REAL=%OHOS_SDK%"
if not defined SDK_REAL if defined DEVECO_SDK_HOME set "SDK_REAL=%DEVECO_SDK_HOME%\default\openharmony\native"
if not defined SDK_REAL if defined OHOS_SDK_HOME set "SDK_REAL=%OHOS_SDK_HOME%\default\openharmony\native"
if not defined SDK_REAL set "SDK_REAL=%ProgramFiles%\Huawei\DevEco Studio\sdk\default\openharmony\native"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" if defined DEVECO_SDK_HOME set "SDK_REAL=%DEVECO_SDK_HOME%\native"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" if defined DEVECO_SDK_HOME set "SDK_REAL=%DEVECO_SDK_HOME%\default\openharmony"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" if defined DEVECO_SDK_HOME set "SDK_REAL=%DEVECO_SDK_HOME%"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" if defined OHOS_SDK_HOME set "SDK_REAL=%OHOS_SDK_HOME%\native"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" if defined OHOS_SDK_HOME set "SDK_REAL=%OHOS_SDK_HOME%\default\openharmony"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" if defined OHOS_SDK_HOME set "SDK_REAL=%OHOS_SDK_HOME%"
if not exist "%SDK_REAL%\build\cmake\ohos.toolchain.cmake" (
  echo ERROR: OHOS native SDK not found.
  echo        Set DEVECO_SDK_HOME to the DevEco Studio SDK root ^(the dir
  echo        containing default\openharmony^), or OHOS_SDK to the native
  echo        SDK dir ^(containing build\cmake\ohos.toolchain.cmake^), then retry.
  exit /b 1
)
echo Using SDK: %SDK_REAL%

rem ---- 2. Space-free junction to the SDK ------------------------------------
rem The SDK path usually contains spaces ("DevEco Studio"). CMake 3.28 in the
rem SDK chokes on unquoted -D values with spaces, and quoting CMAKE_ASM_COMPILER
rem corrupts the generated CMakeASMCompiler.cmake. A junction sidesteps both.
if not exist "%WORK%" mkdir "%WORK%"
if exist "%WORK%\sdk" rmdir "%WORK%\sdk" 2>nul
if exist "%WORK%\sdk" rmdir /s /q "%WORK%\sdk"
mklink /J "%WORK%\sdk" "%SDK_REAL%" >nul
if errorlevel 1 (
  echo ERROR: failed to create junction %WORK%\sdk
  exit /b 1
)
set "SDK=%WORK%\sdk"
set "CMAKE=%SDK%\build-tools\cmake\bin\cmake.exe"
set "NINJA=%SDK%\build-tools\cmake\bin\ninja.exe"
if not exist "%CMAKE%" (
  echo ERROR: cmake not found at %CMAKE%
  exit /b 1
)
set "PATH=%SDK%\llvm\bin;%PATH%"

rem ---- 3. libaom source (git submodule) --------------------------------------
if not exist "%SRC%\CMakeLists.txt" (
  echo ERROR: libaom source not found at %SRC%
  echo        Run: git submodule update --init
  echo        ^(from the repository root; needs access to
  echo         https://aomedia.googlesource.com/aom^)
  exit /b 1
)

rem ---- 4. perl (aom build requirement) ---------------------------------------
if not defined PERL set "PERL=%ProgramFiles%\Git\usr\bin\perl.exe"
if not exist "%PERL%" (
  for /f "delims=" %%I in ('where perl 2^>nul') do if not defined PERL_X set "PERL_X=%%I"
  if defined PERL_X set "PERL=%PERL_X%"
)
if not exist "%PERL%" (
  echo ERROR: perl not found. Install Git for Windows or set PERL=full\path\to\perl.exe
  exit /b 1
)
for %%I in ("%PERL%") do set "PERL_S=%%~sI"
set "PERL_ARG=-DPERL_EXECUTABLE=%PERL_S%"
echo %PERL_S%| find " " >nul
if not errorlevel 1 (
  echo ERROR: perl path "%PERL_S%" contains a space and no 8.3 short name is
  echo        available. Set PERL to a space-free path and retry.
  exit /b 1
)

rem ---- 5. nasm (x86_64 assembly only) ----------------------------------------
if /i "%TARGET%"=="x64" call :setupnasm
if /i "%TARGET%"=="all" call :setupnasm
if errorlevel 1 exit /b 1

rem ---- 6. Build ---------------------------------------------------------------
if /i "%TARGET%"=="arm64" call :buildabi arm64 arm64-v8a arm64-v8a
if /i "%TARGET%"=="x64"    call :buildabi x64   x86_64   x86_64
if /i "%TARGET%"=="all"    call :buildabi arm64 arm64-v8a arm64-v8a
if errorlevel 1 exit /b 1
if /i "%TARGET%"=="all"    call :buildabi x64   x86_64   x86_64
if errorlevel 1 exit /b 1
if /i not "%TARGET%"=="arm64" if /i not "%TARGET%"=="x64" if /i not "%TARGET%"=="all" (
  echo usage: build-aom.cmd [arm64^|x64^|all]
  exit /b 2
)

echo.
echo Done. Updated %VENDORDIR%prebuilt\libaom.a for target(s): %TARGET%
echo Rebuild the HAP to pick up the new binaries.
exit /b 0

rem ============================================================================
:setupnasm
if exist "%NASM_DIR%\nasm.exe" ( set "PATH=%NASM_DIR%;%PATH%" & exit /b 0 )
if not exist "%NASM_ZIP%" (
  echo Downloading nasm 2.16.03 ...
  curl -L --fail --retry 3 -o "%NASM_ZIP%" "%NASM_URL%"
  if errorlevel 1 (
    echo ERROR: download failed. Download
    echo        %NASM_URL%
    echo        manually and place it at %NASM_ZIP%
    exit /b 1
  )
)
tar -xf "%NASM_ZIP%" -C "%WORK%"
if errorlevel 1 exit /b 1
if not exist "%NASM_DIR%\nasm.exe" (
  echo ERROR: nasm.exe not found after extraction ^(expected %NASM_DIR%^)
  exit /b 1
)
set "PATH=%NASM_DIR%;%PATH%"
exit /b 0

rem ============================================================================
:buildabi
rem %1 = label, %2 = OHOS arch, %3 = prebuilt subdir
set "BDIR=%WORK%\build\aom-%~1"
if exist "%BDIR%" rmdir /s /q "%BDIR%"
echo.
echo === libaom %~1 (%~2) ===
rem CMake writes CMAKE_ASM_COMPILER verbatim into CMakeASMCompiler.cmake;
rem backslashes create invalid \U escapes there, so pass forward slashes.
set "ASMCC=%SDK:\=/%"
"%CMAKE%" -G Ninja -S "%SRC%" -B "%BDIR%" ^
  -DCMAKE_TOOLCHAIN_FILE=%SDK%\build\cmake\ohos.toolchain.cmake ^
  -DOHOS_ARCH=%~2 -DOHOS_PLATFORM=OHOS ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCONFIG_AV1_ENCODER=0 -DCONFIG_AV1_DECODER=1 ^
  -DCMAKE_ASM_COMPILER=%ASMCC%/llvm/bin/clang.exe ^
  -DCMAKE_MAKE_PROGRAM=%NINJA% ^
  %PERL_ARG% ^
  -DCMAKE_C_FLAGS_RELEASE="-Oz -DNDEBUG -flax-vector-conversions=none" ^
  -DCMAKE_ASM_FLAGS_RELEASE="-Oz -DNDEBUG"
if errorlevel 1 ( echo ERROR: cmake configure failed for %~1 & exit /b 1 )
"%NINJA%" -C "%BDIR%"
if errorlevel 1 ( echo ERROR: build failed for %~1 & exit /b 1 )
if not exist "%BDIR%\libaom.a" ( echo ERROR: %BDIR%\libaom.a not produced & exit /b 1 )
copy /y "%BDIR%\libaom.a" "%VENDORDIR%prebuilt\%~3\libaom.a" >nul
for %%I in ("%VENDORDIR%prebuilt\%~3\libaom.a") do echo -^> prebuilt\%~3\libaom.a  %%~zI bytes
exit /b 0
