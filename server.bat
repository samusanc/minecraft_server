@echo off
setlocal enabledelayedexpansion

:: ==============================================================================
:: Minecraft Crossplay Server Controller (Windows CMD / Batch)
:: ==============================================================================

cd /d "%~dp0"
set CONTAINER_NAME=minecraft-server
set BACKUP_DIR=%~dp0backups

:: Check Docker Compose
docker compose version >nul 2>&1
if %errorlevel% equ 0 (
    set COMPOSE_CMD=docker compose
) else (
    docker-compose version >nul 2>&1
    if %errorlevel% equ 0 (
        set COMPOSE_CMD=docker-compose
    ) else (
        echo [ERROR] Neither 'docker compose' nor 'docker-compose' is installed or in PATH.
        echo Please install Docker Desktop: https://www.docker.com/products/docker-desktop/
        pause
        exit /b 1
    )
)

:: Check if .env exists
if not exist ".env" (
    if exist ".env.example" (
        echo [!] .env not found. Creating from .env.example with defaults...
        copy ".env.example" ".env" >nul
    ) else (
        echo [ERROR] Missing .env and .env.example files.
        pause
        exit /b 1
    )
)

:: If argument passed, jump directly
if not "%~1"=="" goto handle_args

:menu
cls
echo ================================================================
echo   Minecraft Crossplay Server Controller (Java ^& Bedrock)
echo ================================================================
echo   1. Start Server
echo   2. Stop Server (Graceful)
echo   3. Restart Server
echo   4. Server Status ^& Resource Stats
echo   5. Follow Logs (Ctrl+C to quit)
echo   6. Interactive RCON Admin Console
echo   7. Create World Backup (ZIP)
echo   8. Update Server Docker Image
echo   9. Exit
echo ================================================================
set /p choice="Choose an option [1-9]: "

if "%choice%"=="1" goto start_server
if "%choice%"=="2" goto stop_server
if "%choice%"=="3" goto restart_server
if "%choice%"=="4" goto status_server
if "%choice%"=="5" goto logs_server
if "%choice%"=="6" goto console_server
if "%choice%"=="7" goto backup_server
if "%choice%"=="8" goto update_server
if "%choice%"=="9" exit /b 0
goto menu

:handle_args
if /i "%~1"=="start" goto start_server
if /i "%~1"=="stop" goto stop_server
if /i "%~1"=="restart" goto restart_server
if /i "%~1"=="status" goto status_server
if /i "%~1"=="logs" goto logs_server
if /i "%~1"=="console" goto console_server
if /i "%~1"=="backup" goto backup_server
if /i "%~1"=="update" goto update_server
if /i "%~1"=="help" goto show_help
echo [ERROR] Unknown command: %~1
goto show_help

:start_server
echo ==> Starting Minecraft Server...
%COMPOSE_CMD% up -d
echo [OK] Server container launched.
if "%~1"=="" pause & goto menu
exit /b 0

:stop_server
echo ==> Gracefully stopping Minecraft Server...
docker exec %CONTAINER_NAME% rcon-cli say Server shutting down in 5 seconds... >nul 2>&1
docker exec %CONTAINER_NAME% rcon-cli save-all >nul 2>&1
docker exec %CONTAINER_NAME% rcon-cli stop >nul 2>&1
timeout /t 5 /nobreak >nul 2>&1
%COMPOSE_CMD% down
echo [OK] Minecraft Server stopped.
if "%~1"=="" pause & goto menu
exit /b 0

:restart_server
call :stop_server
call :start_server
if "%~1"=="" pause & goto menu
exit /b 0

:status_server
echo --- Container Status ---
%COMPOSE_CMD% ps
echo.
echo --- Resource Usage ---
docker stats --no-stream %CONTAINER_NAME% 2>nul
if "%~1"=="" pause & goto menu
exit /b 0

:logs_server
echo ==> Following server logs (Press Ctrl+C to return)...
%COMPOSE_CMD% logs -f --tail=100
if "%~1"=="" pause & goto menu
exit /b 0

:console_server
echo ==> Connecting to Minecraft RCON Console...
echo (Type 'exit' to disconnect without stopping the server)
docker exec -it %CONTAINER_NAME% rcon-cli
if "%~1"=="" pause & goto menu
exit /b 0

:backup_server
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c-%%a-%%b)
for /f "tokens=1-2 delims=/:" %%a in ("%TIME%") do (set mytime=%%a%%b)
set mytime=%mytime: =0%
set BACKUP_ZIP=%BACKUP_DIR%\world_backup_%date:~10,4%-%date:~4,2%-%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.zip
set BACKUP_ZIP=%BACKUP_ZIP: =0%

echo ==> Creating backup: %BACKUP_ZIP%
docker exec %CONTAINER_NAME% rcon-cli save-off >nul 2>&1
docker exec %CONTAINER_NAME% rcon-cli save-all flush >nul 2>&1
tar -czf "%BACKUP_DIR%\world_backup.tar.gz" data\ >nul 2>&1 || (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path 'data' -DestinationPath '%BACKUP_ZIP%' -Force"
)
docker exec %CONTAINER_NAME% rcon-cli save-on >nul 2>&1
echo [OK] Backup created successfully in %BACKUP_DIR%
if "%~1"=="" pause & goto menu
exit /b 0

:update_server
echo ==> Pulling latest image updates...
%COMPOSE_CMD% pull
echo [OK] Images updated. Restart server to apply.
if "%~1"=="" pause & goto menu
exit /b 0

:show_help
echo Usage: server.bat [start^|stop^|restart^|status^|logs^|console^|backup^|update]
exit /b 0
