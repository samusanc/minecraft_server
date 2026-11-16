<#
.SYNOPSIS
    Minecraft Crossplay Server Controller (PowerShell)
.DESCRIPTION
    Cross-platform PowerShell automation for the Minecraft Java + Bedrock Docker server.
.EXAMPLE
    .\server.ps1 start
    .\server.ps1 logs
    .\server.ps1 console
    .\server.ps1 backup
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "status", "logs", "console", "backup", "update", "help")]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$AdditionalArgs
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$ContainerName = "minecraft-server"
$BackupDir = Join-Path $ScriptDir "backups"

# Check Docker Compose
function Get-ComposeCommand {
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        $test = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @("docker", "compose")
        }
    }
    if (Get-Command "docker-compose" -ErrorAction SilentlyContinue) {
        return @("docker-compose")
    }
    Write-Error "Neither 'docker compose' nor 'docker-compose' was found. Please ensure Docker Desktop is running."
}

$Compose = Get-ComposeCommand

function Check-Env {
    $envPath = Join-Path $ScriptDir ".env"
    $envExample = Join-Path $ScriptDir ".env.example"
    if (-not (Test-Path $envPath)) {
        if (Test-Path $envExample) {
            Write-Host "[!] .env not found. Copying defaults from .env.example..." -ForegroundColor Yellow
            Copy-Item $envExample $envPath
        } else {
            Write-Error ".env and .env.example are missing."
        }
    }
}

function Start-Server {
    Check-Env
    Write-Host "==> Starting Minecraft Crossplay Server..." -ForegroundColor Cyan
    & $Compose[0] $Compose[1..($Compose.Length-1)] up -d
    Write-Host "[OK] Server container launched." -ForegroundColor Green
    Write-Host "Run '.\server.ps1 logs' to follow progress." -ForegroundColor DarkGray
}

function Stop-Server {
    Write-Host "==> Gracefully shutting down Minecraft Server..." -ForegroundColor Yellow
    $isRunning = (docker inspect -f '{{.State.Running}}' $ContainerName 2>$null) -eq "true"
    if ($isRunning) {
        Write-Host "Notifying players and saving chunks..." -ForegroundColor DarkGray
        docker exec $ContainerName rcon-cli say "Server shutting down in 5 seconds..." 2>$null | Out-Null
        docker exec $ContainerName rcon-cli save-all 2>$null | Out-Null
        docker exec $ContainerName rcon-cli stop 2>$null | Out-Null
        Start-Sleep -Seconds 5
    }
    & $Compose[0] $Compose[1..($Compose.Length-1)] down
    Write-Host "[OK] Minecraft Server stopped." -ForegroundColor Green
}

function Restart-Server {
    Stop-Server
    Start-Sleep -Seconds 2
    Start-Server
}

function Show-Status {
    Write-Host "--- Container Status ---" -ForegroundColor Cyan
    & $Compose[0] $Compose[1..($Compose.Length-1)] ps
    Write-Host ""
    $isRunning = (docker inspect -f '{{.State.Running}}' $ContainerName 2>$null) -eq "true"
    if ($isRunning) {
        Write-Host "--- Resource Usage ---" -ForegroundColor Cyan
        docker stats --no-stream $ContainerName
    } else {
        Write-Host "Server is currently STOPPED." -ForegroundColor Yellow
    }
}

function Show-Logs {
    Write-Host "==> Streaming server logs (Ctrl+C to stop)..." -ForegroundColor Cyan
    & $Compose[0] $Compose[1..($Compose.Length-1)] logs -f --tail=100
}

function Open-Console {
    $isRunning = (docker inspect -f '{{.State.Running}}' $ContainerName 2>$null) -eq "true"
    if (-not $isRunning) {
        Write-Error "Server container is not running."
    }
    Write-Host "==> Connecting to Minecraft RCON Console. (Type 'exit' to detach)" -ForegroundColor Green
    docker exec -it $ContainerName rcon-cli
}

function Backup-Server {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $backupZip = Join-Path $BackupDir "world_backup_$timestamp.zip"

    Write-Host "==> Creating backup: $backupZip" -ForegroundColor Cyan
    $isRunning = (docker inspect -f '{{.State.Running}}' $ContainerName 2>$null) -eq "true"
    if ($isRunning) {
        Write-Host "Pausing world saves..." -ForegroundColor DarkGray
        docker exec $ContainerName rcon-cli save-off 2>$null | Out-Null
        docker exec $ContainerName rcon-cli save-all flush 2>$null | Out-Null
    }

    try {
        Compress-Archive -Path "data" -DestinationPath $backupZip -Force
        Write-Host "[OK] Backup saved to $backupZip" -ForegroundColor Green
    } finally {
        if ($isRunning) {
            docker exec $ContainerName rcon-cli save-on 2>$null | Out-Null
        }
    }
}

function Update-Server {
    Write-Host "==> Pulling latest Docker image updates..." -ForegroundColor Cyan
    & $Compose[0] $Compose[1..($Compose.Length-1)] pull
    Write-Host "[OK] Update completed. Restart the server to apply." -ForegroundColor Green
}

function Show-Help {
    Write-Host "Minecraft Crossplay Server Controller (Java & Bedrock)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\server.ps1 <command>"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  start     Start the server in background"
    Write-Host "  stop      Gracefully save and stop the server"
    Write-Host "  restart   Restart the server"
    Write-Host "  status    Show status, health, and RAM usage"
    Write-Host "  logs      Follow live server logs"
    Write-Host "  console   Open interactive RCON admin terminal"
    Write-Host "  backup    Create safe compressed ZIP backup of worlds"
    Write-Host "  update    Pull the latest Docker image"
    Write-Host "  help      Show this help text"
    Write-Host ""
}

switch ($Command) {
    "start"   { Start-Server }
    "stop"    { Stop-Server }
    "restart" { Restart-Server }
    "status"  { Show-Status }
    "logs"    { Show-Logs }
    "console" { Open-Console }
    "backup"  { Backup-Server }
    "update"  { Update-Server }
    Default   { Show-Help }
}
