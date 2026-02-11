#!/bin/bash

################################################################################
# OpenClaw Automated Deployment Script
# Supports: Local, VPS, Docker, and Cloud Platform deployments
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
NODE_VERSION="${NODE_VERSION:-22}"
INSTALL_METHOD="${INSTALL_METHOD:-npm}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-local}"
AUTO_START_DAEMON="${AUTO_START_DAEMON:-true}"
MIN_DISK_GB="${MIN_DISK_GB:-2}"  # Minimum disk space required (in GB), can be overridden
MIN_RAM_GB="${MIN_RAM_GB:-1}"    # Minimum RAM recommended (in GB), can be overridden
NON_INTERACTIVE="${NON_INTERACTIVE:-true}"  # Run without prompts (default: true)
SKIP_ONBOARDING="${SKIP_ONBOARDING:-false}"  # Skip interactive onboarding (default: false)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (needed for some operations)
check_root() {
    if [[ $EUID -eq 0 ]] && [[ "$ALLOW_ROOT" != "true" ]]; then 
        log_warning "Running as root. Use ALLOW_ROOT=true to proceed anyway."
        exit 1
    fi
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ANTHROPIC_API_KEY=*)
                export ANTHROPIC_API_KEY="${1#*=}"
                shift
                ;;
            --ANTHROPIC_API_KEY)
                export ANTHROPIC_API_KEY="$2"
                shift 2
                ;;
            --GEMINI_API_KEY=*)
                export GEMINI_API_KEY="${1#*=}"
                shift
                ;;
            --GEMINI_API_KEY)
                export GEMINI_API_KEY="$2"
                shift 2
                ;;
            --OPENAI_API_KEY=*)
                export OPENAI_API_KEY="${1#*=}"
                shift
                ;;
            --OPENAI_API_KEY)
                export OPENAI_API_KEY="$2"
                shift 2
                ;;
            --GROQ_API_KEY=*)
                export GROQ_API_KEY="${1#*=}"
                shift
                ;;
            --GROQ_API_KEY)
                export GROQ_API_KEY="$2"
                shift 2
                ;;
            --XAI_API_KEY=*)
                export XAI_API_KEY="${1#*=}"
                shift
                ;;
            --XAI_API_KEY)
                export XAI_API_KEY="$2"
                shift 2
                ;;
            --MISTRAL_API_KEY=*)
                export MISTRAL_API_KEY="${1#*=}"
                shift
                ;;
            --MISTRAL_API_KEY)
                export MISTRAL_API_KEY="$2"
                shift 2
                ;;
            --OPENROUTER_API_KEY=*)
                export OPENROUTER_API_KEY="${1#*=}"
                shift
                ;;
            --OPENROUTER_API_KEY)
                export OPENROUTER_API_KEY="$2"
                shift 2
                ;;
            --GATEWAY_PORT=*)
                export GATEWAY_PORT="${1#*=}"
                shift
                ;;
            --GATEWAY_PORT)
                export GATEWAY_PORT="$2"
                shift 2
                ;;
            --INSTALL_METHOD=*)
                export INSTALL_METHOD="${1#*=}"
                shift
                ;;
            --INSTALL_METHOD)
                export INSTALL_METHOD="$2"
                shift 2
                ;;
            --DEPLOYMENT_TYPE=*)
                export DEPLOYMENT_TYPE="${1#*=}"
                shift
                ;;
            --DEPLOYMENT_TYPE)
                export DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            --MIN_DISK_GB=*)
                export MIN_DISK_GB="${1#*=}"
                shift
                ;;
            --MIN_DISK_GB)
                export MIN_DISK_GB="$2"
                shift 2
                ;;
            --NON_INTERACTIVE=*)
                export NON_INTERACTIVE="${1#*=}"
                shift
                ;;
            --NON_INTERACTIVE)
                export NON_INTERACTIVE="$2"
                shift 2
                ;;
            --SKIP_ONBOARDING=*)
                export SKIP_ONBOARDING="${1#*=}"
                shift
                ;;
            --SKIP_ONBOARDING)
                export SKIP_ONBOARDING="$2"
                shift 2
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                log_warning "Unknown argument: $1"
                shift
                ;;
        esac
    done
}

