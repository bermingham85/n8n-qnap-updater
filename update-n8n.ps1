<#
.SYNOPSIS
    Update n8n Docker container on QNAP NAS to the latest version

.DESCRIPTION
    This script connects to your QNAP NAS via SSH and updates the n8n Docker container
    to the latest version while preserving your data and configuration.

.PARAMETER QnapHost
    QNAP NAS IP address (default: 192.168.50.246)

.PARAMETER ContainerName
    Name of the n8n Docker container (default: n8n)

.PARAMETER BackupBeforeUpdate
    Create backup before updating (default: $true)

.EXAMPLE
    .\update-n8n.ps1
    
.EXAMPLE
    .\update-n8n.ps1 -ContainerName "n8n-production" -BackupBeforeUpdate $false
#>

param(
    [string]$QnapHost = "192.168.50.246",
    [string]$ContainerName = "n8n",
    [bool]$BackupBeforeUpdate = $true,
    [string]$SSHUser = "admin"
)

# Function to execute SSH commands on QNAP
function Invoke-QnapSSH {
    param(
        [string]$Command
    )
    
    Write-Host "Executing on QNAP: $Command" -ForegroundColor Cyan
    ssh "${SSHUser}@${QnapHost}" $Command
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "SSH command failed with exit code: $LASTEXITCODE"
        return $false
    }
    return $true
}

# Check if SSH is available
Write-Host "=== n8n Docker Container Update Script ===" -ForegroundColor Green
Write-Host "Target QNAP: $QnapHost" -ForegroundColor Yellow
Write-Host "Container: $ContainerName" -ForegroundColor Yellow

# Test SSH connection
Write-Host "`nTesting SSH connection to QNAP..." -ForegroundColor Cyan
$testConnection = ssh -o ConnectTimeout=5 "${SSHUser}@${QnapHost}" "echo 'Connection successful'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Cannot connect to QNAP at $QnapHost. Please check:"
    Write-Host "  1. SSH is enabled on your QNAP (Control Panel > Telnet/SSH)" -ForegroundColor Yellow
    Write-Host "  2. Your SSH credentials are correct" -ForegroundColor Yellow
    Write-Host "  3. The QNAP IP address is correct" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ SSH connection successful" -ForegroundColor Green

# Get current container info
Write-Host "`nGetting current container information..." -ForegroundColor Cyan
$containerInfo = ssh "${SSHUser}@${QnapHost}" "docker ps -a --filter name=$ContainerName --format '{{.ID}}|{{.Image}}|{{.Status}}'"

if ([string]::IsNullOrEmpty($containerInfo)) {
    Write-Error "Container '$ContainerName' not found on QNAP"
    Write-Host "Available containers:" -ForegroundColor Yellow
    ssh "${SSHUser}@${QnapHost}" "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'"
    exit 1
}

$containerDetails = $containerInfo -split '\|'
$containerId = $containerDetails[0]
$currentImage = $containerDetails[1]
$status = $containerDetails[2]

Write-Host "✓ Found container:" -ForegroundColor Green
Write-Host "  ID: $containerId" -ForegroundColor White
Write-Host "  Current Image: $currentImage" -ForegroundColor White
Write-Host "  Status: $status" -ForegroundColor White

# Get container configuration for recreation
Write-Host "`nExtracting container configuration..." -ForegroundColor Cyan
$inspectJson = ssh "${SSHUser}@${QnapHost}" "docker inspect $containerId"
$tempInspectFile = Join-Path $env:TEMP "n8n-container-inspect.json"
$inspectJson | Out-File -FilePath $tempInspectFile -Encoding UTF8
Write-Host "✓ Container configuration saved to: $tempInspectFile" -ForegroundColor Green

# Backup if requested
if ($BackupBeforeUpdate) {
    Write-Host "`nCreating backup..." -ForegroundColor Cyan
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupScript = Join-Path $PSScriptRoot "backup-n8n.ps1"
    
    if (Test-Path $backupScript) {
        & $backupScript -QnapHost $QnapHost -ContainerName $ContainerName -BackupTag $timestamp
    } else {
        Write-Warning "Backup script not found. Skipping backup."
        Write-Host "Press Enter to continue without backup, or Ctrl+C to cancel..."
        Read-Host
    }
}

