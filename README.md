# Moodle Easy Setups

Spin up a Moodle test instance on any VPS in minutes. Pull the repo, run the script, done.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/kcanakdag/moodle-easy-setups.git
cd moodle-easy-setups

# Run the deployment script (interactive)
./deploy.sh
```

That's it. The script will:
- Check if Docker is installed (and offer to install it if not)
- Let you pick a Moodle version
- Ask for your domain/IP and port
- Configure Caddy for HTTP or HTTPS (with automatic SSL)
- Generate the config and start everything

## Non-Interactive Mode

For automation or if you know what you want:

```bash
# Deploy Moodle 4.5 with HTTPS on your domain
./deploy.sh -v 4.5 -d moodle.example.com -p 443 -s

# Deploy Moodle 4.0 on your domain (port 80 for clean URLs)
./deploy.sh -v 4.0 -d moodletest.example.com -p 80

# Deploy on a custom port
./deploy.sh -v 4.0 -d example.com -p 8080

# Deploy using just an IP address
./deploy.sh -v 4.0 -d 192.168.1.100 -p 8000

# List available versions
./deploy.sh --list

# Check current deployment status
./deploy.sh --status
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-v, --version` | Moodle version (e.g., 4.0) | interactive |
| `-d, --domain` | Domain or IP address | auto-detected public IP |
| `-p, --port` | Port number | 8000 |
| `-s, --https` | Use HTTPS in wwwroot | no |
| `-b, --bind` | Bind address | 0.0.0.0 |
| `--admin-user` | Admin username | admin |
| `--admin-pass` | Admin password | Moodle123! |
| `--admin-email` | Admin email | admin@example.com |
| `-l, --list` | List available versions | - |
| `--status` | Show deployment status | - |
| `-h, --help` | Show help | - |

## Using a Domain Name

To access Moodle via a domain like `http://moodle.example.com/`:

1. Point your DNS A record to your server's IP address
2. Deploy with port 80:
   ```bash
   ./deploy.sh -v 4.0 -d moodle.example.com -p 80
   ```
3. Make sure port 80 is open in your firewall:
   ```bash
   sudo ufw allow 80/tcp
   ```

If you use a custom port (e.g., 8000), you'll need to include it in the URL: `http://moodle.example.com:8000/`

## After Deployment

Once running, you'll see:
- **Moodle**: `http://your-domain:port` (or just `http://your-domain` if using port 80)
- **Mailpit** (catches all emails): `http://your-domain:8025`

First visit will launch the Moodle installer. Database is pre-configured with:
- Type: PostgreSQL
- Host: `db`
- Database: `moodle`
- User: `moodle`
- Password: `m@0dl3ing`

## Managing Your Instance

```bash
cd versions/4.0  # or whichever version you deployed

# View logs
docker compose logs -f

# Stop Moodle
docker compose down

# Start Moodle
docker compose up -d

# Full reset (removes all data)
docker compose down -v
```

Or re-run `./deploy.sh` in interactive mode to get a menu with restart/stop/reset options.

## Firewall Configuration

If you can't access Moodle from outside, check your firewall:

```bash
# Ubuntu/Debian with UFW
sudo ufw allow 80/tcp    # or your chosen port
sudo ufw allow 8025/tcp  # Mailpit UI (optional)

# CentOS/RHEL with firewalld
sudo firewall-cmd --add-port=80/tcp --permanent
sudo firewall-cmd --reload
```

## Available Versions

- `4.0` - Moodle 4.0.x (PHP 8.0)
- `4.5` - Moodle 4.5.x (PHP 8.3)

More versions coming. To add your own, create a folder in `versions/` with the same structure.

## Project Structure

```
.
├── deploy.sh              # Main deployment script
├── versions/
│   └── 4.0/
│       ├── docker-compose.yml
│       └── moodle/        # Moodle source code
```

## Requirements

- Linux VPS (Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky, AlmaLinux)
- Docker (script will install if missing)
- Git
- Root/sudo access (for Docker installation and port 80)

## Troubleshooting

**Can't access via domain but IP:port works?**
- Make sure DNS is pointing to the correct IP: `nslookup yourdomain.com`
- Use port 80 for clean URLs, or include the port in the URL
- Check firewall allows the port

**Permission errors?**
```bash
sudo chown -R www-data:www-data versions/4.0/moodle
```

**Container won't start?**
```bash
cd versions/4.0
docker compose logs
```

## Notes

- This is for **testing only**, not production
- Default DB password is in the compose file — fine for testing
- The script modifies `config.php` in the selected version folder

## License

MIT
