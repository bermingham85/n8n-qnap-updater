# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a PowerShell-based automation project for managing n8n Docker containers on QNAP NAS devices. The scripts provide safe update workflows with automatic backup and rollback capabilities.

**Key Components:**
- `update-n8n.ps1` - Main update script with rollback support
- `backup-n8n.ps1` - Standalone backup utility
- SSH-based remote Docker management on QNAP NAS

## Environment-Specific Configuration

### Network Configuration
- **n8n Instance URL:** http://192.168.50.246:5678
- **QNAP Host:** 192.168.50.246
- **SSH Port:** 22 (default)
- **n8n Port:** 5678

**Important:** All scripts in this project MUST use the n8n instance at `192.168.50.246:5678`. This is the only n8n instance available and all connections must point to it.

### Data Paths on QNAP
- **n8n Data Volume:** `/share/Container/n8n/.n8n`
- **Backup Storage:** `/share/Container/n8n-backups/`
- **Container Name:** `n8n` (default)

## Common Commands

### Running Scripts

**Update n8n (with automatic backup):**
```powershell
.\update-n8n.ps1
```

**Update without backup:**
```powershell
.\update-n8n.ps1 -BackupBeforeUpdate $false
```

**Manual backup:**
```powershell
.\backup-n8n.ps1
```

**Tagged backup:**
```powershell
.\backup-n8n.ps1 -BackupTag "pre-major-update"
```

### SSH Operations

**Test SSH connection:**
```powershell
ssh admin@192.168.50.246 "echo 'Connection successful'"
```

**Check n8n version:**
```powershell
ssh admin@192.168.50.246 "docker exec n8n n8n --version"
```

**View container logs:**
```powershell
ssh admin@192.168.50.246 "docker logs n8n"
```

**List all containers:**
```powershell
ssh admin@192.168.50.246 "docker ps -a"
```

## Architecture & Design

### Update Workflow
1. **Pre-update validation**: Test SSH connection and verify container exists
2. **Configuration extraction**: Capture current container settings via `docker inspect`
3. **Automatic backup**: Create timestamped backup of n8n data (optional but default)
4. **Image update**: Pull latest `n8nio/n8n:latest` image
5. **Container swap**: Stop old container, rename it (for rollback), create new container
6. **Verification**: Check new container status and version
7. **Rollback capability**: Old container kept as `n8n-old-{timestamp}`

### Backup Strategy
- **Automatic retention**: Keeps last 5 backups, auto-deletes older ones
- **Backup format**: Compressed tar archives (`.tar.gz`)
- **Metadata tracking**: Each backup includes restoration instructions
- **Backup naming**: `n8n-backup-{timestamp}.tar.gz` or `n8n-backup-{custom-tag}.tar.gz`

### Error Handling
- All SSH commands validated with exit code checks
- Automatic rollback on container creation failure
- User confirmation before critical operations
- Detailed error messages with troubleshooting steps

## Script Parameters

### update-n8n.ps1
- `QnapHost` - QNAP IP (default: 192.168.50.246)
- `ContainerName` - Docker container name (default: n8n)
- `BackupBeforeUpdate` - Create backup first (default: $true)
- `SSHUser` - SSH username (default: admin)

### backup-n8n.ps1
- `QnapHost` - QNAP IP (default: 192.168.50.246)
- `ContainerName` - Docker container name (default: n8n)
- `BackupTag` - Custom backup identifier (default: timestamp)
- `BackupPath` - Remote backup directory (default: /share/Container/n8n-backups)
- `SSHUser` - SSH username (default: admin)

## Key Implementation Details

### Docker Container Recreation
The update script reconstructs the container with specific settings (lines 136-146 in update-n8n.ps1):
- Restart policy: `unless-stopped`
- Port mapping: `5678:5678`
- Volume mount: `/share/Container/n8n/.n8n:/home/node/.n8n`
- Environment variables:
  - `N8N_PROTOCOL=http`
  - `N8N_HOST=192.168.50.246`
  - `N8N_PORT=5678`

**Critical:** If the actual n8n container uses different environment variables or volumes, the `$recreateCommand` section must be updated before running the script.

### SSH Command Execution
Both scripts use the `Invoke-QnapSSH` function pattern:
- Commands executed remotely on QNAP via SSH
- Exit codes validated for error detection
- Output captured and displayed with color coding

### Backup Cleanup
The backup script automatically maintains backup count (lines 145-155 in backup-n8n.ps1):
- Sorts backups by timestamp (newest first)
- Keeps 5 most recent
- Removes older backups to prevent disk space issues

## Rollback Procedures

### Method 1: Use Renamed Container
```powershell
ssh admin@192.168.50.246
docker stop n8n
docker rm n8n
docker rename n8n-old-{timestamp} n8n
docker start n8n
```

### Method 2: Restore from Backup
```powershell
ssh admin@192.168.50.246
docker stop n8n
tar -xzf /share/Container/n8n-backups/n8n-backup-{timestamp}.tar.gz -C /share/Container/n8n/
docker start n8n
```

## Development Guidelines

### Testing Changes
- Always test SSH connectivity before making changes
- Verify container names match actual QNAP configuration
- Test with `-BackupBeforeUpdate $false` during development to speed up iterations
- Save `docker inspect` output to temp files for debugging

### Adding Features
- Follow the existing error handling pattern (exit codes, color-coded output)
- Maintain the backup-first philosophy for destructive operations
- Add user confirmation prompts for risky operations
- Update README.md with new parameters or functionality

### Security Considerations
- Never commit SSH credentials or keys
- SSH authentication relies on interactive password prompts
- Container inspection files saved to TEMP directory
- All sensitive data excluded via .gitignore

## Troubleshooting

### SSH Connection Failures
1. Verify QNAP SSH is enabled (Control Panel → Telnet/SSH)
2. Check QNAP IP is reachable: `Test-NetConnection 192.168.50.246 -Port 22`
3. Try manual SSH: `ssh admin@192.168.50.246`

### Container Not Found
- List all containers: `ssh admin@192.168.50.246 "docker ps -a"`
- Check Container Station is running on QNAP
- Verify container name matches (case-sensitive)

### Update Failures
- Check Docker logs: `ssh admin@192.168.50.246 "docker logs n8n"`
- Verify volume paths exist on QNAP
- Confirm port 5678 is not in use by another service
- Review `$recreateCommand` matches actual container config

### Backup Issues
- Ensure `/share/Container/n8n-backups/` directory exists
- Check QNAP disk space: `ssh admin@192.168.50.246 "df -h"`
- Verify permissions on backup directory

## Reference Links

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Docker Hub](https://hub.docker.com/r/n8nio/n8n)
- [QNAP Container Station](https://www.qnap.com/solution/container_station/)
