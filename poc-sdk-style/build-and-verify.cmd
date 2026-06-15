@echo off
rem ============================================================================
rem POC: SDK-style nanoFramework v2 (NFMRK2) build + MDP PE emission (Windows).
rem
rem Native-Windows twin of build-and-verify.sh. Builds the modified Metadata
rem Processor (v4, NFMRK2, AssemblyNativeVersion stamping) from the
rem metadata-processor submodule, packs it and the nanoFramework.Sdk into the
rem local feed, builds the SDK-style Blink app, and verifies the emitted .pe.
rem
rem Usage:  build-and-verify.cmd
rem ============================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "CORELIB_VER=2.0.0-preview.52"
set "CORELIB_DLL=%USERPROFILE%\.nuget\packages\nanoframework.corelibrary\%CORELIB_VER%\lib\netnano1.0\mscorlib.dll"
set "MDP_PROJ=%~dp0..\metadata-processor\MetadataProcessor.MsBuildTask\MetadataProcessor.MsBuildTask.csproj"

if not exist local-feed mkdir local-feed

echo ==^> 0. Build + pack the modified Metadata Processor (v4 NFMRK2, native-version stamping)
del /q "local-feed\nanoFramework.Tools.MetadataProcessor.MsBuildTask.*.nupkg" 2>nul
dotnet pack "%MDP_PROJ%" -c Release -o local-feed -clp:NoSummary || goto :fail
set "MDP_VER="
for %%F in ("local-feed\nanoFramework.Tools.MetadataProcessor.MsBuildTask.*.nupkg") do (
  set "MDP_NUPKG=%%~nxF"
  set "MDP_VER=!MDP_NUPKG:nanoFramework.Tools.MetadataProcessor.MsBuildTask.=!"
  set "MDP_VER=!MDP_VER:.nupkg=!"
)
if "%MDP_VER%"=="" (echo    FAIL: could not determine packed MDP version & goto :fail)
echo    MDP version: %MDP_VER%
if exist "%USERPROFILE%\.nuget\packages\nanoframework.tools.metadataprocessor.msbuildtask\%MDP_VER%" rmdir /s /q "%USERPROFILE%\.nuget\packages\nanoframework.tools.metadataprocessor.msbuildtask\%MDP_VER%"
set "MDP_PKG=%USERPROFILE%\.nuget\packages\nanoframework.tools.metadataprocessor.msbuildtask\%MDP_VER%\lib\net8.0\nanoFramework.Tools.MetadataProcessor.MsBuildTask.dll"

echo.
echo ==^> 1. Pack the local nanoFramework.Sdk into the local feed
dotnet pack nanoFramework.Sdk\nanoFramework.Sdk.csproj -o local-feed -clp:NoSummary || goto :fail
if exist "%USERPROFILE%\.nuget\packages\nanoframework.sdk\1.0.0" rmdir /s /q "%USERPROFILE%\.nuget\packages\nanoframework.sdk\1.0.0"

echo.
echo ==^> 2. Build the SDK-style sample (Sdk="nanoFramework.Sdk/1.0.0")
pushd samples\Blink
if exist bin rmdir /s /q bin
if exist obj rmdir /s /q obj
dotnet build -clp:NoSummary -p:NanoMdpTaskPackageVersion=%MDP_VER% || (popd & goto :fail)

echo.
echo ==^> 3. Outputs
dir /b bin\Debug

set "PE=bin\Debug\Blink.pe"
echo.
echo ==^> 4. Confirm it is a real nanoFramework v2 PE (NFMRK2 magic)
powershell -NoProfile -Command "$b=[IO.File]::ReadAllBytes('%PE%'); if ($b.Length -ge 6 -and (-join([char[]]$b[0..5])) -eq 'NFMRK2') { exit 0 } else { exit 1 }"
if errorlevel 1 (echo    FAIL: bad magic & popd & goto :fail)
echo    OK: %PE% starts with NFMRK2

echo.
echo ==^> 5. WS1 parity gate: same IL through a direct MDP invocation, byte-compare
set "IL=%CD%\obj\Debug\Blink.exe"
set "DIRECT_PROJ=%TEMP%\nano-poc-direct.proj"
set "DIRECT_PE=%TEMP%\Blink.direct.pe"
if exist "%DIRECT_PE%" del /q "%DIRECT_PE%"
(
  echo ^<Project^>
  echo   ^<UsingTask TaskName="MetaDataProcessorTask" AssemblyFile="%MDP_PKG%" /^>
  echo   ^<Target Name="Go"^>
  echo     ^<MetaDataProcessorTask Verbose="false" Parse="%IL%" VerboseMinimize="false"
  echo         DumpMetadata="false" LoadHints="%CORELIB_DLL%"
  echo         Compile="%DIRECT_PE%" GenerateStubs="false" /^>
  echo   ^</Target^>
  echo ^</Project^>
) > "%DIRECT_PROJ%"
dotnet msbuild "%DIRECT_PROJ%" -t:Go -clp:NoSummary >nul || (popd & goto :fail)
fc /b "%PE%" "%DIRECT_PE%" >nul
if errorlevel 1 (echo    FAIL: PE differs from direct MDP output & popd & goto :fail)
echo    OK: SDK PE is BYTE-IDENTICAL to the direct MDP output

echo.
echo ==^> 6. ProjectCapability NanoCSharpProject present (WS2 build-side)
dotnet msbuild Blink.csproj -getItem:ProjectCapability 2>nul | findstr /C:"\"Identity\": \"NanoCSharpProject\"" >nul
if errorlevel 1 (echo    FAIL: capability missing & popd & goto :fail)
echo    OK: NanoCSharpProject capability is on the SDK-style project

echo.
echo ==^> 7. Restore-loop guard: MDP PackageReference is stable across restores
dotnet msbuild Blink.csproj -getItem:PackageReference -p:PkgnanoFramework_Tools_MetadataProcessor_MsBuildTask=loopguard 2>nul | findstr /C:"\"Identity\": \"nanoFramework.Tools.MetadataProcessor.MsBuildTask\"" >nul
if errorlevel 1 (echo    FAIL: MDP PackageReference vanishes once its path resolves -^> VS restore loop & popd & goto :fail)
echo    OK: MDP PackageReference does not oscillate (no VS restore loop)
popd

echo.
echo All POC build-side checks passed.
endlocal
exit /b 0

:fail
echo.
echo BUILD-AND-VERIFY FAILED.
endlocal
exit /b 1