# Print usage information
print_usage() {
    cat << EOF
OpenClaw Automated Deployment Script

Usage: ./deploy-openclaw.sh [OPTIONS]

API Keys (at least one required):
  --ANTHROPIC_API_KEY=<key>       Anthropic API key
  --GEMINI_API_KEY=<key>          Google Gemini API key
  --OPENAI_API_KEY=<key>          OpenAI API key
  --GROQ_API_KEY=<key>            Groq API key
  --XAI_API_KEY=<key>             xAI API key
  --MISTRAL_API_KEY=<key>         Mistral API key
  --OPENROUTER_API_KEY=<key>      OpenRouter API key

Configuration:
  --INSTALL_METHOD=<method>       npm (default), script, or docker
  --DEPLOYMENT_TYPE=<type>        local (default), vps, or docker
  --GATEWAY_PORT=<port>           Gateway port (default: 18789)
  --MIN_DISK_GB=<gb>              Minimum disk space (default: 2)
  --NON_INTERACTIVE=true|false    Run without prompts (default: true)
  --SKIP_ONBOARDING=true|false    Skip interactive setup (default: false)

Examples:
  # Using Anthropic
  ./deploy-openclaw.sh --ANTHROPIC_API_KEY=sk-ant-...

  # Using Google Gemini
  ./deploy-openclaw.sh --GEMINI_API_KEY=AIzaSy...

  # Using OpenAI with custom port
  ./deploy-openclaw.sh --OPENAI_API_KEY=sk-... --GATEWAY_PORT=8080

  # Docker deployment
  ./deploy-openclaw.sh --INSTALL_METHOD=docker --GEMINI_API_KEY=AIzaSy...

  # Low-resource environment
  ./deploy-openclaw.sh --ANTHROPIC_API_KEY=sk-ant-... --MIN_DISK_GB=1

Help:
  ./deploy-openclaw.sh --help
EOF
}

# Detect OS
detect_os() {
    log_info "Detecting operating system..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
            DISTRO="ubuntu"
        elif grep -q "Debian" /etc/os-release 2>/dev/null; then
            DISTRO="debian"
        elif grep -q "CentOS\|Red Hat" /etc/os-release 2>/dev/null; then
            DISTRO="rhel"
        else
            DISTRO="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        DISTRO="macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        OS="windows"
        DISTRO="windows"
        log_warning "Windows detected. Consider using WSL2 for best compatibility."
    else
        OS="unknown"
        DISTRO="unknown"
    fi
    
    log_success "Detected OS: $OS ($DISTRO)"
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check RAM
    if [[ "$OS" == "linux" ]]; then
        TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
        if [[ $TOTAL_RAM -lt $MIN_RAM_GB ]]; then
            log_warning "RAM is less than ${MIN_RAM_GB}GB. Consider adding swap space or setting MIN_RAM_GB to a lower value."
            NEED_SWAP=true
        fi
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ -z "$AVAILABLE_SPACE" ]] || ! [[ "$AVAILABLE_SPACE" =~ ^[0-9]+$ ]]; then
        log_warning "Could not determine available disk space. Proceeding anyway."
    elif [[ $AVAILABLE_SPACE -lt $MIN_DISK_GB ]]; then
        log_error "Insufficient disk space. Need at least ${MIN_DISK_GB}GB available, but only ${AVAILABLE_SPACE}GB found."
        log_info "To override, set: export MIN_DISK_GB=${AVAILABLE_SPACE}"
        exit 1
    else
        log_success "Disk space check passed (${AVAILABLE_SPACE}GB available)"
    fi
    
    log_success "System requirements check passed"
}

