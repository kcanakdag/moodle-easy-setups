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
- Generate the config and start everything

## Non-Interactive Mode

For automation or if you know what you want:

```bash
# Deploy Moodle 4.0 on example.com port 80
./deploy.sh -v 4.0 -d example.com -p 80

# Deploy on custom port, bind to all interfaces
./deploy.sh -v 4.0 -d 192.168.1.100 -p 8080

# List available versions
./deploy.sh --list
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-v, --version` | Moodle version (e.g., 4.0) | interactive |
| `-d, --domain` | Domain or IP address | localhost |
| `-p, --port` | Port number | 8000 |
| `-s, --https` | Use HTTPS in wwwroot | no |
| `-b, --bind` | Bind address | 0.0.0.0 |
| `-l, --list` | List available versions | - |
| `-h, --help` | Show help | - |

## After Deployment

Once running, you'll see:
- **Moodle**: `http://your-domain:port`
- **Mailpit** (catches all emails): `http://your-domain:8025`

First visit will launch the Moodle installer. Database is pre-configured.

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

## Available Versions

- `4.0` - Moodle 4.0.x (PHP 8.0)

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

- Linux VPS (Ubuntu, Debian, CentOS, RHEL, Fedora, etc.)
- Docker (script will install if missing)
- Git

## Notes

- This is for **testing only**, not production
- Default DB password is in the compose file — fine for testing
- The script modifies `config.php` and `docker-compose.yml` in the selected version folder

## License

MIT
