# n8n QNAP Docker Updater

Automated scripts to safely update your n8n Docker container running on QNAP NAS.

## 🎯 Overview

This project provides PowerShell scripts to:
- **Backup** your n8n data before updates
- **Update** n8n Docker container to the latest version
- **Rollback** to previous version if needed
- Preserve all your workflows, credentials, and settings

## 📋 Prerequisites

### On Your Windows Machine
- PowerShell 7.x (already installed)
- SSH client (built into Windows 10/11)

### On Your QNAP NAS
1. **Enable SSH Access**
   - Log into QNAP web interface
   - Go to `Control Panel` → `Telnet/SSH`
   - Check "Allow SSH connection"
   - Default port: 22

2. **Container Station**
   - Must have Container Station installed
   - Docker must be running
   - n8n container must be created and running

3. **Network Access**
   - Your QNAP must be accessible at `192.168.50.246`
   - Port 5678 open for n8n web interface
   - Port 22 open for SSH

## 🚀 Quick Start

### First Time Setup

1. **Test SSH Connection**
   ```powershell
   ssh admin@192.168.50.246
   ```
   Accept the host key fingerprint when prompted.

2. **Find Your n8n Container Name**
   ```powershell
   ssh admin@192.168.50.246 "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'"
   ```

### Running the Update

**Simple Update (with automatic backup):**
```powershell
.\update-n8n.ps1
```

**Update without backup (not recommended):**
```powershell
.\update-n8n.ps1 -BackupBeforeUpdate $false
```

**Update with custom container name:**
```powershell
.\update-n8n.ps1 -ContainerName "my-n8n-container"
```

**Update with custom SSH user:**
```powershell
.\update-n8n.ps1 -SSHUser "myusername"
```

## 📦 Backup Management

### Create Manual Backup

```powershell
.\backup-n8n.ps1
```

### Create Tagged Backup
```powershell
.\backup-n8n.ps1 -BackupTag "before-major-update"
```

### Backup Retention
- Automatically keeps the **last 5 backups**
- Older backups are automatically deleted
- Each backup includes metadata file with restoration instructions

### Backup Location
Backups are stored on your QNAP at:
```
/share/Container/n8n-backups/
```

## 🔧 Advanced Usage

### Custom QNAP Configuration

If your setup differs from defaults, modify these parameters:

```powershell
.\update-n8n.ps1 `
    -QnapHost "192.168.1.100" `
    -ContainerName "n8n-production" `
    -SSHUser "customuser"
```

### Checking Current n8n Version

SSH into your QNAP:
```bash
ssh admin@192.168.50.246
docker exec n8n n8n --version
```

### Manual Container Inspection

Get detailed container info:
```bash
ssh admin@192.168.50.246
docker inspect n8n
```

## 🛟 Rollback Procedures

### Method 1: Use Kept Container (Recommended)

After an update, the old container is renamed (not deleted). To rollback:

```powershell
# SSH into QNAP
ssh admin@192.168.50.246

# Stop new container
docker stop n8n

# Remove new container
docker rm n8n

# List old containers
docker ps -a | grep "n8n-old"

# Rename old container back
docker rename n8n-old-20241128-030000 n8n

# Start old container
docker start n8n
```

### Method 2: Restore from Backup

```powershell
# SSH into QNAP
ssh admin@192.168.50.246

# List available backups
ls -lh /share/Container/n8n-backups/

# Stop n8n container
docker stop n8n

# Restore backup (replace TIMESTAMP with your backup)
tar -xzf /share/Container/n8n-backups/n8n-backup-TIMESTAMP.tar.gz -C /share/Container/n8n/

# Start container
docker start n8n
```

## 📝 What Gets Updated

The update process:
1. ✅ **Pulls** latest n8n Docker image from Docker Hub
2. ✅ **Preserves** all data volumes (workflows, credentials, settings)
3. ✅ **Maintains** port mappings (5678)
4. ✅ **Keeps** environment variables
5. ✅ **Retains** restart policies

The update does **NOT** change:
- Your workflows
- Your credentials
- Your n8n settings
- External API connections
- Database connections

## 🔍 Troubleshooting

### SSH Connection Issues

**Error: Connection refused**
```powershell
# Solution: Enable SSH on QNAP
# Control Panel → Telnet/SSH → Enable SSH
```

**Error: Permission denied (publickey)**
```powershell
# Solution: Use password authentication
ssh -o PreferredAuthentications=password admin@192.168.50.246
```

### Container Issues

**Error: Container not found**
```powershell
# List all containers to find correct name
ssh admin@192.168.50.246 "docker ps -a"
```

**Error: Port already in use**
```powershell
# Check what's using port 5678
ssh admin@192.168.50.246 "netstat -tlnp | grep 5678"
```

### Update Issues

**Container won't start after update**
```powershell
# Check container logs
ssh admin@192.168.50.246 "docker logs n8n"

# Try rollback (see Rollback Procedures)
```

**n8n web interface not accessible**
```powershell
# Verify container is running
ssh admin@192.168.50.246 "docker ps | grep n8n"

# Check if port is mapped correctly
ssh admin@192.168.50.246 "docker port n8n"
```

## ⚠️ Important Notes

### Before Running Update Script

1. **Verify your n8n URL** is in the script (line 143):
   ```powershell
   -e N8N_HOST=192.168.50.246
   ```

2. **Check your data volume path** (line 141):
   ```powershell
   -v /share/Container/n8n/.n8n:/home/node/.n8n
   ```

3. **Important Environment Variables:**
   The script uses default values. If your setup has custom environment variables, you'll need to modify the `$recreateCommand` section in `update-n8n.ps1`.

### Customizing Container Settings

If your n8n container has special configurations (custom environment variables, additional volumes, etc.), you need to:

1. Run: `ssh admin@192.168.50.246 "docker inspect n8n > ~/n8n-config.json"`
2. Review the configuration
3. Update the `$recreateCommand` in `update-n8n.ps1` accordingly

## 📚 Additional Resources

- [n8n Official Documentation](https://docs.n8n.io/)
- [n8n Docker Hub](https://hub.docker.com/r/n8nio/n8n)
- [QNAP Container Station Guide](https://www.qnap.com/solution/container_station/)

## 🔐 Security Considerations

- SSH credentials are never stored in these scripts
- Always use SSH keys for authentication when possible
- Keep your QNAP firmware updated
- Regularly backup your n8n data
- Use strong passwords for n8n admin account

## 📄 Files in This Project

| File | Purpose |
|------|---------|
| `update-n8n.ps1` | Main update script with rollback capability |
| `backup-n8n.ps1` | Standalone backup script |
| `README.md` | This documentation |

## 🤝 Contributing

Found an issue or have improvements? Feel free to modify these scripts for your needs!

## 📞 Support

For n8n-specific issues:
- [n8n Community Forum](https://community.n8n.io/)
- [n8n GitHub Issues](https://github.com/n8n-io/n8n/issues)

For QNAP-specific issues:
- [QNAP Support](https://www.qnap.com/en/support/)

---

**Last Updated:** November 2024  
**n8n Instance:** http://192.168.50.246:5678  
**QNAP Management:** https://192.168.50.246:8443