# Install Node.js if needed
install_node() {
    log_info "Checking Node.js installation..."
    
    if command -v node &> /dev/null; then
        NODE_CURRENT=$(node -v | sed 's/v//' | cut -d. -f1)
        if [[ $NODE_CURRENT -ge $NODE_VERSION ]]; then
            log_success "Node.js $NODE_CURRENT is already installed"
            return
        else
            log_warning "Node.js version $NODE_CURRENT is too old. Need version $NODE_VERSION+"
        fi
    fi
    
    log_info "Installing Node.js $NODE_VERSION..."
    
    if [[ "$OS" == "linux" ]]; then
        # Use NodeSource repository with non-interactive flags
        curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - || true
        
        # Non-interactive apt install
        export DEBIAN_FRONTEND=noninteractive
        sudo -n apt-get update -y > /dev/null 2>&1 || apt-get update -y > /dev/null 2>&1
        sudo -n apt-get install -y -o Dpkg::Pre-Install-Pkgs::=/bin/true -o Dpkg::Post-Install-Pkgs::=/bin/true nodejs > /dev/null 2>&1 || \
        apt-get install -y nodejs > /dev/null 2>&1
    elif [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew install node@${NODE_VERSION} -y > /dev/null 2>&1 || brew install node@${NODE_VERSION} > /dev/null 2>&1
        else
            log_error "Homebrew not found. Please install Node.js manually."
            exit 1
        fi
    fi
    
    log_success "Node.js installed successfully"
}

# Setup swap space if needed
setup_swap() {
    if [[ "$NEED_SWAP" == "true" ]] && [[ "$OS" == "linux" ]]; then
        log_info "Setting up 4GB swap space..."
        
        if [[ ! -f /swapfile ]]; then
            if sudo -n fallocate -l 4G /swapfile 2>/dev/null; then
                sudo -n chmod 600 /swapfile
                sudo -n mkswap /swapfile > /dev/null 2>&1
                sudo -n swapon /swapfile 2>/dev/null
                echo '/swapfile none swap sw 0 0' | sudo -n tee -a /etc/fstab > /dev/null 2>&1
                log_success "Swap space configured"
            else
                log_warning "Could not setup swap (insufficient permissions). Continuing without swap."
            fi
        else
            log_info "Swap file already exists"
        fi
    fi
}

# Install OpenClaw using installer script
install_openclaw_script() {
    log_info "Installing OpenClaw using installer script..."
    
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- \
        --install-method ${INSTALL_METHOD} \
        ${AUTO_ONBOARD:+--no-onboard}
    
    log_success "OpenClaw installed via installer script"
}

# Install OpenClaw via npm
install_openclaw_npm() {
    log_info "Installing OpenClaw via npm..."
    
    # Handle sharp and libvips compatibility
    if [[ "$OS" == "macos" ]]; then
        export SHARP_IGNORE_GLOBAL_LIBVIPS=1
    fi
    
    npm install -g openclaw@${OPENCLAW_VERSION}
    
    log_success "OpenClaw installed via npm"
}

# Install OpenClaw via Docker
install_openclaw_docker() {
    log_info "Installing OpenClaw via Docker..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    # Create data directory
    mkdir -p ~/.openclaw
    
    # Pull and run OpenClaw container
    docker pull ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}
    
    docker run -d \
        --name openclaw \
        --restart unless-stopped \
        -v ~/.openclaw:/root/.openclaw \
        -v ~/openclaw/workspace:/root/openclaw/workspace \
        -p ${GATEWAY_PORT}:18789 \
        ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}
    
    log_success "OpenClaw Docker container started"
    log_info "Run 'docker exec -it openclaw openclaw onboard' to configure"
}

# Run onboarding wizard (non-interactive)
run_onboarding() {
    log_info "Configuring OpenClaw..."
    
    # Skip onboarding if requested or in non-interactive mode
    if [[ "$SKIP_ONBOARDING" == "true" ]] || [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_info "Skipping interactive onboarding (non-interactive mode)"
        log_warning "Remember to configure channels: openclaw channels login"
        return
    fi
    
    # Run interactive onboarding if available
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        docker exec -it openclaw openclaw onboard --install-daemon 2>/dev/null || true
    else
        openclaw onboard --install-daemon 2>/dev/null || true
    fi
    
    log_success "Configuration complete"
}

# Configure environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate gateway token if not exists
    if [[ -z "$OPENCLAW_GATEWAY_TOKEN" ]]; then
        OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        log_info "Generated gateway token: $OPENCLAW_GATEWAY_TOKEN"
    fi
    
    # Create environment file
    cat > ~/.openclaw/.env << EOF
# OpenClaw Environment Configuration
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
OPENCLAW_PORT=${GATEWAY_PORT}
NODE_ENV=${NODE_ENV:-production}

# API Keys (add your keys here)
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# GRADIENT_API_KEY=
EOF
    
    log_success "Environment configuration created at ~/.openclaw/.env"
    log_warning "Remember to add your API keys to ~/.openclaw/.env"
}