# Pull latest n8n image
Write-Host "`nPulling latest n8n image..." -ForegroundColor Cyan
if (-not (Invoke-QnapSSH "docker pull n8nio/n8n:latest")) {
    Write-Error "Failed to pull latest n8n image"
    exit 1
}
Write-Host "✓ Latest n8n image pulled successfully" -ForegroundColor Green

# Stop current container
Write-Host "`nStopping current n8n container..." -ForegroundColor Cyan
if (-not (Invoke-QnapSSH "docker stop $containerId")) {
    Write-Error "Failed to stop container"
    exit 1
}
Write-Host "✓ Container stopped" -ForegroundColor Green

# Rename old container (for rollback capability)
Write-Host "`nRenaming old container for rollback capability..." -ForegroundColor Cyan
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not (Invoke-QnapSSH "docker rename $ContainerName ${ContainerName}-old-${timestamp}")) {
    Write-Warning "Failed to rename container. Continuing..."
}

# Get the docker run command from the inspect data
Write-Host "`nRecreating container with latest image..." -ForegroundColor Cyan

# Extract important settings from inspect (volumes, ports, env vars)
# This is a simplified approach - you may need to adjust based on your specific setup
$recreateCommand = @"
docker run -d \
  --name $ContainerName \
  --restart unless-stopped \
  -p 5678:5678 \
  -v /share/Container/n8n/.n8n:/home/node/.n8n \
  -e N8N_PROTOCOL=http \
  -e N8N_HOST=192.168.50.246 \
  -e N8N_PORT=5678 \
  n8nio/n8n:latest
"@

Write-Host "Executing: $recreateCommand" -ForegroundColor Yellow
Write-Host "`nNote: If your container has custom settings, you may need to adjust the script." -ForegroundColor Yellow
Write-Host "Press Enter to continue with the above configuration, or Ctrl+C to cancel..."
Read-Host

if (-not (Invoke-QnapSSH $recreateCommand.Replace("`n", " "))) {
    Write-Error "Failed to create new container"
    Write-Host "`nAttempting rollback..." -ForegroundColor Yellow
    Invoke-QnapSSH "docker start ${containerId}"
    Invoke-QnapSSH "docker rename ${ContainerName}-old-${timestamp} ${ContainerName}"
    Write-Error "Rollback completed. Old container restarted."
    exit 1
}

Write-Host "✓ New container created successfully" -ForegroundColor Green

# Verify new container is running
Write-Host "`nVerifying new container status..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
$newStatus = ssh "${SSHUser}@${QnapHost}" "docker ps --filter name=$ContainerName --format '{{.Status}}'"

if ($newStatus -match "Up") {
    Write-Host "✓ New container is running!" -ForegroundColor Green
    Write-Host "`n=== Update Complete ===" -ForegroundColor Green
    Write-Host "n8n is now running with the latest version" -ForegroundColor White
    Write-Host "Access your n8n instance at: http://$QnapHost:5678" -ForegroundColor Cyan
    
    # Show version
    Start-Sleep -Seconds 10
    Write-Host "`nFetching new version..." -ForegroundColor Cyan
    $version = ssh "${SSHUser}@${QnapHost}" "docker exec $ContainerName n8n --version"
    Write-Host "n8n Version: $version" -ForegroundColor White
    
    Write-Host "`nOld container kept as: ${ContainerName}-old-${timestamp}" -ForegroundColor Yellow
    Write-Host "You can remove it after verifying everything works:" -ForegroundColor Yellow
    Write-Host "  ssh ${SSHUser}@${QnapHost} 'docker rm ${ContainerName}-old-${timestamp}'" -ForegroundColor Gray
} else {
    Write-Error "New container is not running properly!"
    Write-Host "Status: $newStatus" -ForegroundColor Red
    Write-Host "`nCheck container logs:" -ForegroundColor Yellow
    Write-Host "  ssh ${SSHUser}@${QnapHost} 'docker logs $ContainerName'" -ForegroundColor Gray
}
