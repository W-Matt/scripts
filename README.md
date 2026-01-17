# Aurral Proxmox LXC Installation Script

Automated deployment script for installing [Aurral](https://github.com/lklynet/aurral) (music scrobbling and streaming service) in a Proxmox LXC container.

## Features

- ✅ Automated Ubuntu 24.04 LXC container creation
- ✅ Docker and Docker Compose installation
- ✅ Aurral repository cloning and setup
- ✅ Proper container configuration for Docker (nesting, AppArmor)
- ✅ Interactive configuration wizard
- ✅ Environment file (.env) creation
- ✅ Automatic service startup

## Prerequisites

- Proxmox VE 7.x or 8.x
- Root access to Proxmox host
- Internet connection for downloading templates and packages
- Available storage pool (default: `local-lvm`)
- Available network bridge (default: `vmbr0`)

## Quick Start

### Automated Installation (One Command)

Run this single command on your Proxmox host to create and configure the Aurral LXC container:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/W-Matt/scripts/main/ct/aurral.sh)"
```

**That's it!** The script will:
- ✅ Create an Ubuntu 24.04 LXC container
- ✅ Configure it for Docker (nesting, AppArmor)
- ✅ Install Docker and Docker Compose V2
- ✅ Clone and setup Aurral
- ✅ Start the service automatically

### Default Configuration

The script uses these defaults:
- **Container ID**: Next available (auto-detected)
- **Hostname**: aurral
- **Disk Size**: 8GB
- **CPU Cores**: 2
- **Memory**: 2048MB
- **Network**: DHCP on vmbr0
- **Start on Boot**: Yes

### Access Aurral

After installation completes (2-3 minutes), access Aurral at:
```
http://CONTAINER_IP:8080
```

The IP address will be displayed at the end of installation.

## Configuration

### Environment Variables

The script creates `/opt/aurral/.env` with basic configuration. To customize:

```bash
# Enter the container
pct enter CTID

# Edit environment file
nano /opt/aurral/.env

# Restart Aurral
cd /opt/aurral
docker compose restart
```

### Last.fm Integration

To enable Last.fm scrobbling:

1. Get API credentials from https://www.last.fm/api/account/create
2. Edit `.env` file:
   ```bash
   LASTFM_API_KEY=your_api_key_here
   LASTFM_API_SECRET=your_api_secret_here
   ```
3. Restart the service:
   ```bash
   cd /opt/aurral
   docker compose restart
   ```

### Media Directory

By default, media files should be placed in `/opt/aurral/media`

To mount an external storage location:

```bash
# On Proxmox host
pct set CTID -mp0 /mnt/media,mp=/opt/aurral/media

# Then restart the container
pct restart CTID
```

## Management Commands

### Access Container Shell
```bash
pct enter CTID
```

### View Aurral Logs
```bash
pct exec CTID -- docker compose -f /opt/aurral/docker-compose.yml logs -f
```

### Stop/Start Aurral
```bash
# Stop
pct exec CTID -- docker compose -f /opt/aurral/docker-compose.yml stop

# Start
pct exec CTID -- docker compose -f /opt/aurral/docker-compose.yml start

# Restart
pct exec CTID -- docker compose -f /opt/aurral/docker-compose.yml restart
```

### Update Aurral

The script includes a built-in update function:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/W-Matt/scripts/main/ct/aurral.sh)" -s update
```

Or manually:
```bash
pct enter CTID
cd /opt/aurral
git pull
docker compose pull
docker compose up -d
```

### Stop/Start Container
```bash
# Stop
pct stop CTID

# Start
pct start CTID

# Restart
pct restart CTID
```

## Resource Allocation

### Recommended Specifications

| Use Case | CPU | RAM | Disk |
|----------|-----|-----|------|
| Light (< 1000 tracks) | 1 core | 1GB | 4GB |
| Medium (< 10000 tracks) | 2 cores | 2GB | 8GB |
| Heavy (> 10000 tracks) | 4 cores | 4GB | 16GB |

### Adjust Resources

```bash
# CPU
pct set CTID -cores 4

# Memory
pct set CTID -memory 4096

# Disk resize (GB)
pct resize CTID rootfs +8G
```

## Troubleshooting

### Docker Not Starting

If Docker fails to start inside the container:

1. Check container configuration:
   ```bash
   cat /etc/pve/lxc/CTID.conf
   ```

2. Ensure these lines are present:
   ```
   lxc.apparmor.profile: unconfined
   lxc.cgroup2.devices.allow: a
   lxc.cap.drop:
   features: nesting=1
   ```

3. Restart container:
   ```bash
   pct restart CTID
   ```

### Permission Denied Errors

If you encounter `pivot_root` errors:

1. The script already configures the container properly
2. If issues persist, check Proxmox kernel version:
   ```bash
   pveversion
   ```
3. Update Proxmox if needed

### Cannot Access Web Interface

1. Check if Aurral is running:
   ```bash
   pct exec CTID -- docker compose -f /opt/aurral/docker-compose.yml ps
   ```

2. Check firewall rules on Proxmox host

3. Verify IP address:
   ```bash
   pct exec CTID -- hostname -I
   ```

### Container Won't Start

1. Check container logs:
   ```bash
   pct status CTID
   journalctl -u pve-container@CTID
   ```

2. Verify storage pool has space:
   ```bash
   pvesm status
   ```

## Uninstallation

To completely remove Aurral:

```bash
# Stop and destroy container
pct stop CTID
pct destroy CTID

# Verify removal
pct list
```

## Advanced Configuration

### Using Custom Docker Compose File

The script uses the default `docker-compose.yml`. To use the development version:

```bash
pct enter CTID
cd /opt/aurral
docker compose -f docker-compose.dev.yml up -d
```

### Backup Container

```bash
# Create backup
vzdump CTID --mode snapshot --storage local

# List backups
ls -lh /var/lib/vz/dump/
```

### Restore from Backup

```bash
pct restore CTID /var/lib/vz/dump/vzdump-lxc-CTID-*.tar.zst --storage local-lvm
```

## Security Considerations

- The container runs as **unprivileged** by default for better security
- AppArmor is disabled for Docker compatibility
- Default password is randomly generated
- Consider using a reverse proxy (Nginx Proxy Manager, Traefik) for SSL

### Setting Up SSL with Nginx Proxy Manager

1. Install Nginx Proxy Manager in another container
2. Create a proxy host pointing to `aurral:8080`
3. Enable SSL with Let's Encrypt
4. Access via `https://aurral.yourdomain.com`

## Support

- **Aurral GitHub**: https://github.com/lklynet/aurral
- **Proxmox Documentation**: https://pve.proxmox.com/pve-docs/
- **Docker Documentation**: https://docs.docker.com/

## License

This script is provided as-is for use with Proxmox and Aurral.

## Credits

- Aurral project by lklynet
- Script created for Bob's home lab deployment