# Setup systemd service (Linux only)
setup_systemd() {
    if [[ "$OS" != "linux" ]]; then
        return
    fi
    
    log_info "Setting up systemd service..."
    
    SERVICE_CONTENT="[Unit]
Description=OpenClaw Gateway Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME
Environment=\"PATH=/usr/bin:/usr/local/bin:$HOME/.npm-global/bin\"
ExecStart=$(which openclaw) gateway --port ${GATEWAY_PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target"
    
    # Try with sudo -n first (no password prompt)
    if echo "$SERVICE_CONTENT" | sudo -n tee /etc/systemd/system/openclaw.service > /dev/null 2>&1; then
        sudo -n systemctl daemon-reload 2>/dev/null
        sudo -n systemctl enable openclaw 2>/dev/null
        sudo -n systemctl start openclaw 2>/dev/null
        log_success "Systemd service configured and started"
    else
        # Fallback: Use user-level systemd if available
        mkdir -p ~/.config/systemd/user
        echo "$SERVICE_CONTENT" > ~/.config/systemd/user/openclaw.service
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable openclaw 2>/dev/null || true
        systemctl --user start openclaw 2>/dev/null || true
        log_info "User-level systemd service configured (requires manual sudo setup for system service)"
    fi
}

# Setup firewall rules (non-interactive)
setup_firewall() {
    if [[ "$OS" != "linux" ]]; then
        return
    fi
    
    log_info "Configuring firewall rules..."
    
    if command -v ufw &> /dev/null; then
        if sudo -n ufw allow ${GATEWAY_PORT}/tcp 2>/dev/null; then
            log_success "UFW rule added for port ${GATEWAY_PORT}"
        else
            log_warning "Could not add UFW rule (insufficient permissions)"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        if sudo -n firewall-cmd --permanent --add-port=${GATEWAY_PORT}/tcp 2>/dev/null; then
            sudo -n firewall-cmd --reload 2>/dev/null
            log_success "Firewalld rule added for port ${GATEWAY_PORT}"
        else
            log_warning "Could not add firewall rule (insufficient permissions)"
        fi
    else
        log_warning "No firewall detected. Consider setting up firewall rules manually."
    fi
}

# Health check (non-interactive)
health_check() {
    log_info "Running health check..."
    
    sleep 3  # Wait for service to start
    
    if command -v openclaw &> /dev/null; then
        # Run non-interactive health checks
        if openclaw doctor 2>/dev/null | grep -q "OpenClaw"; then
            log_success "Health check passed"
        else
            log_warning "Health check returned warnings (but continuing)"
        fi
    else
        log_warning "OpenClaw command not found in PATH. PATH may need to be updated."
        log_info "Run: export PATH=~/.npm-global/bin:\$PATH"
    fi
}

# Print deployment summary
print_summary() {
    log_success "==================================="
    log_success "OpenClaw Deployment Complete!"
    log_success "==================================="
    echo ""
    log_info "Deployment Type: $DEPLOYMENT_TYPE"
    log_info "Gateway Port: $GATEWAY_PORT"
    log_info "Config Directory: ~/.openclaw"
    log_info "Mode: $([ "$NON_INTERACTIVE" == "true" ] && echo "Non-Interactive (Automated)" || echo "Interactive")"
    echo ""
    log_info "Next Steps:"
    echo "  1. Add your API keys to ~/.openclaw/openclaw.json or .env"
    echo "     export ANTHROPIC_API_KEY='sk-ant-...'"
    echo "     # or GEMINI_API_KEY, OPENAI_API_KEY, etc."
    echo ""
    echo "  2. Connect messaging channels (if not done):"
    echo "     openclaw channels login whatsapp"
    echo "     openclaw channels login telegram"
    echo "     openclaw channels login discord"
    echo ""
    echo "  3. Start chatting with your bot!"
    echo ""
    
    if [[ -n "$OPENCLAW_GATEWAY_TOKEN" ]]; then
        log_warning "Your gateway token: $OPENCLAW_GATEWAY_TOKEN"
        log_warning "Save this token securely in a password manager!"
    fi
    
    echo ""
    log_info "Useful Commands:"
    echo "  - openclaw status         # Check gateway status"
    echo "  - openclaw logs --follow  # View logs"
    echo "  - openclaw doctor         # Run diagnostics"
    echo "  - openclaw dashboard      # Open web UI (http://localhost:${GATEWAY_PORT})"
    echo "  - openclaw models list    # List available AI models"
    echo ""
    log_info "Documentation:"
    echo "  - Full guide: DEPLOYMENT.md"
    echo "  - Quick start: QUICKSTART.md"
    echo "  - API keys: API_KEYS.md"
    echo ""
}

# Main deployment flow
main() {
    # Parse command-line arguments first
    parse_arguments "$@"
    
    log_info "Starting OpenClaw Automated Deployment"
    log_info "========================================"
    
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_info "Running in NON-INTERACTIVE mode (no prompts)"
    fi
    
    echo ""
    
    # Pre-flight checks
    detect_os
    check_requirements
    
    # Installation
    case "$INSTALL_METHOD" in
        npm)
            install_node
            setup_swap
            install_openclaw_npm
            ;;
        script)
            install_openclaw_script
            ;;
        docker)
            install_openclaw_docker
            ;;
        *)
            log_error "Unknown install method: $INSTALL_METHOD"
            exit 1
            ;;
    esac
    
    # Post-installation setup
    if [[ "$DEPLOYMENT_TYPE" != "docker" ]]; then
        setup_environment
        
        if [[ "$AUTO_START_DAEMON" == "true" ]]; then
            setup_systemd
        fi
        
        # Skip onboarding in non-interactive mode
        if [[ "$NON_INTERACTIVE" != "true" ]] && [[ "$SKIP_ONBOARDING" != "true" ]]; then
            run_onboarding
        else
            run_onboarding  # This will skip in non-interactive mode
        fi
    else
        # Docker setup
        setup_environment
        log_info "Docker container is running. Configure channels manually:"
        log_info "  docker exec -it openclaw openclaw channels login"
    fi
    
    # Security and networking
    setup_firewall
    
    # Verification (non-blocking)
    health_check || true
    
    # Summary
    print_summary
}

# Run main function
main "$@"
