#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_DIR="$SCRIPT_DIR/versions"

# Default values
DEFAULT_PORT=8000
DEFAULT_DOMAIN="localhost"
DEFAULT_PROTOCOL="http"

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║       Moodle Docker Deployment           ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Docker is installed
check_docker() {
    log_info "Checking Docker installation..."
    
    if command -v docker &> /dev/null; then
        log_success "Docker is installed: $(docker --version)"
        return 0
    fi
    
    log_warn "Docker is not installed."
    read -p "Would you like to install Docker? (y/n): " install_docker
    
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        install_docker
    else
        log_error "Docker is required. Exiting."
        exit 1
    fi
}

install_docker() {
    log_info "Installing Docker..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "Cannot detect OS. Please install Docker manually."
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            log_info "Detected $OS - Installing via apt..."
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|fedora|rocky|almalinux)
            log_info "Detected $OS - Installing via dnf/yum..."
            sudo dnf -y install dnf-plugins-core || sudo yum -y install yum-utils
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || \
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || \
                sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            log_warn "Unsupported OS: $OS"
            log_info "Attempting generic install script..."
            curl -fsSL https://get.docker.com | sudo sh
            ;;
    esac
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    if ! groups | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warn "Added $USER to docker group. You may need to log out and back in."
    fi
    
    log_success "Docker installed successfully!"
}

# Check Docker Compose
check_docker_compose() {
    log_info "Checking Docker Compose..."
    
    if docker compose version &> /dev/null; then
        log_success "Docker Compose (plugin) is available"
        COMPOSE_CMD="docker compose"
        return 0
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose (standalone) is available"
        COMPOSE_CMD="docker-compose"
        return 0
    fi
    
    log_error "Docker Compose not found. Please install it."
    exit 1
}

