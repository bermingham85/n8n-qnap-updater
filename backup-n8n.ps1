<#
.SYNOPSIS
    Backup n8n data from Docker container on QNAP NAS

.DESCRIPTION
    Creates a backup of n8n data directory before updates. Backups are timestamped
    and stored on the QNAP for easy restoration if needed.

.PARAMETER QnapHost
    QNAP NAS IP address (default: 192.168.50.246)

.PARAMETER ContainerName
    Name of the n8n Docker container (default: n8n)

.PARAMETER BackupTag
    Optional tag to append to backup name (default: current timestamp)

.PARAMETER BackupPath
    Path on QNAP where backups will be stored (default: /share/Container/n8n-backups)

.EXAMPLE
    .\backup-n8n.ps1
    
.EXAMPLE
    .\backup-n8n.ps1 -BackupTag "pre-update-v1.20"
#>

param(
    [string]$QnapHost = "192.168.50.246",
    [string]$ContainerName = "n8n",
    [string]$BackupTag = "",
    [string]$BackupPath = "/share/Container/n8n-backups",
    [string]$SSHUser = "admin"
)

Write-Host "=== n8n Backup Script ===" -ForegroundColor Green
Write-Host "Target QNAP: $QnapHost" -ForegroundColor Yellow

# Generate backup name
if ([string]::IsNullOrEmpty($BackupTag)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupTag = $timestamp
}
$backupName = "n8n-backup-${BackupTag}"

Write-Host "Backup name: $backupName" -ForegroundColor Yellow

# Test SSH connection
Write-Host "`nTesting SSH connection..." -ForegroundColor Cyan
$testConnection = ssh -o ConnectTimeout=5 "${SSHUser}@${QnapHost}" "echo 'Connected'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Cannot connect to QNAP at $QnapHost"
    exit 1
}
Write-Host "✓ SSH connection successful" -ForegroundColor Green

# Create backup directory if it doesn't exist
Write-Host "`nEnsuring backup directory exists..." -ForegroundColor Cyan
ssh "${SSHUser}@${QnapHost}" "mkdir -p $BackupPath"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create backup directory"
    exit 1
}
Write-Host "✓ Backup directory ready: $BackupPath" -ForegroundColor Green

# Get n8n data volume location
Write-Host "`nLocating n8n data volume..." -ForegroundColor Cyan
$volumeInfo = ssh "${SSHUser}@${QnapHost}" "docker inspect --format='{{range .Mounts}}{{.Source}}:{{.Destination}}{{end}}' $ContainerName"

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($volumeInfo)) {
    Write-Error "Failed to get container volume information"
    Write-Host "Trying alternative method..." -ForegroundColor Yellow
    # Fallback to default path
    $sourcePath = "/share/Container/n8n/.n8n"
} else {
    # Extract source path for .n8n directory
    $sourcePath = ($volumeInfo -split ':')[0]
    if ([string]::IsNullOrEmpty($sourcePath)) {
        $sourcePath = "/share/Container/n8n/.n8n"
    }
}

Write-Host "✓ n8n data location: $sourcePath" -ForegroundColor Green

# Create backup using tar
Write-Host "`nCreating backup archive..." -ForegroundColor Cyan
Write-Host "This may take a few minutes depending on data size..." -ForegroundColor Yellow

$backupCommand = "tar -czf ${BackupPath}/${backupName}.tar.gz -C $(dirname $sourcePath) $(basename $sourcePath)"
Write-Host "Executing: $backupCommand" -ForegroundColor Gray

ssh "${SSHUser}@${QnapHost}" $backupCommand

if ($LASTEXITCODE -ne 0) {
    Write-Error "Backup creation failed"
    exit 1
}

Write-Host "✓ Backup archive created" -ForegroundColor Green

# Get backup file size
$backupSize = ssh "${SSHUser}@${QnapHost}" "du -h ${BackupPath}/${backupName}.tar.gz | cut -f1"
Write-Host "Backup size: $backupSize" -ForegroundColor White

# Create backup metadata
Write-Host "`nCreating backup metadata..." -ForegroundColor Cyan
$metadata = @"
Backup Information
==================
Backup Name: $backupName
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Source Path: $sourcePath
Container: $ContainerName
QNAP Host: $QnapHost

Restoration Command:
--------------------
ssh ${SSHUser}@${QnapHost} 'tar -xzf ${BackupPath}/${backupName}.tar.gz -C /share/Container/n8n/'

Or to restore to a different location:
ssh ${SSHUser}@${QnapHost} 'tar -xzf ${BackupPath}/${backupName}.tar.gz -C /path/to/restore/'
"@

$metadataFile = "${BackupPath}/${backupName}.txt"
ssh "${SSHUser}@${QnapHost}" "cat > $metadataFile" <<< $metadata

Write-Host "✓ Backup metadata saved" -ForegroundColor Green

# List recent backups
Write-Host "`n=== Backup Complete ===" -ForegroundColor Green
Write-Host "Backup location: ${BackupPath}/${backupName}.tar.gz" -ForegroundColor Cyan
Write-Host "Backup size: $backupSize" -ForegroundColor White

Write-Host "`nRecent backups:" -ForegroundColor Yellow
ssh "${SSHUser}@${QnapHost}" "ls -lh ${BackupPath}/*.tar.gz | tail -5"

Write-Host "`nTo restore this backup:" -ForegroundColor Cyan
Write-Host "  1. Stop n8n container:" -ForegroundColor White
Write-Host "     ssh ${SSHUser}@${QnapHost} 'docker stop $ContainerName'" -ForegroundColor Gray
Write-Host "  2. Restore backup:" -ForegroundColor White
Write-Host "     ssh ${SSHUser}@${QnapHost} 'tar -xzf ${BackupPath}/${backupName}.tar.gz -C /share/Container/n8n/'" -ForegroundColor Gray
Write-Host "  3. Start n8n container:" -ForegroundColor White
Write-Host "     ssh ${SSHUser}@${QnapHost} 'docker start $ContainerName'" -ForegroundColor Gray

# Cleanup old backups (keep last 5)
Write-Host "`nChecking for old backups to cleanup..." -ForegroundColor Cyan
$backupCount = ssh "${SSHUser}@${QnapHost}" "ls -1 ${BackupPath}/n8n-backup-*.tar.gz 2>/dev/null | wc -l"

if ($backupCount -gt 5) {
    Write-Host "Found $backupCount backups. Removing old backups (keeping last 5)..." -ForegroundColor Yellow
    ssh "${SSHUser}@${QnapHost}" "cd ${BackupPath} && ls -t n8n-backup-*.tar.gz | tail -n +6 | xargs rm -f"
    Write-Host "✓ Old backups cleaned up" -ForegroundColor Green
} else {
    Write-Host "✓ Backup count ($backupCount) is within limit" -ForegroundColor Green
}
