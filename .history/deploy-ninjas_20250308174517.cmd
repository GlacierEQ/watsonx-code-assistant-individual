@echo off
echo.
echo ========================================================
echo           NINJA BUILD TEAM DEPLOYMENT SYSTEM
echo                      [Windows]
echo ========================================================
echo.

:: Check for Python installation
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found. Please install Python 3.x and try again.
    exit /b 1
)

:: Check for Ninja
where ninja >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Ninja not found in PATH. Will try to install via pip...
    python -m pip install ninja
)

:: Set up configuration
if not exist ninja-hosts.txt (
    echo [INFO] Creating default ninja-hosts.txt file...
    echo localhost 8374 > ninja-hosts.txt
    echo # Add more hosts below as needed - one per line >> ninja-hosts.txt
    echo # hostname1 8374 >> ninja-hosts.txt
    echo # hostname2 8374 >> ninja-hosts.txt
)

:: Deploy the ninjas!
echo [INFO] Deploying ninja build team...
python scripts\ninja-team.py --mode recursive --hosts ninja-hosts.txt --recursive-depth 3 --config scripts\ninja-team-config.json %*

echo.
if %ERRORLEVEL% EQU 0 (
    echo ==============================================
    echo        NINJA DEPLOYMENT SUCCESSFUL!
    echo ==============================================
) else (
    echo [ERROR] Ninja deployment failed with code %ERRORLEVEL%
)

exit /b %ERRORLEVEL%