# List available versions
list_versions() {
    local versions=()
    for dir in "$VERSIONS_DIR"/*/; do
        if [ -d "$dir" ]; then
            versions+=("$(basename "$dir")")
        fi
    done
    echo "${versions[@]}"
}

# Select version interactively
select_version() {
    local versions=($(list_versions))
    
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "No Moodle versions found in $VERSIONS_DIR"
        exit 1
    fi
    
    echo -e "\n${BLUE}Available Moodle versions:${NC}"
    for i in "${!versions[@]}"; do
        echo "  $((i+1))) ${versions[$i]}"
    done
    
    while true; do
        read -p "Select version (1-${#versions[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#versions[@]} ]; then
            SELECTED_VERSION="${versions[$((choice-1))]}"
            break
        fi
        log_warn "Invalid selection. Try again."
    done
    
    log_success "Selected Moodle $SELECTED_VERSION"
}


# Get deployment configuration from user
get_config() {
    echo -e "\n${BLUE}Deployment Configuration:${NC}"
    
    # Domain/IP
    read -p "Enter domain or IP (default: $DEFAULT_DOMAIN): " input_domain
    DOMAIN="${input_domain:-$DEFAULT_DOMAIN}"
    
    # Port
    read -p "Enter port (default: $DEFAULT_PORT): " input_port
    PORT="${input_port:-$DEFAULT_PORT}"
    
    # Protocol
    read -p "Use HTTPS? (y/n, default: n): " use_https
    if [[ "$use_https" =~ ^[Yy]$ ]]; then
        PROTOCOL="https"
    else
        PROTOCOL="http"
    fi
    
    # Build wwwroot
    if [ "$PORT" = "80" ] || [ "$PORT" = "443" ]; then
        WWWROOT="${PROTOCOL}://${DOMAIN}"
    else
        WWWROOT="${PROTOCOL}://${DOMAIN}:${PORT}"
    fi
    
    # Bind to all interfaces?
    read -p "Bind to all interfaces (0.0.0.0)? Required for external access (y/n, default: y): " bind_all
    if [[ "$bind_all" =~ ^[Nn]$ ]]; then
        BIND_ADDRESS="127.0.0.1"
    else
        BIND_ADDRESS="0.0.0.0"
    fi
    
    echo -e "\n${BLUE}Configuration Summary:${NC}"
    echo "  Version:  Moodle $SELECTED_VERSION"
    echo "  URL:      $WWWROOT"
    echo "  Bind:     $BIND_ADDRESS:$PORT"
    echo ""
    
    read -p "Proceed with deployment? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled."
        exit 0
    fi
}

# Generate config.php
generate_config() {
    local version_dir="$VERSIONS_DIR/$SELECTED_VERSION"
    local config_file="$version_dir/moodle/config.php"
    
    log_info "Generating config.php..."
    
    cat > "$config_file" << EOF
<?php  // Moodle configuration file - Generated by deploy.sh

unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'pgsql';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'db';
\$CFG->dbname    = 'moodle';
\$CFG->dbuser    = 'moodle';
\$CFG->dbpass    = 'm@0dl3ing';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array (
  'dbpersist' => 0,
  'dbport' => 5432,
  'dbsocket' => '',
);

\$CFG->wwwroot   = '$WWWROOT';
\$CFG->dataroot  = '/var/www/moodledata';
\$CFG->admin     = 'admin';

\$CFG->directorypermissions = 0777;

require_once(__DIR__ . '/lib/setup.php');

// There is no php closing tag in this file,
// it is intentional because it prevents trailing whitespace problems!
EOF

    log_success "config.php generated"
}

# Update docker-compose port binding
update_docker_compose() {
    local version_dir="$VERSIONS_DIR/$SELECTED_VERSION"
    local compose_file="$version_dir/docker-compose.yml"
    
    log_info "Updating docker-compose.yml port binding..."
    
    # Use sed to update the port binding for the web service
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed
        sed -i '' "s|\"127.0.0.1:8000:80\"|\"${BIND_ADDRESS}:${PORT}:80\"|g" "$compose_file"
        sed -i '' "s|\"0.0.0.0:[0-9]*:80\"|\"${BIND_ADDRESS}:${PORT}:80\"|g" "$compose_file"
    else
        # Linux sed
        sed -i "s|\"127.0.0.1:8000:80\"|\"${BIND_ADDRESS}:${PORT}:80\"|g" "$compose_file"
        sed -i "s|\"0.0.0.0:[0-9]*:80\"|\"${BIND_ADDRESS}:${PORT}:80\"|g" "$compose_file"
    fi
    
    log_success "docker-compose.yml updated"
}

# Deploy Moodle
deploy() {
    local version_dir="$VERSIONS_DIR/$SELECTED_VERSION"
    
    log_info "Starting deployment..."
    
    cd "$version_dir"
    
    # Stop existing containers if running
    $COMPOSE_CMD down 2>/dev/null || true
    
    # Pull latest images
    log_info "Pulling Docker images..."
    $COMPOSE_CMD pull
    
    # Start containers
    log_info "Starting containers..."
    $COMPOSE_CMD up -d
    
    # Wait for services
    log_info "Waiting for services to be ready..."
    sleep 5
    
    # Check if containers are running
    if $COMPOSE_CMD ps | grep -q "Up"; then
        log_success "Containers are running!"
    else
        log_error "Some containers failed to start. Check logs with: docker compose logs"
        exit 1
    fi
    
    echo -e "\n${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Moodle URL:    ${BLUE}$WWWROOT${NC}"
    echo -e "  Mailpit UI:    ${BLUE}http://${DOMAIN}:8025${NC}"
    echo ""
    echo -e "  ${YELLOW}First time? Run the Moodle installer at the URL above.${NC}"
    echo ""
    echo -e "  Useful commands (run from $version_dir):"
    echo "    $COMPOSE_CMD logs -f      # View logs"
    echo "    $COMPOSE_CMD down         # Stop Moodle"
    echo "    $COMPOSE_CMD up -d        # Start Moodle"
    echo ""
}

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION   Moodle version to deploy (e.g., 4.0)"
    echo "  -d, --domain DOMAIN     Domain or IP address (default: localhost)"
    echo "  -p, --port PORT         Port number (default: 8000)"
    echo "  -s, --https             Use HTTPS protocol"
    echo "  -b, --bind ADDRESS      Bind address (default: 0.0.0.0)"
    echo "  -l, --list              List available versions"
    echo "  -h, --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 -v 4.0 -d example.com -p 80       # Non-interactive"
    echo "  $0 --list                             # List versions"
}

# Parse command line arguments
parse_args() {
    INTERACTIVE=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                SELECTED_VERSION="$2"
                INTERACTIVE=false
                shift 2
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -s|--https)
                PROTOCOL="https"
                shift
                ;;
            -b|--bind)
                BIND_ADDRESS="$2"
                shift 2
                ;;
            -l|--list)
                echo "Available versions:"
                for v in $(list_versions); do
                    echo "  - $v"
                done
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set defaults for non-interactive mode
    DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
    PORT="${PORT:-$DEFAULT_PORT}"
    PROTOCOL="${PROTOCOL:-$DEFAULT_PROTOCOL}"
    BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
    
    # Build wwwroot
    if [ "$PORT" = "80" ] || [ "$PORT" = "443" ]; then
        WWWROOT="${PROTOCOL}://${DOMAIN}"
    else
        WWWROOT="${PROTOCOL}://${DOMAIN}:${PORT}"
    fi
}

# Main
main() {
    print_banner
    parse_args "$@"
    
    check_docker
    check_docker_compose
    
    if [ "$INTERACTIVE" = true ]; then
        select_version
        get_config
    else
        # Validate version exists
        if [ ! -d "$VERSIONS_DIR/$SELECTED_VERSION" ]; then
            log_error "Version $SELECTED_VERSION not found"
            exit 1
        fi
        log_info "Deploying Moodle $SELECTED_VERSION to $WWWROOT"
    fi
    
    generate_config
    update_docker_compose
    deploy
}

main "$@"
