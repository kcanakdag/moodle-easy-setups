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
DEFAULT_PROTOCOL="http"

# Auto-detect public IP
detect_public_ip() {
    local ip=""
    # Try multiple services in case one is down
    ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s --max-time 3 icanhazip.com 2>/dev/null) || \
    ip=$(curl -s --max-time 3 ipecho.net/plain 2>/dev/null) || \
    ip="localhost"
    echo "$ip"
}

DEFAULT_DOMAIN="$(detect_public_ip)"

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

# Detect existing deployment
detect_existing_deployment() {
    local found_version=""
    local found_wwwroot=""
    local is_running=false
    
    for dir in "$VERSIONS_DIR"/*/; do
        if [ -d "$dir" ]; then
            local version=$(basename "$dir")
            local config_file="$dir/moodle/config.php"
            
            # Check if config.php exists and has wwwroot
            if [ -f "$config_file" ]; then
                found_wwwroot=$(grep -oP "\\\$CFG->wwwroot\s*=\s*'\K[^']+" "$config_file" 2>/dev/null || true)
                if [ -n "$found_wwwroot" ]; then
                    found_version="$version"
                    
                    # Check if containers are running
                    cd "$dir"
                    if docker compose ps 2>/dev/null | grep -q "Up"; then
                        is_running=true
                    fi
                    cd - > /dev/null
                    break
                fi
            fi
        fi
    done
    
    if [ -n "$found_version" ]; then
        echo "$found_version|$found_wwwroot|$is_running"
    fi
}

# Handle existing deployment
handle_existing_deployment() {
    local existing=$(detect_existing_deployment)
    
    if [ -z "$existing" ]; then
        return 1  # No existing deployment
    fi
    
    local version=$(echo "$existing" | cut -d'|' -f1)
    local wwwroot=$(echo "$existing" | cut -d'|' -f2)
    local running=$(echo "$existing" | cut -d'|' -f3)
    
    echo -e "\n${YELLOW}Existing deployment detected:${NC}"
    echo "  Version: Moodle $version"
    echo "  URL:     $wwwroot"
    if [ "$running" = "true" ]; then
        echo -e "  Status:  ${GREEN}Running${NC}"
    else
        echo -e "  Status:  ${RED}Stopped${NC}"
    fi
    echo ""
    
    echo "What would you like to do?"
    echo "  1) Reconfigure (change domain/port)"
    echo "  2) Restart containers"
    echo "  3) Stop containers"
    echo "  4) Full reset (delete data and redeploy)"
    echo "  5) Deploy a different version"
    echo "  6) Exit"
    echo ""
    
    while true; do
        read -p "Select option (1-6): " choice
        case $choice in
            1)
                SELECTED_VERSION="$version"
                return 1  # Continue with normal config flow
                ;;
            2)
                SELECTED_VERSION="$version"
                cd "$VERSIONS_DIR/$version"
                log_info "Restarting containers..."
                $COMPOSE_CMD restart
                log_success "Containers restarted!"
                echo -e "\n  Moodle URL: ${BLUE}$wwwroot${NC}"
                exit 0
                ;;
            3)
                cd "$VERSIONS_DIR/$version"
                log_info "Stopping containers..."
                $COMPOSE_CMD down
                log_success "Containers stopped."
                exit 0
                ;;
            4)
                SELECTED_VERSION="$version"
                cd "$VERSIONS_DIR/$version"
                log_warn "This will delete all Moodle data!"
                read -p "Are you sure? (yes/no): " confirm
                if [ "$confirm" = "yes" ]; then
                    log_info "Removing containers and volumes..."
                    $COMPOSE_CMD down -v
                    log_success "Reset complete."
                    return 1  # Continue with fresh deploy
                else
                    log_info "Cancelled."
                    exit 0
                fi
                ;;
            5)
                return 1  # Continue with version selection
                ;;
            6)
                exit 0
                ;;
            *)
                log_warn "Invalid selection. Try again."
                ;;
        esac
    done
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
    
    # Domain/IP (show detected IP)
    if [ "$DEFAULT_DOMAIN" != "localhost" ]; then
        log_info "Detected public IP: $DEFAULT_DOMAIN"
    fi
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

# Generate .env file for docker-compose
generate_env_file() {
    local version_dir="$VERSIONS_DIR/$SELECTED_VERSION"
    local env_file="$version_dir/.env"
    
    log_info "Generating .env file..."
    
    cat > "$env_file" << EOF
# Generated by deploy.sh
BIND_ADDRESS=${BIND_ADDRESS}
WEB_PORT=${PORT}
MAILPIT_UI_PORT=8025
MAILPIT_SMTP_PORT=1025
EOF

    log_success ".env file generated"
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
    echo "  -d, --domain DOMAIN     Domain or IP address (default: auto-detected public IP)"
    echo "  -p, --port PORT         Port number (default: 8000)"
    echo "  -s, --https             Use HTTPS protocol"
    echo "  -b, --bind ADDRESS      Bind address (default: 0.0.0.0)"
    echo "  -l, --list              List available versions"
    echo "  --status                Show current deployment status"
    echo "  -h, --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 -v 4.0 -d example.com -p 80       # Non-interactive"
    echo "  $0 --list                             # List versions"
    echo "  $0 --status                           # Check deployment status"
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
            --status)
                check_docker_compose
                existing=$(detect_existing_deployment)
                if [ -z "$existing" ]; then
                    echo "No deployment found."
                else
                    version=$(echo "$existing" | cut -d'|' -f1)
                    wwwroot=$(echo "$existing" | cut -d'|' -f2)
                    running=$(echo "$existing" | cut -d'|' -f3)
                    echo "Version: Moodle $version"
                    echo "URL:     $wwwroot"
                    if [ "$running" = "true" ]; then
                        echo "Status:  Running"
                    else
                        echo "Status:  Stopped"
                    fi
                fi
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
        # Check for existing deployment first
        if handle_existing_deployment; then
            exit 0  # Handled by the function
        fi
        
        # If no version selected yet (new deploy or "deploy different version")
        if [ -z "$SELECTED_VERSION" ]; then
            select_version
        fi
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
    generate_env_file
    deploy
}

main "$@"
