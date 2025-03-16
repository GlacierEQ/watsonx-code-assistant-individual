@echo off
REM Windows implementation of make command for Ninja deployment

IF "%1"=="deploy-ninjas" (
    powershell.exe -ExecutionPolicy Bypass -File Deploy-Ninjas.ps1 -Initialize
    exit /b %ERRORLEVEL%
)

IF "%1"=="deploy-ninjas-full" (
    powershell.exe -ExecutionPolicy Bypass -File Deploy-Ninjas.ps1 -Full -Initialize
    exit /b %ERRORLEVEL%
)

IF "%1"=="init" (
    powershell.exe -ExecutionPolicy Bypass -File scripts\init-build-env.ps1
    exit /b %ERRORLEVEL%
)

IF "%1"=="clean" (
    powershell.exe -ExecutionPolicy Bypass -File Deploy-Ninjas.ps1 -Clean
    exit /b %ERRORLEVEL%
)

IF "%1"=="help" (
    powershell.exe -ExecutionPolicy Bypass -File Deploy-Ninjas.ps1 -Help
    exit /b %ERRORLEVEL%
)

echo Unknown or missing command: %1
echo Available commands:
echo   make deploy-ninjas       - Deploy basic ninja team
echo   make deploy-ninjas-full  - Deploy full recursive ninja team
echo   make init                - Initialize build environment
echo   make clean               - Clean build artifacts
echo   make help                - Show help information
exit /b 1
