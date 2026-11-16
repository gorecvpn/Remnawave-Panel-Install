#!/usr/bin/env bash
# Version: 4.7.0-gorec
set -e
SCRIPT_VERSION="4.7.0-gorec"

# Original invocation, captured before any shifting, so a self-update can
# re-exec the new script with exactly the command the user typed.
SCRIPT_ORIGINAL_ARGS=("$@")

# Handle @ prefix for consistency with other scripts
if [ $# -gt 0 ] && [ "$1" = "@" ]; then
    shift
fi

# Parse command line arguments
COMMAND=""
if [ $# -gt 0 ]; then
    COMMAND="$1"
    shift
fi

# ============================================
# Script delivery
#
# raw.githubusercontent.com is unreachable on a good share of the networks these
# servers live on (blocked, DNS-poisoned or rate-limited), so every download
# walks a mirror list and takes the first source that returns something which
# actually parses as this script. jsDelivr serves the same git ref from several
# independent CDNs; it is only a fallback because a branch ref can be cached
# there for up to ~12h, while raw.githubusercontent is always current.
# ============================================
SCRIPT_REPO="gorecvpn/Remnawave-Panel-Install"
SCRIPT_REF="main"
SCRIPT_FILE="remnanode.sh"
SCRIPT_URL="https://raw.githubusercontent.com/${SCRIPT_REPO}/${SCRIPT_REF}/${SCRIPT_FILE}"
SCRIPT_URL_OVERRIDDEN="false"   # set by --source
SCRIPT_SOURCE_USED=""           # mirror the last successful download came from

# ============================================
# Force mode variables (for non-interactive installation)
# --force skips ALL prompts EXCEPT secret-key input
# ============================================
FORCE_MODE="false"
FORCE_SECRET_KEY=""       # If empty in force mode → will ask interactively
FORCE_NODE_PORT=""        # If empty in force mode → uses default 3000
FORCE_XTLS_PORT=""        # If empty in force mode → uses default 61000
FORCE_INSTALL_XRAY=""     # If empty in force mode → skip xray installation

# ============================================
# Image tag override (--tag)
# Installs a specific remnawave/node version instead of `latest`, e.g.
# `--tag 2.8.0` to stay on the 2.x line while the panel is not updated yet.
# Only exact versions exist upstream (no floating `2`/`3` tag).
# ============================================
NODE_IMAGE_TAG=""

# ============================================
# Auto-restart variables
# ============================================
AUTORESTART_SUBCOMMAND=""
AUTORESTART_HOUR=""
AUTORESTART_MINUTE=""
AUTORESTART_SCHEDULE=""

while [[ $# -gt 0 ]]; do
    key="$1"
    
    case $key in
        --force|-f)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_MODE="true"
            else
                echo "Ошибка: параметр --force допустим только с командой 'install'."
                exit 1
            fi
            shift
        ;;
        --secret-key|--secret|--key)
            if [[ "$COMMAND" == "install" ]]; then
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    FORCE_SECRET_KEY="$2"
                    shift 2
                else
                    # Try to extract value from --secret-key=VALUE format
                    if [[ "$1" =~ ^--[^=]+=(.+)$ ]]; then
                        FORCE_SECRET_KEY="${BASH_REMATCH[1]}"
                        shift
                    else
                        echo "Ошибка: для --secret-key нужно указать значение."
                        exit 1
                    fi
                fi
            else
                echo "Ошибка: параметр --secret-key допустим только с командой 'install'."
                exit 1
            fi
        ;;
        --secret-key=*|--secret=*|--key=*)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_SECRET_KEY="${1#*=}"
                shift
            else
                echo "Ошибка: параметр --secret-key допустим только с командой 'install'."
                exit 1
            fi
        ;;
        --port)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_NODE_PORT="$2"
                shift 2
            else
                echo "Ошибка: параметр --port допустим только с командой 'install'."
                exit 1
            fi
        ;;
        --port=*)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_NODE_PORT="${1#*=}"
                shift
            else
                echo "Ошибка: параметр --port допустим только с командой 'install'."
                exit 1
            fi
        ;;
        --xtls-port)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_XTLS_PORT="$2"
                shift 2
            else
                echo "Ошибка: параметр --xtls-port допустим только с командой 'install'."
                exit 1
            fi
        ;;
        --xtls-port=*)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_XTLS_PORT="${1#*=}"
                shift
            else
                echo "Ошибка: параметр --xtls-port допустим только с командой 'install'."
                exit 1
            fi
        ;;
        --xray)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_INSTALL_XRAY="true"
            else
                echo "Ошибка: параметр --xray допустим только с командой 'install'."
                exit 1
            fi
            shift
        ;;
        --no-xray)
            if [[ "$COMMAND" == "install" ]]; then
                FORCE_INSTALL_XRAY="false"
            else
                echo "Ошибка: параметр --no-xray допустим только с командой 'install'."
                exit 1
            fi
            shift
        ;;
        --name)
            if [[ "$COMMAND" == "install" || "$COMMAND" == "install-script" ]]; then
                APP_NAME="$2"
                shift # past argument
            else
                echo "Ошибка: параметр --name допустим только с командами 'install' и 'install-script'."
                exit 1
            fi
            shift # past value
        ;;
        --dev)
            if [[ "$COMMAND" == "install" ]]; then
                USE_DEV_BRANCH="true"
            else
                echo "Ошибка: параметр --dev допустим только с командой 'install'."
                exit 1
            fi
            shift # past argument
        ;;
        --tag|--version|--node-version)
            if [[ "$COMMAND" == "install" || "$COMMAND" == "update" ]]; then
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    NODE_IMAGE_TAG="$2"
                    shift 2
                else
                    echo "Ошибка: для --tag нужно указать значение (например, --tag 3.4.1)."
                    exit 1
                fi
            else
                echo "Ошибка: параметр --tag допустим только с командами 'install' и 'update'."
                exit 1
            fi
        ;;
        --tag=*|--version=*|--node-version=*)
            if [[ "$COMMAND" == "install" || "$COMMAND" == "update" ]]; then
                NODE_IMAGE_TAG="${1#*=}"
                if [ -z "$NODE_IMAGE_TAG" ]; then
                    echo "Ошибка: для --tag нужно указать значение (например, --tag=3.4.1)."
                    exit 1
                fi
                shift
            else
                echo "Ошибка: параметр --tag допустим только с командами 'install' и 'update'."
                exit 1
            fi
        ;;
        --source)
            if [[ "$COMMAND" == "install-script" ]]; then
                if [[ -n "$2" && "$2" =~ remnanode\.sh$ ]]; then
                    SCRIPT_URL="$2"
                    SCRIPT_URL_OVERRIDDEN="true"
                    shift 2
                else
                    echo "Ошибка: в --source нужно указать URL файла remnanode.sh."
                    exit 1
                fi
            else
                echo "Ошибка: параметр --source допустим только с командой 'install-script'."
                exit 1
            fi
        ;;
        --help|-h)
            show_command_help "$COMMAND"
            exit 0
        ;;
        enable|disable|status|test)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_SUBCOMMAND="$1"
            else
                echo "Неизвестный аргумент: $key"
                exit 1
            fi
            shift
        ;;
        --hour=*)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_HOUR="${1#*=}"
            else
                echo "Ошибка: параметр --hour допустим только с командой 'auto-restart'."
                exit 1
            fi
            shift
        ;;
        --hour)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_HOUR="$2"
                shift 2
            else
                echo "Ошибка: параметр --hour допустим только с командой 'auto-restart'."
                exit 1
            fi
        ;;
        --minute=*)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_MINUTE="${1#*=}"
            else
                echo "Ошибка: параметр --minute допустим только с командой 'auto-restart'."
                exit 1
            fi
            shift
        ;;
        --minute)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_MINUTE="$2"
                shift 2
            else
                echo "Ошибка: параметр --minute допустим только с командой 'auto-restart'."
                exit 1
            fi
        ;;
        --schedule=*)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_SCHEDULE="${1#*=}"
            else
                echo "Ошибка: параметр --schedule допустим только с командой 'auto-restart'."
                exit 1
            fi
            shift
        ;;
        --schedule)
            if [[ "$COMMAND" == "auto-restart" ]]; then
                AUTORESTART_SCHEDULE="$2"
                shift 2
            else
                echo "Ошибка: параметр --schedule допустим только с командой 'auto-restart'."
                exit 1
            fi
        ;;
        *)
            echo "Неизвестный аргумент: $key"
            exit 1
        ;;
    esac
done

# Fetch IP address from ipinfo.io API
NODE_IP=$(curl -s -4 ifconfig.io)

# If the IPv4 retrieval is empty, attempt to retrieve the IPv6 address
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(curl -s -6 ifconfig.io)
fi

if [[ "$COMMAND" == "install" || "$COMMAND" == "install-script" ]] && [ -z "$APP_NAME" ]; then
    APP_NAME="remnanode"
fi
# Set script name if APP_NAME is not set
if [ -z "$APP_NAME" ]; then
    SCRIPT_NAME=$(basename "$0")
    APP_NAME="${SCRIPT_NAME%.*}"
fi

INSTALL_DIR="/opt"
APP_DIR="$INSTALL_DIR/$APP_NAME"
DATA_DIR="/var/lib/$APP_NAME"
LOG_DIR="/var/log/$APP_NAME"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"
XRAY_FILE="$DATA_DIR/xray"
GEOIP_FILE="$DATA_DIR/geoip.dat"
GEOSITE_FILE="$DATA_DIR/geosite.dat"

# Default internal port (XTLS_API only, other internal ports now use unix sockets)
# Legacy: remnawave/node dropped XTLS_API_PORT from its config schema in 2.8.0 and
# replaced it with XTLS_API_SOCKET_PATH (an abstract unix socket generated at
# container start by /etc/s6-overlay/scripts/init-env.sh). The value is still
# written to .env for anyone pinned to <= 2.7.x, but it must never block an install.
DEFAULT_XTLS_API_PORT=61000

# --- Node <-> panel version coupling -----------------------------------------
# node 3.3.0 .. 3.3.2 install an SNICallback that rejects every TLS handshake
# whose SNI != deriveSni(caCert, jwtPublicKey) (node: src/main.ts ->
# makeSniVerifier, plus requestCert/rejectUnauthorized). The matching
# client-side helper exists in the panel only from backend 3.3.0 on
# (src/common/utils/certs/generate-servername.util.ts, used by axios.service.ts).
#
#   node 3.3.x     +  panel <  3.3.0  ->  every request dies with "unknown sni"
#   node <  3.3.0  +  panel >= 3.3.0  ->  fine (old node ignores the servername)
#
# node 3.4.0 put that whole path behind a new SNI_VERIFICATION env var which
# defaults to "false" (node commit 84a79955), so from 3.4.0 on the listener is
# back to the plain key/cert/ca of the 3.2.x line and talks to any panel again.
# The gate below therefore only covers the 3.3.x window.
NODE_SNI_MIN_VERSION="3.3.0"    # first node release that enforces the derived SNI
NODE_SNI_OPTIONAL_VERSION="3.4.0"  # first node release where it is opt-in (off by default)
PANEL_COMPAT_ACK_FILE="$APP_DIR/.panel-compat-ack"

# Deprecated ports (removed in v2.5.0+ of remnawave/node)
# SUPERVISORD_PORT and INTERNAL_REST_PORT are no longer needed
# They now use unix sockets: /run/supervisord.sock and /run/remnawave-internal.sock

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

colorized_echo() {
    local color=$1
    local text=$2
    local style=${3:-0}  # Default style is normal

    case $color in
        "red") printf "\e[${style};91m${text}\e[0m\n" ;;
        "green") printf "\e[${style};92m${text}\e[0m\n" ;;
        "yellow") printf "\e[${style};93m${text}\e[0m\n" ;;
        "blue") printf "\e[${style};94m${text}\e[0m\n" ;;
        "magenta") printf "\e[${style};95m${text}\e[0m\n" ;;
        "cyan") printf "\e[${style};96m${text}\e[0m\n" ;;
        *) echo "${text}" ;;
    esac
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "Эту команду нужно запускать от root."
        exit 1
    fi
}


check_system_requirements() {
    local errors=0
    
    # Проверяем свободное место (минимум 1GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # 1GB в KB
        colorized_echo red "Ошибка: мало места на диске. Нужно не меньше 1 ГБ."
        errors=$((errors + 1))
    fi
    
    # Проверяем RAM (минимум 512MB)
    local available_ram=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_ram" -lt 256 ]; then
        colorized_echo yellow "Внимание: мало свободной памяти (${available_ram} МБ). Производительность может пострадать."
    fi
    
    # Проверяем архитектуру
    if ! identify_the_operating_system_and_architecture 2>/dev/null; then
        colorized_echo red "Ошибка: архитектура системы не поддерживается."
        errors=$((errors + 1))
    fi
    
    return $errors
}

detect_os() {
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
        if [[ "$OS" == "Amazon Linux" ]]; then
            OS="Amazon"
        fi
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        colorized_echo red "Операционная система не поддерживается"
        exit 1
    fi
}

detect_and_update_package_manager() {
    colorized_echo blue "Обновляю пакетный менеджер"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        PKG_MANAGER="apt-get"
        $PKG_MANAGER update -qq >/dev/null 2>&1
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]] || [[ "$OS" == "Amazon"* ]]; then
        PKG_MANAGER="yum"
        $PKG_MANAGER update -y -q >/dev/null 2>&1
        if [[ "$OS" != "Amazon" ]]; then
            $PKG_MANAGER install -y -q epel-release >/dev/null 2>&1
        fi
    elif [[ "$OS" == "Fedora"* ]]; then
        PKG_MANAGER="dnf"
        $PKG_MANAGER update -q -y >/dev/null 2>&1
    elif [[ "$OS" == "Arch"* ]]; then
        PKG_MANAGER="pacman"
        $PKG_MANAGER -Sy --noconfirm --quiet >/dev/null 2>&1
    elif [[ "$OS" == "openSUSE"* ]]; then
        PKG_MANAGER="zypper"
        $PKG_MANAGER refresh --quiet >/dev/null 2>&1
    else
        colorized_echo red "Операционная система не поддерживается"
        exit 1
    fi
}

detect_compose() {
    if docker compose >/dev/null 2>&1; then
        COMPOSE='docker compose'
    elif docker-compose >/dev/null 2>&1; then
        COMPOSE='docker-compose'
    else
        if [[ "$OS" == "Amazon"* ]]; then
            colorized_echo blue "Плагин Docker Compose не найден. Пробую установить вручную..."
            mkdir -p /usr/libexec/docker/cli-plugins
            curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/libexec/docker/cli-plugins/docker-compose >/dev/null 2>&1
            chmod +x /usr/libexec/docker/cli-plugins/docker-compose
            if docker compose >/dev/null 2>&1; then
                COMPOSE='docker compose'
                colorized_echo green "Плагин Docker Compose установлен"
            else
                colorized_echo red "Не удалось установить плагин Docker Compose. Проверьте настройки системы."
                exit 1
            fi
        else
            colorized_echo red "docker compose не найден"
            exit 1
        fi
    fi
}

install_package() {
    if [ -z "$PKG_MANAGER" ]; then
        detect_and_update_package_manager
    fi

    PACKAGE=$1
    colorized_echo blue "Устанавливаю $PACKAGE"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        $PKG_MANAGER -y -qq install "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]] || [[ "$OS" == "Amazon"* ]]; then
        $PKG_MANAGER install -y -q "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "Fedora"* ]]; then
        $PKG_MANAGER install -y -q "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "Arch"* ]]; then
        $PKG_MANAGER -S --noconfirm --quiet "$PACKAGE" >/dev/null 2>&1
    elif [[ "$OS" == "openSUSE"* ]]; then
        $PKG_MANAGER --quiet install -y "$PACKAGE" >/dev/null 2>&1
    else
        colorized_echo red "Операционная система не поддерживается"
        exit 1
    fi
}

install_docker() {
    colorized_echo blue "Устанавливаю Docker"
    if [[ "$OS" == "Amazon"* ]]; then
        amazon-linux-extras enable docker >/dev/null 2>&1
        yum install -y docker >/dev/null 2>&1
        systemctl start docker
        systemctl enable docker
        colorized_echo green "Docker установлен (Amazon Linux)"
    else
        curl -fsSL https://get.docker.com | sh
        colorized_echo green "Docker установлен"
    fi
}

install_remnanode_script() {
    colorized_echo blue "Устанавливаю скрипт remnanode v$SCRIPT_VERSION"
    TARGET_PATH="/usr/local/bin/$APP_NAME"

    [ -d /usr/local/bin ] || mkdir -p /usr/local/bin

    # Download to a temp file and validate before touching $TARGET_PATH: a
    # half-transferred file or a captive-portal page must never replace a
    # working CLI. Falls through the mirror list (GitHub raw, then jsDelivr).
    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.inst.XXXXXX") || {
        colorized_echo red "Не удалось создать временный файл"
        exit 1
    }

    if ! fetch_script_file "$tmp"; then
        rm -f "$tmp"
        colorized_echo yellow "⚠️  Не удалось скачать скрипт ни с одного зеркала"
        # Fall back to the copy we are executing right now — it is by definition
        # a valid script of this exact version.
        if [ -f "${BASH_SOURCE[0]}" ] && install -m 755 "${BASH_SOURCE[0]}" "$TARGET_PATH" 2>/dev/null; then
            colorized_echo green "Скрипт remnanode v$SCRIPT_VERSION установлен из локальной копии в $TARGET_PATH"
            return 0
        fi
        colorized_echo red "Не удалось установить скрипт remnanode в $TARGET_PATH"
        exit 1
    fi

    if ! install -m 755 "$tmp" "$TARGET_PATH"; then
        rm -f "$tmp"
        colorized_echo red "Не удалось установить скрипт remnanode в $TARGET_PATH"
        exit 1
    fi
    rm -f "$tmp"
    colorized_echo blue "Скрипт remnanode скачан с $SCRIPT_SOURCE_USED"

    # Получаем версию установленного скрипта
    local installed_version=$(grep "^SCRIPT_VERSION=" "$TARGET_PATH" 2>/dev/null | head -1 | cut -d'"' -f2)
    if [ -n "$installed_version" ]; then
        colorized_echo green "Скрипт remnanode v$installed_version установлен в $TARGET_PATH"
    else
        colorized_echo green "Скрипт remnanode установлен в $TARGET_PATH"
    fi
}

# Улучшенная функция проверки доступности портов
validate_port() {
    local port="$1"
    
    # Проверяем диапазон портов
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    
    # Проверяем, что порт не зарезервирован системой
    if [ "$port" -lt 1024 ] && [ "$(id -u)" != "0" ]; then
        colorized_echo yellow "Внимание: для порта $port нужны права root"
    fi
    
    return 0
}

# Улучшенная функция получения занятых портов с fallback
get_occupied_ports() {
    local ports=""
    
    if command -v ss &>/dev/null; then
        ports=$(ss -tuln 2>/dev/null | awk 'NR>1 {print $5}' | grep -Eo '[0-9]+$' | sort -n | uniq)
    elif command -v netstat &>/dev/null; then
        ports=$(netstat -tuln 2>/dev/null | awk 'NR>2 {print $4}' | grep -Eo '[0-9]+$' | sort -n | uniq)
    else
        colorized_echo yellow "Нет ни ss, ни netstat. Устанавливаю net-tools..."
        detect_os
        if install_package net-tools; then
            if command -v netstat &>/dev/null; then
                ports=$(netstat -tuln 2>/dev/null | awk 'NR>2 {print $4}' | grep -Eo '[0-9]+$' | sort -n | uniq)
            fi
        else
            colorized_echo yellow "Не удалось установить net-tools. Пропускаю проверку занятых портов."
            return 1
        fi
    fi
    
    OCCUPIED_PORTS="$ports"
    return 0
}
is_port_occupied() {
    if echo "$OCCUPIED_PORTS" | grep -q -w "$1"; then
        return 0
    else
        return 1
    fi
}

# ============================================
# DEPRECATED: Port group functions removed in v4.0.0
# Node v2.5.0+ uses unix sockets for internal communication
# Only XTLS_API_PORT is still configurable
# ============================================

install_latest_xray_core() {
    identify_the_operating_system_and_architecture
    mkdir -p "$DATA_DIR"
    cd "$DATA_DIR"
    
    # Fetch the newest release INCLUDING pre-releases.
    # GitHub's /releases/latest endpoint returns only the newest *stable* release, but
    # the current node build requires the pre-release Xray-core. The /releases list is
    # ordered newest-first and includes pre-releases, so we take its first entry.
    local release_json
    release_json=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=1") || true
    latest_release=$(echo "$release_json" | grep -oP '"tag_name":\s*"\K(.*?)(?=")' | head -n1) || true
    local is_prerelease
    is_prerelease=$(echo "$release_json" | grep -oP '"prerelease":\s*\K(true|false)' | head -n1) || true

    if [ -z "$latest_release" ]; then
        colorized_echo red "Не удалось узнать последнюю версию Xray-core."
        exit 1
    fi

    if [ "$is_prerelease" = "true" ]; then
        colorized_echo yellow "⚠️  Самая новая версия Xray-core — предварительная (pre-release): ${latest_release}"
    fi
    
    if ! dpkg -s unzip >/dev/null 2>&1; then
        colorized_echo blue "Устанавливаю unzip..."
        detect_os
        install_package unzip
    fi
    
    xray_filename="Xray-linux-$ARCH.zip"
    xray_download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_release}/${xray_filename}"
    
    colorized_echo blue "Скачиваю Xray-core версии ${latest_release}..."
    wget "${xray_download_url}" -q
    if [ $? -ne 0 ]; then
        colorized_echo red "Ошибка: не удалось скачать Xray-core."
        exit 1
    fi
    
    colorized_echo blue "Распаковываю Xray-core..."
    unzip -o "${xray_filename}" -d "$DATA_DIR" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        colorized_echo red "Ошибка: не удалось распаковать Xray-core."
        exit 1
    fi

    rm "${xray_filename}"
    chmod +x "$XRAY_FILE"
    
    # Check what files were extracted
    colorized_echo blue "Распакованные файлы:"
    if [ -f "$XRAY_FILE" ]; then
        colorized_echo green "  ✅ исполняемый файл xray"
    fi
    if [ -f "$GEOIP_FILE" ]; then
        colorized_echo green "  ✅ geoip.dat"
    fi
    if [ -f "$GEOSITE_FILE" ]; then
        colorized_echo green "  ✅ geosite.dat"
    fi
    
    colorized_echo green "Xray-core (${latest_release}) установлен в $XRAY_FILE"
}

setup_log_rotation() {
    check_running_as_root

    # Check if the log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        colorized_echo blue "Создаю папку $LOG_DIR"
        mkdir -p "$LOG_DIR"
    else
        colorized_echo green "Папка $LOG_DIR уже есть"
    fi

    # Migration: move existing log files from old location (/var/lib -> /var/log)
    local OLD_LOG_DIR="/var/lib/$APP_NAME"
    if ls "$OLD_LOG_DIR"/*.log 1>/dev/null 2>&1; then
        mv "$OLD_LOG_DIR"/*.log "$LOG_DIR/"
        colorized_echo blue "Логи перенесены из $OLD_LOG_DIR в $LOG_DIR"
    fi

    # Check if logrotate is installed
    if ! command -v logrotate &> /dev/null; then
        colorized_echo blue "Устанавливаю logrotate"
        detect_os
        install_package logrotate
    else
        colorized_echo green "logrotate уже установлен"
    fi

    # Check if logrotate config already exists
    LOGROTATE_CONFIG="/etc/logrotate.d/remnanode"

    # Migration: update old logrotate config path (/var/lib -> /var/log)
    if [ -f "$LOGROTATE_CONFIG" ] && grep -q "$OLD_LOG_DIR" "$LOGROTATE_CONFIG"; then
        sed -i "s|$OLD_LOG_DIR|$LOG_DIR|g" "$LOGROTATE_CONFIG"
        colorized_echo blue "Конфиг logrotate перенесён: $OLD_LOG_DIR -> $LOG_DIR"
    fi

    if [ -f "$LOGROTATE_CONFIG" ]; then
        colorized_echo yellow "Конфиг logrotate уже есть: $LOGROTATE_CONFIG"
        read -p "Перезаписать его? (y/n): " -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            colorized_echo yellow "Оставляю текущий конфиг logrotate"
            return
        fi
    fi

    # Create logrotate configuration
    colorized_echo blue "Создаю конфиг logrotate: $LOGROTATE_CONFIG"
    cat > "$LOGROTATE_CONFIG" <<EOL
$LOG_DIR/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOL

    chmod 644 "$LOGROTATE_CONFIG"
    
    # Test logrotate configuration
    colorized_echo blue "Проверяю конфиг logrotate"
    if logrotate -d "$LOGROTATE_CONFIG" &> /dev/null; then
        colorized_echo green "Конфиг logrotate в порядке"
        
        # Ask if user wants to run logrotate now
        read -p "Запустить logrotate сейчас? (y/n): " -r run_now
        if [[ $run_now =~ ^[Yy]$ ]]; then
            colorized_echo blue "Запускаю logrotate"
            if logrotate -vf "$LOGROTATE_CONFIG"; then
                colorized_echo green "logrotate выполнен"
            else
                colorized_echo red "Ошибка при запуске logrotate"
            fi
        fi
    else
        colorized_echo red "Проверка конфига logrotate не прошла"
        logrotate -d "$LOGROTATE_CONFIG"
    fi
    
    # Update docker-compose.yml to mount logs directory
    if [ -f "$COMPOSE_FILE" ]; then
        colorized_echo blue "Добавляю в docker-compose.yml монтирование папки логов"
        

        colorized_echo blue "Делаю резервную копию docker-compose.yml..."
        backup_file=$(create_backup "$COMPOSE_FILE")
        if [ $? -eq 0 ]; then
            colorized_echo green "Резервная копия: $backup_file"
        else
            colorized_echo red "Не удалось сделать резервную копию"
            return
        fi

        # Migration: /var/lib/$APP_NAME -> /var/log/$APP_NAME for log volumes
        # Migrate active volume line
        if grep -q "$OLD_LOG_DIR:$OLD_LOG_DIR" "$COMPOSE_FILE" 2>/dev/null; then
            sed -i "s|$OLD_LOG_DIR:$OLD_LOG_DIR|$LOG_DIR:$LOG_DIR|g" "$COMPOSE_FILE"
            colorized_echo blue "Том перенесён: $OLD_LOG_DIR -> $LOG_DIR"
        fi

        # Migrate commented volume line (handles "# - path" and "#   - path")
        if grep -q "#.*- $OLD_LOG_DIR:$OLD_LOG_DIR" "$COMPOSE_FILE" 2>/dev/null; then
            sed -i "s|#\(.*- \)$OLD_LOG_DIR:$OLD_LOG_DIR|#\1$LOG_DIR:$LOG_DIR|g" "$COMPOSE_FILE"
            colorized_echo blue "Закомментированный том перенесён: $OLD_LOG_DIR -> $LOG_DIR"
        fi

        local service_indent=$(get_service_property_indentation "$COMPOSE_FILE")
        local indent_type=""
        if [[ "$service_indent" =~ $'\t' ]]; then
            indent_type=$'\t'
        else
            indent_type="  "
        fi
        local volume_item_indent="${service_indent}${indent_type}"
        

        local escaped_service_indent=$(escape_for_sed "$service_indent")
        local escaped_volume_item_indent=$(escape_for_sed "$volume_item_indent")
        

        if grep -q "^${escaped_service_indent}volumes:" "$COMPOSE_FILE"; then
            # Check for UNCOMMENTED volume line (not starting with #)
            if grep -qE "^[[:space:]]*-[[:space:]]*${LOG_DIR}:${LOG_DIR}" "$COMPOSE_FILE"; then
                colorized_echo yellow "Том логов уже есть в разделе volumes"
            # Check for COMMENTED volume line and uncomment it
            elif grep -qE "^[[:space:]]*#[[:space:]]*-[[:space:]]*${LOG_DIR}:${LOG_DIR}" "$COMPOSE_FILE"; then
                sed -i "s|^\\([[:space:]]*\\)#[[:space:]]*\\(-[[:space:]]*${LOG_DIR}:${LOG_DIR}\\)|\\1\\2|g" "$COMPOSE_FILE"
                colorized_echo green "Строка тома логов раскомментирована"
            else
                sed -i "/^${escaped_service_indent}volumes:/a\\${volume_item_indent}- $LOG_DIR:$LOG_DIR" "$COMPOSE_FILE"
                colorized_echo green "Том логов добавлен в раздел volumes"
            fi
        elif grep -q "^${escaped_service_indent}# volumes:" "$COMPOSE_FILE"; then
            # Uncomment the volumes: key
            sed -i "s|^${escaped_service_indent}# volumes:|${service_indent}volumes:|g" "$COMPOSE_FILE"

            # Check for commented LOG_DIR line with flexible whitespace matching
            if grep -qE "^[[:space:]]*#[[:space:]]*-[[:space:]]*${LOG_DIR}:${LOG_DIR}" "$COMPOSE_FILE"; then
                sed -i "s|^\\([[:space:]]*\\)#[[:space:]]*\\(-[[:space:]]*${LOG_DIR}:${LOG_DIR}\\)|\\1\\2|g" "$COMPOSE_FILE"
                colorized_echo green "Раздел volumes и строка тома логов раскомментированы"
            else
                sed -i "/^${escaped_service_indent}volumes:/a\\${volume_item_indent}- $LOG_DIR:$LOG_DIR" "$COMPOSE_FILE"
                colorized_echo green "Раздел volumes раскомментирован, том логов добавлен"
            fi
        else
            sed -i "/^${escaped_service_indent}restart: always/a\\${service_indent}volumes:\\n${volume_item_indent}- $LOG_DIR:$LOG_DIR" "$COMPOSE_FILE"
            colorized_echo green "Добавлен раздел volumes с томом логов"
        fi
        

        colorized_echo blue "Проверяю docker-compose.yml..."
        if validate_compose_file "$COMPOSE_FILE"; then
            colorized_echo green "docker-compose.yml в порядке"
            cleanup_old_backups "$COMPOSE_FILE"

            if is_remnanode_up; then
                read -p "Перезапустить RemnaNode, чтобы применить изменения? (y/n): " -r restart_now
                if [[ $restart_now =~ ^[Yy]$ ]]; then
                    colorized_echo blue "Перезапускаю RemnaNode"
                    restart_command -n
                    colorized_echo green "RemnaNode перезапущена"
                else
                    colorized_echo yellow "Не забудьте перезапустить RemnaNode, чтобы изменения вступили в силу"
                fi
            fi
        else
            colorized_echo red "docker-compose.yml не прошёл проверку! Восстанавливаю резервную копию..."
            if restore_backup "$backup_file" "$COMPOSE_FILE"; then
                colorized_echo green "Резервная копия восстановлена"
            else
                colorized_echo red "Не удалось восстановить резервную копию!"
            fi
            return
        fi
    else
        colorized_echo yellow "Файл Docker Compose не найден. Папка логов будет подключена при следующей установке."
    fi
    
    colorized_echo green "Ротация логов настроена"
    echo
    echo -e "\033[38;5;250mКак указать в конфиге Xray:\033[0m"
    echo -e "\033[38;5;8m┌──────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[38;5;8m│\033[0m  \033[38;5;213m\"log\"\033[0m: {                                       \033[38;5;8m│\033[0m"
    echo -e "\033[38;5;8m│\033[0m      \033[38;5;213m\"error\"\033[0m: \033[38;5;113m\"$LOG_DIR/error.log\"\033[0m,      \033[38;5;8m│\033[0m"
    echo -e "\033[38;5;8m│\033[0m      \033[38;5;213m\"access\"\033[0m: \033[38;5;113m\"$LOG_DIR/access.log\"\033[0m,    \033[38;5;8m│\033[0m"
    echo -e "\033[38;5;8m│\033[0m      \033[38;5;213m\"loglevel\"\033[0m: \033[38;5;113m\"warning\"\033[0m                    \033[38;5;8m│\033[0m"
    echo -e "\033[38;5;8m│\033[0m  }                                              \033[38;5;8m│\033[0m"
    echo -e "\033[38;5;8m└──────────────────────────────────────────────────┘\033[0m"
    echo -e "\033[38;5;250mДобавьте это в конфиг Xray в панели, чтобы включить логи.\033[0m"
}

# ============================================
# Selfsteal Socket Integration
# ============================================

# Socket path for nginx-selfsteal
SELFSTEAL_SOCKET="/dev/shm/nginx.sock"

# Check if selfsteal socket exists
check_selfsteal_socket() {
    if [ -S "$SELFSTEAL_SOCKET" ]; then
        return 0
    fi
    return 1
}

# Enable /dev/shm volume in docker-compose.yml
enable_shm_volume() {
    local compose_file="$1"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    # Check if already uncommented
    if grep -qE "^[[:space:]]*-[[:space:]]*/dev/shm:/dev/shm" "$compose_file"; then
        colorized_echo green "✅ Том /dev/shm уже подключён"
        return 0
    fi
    
    # Check if commented and uncomment
    if grep -qE "^[[:space:]]*#.*-[[:space:]]*/dev/shm:/dev/shm" "$compose_file"; then
        colorized_echo blue "Подключаю том /dev/shm для доступа к сокету selfsteal..."
        
        # First, check if 'volumes:' is also commented and uncomment it
        if grep -qE "^[[:space:]]*#[[:space:]]*volumes:" "$compose_file"; then
            sed -i 's|^[[:space:]]*#[[:space:]]*\(volumes:\)|    \1|' "$compose_file"
        fi
        
        # Then uncomment the /dev/shm line
        sed -i 's|^[[:space:]]*#[[:space:]]*\(-[[:space:]]*/dev/shm:/dev/shm.*\)|      \1|' "$compose_file"
        
        if docker compose -f "$compose_file" config >/dev/null 2>&1; then
            colorized_echo green "✅ Том /dev/shm подключён"
            return 0
        else
            colorized_echo red "docker-compose.yml не прошёл проверку после изменения"
            return 1
        fi
    fi
    
    colorized_echo yellow "⚠️  Строка тома /dev/shm в docker-compose.yml не найдена"
    return 1
}

# Configure selfsteal socket access after installation
configure_selfsteal_integration() {
    echo
    colorized_echo cyan "🔍 Ищу установленный Selfsteal (nginx/caddy)..."
    
    if check_selfsteal_socket; then
        colorized_echo green "✅ Найден сокет selfsteal: $SELFSTEAL_SOCKET"
        colorized_echo blue "   Открываю контейнеру remnanode доступ к сокету..."
        
        if enable_shm_volume "$COMPOSE_FILE"; then
            colorized_echo green "✅ remnanode настроена на работу с сокетом selfsteal"
            echo
            colorized_echo cyan "📋 Настройка Xray Reality:"
            colorized_echo white "   \"target\": \"$SELFSTEAL_SOCKET\","
            colorized_echo white "   \"xver\": 1"
        fi
    else
        colorized_echo gray "   Сокет selfsteal не найден"
        colorized_echo gray "   Если позже поставите selfsteal с --nginx, выполните:"
        colorized_echo white "   remnanode enable-socket"
    fi
}

# Command to enable socket access manually
enable_socket_command() {
    echo
    colorized_echo cyan "🔌 Настройка сокета Selfsteal"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        colorized_echo red "❌ docker-compose.yml не найден: $COMPOSE_FILE"
        colorized_echo gray "   Сначала установите remnanode: remnanode install"
        exit 1
    fi
    
    # Check if socket exists
    if check_selfsteal_socket; then
        colorized_echo green "✅ Сокет selfsteal найден: $SELFSTEAL_SOCKET"
    else
        colorized_echo yellow "⚠️  Сокет selfsteal не найден: $SELFSTEAL_SOCKET"
        colorized_echo gray "   Убедитесь, что selfsteal с --nginx установлен и запущен"
        echo
        read -p "Всё равно продолжить? [y/N]: " -r confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            colorized_echo gray "Отменено"
            exit 0
        fi
    fi
    
    echo
    if enable_shm_volume "$COMPOSE_FILE"; then
        echo
        colorized_echo blue "🔄 Перезапускаю контейнер remnanode..."
        
        cd "$APP_DIR"
        if docker compose down && docker compose up -d; then
            colorized_echo green "✅ remnanode перезапущена с доступом к сокету"
            
            # Verify
            sleep 2
            if docker exec "$APP_NAME" ls -la /dev/shm/nginx.sock >/dev/null 2>&1; then
                colorized_echo green "✅ Проверено: контейнер видит $SELFSTEAL_SOCKET"
            else
                colorized_echo yellow "⚠️  Сокет пока недоступен (возможно, selfsteal не запущен)"
            fi
        else
            colorized_echo red "❌ Не удалось перезапустить remnanode"
        fi
        
        echo
        colorized_echo cyan "📋 Настройка Xray Reality:"
        colorized_echo white "   \"target\": \"$SELFSTEAL_SOCKET\","
        colorized_echo white "   \"xver\": 1"
    else
        colorized_echo red "❌ Не удалось открыть доступ к сокету"
    fi
}

# Compare two dotted versions. Returns 0 when $1 >= $2.
# Non-numeric tags (latest, dev, ...) are handled by the callers, not here.
version_gte() {
    [ "$1" = "$2" ] && return 0
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# ===== Script self-delivery =================================================

# Mirrors, most authoritative first. A --source override wins outright.
script_mirror_urls() {
    if [ "$SCRIPT_URL_OVERRIDDEN" = "true" ]; then
        printf '%s\n' "$SCRIPT_URL"
        return 0
    fi
    printf '%s\n' \
        "https://raw.githubusercontent.com/${SCRIPT_REPO}/${SCRIPT_REF}/${SCRIPT_FILE}" \
        "https://cdn.jsdelivr.net/gh/${SCRIPT_REPO}@${SCRIPT_REF}/${SCRIPT_FILE}" \
        "https://fastly.jsdelivr.net/gh/${SCRIPT_REPO}@${SCRIPT_REF}/${SCRIPT_FILE}" \
        "https://gcore.jsdelivr.net/gh/${SCRIPT_REPO}@${SCRIPT_REF}/${SCRIPT_FILE}" \
        "https://testingcf.jsdelivr.net/gh/${SCRIPT_REPO}@${SCRIPT_REF}/${SCRIPT_FILE}"
}

# A downloaded file is only accepted as "our script" if it carries a shebang,
# a version line, a plausible size, and — decisively — parses as bash. That
# rejects captive-portal pages, CDN error bodies and truncated transfers, all
# of which would otherwise be installed over a working script.
script_download_is_valid() {
    local file="$1"

    [ -s "$file" ] || return 1
    head -n1 "$file" | grep -q '^#!' || return 1
    grep -q "^SCRIPT_VERSION=" "$file" || return 1
    [ "$(wc -c < "$file" 2>/dev/null || echo 0)" -ge 20000 ] || return 1
    bash -n "$file" >/dev/null 2>&1 || return 1

    return 0
}

# Download the script into $1, trying every mirror. Sets SCRIPT_SOURCE_USED.
fetch_script_file() {
    local out="$1"
    local url

    while IFS= read -r url; do
        [ -n "$url" ] || continue
        if curl -fsSL --connect-timeout 7 --max-time 90 --retry 1 --retry-delay 1 \
                "$url" -o "$out" 2>/dev/null && script_download_is_valid "$out"; then
            SCRIPT_SOURCE_USED="$url"
            return 0
        fi
        rm -f "$out" 2>/dev/null || true
    done < <(script_mirror_urls)

    return 1
}

# Version string of a downloaded script file.
script_file_version() {
    grep "^SCRIPT_VERSION=" "$1" 2>/dev/null | head -1 | cut -d'"' -f2
}

# Latest published version, or empty when every mirror is unreachable.
get_remote_script_version() {
    local tmp ver
    tmp=$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.ver.XXXXXX") || return 1
    if fetch_script_file "$tmp"; then
        ver=$(script_file_version "$tmp")
        rm -f "$tmp"
        printf '%s' "$ver"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# Install the running script fresh from the mirrors and hand control over to it
# with the user's original arguments. Never asks: an outdated script cannot be
# trusted to run the current migrations, so staying on it is not an option.
#
# REMNANODE_SELFUPDATE_DONE guards against a re-exec loop if the installed copy
# still reports an old version (different install path, read-only /usr/local/bin).
ensure_latest_script() {
    local target_path="/usr/local/bin/$APP_NAME"

    [ "${REMNANODE_SELFUPDATE_DONE:-0}" = "1" ] && return 0
    [ "$SCRIPT_URL_OVERRIDDEN" = "true" ] && return 0

    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.upd.XXXXXX") || return 0

    if ! fetch_script_file "$tmp"; then
        rm -f "$tmp"
        colorized_echo yellow "⚠️  Ни одно зеркало скрипта недоступно — продолжаю на v$SCRIPT_VERSION"
        return 0
    fi

    local remote_version
    remote_version=$(script_file_version "$tmp")

    if [ -z "$remote_version" ] || ! version_gte "$remote_version" "$SCRIPT_VERSION" || \
       [ "$remote_version" = "$SCRIPT_VERSION" ]; then
        rm -f "$tmp"
        colorized_echo green "✅ Скрипт последней версии (v$SCRIPT_VERSION)"
        return 0
    fi

    colorized_echo yellow "🔄 Обновление скрипта: v$SCRIPT_VERSION → v$remote_version (применяю автоматически)"
    colorized_echo gray   "   Источник: $SCRIPT_SOURCE_USED"

    if [ ! -d /usr/local/bin ]; then
        mkdir -p /usr/local/bin 2>/dev/null || true
    fi

    if ! install -m 755 "$tmp" "$target_path" 2>/dev/null; then
        rm -f "$tmp"
        colorized_echo yellow "⚠️  Не удалось записать $target_path — продолжаю на v$SCRIPT_VERSION"
        return 0
    fi
    rm -f "$tmp"

    local installed_version
    installed_version=$(grep "^SCRIPT_VERSION=" "$target_path" 2>/dev/null | head -1 | cut -d'"' -f2)
    if [ "$installed_version" != "$remote_version" ]; then
        colorized_echo yellow "⚠️  Проверка обновления не прошла (ожидалась v$remote_version, получена v${installed_version:-unknown})"
        return 0
    fi

    colorized_echo green "✅ Обновлено до v$installed_version — продолжаю"
    echo

    export REMNANODE_SELFUPDATE_DONE=1
    exec "$target_path" "${SCRIPT_ORIGINAL_ARGS[@]}"
}

# True when the requested tag lands inside the SNI-gated node window
# (>= 3.3.0 and < 3.4.0). Floating tags (latest / dev) resolve to the newest
# release, which is past that window and ships SNI_VERIFICATION=false.
node_tag_needs_sni_panel() {
    local tag="$1"

    case "$tag" in
        latest|dev|"") return 1 ;;
    esac

    # Strip a leading "v" and anything after the patch (e.g. 3.3.0-rc1)
    local ver="${tag#v}"
    ver="${ver%%-*}"

    if [[ "$ver" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        # Pad to major.minor.patch so "3.4" is not sorted below "3.4.0"
        while [ "$(printf '%s' "$ver" | tr -cd '.' | wc -c)" -lt 2 ]; do
            ver="${ver}.0"
        done
        version_gte "$ver" "$NODE_SNI_MIN_VERSION" || return 1
        version_gte "$ver" "$NODE_SNI_OPTIONAL_VERSION" && return 1
        return 0
    fi

    # Unrecognised tag → nothing points at the narrow 3.3.x window, don't nag
    return 1
}

# One-time confirmation that the panel is already on 3.3.0+ before moving the
# node onto the SNI-gated 3.3.x line. Once acknowledged we never ask again.
# Returns 0 to proceed, 1 to abort.
confirm_panel_supports_sni() {
    local tag="$1"
    local context="${2:-install}"

    node_tag_needs_sni_panel "$tag" || return 0
    [ -f "$PANEL_COMPAT_ACK_FILE" ] && return 0

    if [ "$FORCE_MODE" == "true" ]; then
        colorized_echo yellow "⚠️  node 3.3.x требует панель Remnawave >= $NODE_SNI_MIN_VERSION (--force: не спрашиваю)"
        mark_panel_compat_ack
        return 0
    fi

    if [ ! -t 0 ]; then
        colorized_echo yellow "⚠️  node 3.3.x требует панель Remnawave >= $NODE_SNI_MIN_VERSION (неинтерактивный режим: не спрашиваю)"
        mark_panel_compat_ack
        return 0
    fi

    echo
    colorized_echo yellow "==================================================="
    colorized_echo yellow "⚠️  Требование к версии панели"
    colorized_echo yellow "==================================================="
    colorized_echo white  "   Ноды версий 3.3.0 .. 3.3.2 принимают подключения только от"
    colorized_echo white  "   панели версии $NODE_SNI_MIN_VERSION или новее."
    echo
    colorized_echo gray   "   Эти версии отклоняют TLS-рукопожатие, если панель не передаёт"
    colorized_echo gray   "   производный SNI. Со старой панелью нода просто будет"
    colorized_echo gray   "   офлайн ('unknown sni' в логах ноды)."
    echo
    colorized_echo gray   "   С node $NODE_SNI_OPTIONAL_VERSION+ эта проверка включается по желанию (SNI_VERIFICATION, по"
    colorized_echo gray   "   умолчанию выключена), поэтому со старой панелью берите тег вне 3.3.x:"
    colorized_echo green  "      sudo $APP_NAME $context            # последняя (3.4+, без проверки SNI)"
    colorized_echo green  "      sudo $APP_NAME $context --tag 3.2.2"
    echo
    read -p "   Ваша панель уже версии $NODE_SNI_MIN_VERSION или новее? [y/N]: " -r panel_ok
    echo

    if [[ ! "$panel_ok" =~ ^[Yy]$ ]]; then
        colorized_echo red "❌ Отменено — сначала обновите панель или выберите тег вне 3.3.x"
        return 1
    fi

    mark_panel_compat_ack
    return 0
}

# Record that the panel-compat question has been settled, so neither `update`
# nor `up` asks (or holds back the pull) again.
mark_panel_compat_ack() {
    mkdir -p "$APP_DIR" 2>/dev/null || true
    {
        echo "# The Remnawave panel is on $NODE_SNI_MIN_VERSION+ (operator-confirmed, or"
        echo "# accepted implicitly via --force / a non-interactive run)."
        echo "# node 3.3.0 .. 3.3.2 enforce a derived-SNI TLS handshake; from"
        echo "# $NODE_SNI_OPTIONAL_VERSION on it is opt-in via SNI_VERIFICATION (default false)."
        echo "acknowledged_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$PANEL_COMPAT_ACK_FILE" 2>/dev/null || true
}

# Newest published node tags, best-effort (Docker Hub needs no auth and mirrors
# the same tags as GHCR). Used to make a wrong --tag actionable.
list_available_node_tags() {
    curl -s --max-time 10 "https://hub.docker.com/v2/repositories/remnawave/node/tags?page_size=25" 2>/dev/null \
        | grep -oE '"name":"[^"]+"' | cut -d'"' -f4
}

# Check that an image tag actually exists before writing it into docker-compose.
# A typo would otherwise only surface as a confusing pull failure later.
# NOTE: remnawave/node publishes ONLY exact versions (3.0.0, 2.8.0, ...) plus
# latest/dev — there is no floating major tag like ":2", unlike the backend.
# `docker manifest inspect` needs no pull; if the registry itself is unreachable
# we do not block the install — the pull will report the real problem.
verify_node_tag_exists() {
    local registry="$1"
    local tag="$2"

    if docker manifest inspect "${registry}:${tag}" >/dev/null 2>&1; then
        return 0
    fi

    # Distinguish "tag missing" from "cannot check at all"
    if ! docker manifest inspect "${registry}:latest" >/dev/null 2>&1; then
        colorized_echo yellow "⚠️  Не удалось проверить тег '${tag}' (реестр недоступен) — продолжаю"
        return 0
    fi

    # Registry is reachable → the tag is genuinely absent. Help the user out.
    local tags
    tags=$(list_available_node_tags)
    if [ -n "$tags" ]; then
        # A bare major like "2" is the most likely mistake — suggest its newest release
        if [[ "$tag" =~ ^[0-9]+$ ]]; then
            local newest
            newest=$(echo "$tags" | grep -E "^${tag}\.[0-9]+\.[0-9]+$" | head -1)
            if [ -n "$newest" ]; then
                colorized_echo yellow "   Примечание: у remnawave/node нет плавающего тега '${tag}' — укажите точную версию."
                colorized_echo green  "   Возможно, вы имели в виду:  --tag ${newest}"
            fi
        fi
        colorized_echo yellow "   Доступные теги: $(echo "$tags" | head -8 | tr '\n' ' ')"
    fi
    return 1
}

install_remnanode() {

    if ! check_system_requirements; then
        colorized_echo red "Проверка системных требований не прошла. Установка прервана."
        exit 1
    fi

    colorized_echo blue "Создаю папку $APP_DIR"
    mkdir -p "$APP_DIR"

    colorized_echo blue "Создаю папку $DATA_DIR"
    mkdir -p "$DATA_DIR"

    # Get SECRET_KEY (from command line or interactive input)
    if [ -n "$FORCE_SECRET_KEY" ]; then
        SECRET_KEY_VALUE="$FORCE_SECRET_KEY"
        colorized_echo green "✅ Использую SECRET_KEY из командной строки"
    else
        colorized_echo blue "Вставьте SECRET_KEY из панели Remnawave, затем нажмите Enter на новой пустой строке: "
        SECRET_KEY_VALUE=""
        while IFS= read -r line; do
            if [[ -z $line ]]; then
                break
            fi
            SECRET_KEY_VALUE="$SECRET_KEY_VALUE$line"
        done
    fi

    # Validate SECRET_KEY
    if [ -z "$SECRET_KEY_VALUE" ]; then
        colorized_echo red "❌ SECRET_KEY обязателен!"
        exit 1
    fi

    get_occupied_ports
    
    # Get NODE_PORT (from command line or interactive input)
    if [ -n "$FORCE_NODE_PORT" ]; then
        NODE_PORT="$FORCE_NODE_PORT"
        if ! validate_port "$NODE_PORT"; then
            colorized_echo red "❌ Неверный NODE_PORT: $NODE_PORT"
            exit 1
        fi
        if is_port_occupied "$NODE_PORT"; then
            colorized_echo red "❌ NODE_PORT $NODE_PORT уже занят!"
            exit 1
        fi
        colorized_echo green "✅ Использую NODE_PORT: $NODE_PORT"
    elif [ "$FORCE_MODE" == "true" ]; then
        # Force mode without explicit port: use default 3000
        NODE_PORT=3000
        if is_port_occupied "$NODE_PORT"; then
            colorized_echo red "❌ NODE_PORT по умолчанию ($NODE_PORT) уже занят!"
            colorized_echo yellow "   Укажите другой порт через --port=PORT"
            exit 1
        fi
        colorized_echo green "✅ Использую NODE_PORT по умолчанию: $NODE_PORT"
    else
        while true; do
            read -p "Введите NODE_PORT (по умолчанию 3000): " -r NODE_PORT
            NODE_PORT=${NODE_PORT:-3000}
            
            if validate_port "$NODE_PORT"; then
                if is_port_occupied "$NODE_PORT"; then
                    colorized_echo red "Порт $NODE_PORT уже занят. Введите другой порт."
                    colorized_echo blue "Занятые порты: $(echo $OCCUPIED_PORTS | tr '\n' ' ')"
                else
                    break
                fi
            else
                colorized_echo red "Неверный порт. Введите число от 1 до 65535."
            fi
        done
    fi

    # ============================================
    # Internal ports (legacy XTLS_API_PORT only)
    #
    # remnawave/node removed XTLS_API_PORT from its config schema in 2.8.0 and
    # replaced it with XTLS_API_SOCKET_PATH, an abstract unix socket generated
    # inside the container by /etc/s6-overlay/scripts/init-env.sh. Nothing binds
    # 61000 on a modern node, so this value must never block or interrupt an
    # install — it is kept in .env purely for installs pinned to <= 2.7.x.
    # ============================================

    if [ -n "$FORCE_XTLS_PORT" ]; then
        XTLS_API_PORT="$FORCE_XTLS_PORT"
        if ! validate_port "$XTLS_API_PORT"; then
            colorized_echo red "❌ Неверный XTLS_API_PORT: $XTLS_API_PORT"
            exit 1
        fi
        if is_port_occupied "$XTLS_API_PORT"; then
            colorized_echo yellow "⚠️  XTLS_API_PORT $XTLS_API_PORT занят (на node 2.8.0+ не важно, там он не используется)"
        fi
        colorized_echo green "✅ Использую XTLS_API_PORT: $XTLS_API_PORT"
    else
        XTLS_API_PORT=$DEFAULT_XTLS_API_PORT
        # Pick the next free port instead of aborting: on node 2.8.0+ the value is
        # unused anyway, and on <= 2.7.x a free port is what we want regardless.
        if is_port_occupied "$XTLS_API_PORT"; then
            local candidate=$XTLS_API_PORT
            local attempts=0
            while [ $attempts -lt 50 ] && is_port_occupied "$candidate"; do
                candidate=$((candidate + 1))
                attempts=$((attempts + 1))
            done
            if [ $attempts -lt 50 ]; then
                colorized_echo yellow "⚠️  XTLS_API_PORT по умолчанию ($XTLS_API_PORT) занят → использую $candidate"
                XTLS_API_PORT=$candidate
            else
                colorized_echo yellow "⚠️  Не нашёл свободный порт рядом с $XTLS_API_PORT — оставляю $XTLS_API_PORT (на node 2.8.0+ не используется)"
            fi
        fi
        colorized_echo gray "ℹ️  XTLS_API_PORT: $XTLS_API_PORT (устаревший, node 2.8.0+ его игнорирует; задать: --xtls-port)"
    fi
    echo

    # Install Xray-core only when explicitly requested via --xray.
    # We no longer prompt for it during installation: the "latest" stable Xray-core
    # is currently incompatible with the newest node (only the pre-release build works),
    # so installing the stable release here would be useless.
    INSTALL_XRAY=false
    if [ "$FORCE_INSTALL_XRAY" == "true" ]; then
        colorized_echo green "✅ Устанавливаю Xray-core (флаг --xray)"
        INSTALL_XRAY=true
        install_latest_xray_core
    else
        colorized_echo gray "ℹ️  Пропускаю установку Xray-core (флаг --xray или позже команда 'core-update')"
        INSTALL_XRAY=false
    fi

    colorized_echo blue "Создаю файл .env"
    cat > "$ENV_FILE" <<EOL
### NODE ###
NODE_PORT=$NODE_PORT

### XRAY ###
SECRET_KEY=$SECRET_KEY_VALUE

### Legacy: removed from the node config schema in 2.8.0 (replaced by an
### internally generated XTLS_API_SOCKET_PATH). Kept for installs pinned to <= 2.7.x.
XTLS_API_PORT=$XTLS_API_PORT

### node 3.4.0+: verify that the panel presents the derived SNI on every TLS
### handshake. Off by default upstream; turn it on only when the panel is on
### 3.3.0 or newer, otherwise the node stops accepting connections.
#SNI_VERIFICATION=true
EOL
    colorized_echo green "Файл окружения сохранён: $ENV_FILE"

    # Determine image based on --dev / --tag flags
    IMAGE_TAG="latest"
    IMAGE_REGISTRY="ghcr.io/remnawave/node"
    if [ "$USE_DEV_BRANCH" == "true" ]; then
        IMAGE_TAG="dev"
        IMAGE_REGISTRY="remnawave/node"
    fi

    # --tag wins over --dev: an explicit version is never a guess
    if [ -n "$NODE_IMAGE_TAG" ]; then
        if [ "$USE_DEV_BRANCH" == "true" ]; then
            colorized_echo yellow "⚠️  Указаны и --dev, и --tag — использую --tag $NODE_IMAGE_TAG"
            IMAGE_REGISTRY="ghcr.io/remnawave/node"
        fi
        IMAGE_TAG="$NODE_IMAGE_TAG"
        if ! verify_node_tag_exists "$IMAGE_REGISTRY" "$IMAGE_TAG"; then
            colorized_echo red "Образ ${IMAGE_REGISTRY}:${IMAGE_TAG} не найден в реестре."
            colorized_echo yellow "   Доступные теги: https://github.com/remnawave/node/pkgs/container/node"
            exit 1
        fi
        colorized_echo green "✅ Образ ноды закреплён: ${IMAGE_REGISTRY}:${IMAGE_TAG}"
    fi

    # node 3.3.x only talks to panel 3.3.0+ (derived-SNI TLS gate) — confirm once
    if ! confirm_panel_supports_sni "$IMAGE_TAG" "install"; then
        exit 1
    fi

    colorized_echo blue "Создаю файл docker-compose.yml"
    
    # Create docker-compose.yml with commented volumes section
    cat > "$COMPOSE_FILE" <<EOL
services:
  remnanode:
    container_name: $APP_NAME
    hostname: $APP_NAME
    image: ${IMAGE_REGISTRY}:${IMAGE_TAG}
    env_file:
      - .env
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
EOL

    # Add volumes section (commented by default)
    if [ "$INSTALL_XRAY" == "true" ]; then
        # If Xray is installed, add uncommented volumes section
        cat >> "$COMPOSE_FILE" <<EOL
    volumes:
      - $XRAY_FILE:/usr/local/bin/xray
EOL
        
        # Add geo files if they exist
        if [ -f "$GEOIP_FILE" ]; then
            echo "      - $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$COMPOSE_FILE"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "      - $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$COMPOSE_FILE"
        fi
        
        cat >> "$COMPOSE_FILE" <<EOL
      # - $LOG_DIR:$LOG_DIR
      # - /dev/shm:/dev/shm  # Uncomment for selfsteal socket access
EOL
    else
        # If Xray is not installed, add commented volumes section
        # Use same indentation format as when Xray is installed for consistency
        cat >> "$COMPOSE_FILE" <<EOL
    # volumes:
      # - $XRAY_FILE:/usr/local/bin/xray
      # - $GEOIP_FILE:/usr/local/share/xray/geoip.dat
      # - $GEOSITE_FILE:/usr/local/share/xray/geosite.dat
      # - $LOG_DIR:$LOG_DIR
      # - /dev/shm:/dev/shm  # Uncomment for selfsteal socket access
EOL
    fi

    colorized_echo green "Файл Docker Compose сохранён: $COMPOSE_FILE"
}

uninstall_remnanode_script() {
    if [ -f "/usr/local/bin/$APP_NAME" ]; then
        colorized_echo yellow "Удаляю скрипт remnanode"
        rm "/usr/local/bin/$APP_NAME"
    fi
}

uninstall_remnanode() {
    if [ -d "$APP_DIR" ]; then
        colorized_echo yellow "Удаляю папку: $APP_DIR"
        rm -r "$APP_DIR"
    fi
}

uninstall_remnanode_docker_images() {
    images=$(docker images | grep remnawave/node | awk '{print $3}')
    if [ -n "$images" ]; then
        colorized_echo yellow "Удаляю Docker-образы remnanode"
        for image in $images; do
            if docker rmi "$image" >/dev/null 2>&1; then
                colorized_echo yellow "Образ $image удалён"
            fi
        done
    fi
}

uninstall_remnanode_data_files() {
    if [ -d "$DATA_DIR" ]; then
        colorized_echo yellow "Удаляю папку: $DATA_DIR"
        rm -r "$DATA_DIR"
    fi
}

# Force IPv4 for outbound connections by configuring /etc/gai.conf
# This fixes Docker pull failures on servers with broken IPv6 connectivity
enable_ipv4_preference() {
    local gai_conf="/etc/gai.conf"
    local ipv4_rule="precedence ::ffff:0:0/96  100"

    # Already configured
    if grep -q "^precedence ::ffff:0:0/96" "$gai_conf" 2>/dev/null; then
        return 0
    fi

    colorized_echo yellow "🔧 Включаю приоритет IPv4 для сетевых подключений..."

    if [ -f "$gai_conf" ]; then
        # Uncomment existing rule if present
        if grep -q "^#precedence ::ffff:0:0/96" "$gai_conf"; then
            sed -i 's/^#precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/' "$gai_conf"
            colorized_echo green "✅ Приоритет IPv4 включён (раскомментировано правило в $gai_conf)"
            return 0
        fi
    fi

    # Append rule
    echo "$ipv4_rule" >> "$gai_conf"
    colorized_echo green "✅ Приоритет IPv4 включён (добавлено правило в $gai_conf)"
}

# Pull docker images with retry logic to handle transient network failures
# (IPv6 connection resets, ghcr.io timeouts, etc.)
# On IPv6 failures, automatically switches to IPv4 preference before retrying
docker_pull_with_retry() {
    local max_retries=3
    local retry_delay=5
    local attempt=1
    local pull_output=""
    local ipv4_forced=false

    while [ $attempt -le $max_retries ]; do
        pull_output=$($COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" pull 2>&1) && {
            echo "$pull_output"
            return 0
        }

        echo "$pull_output"

        # Detect IPv6 connection failures and switch to IPv4
        if [ "$ipv4_forced" = false ] && echo "$pull_output" | grep -qE '\[([0-9a-f]{0,4}:){2,}[0-9a-f]{0,4}\]'; then
            colorized_echo yellow "⚠️  Ошибка подключения по IPv6 (попытка $attempt/$max_retries)"
            enable_ipv4_preference
            ipv4_forced=true
            colorized_echo blue "🔄 Повтор через IPv4 через ${retry_delay} с..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        elif [ $attempt -lt $max_retries ]; then
            colorized_echo yellow "⚠️  Не удалось скачать образ (попытка $attempt/$max_retries). Повтор через ${retry_delay} с..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        else
            colorized_echo red "❌ Не удалось скачать образ за $max_retries попыток."
            colorized_echo yellow "   Обычно это проблема с сетью."
            colorized_echo yellow "   Попробуйте позже: sudo $APP_NAME up"
            return 1
        fi

        attempt=$((attempt + 1))
    done
}

# True when the image docker-compose.yml points at is already in the local store.
image_present_locally() {
    [ -f "$COMPOSE_FILE" ] || return 1

    local image
    image=$(grep -E "^[[:space:]]*image:[[:space:]]*[^[:space:]]*remnawave/node:" "$COMPOSE_FILE" 2>/dev/null \
            | head -1 | sed 's/.*image:[[:space:]]*//' | tr -d "\"'" | xargs)
    [ -n "$image" ] || return 1

    [ -n "$(docker images "$image" --format '{{.ID}}' 2>/dev/null | head -1)" ]
}

up_remnanode() {
    # Run migration for deprecated ports before starting (silent mode)
    migrate_deprecated_ports 2>/dev/null || true

    # Run migration for cap_add NET_ADMIN (silent mode)
    migrate_cap_add 2>/dev/null || true

    # Run migration for log volumes /var/lib -> /var/log (silent mode)
    migrate_log_volumes 2>/dev/null || true

    # `up` and `restart` are lifecycle commands, not upgrades. Pulling here would
    # silently move anyone on a floating tag onto a newer node release just for
    # restarting a container — a release that may need a newer panel (as 3.3.x
    # did with its derived-SNI gate). Whoever wants a new image runs `update`.
    #
    # The one exception is a first start with nothing in the local image store:
    # there is no version to preserve, and pulling explicitly keeps the retry
    # logic that a bare `compose up` does not have.
    if ! image_present_locally; then
        colorized_echo blue "Образа нет локально — скачиваю"
        docker_pull_with_retry
    fi

    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" up -d --remove-orphans
}

down_remnanode() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" down
}

show_remnanode_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs
}

follow_remnanode_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs -f
}

update_remnanode_script() {
    local target_path="/usr/local/bin/$APP_NAME"

    # Получаем текущую версию перед обновлением
    local old_version="unknown"
    if [ -f "$target_path" ]; then
        old_version=$(grep "^SCRIPT_VERSION=" "$target_path" 2>/dev/null | head -1 | cut -d'"' -f2)
        [ -z "$old_version" ] && old_version="unknown"
    fi

    colorized_echo blue "Обновляю скрипт remnanode (сейчас: v$old_version)"

    # Скачиваем во временный файл, а не через `curl | install /dev/stdin`:
    # на минимальных системах /dev/stdin недоступен и install падает с
    # "No such file or directory", curl получает ошибку 23, а файл остаётся
    # старым — из-за чего вызывающий код зацикливался на обновлении.
    # fetch_script_file обходит все зеркала и валидирует результат (shebang,
    # версия, размер, `bash -n`), так что подменить рабочий CLI мусором нельзя.
    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX") || {
        colorized_echo red "Не удалось создать временный файл"
        return 1
    }

    if ! fetch_script_file "$tmp_file"; then
        colorized_echo red "Не удалось скачать рабочий скрипт ни с одного зеркала"
        rm -f "$tmp_file"
        return 1
    fi

    local new_version
    new_version=$(script_file_version "$tmp_file")
    colorized_echo blue "Скачано с $SCRIPT_SOURCE_USED"

    # Устанавливаем из обычного файла (без /dev/stdin)
    if ! install -m 755 "$tmp_file" "$target_path"; then
        colorized_echo red "Не удалось установить обновлённый скрипт в $target_path"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"

    # Проверяем, что версия на диске действительно сменилась
    local installed_version
    installed_version=$(grep "^SCRIPT_VERSION=" "$target_path" 2>/dev/null | head -1 | cut -d'"' -f2)
    if [ "$installed_version" != "$new_version" ]; then
        colorized_echo red "Проверка обновления скрипта не прошла (ожидалась v$new_version, получена v${installed_version:-unknown})"
        return 1
    fi

    colorized_echo green "Скрипт remnanode обновлён: v$old_version → v$installed_version"
    return 0
}

update_remnanode() {
    docker_pull_with_retry
}

is_remnanode_installed() {
    if [ -d "$APP_DIR" ]; then
        return 0
    else
        return 1
    fi
}

is_remnanode_up() {
    if ! is_remnanode_installed; then
        return 1
    fi
    
    detect_compose
    if [ -z "$($COMPOSE -f $COMPOSE_FILE ps -q -a)" ]; then
        return 1
    else
        return 0
    fi
}

# Функция для получения версии RemnaNode из контейнера
get_remnanode_version() {
    local container_name="$APP_NAME"
    
    # Проверяем что контейнер запущен
    if ! docker exec "$container_name" echo "test" >/dev/null 2>&1; then
        echo "unknown"
        return 1
    fi
    
    # Пробуем получить версию из package.json с помощью awk
    local version=$(docker exec "$container_name" awk -F'"' '/"version"/{print $4; exit}' package.json 2>/dev/null)
    
    if [ -z "$version" ]; then
        # Альтернативный способ с sed
        version=$(docker exec "$container_name" sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null | head -1)
    fi
    
    if [ -z "$version" ]; then
        echo "unknown"
        return 1
    fi
    
    echo "$version"
    return 0
}

# Функция для получения версии Xray из контейнера
get_container_xray_version() {
    local container_name="$APP_NAME"
    
    # Проверяем что контейнер запущен
    if ! docker exec "$container_name" echo "test" >/dev/null 2>&1; then
        echo "unknown"
        return 1
    fi
    
    # Получаем версию xray из контейнера
    local version_output=$(docker exec "$container_name" xray version 2>/dev/null | head -1)
    
    if [ -z "$version_output" ]; then
        # Пробуем через полный путь
        version_output=$(docker exec "$container_name" /usr/local/bin/xray version 2>/dev/null | head -1)
    fi
    
    if [ -z "$version_output" ]; then
        echo "unknown"
        return 1
    fi
    
    # Парсим версию: "Xray 25.10.15 (Xray, Penetrates Everything.) ..."
    local version=$(echo "$version_output" | awk '{print $2}')
    
    if [ -z "$version" ]; then
        echo "unknown"
        return 1
    fi
    
    echo "$version"
    return 0
}

install_command() {
    check_running_as_root
    if is_remnanode_installed; then
        colorized_echo red "Remnanode уже установлена в $APP_DIR"
        if [ "$FORCE_MODE" == "true" ]; then
            colorized_echo yellow "⚠️  Режим --force: перезаписываю текущую установку"
        else
            read -p "Перезаписать текущую установку? (y/n) "
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                colorized_echo red "Установка отменена"
                exit 1
            fi
        fi
    fi
    detect_os
    if ! command -v curl >/dev/null 2>&1; then
        install_package curl
    fi
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    fi

    detect_compose
    install_remnanode_script
    install_remnanode
    
    # Check for selfsteal socket and enable volume if needed
    configure_selfsteal_integration
    
    up_remnanode
    follow_remnanode_logs

    # final message
    clear
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo -e "\033[1;37m🎉 RemnaNode установлена!\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo
    
    echo -e "\033[1;37m🌐 Данные для подключения:\033[0m"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "IP-адрес:   " "$NODE_IP"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Порт:       " "$NODE_PORT"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s:%s\033[0m\n" "Адрес:      " "$NODE_IP" "$NODE_PORT"
    echo
    
    echo -e "\033[1;37m📋 Что дальше:\033[0m"
    echo -e "   \033[38;5;250m1.\033[0m Добавьте ноду в панель Remnawave по IP и порту выше"
    echo -e "   \033[38;5;250m2.\033[0m Настройте ротацию логов: \033[38;5;15msudo $APP_NAME setup-logs\033[0m"
    
    if [ "$INSTALL_XRAY" == "true" ]; then
        echo -e "   \033[38;5;250m3.\033[0m \033[1;37mXray-core уже установлен и готов! ✅\033[0m"
    else
        echo -e "   \033[38;5;250m3.\033[0m Установите Xray-core: \033[38;5;15msudo $APP_NAME core-update\033[0m"
    fi
    
    echo -e "   \033[38;5;250m4.\033[0m Закройте порт через UFW: \033[38;5;15msudo ufw allow from \033[38;5;244mPANEL_IP\033[38;5;15m to any port $NODE_PORT\033[0m"
    echo -e "      \033[38;5;8m(Включить UFW: \033[38;5;15msudo ufw enable\033[38;5;8m)\033[0m"
    echo
    
    echo -e "\033[1;37m🛠️  Быстрые команды:\033[0m"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "status" "📊 Статус сервисов"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "logs" "📋 Логи контейнера"
    printf "   \033[38;5;15m%-15s\033[0m %s\n" "restart" "🔄 Перезапустить сервис"
    if [ "$INSTALL_XRAY" == "true" ]; then
        printf "   \033[38;5;15m%-15s\033[0m %s\n" "xray_log_out" "📤 Логи Xray"
    fi
    echo
    
    echo -e "\033[1;37m📁 Где лежат файлы:\033[0m"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Конфигурация:  " "$APP_DIR"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Данные:        " "$DATA_DIR"
    if [ "$INSTALL_XRAY" == "true" ]; then
        printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Файл Xray:     " "$XRAY_FILE"
    fi
    echo
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    echo -e "\033[38;5;8m💡 Все команды: \033[38;5;15msudo $APP_NAME\033[0m"
    echo -e "\033[38;5;8m📚 Проект: \033[38;5;250mhttps://gig.ovh\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
}

uninstall_command() {
    check_running_as_root
    if ! is_remnanode_installed; then
        colorized_echo red "Remnanode не установлена!"
        exit 1
    fi
    
    read -p "Точно удалить Remnanode? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo red "Отменено"
        exit 1
    fi
    
    detect_compose
    if is_remnanode_up; then
        down_remnanode
    fi
    uninstall_remnanode_script
    uninstall_remnanode
    uninstall_remnanode_docker_images
    
    read -p "Удалить также данные Remnanode ($DATA_DIR)? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo green "Remnanode удалена"
    else
        uninstall_remnanode_data_files
        colorized_echo green "Remnanode удалена"
    fi
}

install_script_command() {
    check_running_as_root
    colorized_echo blue "Устанавливаю скрипт RemnaNode глобально"
    install_remnanode_script

    # Report what actually landed on disk — install_remnanode_script fetches the
    # newest published script, which is usually not the version running here.
    local installed_version
    installed_version=$(grep "^SCRIPT_VERSION=" "/usr/local/bin/$APP_NAME" 2>/dev/null | head -1 | cut -d'"' -f2)

    colorized_echo green "✅ Скрипт установлен!"
    colorized_echo white "   Версия: ${installed_version:-$SCRIPT_VERSION}"
    colorized_echo white "   Путь: /usr/local/bin/$APP_NAME"
    colorized_echo white "Теперь '$APP_NAME' можно запускать из любой папки"
}

uninstall_script_command() {
    check_running_as_root
    if [ ! -f "/usr/local/bin/$APP_NAME" ]; then
        colorized_echo red "❌ Скрипт не найден: /usr/local/bin/$APP_NAME"
        exit 1
    fi
    
    read -p "Точно удалить скрипт? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo yellow "Операция отменена"
        exit 0
    fi
    
    colorized_echo blue "Удаляю скрипт RemnaNode"
    uninstall_remnanode_script
    colorized_echo green "✅ Скрипт удалён!"
}

up_command() {
    help() {
        colorized_echo red "Использование: remnanode up [опции]"
        echo "ОПЦИИ:"
        echo "  -h, --help        показать эту справку"
        echo "  -n, --no-logs     не показывать логи после запуска"
    }
    
    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs) no_logs=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Ошибка: неверная опция: $1" >&2; help; exit 0 ;;
        esac
        shift
    done
    
    if ! is_remnanode_installed; then
        colorized_echo red "Remnanode не установлена!"
        exit 1
    fi
    
    detect_compose
    
    if is_remnanode_up; then
        colorized_echo red "Remnanode уже запущена"
        exit 1
    fi
    
    up_remnanode
    if [ "$no_logs" = false ]; then
        follow_remnanode_logs
    fi
}

down_command() {
    if ! is_remnanode_installed; then
        colorized_echo red "Remnanode не установлена!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_remnanode_up; then
        colorized_echo red "Remnanode уже остановлена"
        exit 1
    fi
    
    down_remnanode
}

restart_command() {
    help() {
        colorized_echo red "Использование: remnanode restart [опции]"
        echo "ОПЦИИ:"
        echo "  -h, --help        показать эту справку"
        echo "  -n, --no-logs     не показывать логи после запуска"
    }
    
    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs) no_logs=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Ошибка: неверная опция: $1" >&2; help; exit 0 ;;
        esac
        shift
    done
    
    if ! is_remnanode_installed; then
        colorized_echo red "Remnanode не установлена!"
        exit 1
    fi
    
    detect_compose
    
    down_remnanode
    up_remnanode
    
    # Добавляем поддержку флага --no-logs
    if [ "$no_logs" = false ]; then
        follow_remnanode_logs
    fi
}

status_command() {
    echo -e "\033[1;37m📊 Проверка статуса RemnaNode:\033[0m"
    echo
    
    if ! is_remnanode_installed; then
        printf "   \033[38;5;15m%s\033[0m \033[1;31m❌ Не установлена\033[0m\n" "Статус:     "
        echo -e "\033[38;5;8m   Установка: '\033[38;5;15msudo $APP_NAME install\033[38;5;8m'\033[0m"
        exit 1
    fi
    
    detect_compose
    
    if ! is_remnanode_up; then
        printf "   \033[38;5;15m%s\033[0m \033[1;33m⏹️  Остановлена\033[0m\n" "Статус:     "
        echo -e "\033[38;5;8m   Запуск: '\033[38;5;15msudo $APP_NAME up\033[38;5;8m'\033[0m"
        exit 1
    fi
    
    printf "   \033[38;5;15m%s\033[0m \033[1;32m✅ Работает\033[0m\n" "Статус:     "
    
    # Получаем порт через универсальную функцию
    local node_port=$(get_env_variable "NODE_PORT")
    # Fallback to old variable for backward compatibility
    if [ -z "$node_port" ]; then
        node_port=$(get_env_variable "APP_PORT")
    fi
    
    if [ -n "$node_port" ]; then
        printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Порт:       " "$node_port"
    fi
    
    # Получаем версию RemnaNode
    local node_version=$(get_remnanode_version 2>/dev/null || echo "unknown")
    if [ "$node_version" != "unknown" ]; then
        printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250mv%s\033[0m\n" "RemnaNode:" "$node_version"
    fi
    
    # Проверяем Xray
    local xray_version=$(get_current_xray_core_version)
    printf "   \033[38;5;15m%-12s\033[0m \033[38;5;250m%s\033[0m\n" "Xray Core:" "${xray_version/#Not installed/Не установлен}"
    
    echo
}

logs_command() {
    help() {
        colorized_echo red "Использование: remnanode logs [опции]"
        echo "ОПЦИИ:"
        echo "  -h, --help        показать эту справку"
        echo "  -n, --no-follow   не следить за логами в реальном времени"
    }
    
    local no_follow=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-follow) no_follow=true ;;
            -h|--help) help; exit 0 ;;
            *) echo "Ошибка: неверная опция: $1" >&2; help; exit 0 ;;
        esac
        shift
    done
    
    if ! is_remnanode_installed; then
        colorized_echo red "Remnanode не установлена!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_remnanode_up; then
        colorized_echo red "Remnanode не запущена."
        exit 1
    fi
    
    if [ "$no_follow" = true ]; then
        show_remnanode_logs
    else
        follow_remnanode_logs
    fi
}

# Функция для получения переменной окружения из .env или docker-compose.yml
get_env_variable() {
    local var_name="$1"
    local value=""
    
    # Сначала пробуем .env файл
    if [ -f "$ENV_FILE" ]; then
        value=$(grep "^${var_name}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    # Если не нашли в .env, ищем в docker-compose.yml
    if [ -z "$value" ] && [ -f "$COMPOSE_FILE" ]; then
        # Проверяем секцию environment в docker-compose.yml
        value=$(grep -A 20 "environment:" "$COMPOSE_FILE" 2>/dev/null | grep "${var_name}=" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs)
    fi
    
    echo "$value"
}

# Функция для проверки, используется ли .env или переменные в docker-compose.yml
check_env_configuration() {
    local uses_env_file=false
    local uses_inline_env=false
    
    # Проверяем наличие .env файла
    if [ -f "$ENV_FILE" ] && [ -s "$ENV_FILE" ]; then
        uses_env_file=true
    fi
    
    # Проверяем наличие env_file в docker-compose.yml
    if [ -f "$COMPOSE_FILE" ]; then
        if grep -q "env_file:" "$COMPOSE_FILE" 2>/dev/null; then
            uses_env_file=true
        fi
        
        # Проверяем наличие inline environment переменных
        if grep -A 5 "environment:" "$COMPOSE_FILE" 2>/dev/null | grep -q "NODE_PORT\|APP_PORT\|SECRET_KEY\|SSL_CERT"; then
            uses_inline_env=true
        fi
    fi
    
    if [ "$uses_env_file" = true ]; then
        echo "env_file"
    elif [ "$uses_inline_env" = true ]; then
        echo "inline"
    else
        echo "unknown"
    fi
}

# Функция для миграции старых переменных окружения к новым
migrate_env_variables() {
    echo
    colorized_echo blue "🔄 Проверяю, нужна ли миграция переменных окружения..."
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    if ! is_remnanode_installed; then
        colorized_echo yellow "⚠️  RemnaNode не установлена, мигрировать нечего"
        return 0
    fi
    
    local env_type=$(check_env_configuration)
    
    colorized_echo blue "🔍 Тип конфигурации: $env_type"
    echo
    
    if [ "$env_type" = "env_file" ]; then
        migrate_env_file
    elif [ "$env_type" = "inline" ]; then
        migrate_inline_env
    else
        colorized_echo yellow "⚠️  Неизвестный тип конфигурации, пропускаю миграцию"
        return 0
    fi
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
}

# Функция для миграции .env файла
migrate_env_file() {
    local env_file="$ENV_FILE"
    
    if [ ! -f "$env_file" ]; then
        colorized_echo yellow "⚠️  Файл .env не найден, пропускаю миграцию"
        return 0
    fi
    
    local needs_migration=false
    local has_app_port=false
    local has_ssl_cert=false
    
    # Проверяем наличие старых переменных
    if grep -q "^APP_PORT=" "$env_file"; then
        has_app_port=true
        needs_migration=true
    fi
    
    if grep -q "^SSL_CERT=" "$env_file"; then
        has_ssl_cert=true
        needs_migration=true
    fi
    
    if [ "$needs_migration" = false ]; then
        colorized_echo green "✅ Файл .env в актуальном формате"
        colorized_echo blue "   Миграция не нужна — все переменные в новом формате:"
        colorized_echo blue "   • NODE_PORT (вместо APP_PORT)"
        colorized_echo blue "   • SECRET_KEY (вместо SSL_CERT)"
        return 0
    fi
    
    colorized_echo blue "🔄 В .env найдены старые переменные:"
    if [ "$has_app_port" = true ]; then
        colorized_echo yellow "   • APP_PORT → будет перенесён в NODE_PORT"
    fi
    if [ "$has_ssl_cert" = true ]; then
        colorized_echo yellow "   • SSL_CERT → будет перенесён в SECRET_KEY"
    fi
    echo
    colorized_echo blue "📝 Начинаю миграцию..."
    
    # Создаем backup
    local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$env_file" "$backup_file"
    colorized_echo green "✅ Резервная копия: $backup_file"
    
    # Выполняем миграцию
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^APP_PORT= ]]; then
            # Заменяем APP_PORT на NODE_PORT
            echo "$line" | sed 's/^APP_PORT=/NODE_PORT=/' >> "$temp_file"
            colorized_echo green "  ✅ Перенесено: APP_PORT → NODE_PORT"
        elif [[ "$line" =~ ^SSL_CERT= ]]; then
            # Заменяем SSL_CERT на SECRET_KEY
            echo "$line" | sed 's/^SSL_CERT=/SECRET_KEY=/' >> "$temp_file"
            colorized_echo green "  ✅ Перенесено: SSL_CERT → SECRET_KEY"
        elif [[ "$line" =~ ^###[[:space:]]*APP[[:space:]]*### ]]; then
            # Заменяем заголовок секции
            echo "### NODE ###" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$env_file"
    
    # Заменяем оригинальный файл
    mv "$temp_file" "$env_file"
    
    echo
    colorized_echo green "🎉 Миграция .env завершена!"
    colorized_echo blue "📋 Итог:"
    if [ "$has_app_port" = true ]; then
        colorized_echo green "   ✅ APP_PORT → NODE_PORT"
    fi
    if [ "$has_ssl_cert" = true ]; then
        colorized_echo green "   ✅ SSL_CERT → SECRET_KEY"
    fi
    colorized_echo blue "💾 Резервная копия: $backup_file"
    echo
    colorized_echo yellow "⚠️  Примечание: старые переменные устарели и будут удалены в будущих версиях"
    echo
    
    return 0
}

# Функция для миграции inline переменных в docker-compose.yml
migrate_inline_env() {
    local compose_file="$COMPOSE_FILE"
    
    if [ ! -f "$compose_file" ]; then
        colorized_echo yellow "⚠️  docker-compose.yml не найден, пропускаю миграцию"
        return 0
    fi
    
    local needs_migration=false
    
    # Проверяем наличие старых переменных в docker-compose.yml
    if grep -A 10 "environment:" "$compose_file" | grep -q "APP_PORT\|SSL_CERT"; then
        needs_migration=true
    fi
    
    if [ "$needs_migration" = false ]; then
        colorized_echo green "✅ docker-compose.yml в актуальном формате"
        colorized_echo blue "   Миграция не нужна — все переменные в новом формате:"
        colorized_echo blue "   • NODE_PORT (вместо APP_PORT)"
        colorized_echo blue "   • SECRET_KEY (вместо SSL_CERT)"
        return 0
    fi
    
    colorized_echo blue "🔄 В docker-compose.yml найдены старые переменные:"
    if grep -A 10 "environment:" "$compose_file" | grep -q "APP_PORT"; then
        colorized_echo yellow "   • APP_PORT → будет перенесён в NODE_PORT"
    fi
    if grep -A 10 "environment:" "$compose_file" | grep -q "SSL_CERT"; then
        colorized_echo yellow "   • SSL_CERT → будет перенесён в SECRET_KEY"
    fi
    echo
    colorized_echo blue "📝 Начинаю миграцию..."
    
    # Создаем backup
    local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$compose_file" "$backup_file"
    colorized_echo green "✅ Резервная копия: $backup_file"
    
    # Выполняем миграцию
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ "$line" =~ APP_PORT ]]; then
            # Заменяем APP_PORT на NODE_PORT
            echo "$line" | sed 's/APP_PORT/NODE_PORT/g' >> "$temp_file"
            colorized_echo green "  ✅ Перенесено: APP_PORT → NODE_PORT"
        elif [[ "$line" =~ SSL_CERT ]]; then
            # Заменяем SSL_CERT на SECRET_KEY
            echo "$line" | sed 's/SSL_CERT/SECRET_KEY/g' >> "$temp_file"
            colorized_echo green "  ✅ Перенесено: SSL_CERT → SECRET_KEY"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$compose_file"
    
    # Заменяем оригинальный файл
    mv "$temp_file" "$compose_file"
    
    echo
    colorized_echo green "🎉 Миграция docker-compose.yml завершена!"
    colorized_echo blue "💾 Резервная копия: $backup_file"
    echo
    
    # Предлагаем мигрировать на .env файл
    colorized_echo blue "💡 Совет: перенесите переменные в файл .env — так безопаснее"
    colorized_echo blue "   Переменные прямо в docker-compose.yml защищены хуже"
    echo
    read -p "Перенести в файл .env сейчас? (y/n): " -r migrate_to_env
    
    if [[ $migrate_to_env =~ ^[Yy]$ ]]; then
        migrate_to_env_file
    else
        colorized_echo yellow "⚠️  Оставляю переменные в docker-compose.yml"
    fi
    
    echo
    colorized_echo yellow "⚠️  Примечание: старые переменные устарели и будут удалены в будущих версиях"
    echo
    
    return 0
}

# Функция для миграции inline переменных в .env файл
migrate_to_env_file() {
    colorized_echo blue "🔄 Переношу переменные из docker-compose.yml в файл .env..."
    
    # Извлекаем переменные из docker-compose.yml
    local node_port=$(grep -A 10 "environment:" "$COMPOSE_FILE" 2>/dev/null | grep "NODE_PORT" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs)
    local secret_key=$(grep -A 10 "environment:" "$COMPOSE_FILE" 2>/dev/null | grep "SECRET_KEY" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs)
    
    # Создаем .env файл
    cat > "$ENV_FILE" <<EOL
### NODE ###
NODE_PORT=${node_port:-3000}

### XRAY ###
SECRET_KEY=$secret_key
EOL
    
    colorized_echo green "✅ Файл .env создан: $ENV_FILE"
    
    # Обновляем docker-compose.yml для использования env_file
    local temp_file=$(mktemp)
    local in_environment_section=false
    local environment_indent=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*environment:[[:space:]]*$ ]]; then
            in_environment_section=true
            environment_indent=$(echo "$line" | sed 's/environment:.*//' | grep -o '^[[:space:]]*')
            # Заменяем environment на env_file
            echo "${environment_indent}env_file:" >> "$temp_file"
            echo "${environment_indent}  - .env" >> "$temp_file"
            continue
        fi
        
        if [ "$in_environment_section" = true ]; then
            # Пропускаем строки с переменными окружения
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(NODE_PORT|SECRET_KEY|APP_PORT|SSL_CERT) ]]; then
                continue
            elif [[ "$line" =~ ^[[:space:]]*[A-Z_]+=.* ]]; then
                continue
            else
                in_environment_section=false
            fi
        fi
        
        if [ "$in_environment_section" = false ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$COMPOSE_FILE"
    
    # Заменяем оригинальный файл
    mv "$temp_file" "$COMPOSE_FILE"
    
    colorized_echo green "✅ docker-compose.yml теперь использует файл .env"
}

# ============================================
# Migration: Remove deprecated internal ports (v4.0.0)
# Since remnawave/node v2.5.0, SUPERVISORD_PORT and INTERNAL_REST_PORT
# are no longer used - they now use unix sockets internally
# ============================================
migrate_deprecated_ports() {
    local env_file="$ENV_FILE"
    local migrated=false
    local changes=""
    
    if [ ! -f "$env_file" ]; then
        return 0
    fi
    
    # Check for deprecated variables
    local has_supervisord_port=false
    local has_internal_rest_port=false
    
    if grep -q "^SUPERVISORD_PORT=" "$env_file" 2>/dev/null; then
        has_supervisord_port=true
    fi
    
    if grep -q "^INTERNAL_REST_PORT=" "$env_file" 2>/dev/null; then
        has_internal_rest_port=true
    fi
    
    if [ "$has_supervisord_port" = false ] && [ "$has_internal_rest_port" = false ]; then
        return 0
    fi
    
    echo
    colorized_echo cyan "🔄 Миграция: удаляю устаревшие настройки портов"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    colorized_echo blue "   С remnawave/node v2.5.0 внутренняя связь идёт через unix-сокеты."
    colorized_echo blue "   Из .env будут удалены устаревшие переменные:"
    
    if [ "$has_supervisord_port" = true ]; then
        colorized_echo yellow "   • SUPERVISORD_PORT (теперь /run/supervisord.sock)"
    fi
    
    if [ "$has_internal_rest_port" = true ]; then
        colorized_echo yellow "   • INTERNAL_REST_PORT (теперь /run/remnawave-internal.sock)"
    fi
    
    echo
    
    # Create backup before modifying
    local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$env_file" "$backup_file"
    
    # Remove deprecated variables
    if [ "$has_supervisord_port" = true ]; then
        sed -i '/^SUPERVISORD_PORT=/d' "$env_file"
        colorized_echo green "   ✅ SUPERVISORD_PORT удалён"
        migrated=true
    fi
    
    if [ "$has_internal_rest_port" = true ]; then
        sed -i '/^INTERNAL_REST_PORT=/d' "$env_file"
        colorized_echo green "   ✅ INTERNAL_REST_PORT удалён"
        migrated=true
    fi
    
    # Remove old comment section if exists
    sed -i '/^### Internal (local) ports$/d' "$env_file"
    
    # Update comment for XTLS_API_PORT if it exists
    if grep -q "^XTLS_API_PORT=" "$env_file"; then
        # Check if there's already the new comment above it
        if ! grep -q "^### Internal port" "$env_file"; then
            sed -i 's/^XTLS_API_PORT=/\n### Internal port (only XTLS_API_PORT is configurable since node v2.5.0)\nXTLS_API_PORT=/' "$env_file"
            # Remove any resulting double newlines
            sed -i '/^$/N;/^\n$/d' "$env_file"
        fi
    fi
    
    # Remove empty lines at the end of file and clean up
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$env_file" 2>/dev/null || true
    
    if [ "$migrated" = true ]; then
        echo
        colorized_echo green "🎉 Миграция завершена!"
        colorized_echo gray "   Резервная копия: $backup_file"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    fi
    
    return 0
}

# ============================================
# Migration: Add cap_add NET_ADMIN (v4.2.0)
# Since remnawave/node v2.6.0, NET_ADMIN capability is needed
# for IP Management features (view/drop user connections)
# ============================================
migrate_cap_add() {
    local compose_file="$COMPOSE_FILE"
    
    if [ ! -f "$compose_file" ]; then
        return 0
    fi
    
    # Check if cap_add with NET_ADMIN already exists (uncommented)
    if grep -qE "^[[:space:]]+cap_add:" "$compose_file" && \
       grep -qE "^[[:space:]]+-[[:space:]]*NET_ADMIN" "$compose_file"; then
        return 0
    fi
    
    echo
    colorized_echo cyan "🔄 Миграция: добавляю право NET_ADMIN (remnawave/node v2.6.0+)"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    colorized_echo blue "   NET_ADMIN включает управление IP:"
    colorized_echo blue "   • просмотр подключений пользователей с любой ноды"
    colorized_echo blue "   • удалённый разрыв подключений пользователей"
    echo
    
    # Create backup before modifying
    local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$compose_file" "$backup_file"
    
    # Determine indentation from docker-compose.yml
    local service_indent=$(get_service_property_indentation "$compose_file")
    local indent_type=""
    if [[ "$service_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local item_indent="${service_indent}${indent_type}"
    
    local escaped_service_indent=$(escape_for_sed "$service_indent")
    
    # Add cap_add section before ulimits (or after restart: always as fallback)
    local inserted=false
    
    if grep -q "^${escaped_service_indent}ulimits:" "$compose_file"; then
        # Insert cap_add block before ulimits using temp file approach
        local temp_file=$(mktemp)
        local ulimits_found=false
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^${service_indent}ulimits: ]] && [ "$ulimits_found" = false ]; then
                ulimits_found=true
                echo "${service_indent}cap_add:" >> "$temp_file"
                echo "${item_indent}- NET_ADMIN" >> "$temp_file"
            fi
            echo "$line" >> "$temp_file"
        done < "$compose_file"
        
        mv "$temp_file" "$compose_file"
        inserted=true
    elif grep -q "^${escaped_service_indent}restart:" "$compose_file"; then
        # Insert cap_add block after restart: always using temp file approach
        local temp_file=$(mktemp)
        
        while IFS= read -r line; do
            echo "$line" >> "$temp_file"
            if [[ "$line" =~ ^${service_indent}restart: ]]; then
                echo "${service_indent}cap_add:" >> "$temp_file"
                echo "${item_indent}- NET_ADMIN" >> "$temp_file"
            fi
        done < "$compose_file"
        
        mv "$temp_file" "$compose_file"
        inserted=true
    fi
    
    if [ "$inserted" = false ]; then
        colorized_echo yellow "⚠️  Не нашёл, куда вставить cap_add"
        rm -f "$backup_file"
        return 1
    fi
    
    # Validate the modified file
    colorized_echo blue "   Проверяю docker-compose.yml..."
    if validate_compose_file "$compose_file"; then
        colorized_echo green "   ✅ cap_add: NET_ADMIN добавлен"
        colorized_echo gray "   Резервная копия: $backup_file"
        cleanup_old_backups "$compose_file"
    else
        colorized_echo red "   ❌ Проверка не прошла! Восстанавливаю резервную копию..."
        if restore_backup "$backup_file" "$compose_file"; then
            colorized_echo green "   ✅ Резервная копия восстановлена"
        else
            colorized_echo red "   ❌ Не удалось восстановить резервную копию!"
        fi
        return 1
    fi
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    return 0
}

# ============================================
# Migration: /var/lib/$APP_NAME -> /var/log/$APP_NAME
# Handles log volumes, logrotate config, and log files
# ============================================
migrate_log_volumes() {
    local compose_file="$COMPOSE_FILE"
    local old_log_dir="/var/lib/$APP_NAME"
    local new_log_dir="$LOG_DIR"
    local migrated=false

    # Skip if old path doesn't exist anywhere
    if [ ! -f "$compose_file" ] && [ ! -d "$old_log_dir" ] && \
       ! grep -q "$old_log_dir" /etc/logrotate.d/remnanode 2>/dev/null; then
        return 0
    fi

    # Migrate docker-compose.yml volumes
    if [ -f "$compose_file" ]; then
        # Migrate active volume line
        if grep -q "$old_log_dir:$old_log_dir" "$compose_file" 2>/dev/null; then
            if [ "$migrated" = false ]; then
                echo
                colorized_echo cyan "🔄 Миграция: путь логов /var/lib -> /var/log"
                echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
                migrated=true
            fi
            sed -i "s|$old_log_dir:$old_log_dir|$new_log_dir:$new_log_dir|g" "$compose_file"
            colorized_echo blue "   Том перенесён: $old_log_dir -> $new_log_dir"
        fi

        # Migrate commented volume line
        if grep -q "#.*- $old_log_dir:$old_log_dir" "$compose_file" 2>/dev/null; then
            if [ "$migrated" = false ]; then
                echo
                colorized_echo cyan "🔄 Миграция: путь логов /var/lib -> /var/log"
                echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
                migrated=true
            fi
            sed -i "s|#\(.*- \)$old_log_dir:$old_log_dir|#\1$new_log_dir:$new_log_dir|g" "$compose_file"
            colorized_echo blue "   Закомментированный том перенесён"
        fi
    fi

    # Migrate logrotate config
    local logrotate_config="/etc/logrotate.d/remnanode"
    if [ -f "$logrotate_config" ] && grep -q "$old_log_dir" "$logrotate_config" 2>/dev/null; then
        if [ "$migrated" = false ]; then
            echo
            colorized_echo cyan "🔄 Миграция: путь логов /var/lib -> /var/log"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
            migrated=true
        fi
        sed -i "s|$old_log_dir|$new_log_dir|g" "$logrotate_config"
        colorized_echo blue "   Конфиг logrotate перенесён"
    fi

    # Migrate log files
    if ls "$old_log_dir"/*.log 1>/dev/null 2>&1; then
        if [ "$migrated" = false ]; then
            echo
            colorized_echo cyan "🔄 Миграция: путь логов /var/lib -> /var/log"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
            migrated=true
        fi
        mkdir -p "$new_log_dir"
        mv "$old_log_dir"/*.log "$new_log_dir/"
        colorized_echo blue "   Логи перенесены в $new_log_dir"
    fi

    if [ "$migrated" = true ]; then
        echo
        echo -e "\033[38;5;250m   Обновите конфиг Xray в панели:\033[0m"
        echo -e "\033[38;5;8m   ┌──────────────────────────────────────────────────┐\033[0m"
        echo -e "\033[38;5;8m   │\033[0m  \033[38;5;213m\"log\"\033[0m: {                                       \033[38;5;8m│\033[0m"
        echo -e "\033[38;5;8m   │\033[0m      \033[38;5;213m\"error\"\033[0m: \033[38;5;113m\"$new_log_dir/error.log\"\033[0m,      \033[38;5;8m│\033[0m"
        echo -e "\033[38;5;8m   │\033[0m      \033[38;5;213m\"access\"\033[0m: \033[38;5;113m\"$new_log_dir/access.log\"\033[0m,    \033[38;5;8m│\033[0m"
        echo -e "\033[38;5;8m   │\033[0m      \033[38;5;213m\"loglevel\"\033[0m: \033[38;5;113m\"warning\"\033[0m                    \033[38;5;8m│\033[0m"
        echo -e "\033[38;5;8m   │\033[0m  }                                              \033[38;5;8m│\033[0m"
        echo -e "\033[38;5;8m   └──────────────────────────────────────────────────┘\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    fi

    return 0
}

# ============================================
# Audit: Check docker-compose.yml against current template (v4.2.0)
# - No inline environment vars → offer to regenerate from template
# - Has inline environment vars → only add missing cap_add silently
# ============================================
audit_compose_file() {
    local compose_file="$COMPOSE_FILE"
    
    if [ ! -f "$compose_file" ]; then
        return 0
    fi
    
    # Detect if user has inline environment variables in docker-compose.yml
    local has_inline_env=false
    if grep -qE "^[[:space:]]+environment:" "$compose_file"; then
        # Check that there are actual variable lines (not just the key)
        if grep -A 20 "environment:" "$compose_file" | grep -qE "^[[:space:]]+-[[:space:]]*[A-Z_]+=|^[[:space:]]+[A-Z_]+="; then
            has_inline_env=true
        fi
    fi
    
    # If user has inline environment: don't offer regeneration,
    # just ensure cap_add is present (migrate_cap_add already handles this)
    if [ "$has_inline_env" = true ]; then
        return 0
    fi
    
    # --- No inline env: check if file needs regeneration ---
    local needs_regen=false
    local issues=()
    
    # Check for deprecated 'version:' key
    if grep -qE "^version:" "$compose_file"; then
        needs_regen=true
        issues+=("deprecated 'version:' key")
    fi
    
    # Check for missing hostname
    if ! grep -qE "^[[:space:]]+hostname:" "$compose_file"; then
        needs_regen=true
        issues+=("missing 'hostname:'")
    fi
    
    # Check for missing cap_add: NET_ADMIN
    if ! (grep -qE "^[[:space:]]+cap_add:" "$compose_file" && \
          grep -qE "^[[:space:]]+-[[:space:]]*NET_ADMIN" "$compose_file"); then
        needs_regen=true
        issues+=("missing 'cap_add: NET_ADMIN'")
    fi
    
    # Check for missing ulimits
    if ! grep -qE "^[[:space:]]+ulimits:" "$compose_file"; then
        needs_regen=true
        issues+=("missing 'ulimits:'")
    fi
    
    # Check for missing network_mode: host
    if ! grep -qE "^[[:space:]]+network_mode:[[:space:]]*host" "$compose_file"; then
        needs_regen=true
        issues+=("missing 'network_mode: host'")
    fi
    
    if [ "$needs_regen" = false ]; then
        return 0
    fi
    
    echo
    colorized_echo cyan "🔍 Проверка Docker Compose"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    colorized_echo yellow "   ⚠️  docker-compose.yml устарел:"
    for issue in "${issues[@]}"; do
        colorized_echo yellow "      • $issue"
    done
    echo
    
    colorized_echo blue "   docker-compose.yml можно пересоздать по текущему шаблону."
    colorized_echo gray "   Все настройки (image, volumes, env_file) сохранятся."
    echo
    read -p "   Пересоздать docker-compose.yml? [y/N]: " -r regen_choice
    
    if [[ $regen_choice =~ ^[Yy]$ ]]; then
        regenerate_compose_file
    else
        colorized_echo gray "   Пропущено. Отредактировать вручную: $APP_NAME edit"
    fi
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    return 0
}

# Regenerate docker-compose.yml preserving user settings (image, volumes, container name)
regenerate_compose_file() {
    local compose_file="$COMPOSE_FILE"
    
    colorized_echo blue "   📝 Пересоздаю docker-compose.yml..."
    
    # Extract current image
    local current_image=$(grep -E "image:.*remnawave/node" "$compose_file" 2>/dev/null | awk '{print $NF}' | tr -d '"' | tr -d "'" | head -1)
    if [ -z "$current_image" ]; then
        current_image="ghcr.io/remnawave/node:latest"
    fi
    
    # Extract current container name
    local current_container=$(grep -E "container_name:" "$compose_file" 2>/dev/null | awk '{print $NF}' | tr -d '"' | tr -d "'" | head -1)
    if [ -z "$current_container" ]; then
        current_container="$APP_NAME"
    fi
    
    # Extract existing volumes section (both active and commented)
    local volumes=()
    local commented_volumes=()
    local has_volumes_section=false
    local volumes_section_commented=false
    local in_volumes=false
    while IFS= read -r line; do
        # Uncommented volumes: key
        if [[ "$line" =~ ^[[:space:]]+volumes:[[:space:]]*$ ]]; then
            in_volumes=true
            has_volumes_section=true
            continue
        fi
        # Commented volumes: key (e.g. "    # volumes:")
        if [[ "$line" =~ ^[[:space:]]+#[[:space:]]*volumes:[[:space:]]*$ ]]; then
            in_volumes=true
            has_volumes_section=true
            volumes_section_commented=true
            continue
        fi
        if [ "$in_volumes" = true ]; then
            # Active volume entry
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                local vol_entry=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')
                volumes+=("$vol_entry")
            # Commented volume entry (e.g. "    #   - /path:/path" or "      # - /path:/path")
            elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*-[[:space:]] ]]; then
                local vol_entry=$(echo "$line" | sed 's/^[[:space:]]*#[[:space:]]*-[[:space:]]*//')
                commented_volumes+=("$vol_entry")
            # Empty line inside volumes section — skip
            elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
                continue
            # Any other property means end of volumes
            else
                break
            fi
        fi
    done < "$compose_file"
    
    # Create backup
    local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$compose_file" "$backup_file"
    colorized_echo green "   ✅ Резервная копия: $backup_file"
    
    # Generate new docker-compose.yml from current template
    cat > "$compose_file" <<EOL
services:
  remnanode:
    container_name: $current_container
    hostname: $current_container
    image: $current_image
    env_file:
      - .env
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
EOL
    
    # Re-add volumes section
    if [ ${#volumes[@]} -gt 0 ]; then
        # Has active volumes — write them, plus any commented ones
        echo "    volumes:" >> "$compose_file"
        for vol in "${volumes[@]}"; do
            echo "      - $vol" >> "$compose_file"
        done
        for vol in "${commented_volumes[@]}"; do
            echo "      # - $vol" >> "$compose_file"
        done
    elif [ ${#commented_volumes[@]} -gt 0 ]; then
        # Only commented volumes — preserve them
        echo "    # volumes:" >> "$compose_file"
        for vol in "${commented_volumes[@]}"; do
            echo "    #   - $vol" >> "$compose_file"
        done
    elif [ "$has_volumes_section" = false ]; then
        # No volumes section at all — add default commented template
        cat >> "$compose_file" <<EOL
    # volumes:
    #   - $XRAY_FILE:/usr/local/bin/xray
    #   - $GEOIP_FILE:/usr/local/share/xray/geoip.dat
    #   - $GEOSITE_FILE:/usr/local/share/xray/geosite.dat
    #   - $LOG_DIR:$LOG_DIR
    #   - /dev/shm:/dev/shm  # Uncomment for selfsteal socket access
EOL
    fi
    
    # Validate the regenerated file
    colorized_echo blue "   Проверяю новый docker-compose.yml..."
    if validate_compose_file "$compose_file"; then
        colorized_echo green "   ✅ docker-compose.yml пересоздан"
        colorized_echo green "   💾 Резервная копия сохранена: $backup_file"
    else
        colorized_echo red "   ❌ Проверка не прошла! Восстанавливаю резервную копию..."
        if restore_backup "$backup_file" "$compose_file"; then
            colorized_echo green "   ✅ Резервная копия восстановлена"
        else
            colorized_echo red "   ❌ Не удалось восстановить резервную копию!"
        fi
        return 1
    fi
    
    return 0
}

# Старая функция для обратной совместимости (теперь просто вызывает новую)
# migrate_env_variables() - уже определена выше

# update_command() {
#     check_running_as_root
#     if ! is_remnanode_installed; then
#         echo -e "\033[1;31m❌ RemnaNode not installed!\033[0m"
#         echo -e "\033[38;5;8m   Run '\033[38;5;15msudo $APP_NAME install\033[38;5;8m' first\033[0m"
#         exit 1
#     fi
    
#     detect_compose
    
#     echo -e "\033[1;37m🔄 Starting RemnaNode Update...\033[0m"
#     echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
#     echo -e "\033[38;5;250m📝 Step 1:\033[0m Updating script..."
#     update_remnanode_script
#     echo -e "\033[1;32m✅ Script updated\033[0m"
    
#     echo -e "\033[38;5;250m📝 Step 2:\033[0m Pulling latest version..."
#     update_remnanode
#     echo -e "\033[1;32m✅ Image updated\033[0m"
    
#     echo -e "\033[38;5;250m📝 Step 3:\033[0m Restarting services..."
#     down_remnanode
#     up_remnanode
#     echo -e "\033[1;32m✅ Services restarted\033[0m"
    
#     echo
#     echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
#     echo -e "\033[1;37m🎉 RemnaNode updated successfully!\033[0m"
#     echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
# }



# Display-only translation of update_command's $update_reason. The English
# value itself is still matched by the update logic below, so it stays as is.
_update_reason_ru() {
    case "$1" in
        "Local image not found, downloaded new version") echo "Локального образа не было, скачана новая версия" ;;
        "New version downloaded via docker pull") echo "Новая версия скачана через docker pull" ;;
        "Already up to date (verified via docker pull)") echo "Уже последняя версия (проверено через docker pull)" ;;
        "Unable to verify current version") echo "Не удалось проверить текущую версию" ;;
        "Image re-pinned to "*) echo "Образ перезакреплён на ${1#Image re-pinned to }" ;;
        "Running container does not match "*) echo "Запущенный контейнер не совпадает с ${1#Running container does not match }" ;;
        *) echo "$1" ;;
    esac
}

update_command() {
    check_running_as_root
    if ! is_remnanode_installed; then
        echo -e "\033[1;31m❌ RemnaNode не установлена!\033[0m"
        echo -e "\033[38;5;8m   Сначала выполните '\033[38;5;15msudo $APP_NAME install\033[38;5;8m'\033[0m"
        exit 1
    fi
    
    detect_compose
    
    echo -e "\033[1;37m🔄 Проверяю обновления RemnaNode...\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    # Проверяем и обновляем скрипт ПЕРВЫМ ДЕЛОМ
    echo -e "\033[38;5;250m📝 Шаг 1:\033[0m проверяю версию скрипта..."
    # Applies a newer script and re-execs into it with the same arguments — no
    # prompt, no "please run update again". Migrations only ship with the script,
    # so running an update from an outdated copy is never the right outcome.
    ensure_latest_script
    echo

    # Определяем используемый тег из docker-compose.yml
    local current_tag="latest"
    if [ -f "$COMPOSE_FILE" ]; then
        current_tag=$(grep -E "image:.*remnawave/node:" "$COMPOSE_FILE" | sed 's/.*remnawave\/node://' | tr -d '"' | tr -d "'" | xargs)
        if [ -z "$current_tag" ]; then
            current_tag="latest"
        fi
    fi
    
    # Determine registry from compose file (ghcr.io or Docker Hub) — needed both
    # for the optional --tag re-pin below and for the image lookups further down.
    local image_name
    if grep -q "ghcr.io/remnawave/node" "$COMPOSE_FILE" 2>/dev/null; then
        image_name="ghcr.io/remnawave/node"
    else
        image_name="remnawave/node"
    fi

    # `update --tag X` re-pins the compose image. This is the escape hatch out of
    # the SNI-gated 3.3.x line for anyone still on panel 3.2.x.
    #
    # The target tag is what the node will actually run, so it — not the tag
    # currently in the file — is what the panel-compat gate has to judge. The
    # gate therefore runs BEFORE anything is written: declining must leave the
    # installation exactly as it was.
    local requested_tag="$current_tag"
    local tag_repinned=false
    if [ -n "$NODE_IMAGE_TAG" ] && [ "$NODE_IMAGE_TAG" != "$current_tag" ]; then
        requested_tag="$NODE_IMAGE_TAG"
    fi

    echo -e "\033[38;5;250m🏷️  Текущий тег:\033[0m \033[38;5;15m$current_tag\033[0m"
    if [ "$requested_tag" != "$current_tag" ]; then
        echo -e "\033[38;5;250m🏷️  Запрошенный тег:\033[0m \033[38;5;15m$requested_tag\033[0m"
    fi

    # node 3.3.x only talks to panel 3.3.0+ (derived-SNI TLS gate) — confirm once,
    # BEFORE anything is pulled or rewritten, so a wrong answer costs nothing.
    if ! confirm_panel_supports_sni "$requested_tag" "update"; then
        exit 0
    fi

    if [ "$requested_tag" != "$current_tag" ]; then
        if ! verify_node_tag_exists "$image_name" "$requested_tag"; then
            echo -e "\033[1;31m❌ Образ ${image_name}:${requested_tag} не найден в реестре.\033[0m"
            exit 1
        fi

        cp "$COMPOSE_FILE" "${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        sed -i -E "s|(image:[[:space:]]*)([^[:space:]]*remnawave/node):[^[:space:]\"']*|\1\2:${requested_tag}|" "$COMPOSE_FILE"

        # Confirm the rewrite actually landed — a compose file with an unexpected
        # image line would otherwise be reported as re-pinned while unchanged.
        local repinned_tag
        repinned_tag=$(grep -E "image:.*remnawave/node:" "$COMPOSE_FILE" | sed 's/.*remnawave\/node://' | tr -d '"' | tr -d "'" | xargs)
        if [ "$repinned_tag" != "$requested_tag" ]; then
            echo -e "\033[1;31m❌ Не удалось сменить тег образа в $COMPOSE_FILE (по-прежнему '${repinned_tag:-unknown}')\033[0m"
            echo -e "\033[38;5;244m   Исправьте строку 'image:' вручную и запустите обновление снова.\033[0m"
            exit 1
        fi

        echo -e "\033[1;32m✅ Образ ноды перезакреплён:\033[0m \033[38;5;15m${image_name}:${requested_tag}\033[0m"
        current_tag="$requested_tag"
        tag_repinned=true
    fi

    # Получаем локальную версию образа
    echo -e "\033[38;5;250m📝 Шаг 2:\033[0m проверяю локальный образ..."
    local local_image_id=""
    local local_created=""

    if docker images ${image_name}:$current_tag --format "table {{.ID}}\t{{.CreatedAt}}" | grep -v "IMAGE ID" > /dev/null 2>&1; then
        local_image_id=$(docker images ${image_name}:$current_tag --format "{{.ID}}" | head -1)
        local_created=$(docker images ${image_name}:$current_tag --format "{{.CreatedAt}}" | head -1 | cut -d' ' -f1,2)
        
        echo -e "\033[1;32m✅ Локальный образ найден\033[0m"
        echo -e "\033[38;5;8m   ID образа: $local_image_id\033[0m"
        echo -e "\033[38;5;8m   Создан: $local_created\033[0m"
    else
        echo -e "\033[1;33m⚠️  Локальный образ не найден\033[0m"
        local_image_id="none"
    fi
    
    # Проверяем обновления через docker pull
    echo -e "\033[38;5;250m📝 Шаг 3:\033[0m ищу обновления через docker pull..."
    
    # Сохраняем текущий образ ID для сравнения
    local old_image_id="$local_image_id"
    
    # Запускаем docker pull
    if $COMPOSE -f $COMPOSE_FILE pull --quiet 2>/dev/null; then
        # Проверяем, изменился ли ID образа после pull
        local new_image_id=$(docker images ${image_name}:$current_tag --format "{{.ID}}" | head -1)
        
        local needs_update=false
        local update_reason=""
        
        if [ "$old_image_id" = "none" ]; then
            needs_update=true
            update_reason="Local image not found, downloaded new version"
            echo -e "\033[1;33m🔄 Скачан новый образ\033[0m"
        elif [ "$old_image_id" != "$new_image_id" ]; then
            needs_update=true
            update_reason="New version downloaded via docker pull"
            echo -e "\033[1;33m🔄 Найдена и скачана новая версия\033[0m"
        else
            needs_update=false
            update_reason="Already up to date (verified via docker pull)"
            echo -e "\033[1;32m✅ Уже последняя версия\033[0m"
        fi
    else
        echo -e "\033[1;33m⚠️  docker pull не удался, считаю, что обновление нужно\033[0m"
        local needs_update=true
        local update_reason="Unable to verify current version"
        local new_image_id="$old_image_id"
    fi

    # The pull comparison only answers "did the image behind this tag change".
    # It says nothing about whether the RUNNING container is built from it, so
    # two cases would otherwise end in a silent no-op:
    #   • `update --tag X` where X is already in the local image store
    #   • an earlier update that pulled but was interrupted before the restart
    # Reconcile against the container itself.
    if [ "$needs_update" = false ]; then
        local running_image_id=""
        running_image_id=$(docker inspect -f '{{.Image}}' "$APP_NAME" 2>/dev/null | sed 's/^sha256://' | cut -c1-12)
        local target_image_id="$new_image_id"

        if [ "$tag_repinned" = true ]; then
            needs_update=true
            update_reason="Image re-pinned to ${current_tag}"
            echo -e "\033[1;33m🔄 Тег перезакреплён на ${current_tag} — контейнер нужно пересоздать\033[0m"
        elif [ -n "$running_image_id" ] && [ -n "$target_image_id" ] && \
             [ "$target_image_id" != "none" ] && [ "$running_image_id" != "$target_image_id" ]; then
            needs_update=true
            update_reason="Running container does not match ${image_name}:${current_tag}"
            echo -e "\033[1;33m🔄 Запущенный контейнер не совпадает с образом в compose\033[0m"
        fi
    fi
    
    echo
    echo -e "\033[1;37m📊 Анализ обновления:\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    
    if [ "$needs_update" = true ]; then
        echo -e "\033[1;33m🔄 Есть обновление\033[0m"
        echo -e "\033[38;5;250m   Причина: \033[38;5;15m$(_update_reason_ru "$update_reason")\033[0m"
        echo
        
        # Автоматически продолжаем, когда решение уже принято: новая версия
        # скачана, пользователь явно задал --tag, или контейнер рассинхронизирован
        # с compose-файлом (в последних двух случаях спрашивать нечего).
        if [[ "$update_reason" == *"downloaded"* ]] || [ "$tag_repinned" = true ] || \
           [[ "$update_reason" == *"does not match"* ]] || [ "$FORCE_MODE" == "true" ] || [ ! -t 0 ]; then
            echo -e "\033[1;37m🚀 Продолжаю обновление...\033[0m"
        else
            read -p "Обновить? (y/n): " -r confirm_update
            if [[ ! $confirm_update =~ ^[Yy]$ ]]; then
                echo -e "\033[1;31m❌ Обновление отменено\033[0m"
                exit 0
            fi
        fi
        
        echo
        echo -e "\033[1;37m🚀 Обновляю...\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        
        # Проверяем и мигрируем переменные окружения
        echo -e "\033[38;5;250m📝 Шаг 4:\033[0m проверяю переменные окружения..."
        migrate_env_variables
        
        # Миграция устаревших портов (v4.0.0+)
        migrate_deprecated_ports

        # Миграция cap_add NET_ADMIN (v4.2.0+)
        migrate_cap_add

        # Миграция log volumes /var/lib -> /var/log (v4.3.0+)
        migrate_log_volumes
        
        # Аудит docker-compose.yml на соответствие актуальному шаблону
        audit_compose_file
        
        # Проверяем, запущен ли контейнер
        local was_running=false
        if is_remnanode_up; then
            was_running=true
            echo -e "\033[38;5;250m📝 Шаг 5:\033[0m останавливаю контейнер..."
            if down_remnanode; then
                echo -e "\033[1;32m✅ Контейнер остановлен\033[0m"
            else
                echo -e "\033[1;31m❌ Не удалось остановить контейнер\033[0m"
                exit 1
            fi
        else
            echo -e "\033[38;5;250m📝 Шаг 5:\033[0m контейнер не запущен, останавливать нечего..."
        fi
        
        # Загружаем образ только если еще не загружен
        if [[ "$update_reason" != *"downloaded"* ]]; then
            echo -e "\033[38;5;250m📝 Шаг 6:\033[0m скачиваю последний образ..."
            if update_remnanode; then
                echo -e "\033[1;32m✅ Образ обновлён\033[0m"
                # Обновляем ID образа
                new_image_id=$(docker images ${image_name}:$current_tag --format "{{.ID}}" | head -1)
            else
                echo -e "\033[1;31m❌ Не удалось скачать образ\033[0m"
                
                # Если контейнер был запущен, пытаемся его восстановить
                if [ "$was_running" = true ]; then
                    echo -e "\033[38;5;250m🔄 Пробую восстановить сервис...\033[0m"
                    up_remnanode
                fi
                exit 1
            fi
        else
            echo -e "\033[38;5;250m📝 Шаг 6:\033[0m образ уже обновлён при проверке\033[0m"
        fi
        
        # Запускаем контейнер только если он был запущен ранее
        if [ "$was_running" = true ]; then
            echo -e "\033[38;5;250m📝 Шаг 7:\033[0m запускаю обновлённый контейнер..."
            if up_remnanode; then
                echo -e "\033[1;32m✅ Контейнер запущен\033[0m"
            else
                echo -e "\033[1;31m❌ Не удалось запустить контейнер\033[0m"
                exit 1
            fi
        else
            echo -e "\033[38;5;250m📝 Шаг 7:\033[0m контейнер не был запущен, оставляю остановленным..."
        fi
        
        # Показываем финальную информацию
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo -e "\033[1;37m🎉 RemnaNode обновлена!\033[0m"
        
        # Получаем актуальную информацию об образе
        local final_image_id=$(docker images ${image_name}:$current_tag --format "{{.ID}}" | head -1)
        local final_created=$(docker images ${image_name}:$current_tag --format "{{.CreatedAt}}" | head -1 | cut -d' ' -f1,2)
        
        # Fallback если не нашли по полному имени
        if [ -z "$final_image_id" ]; then
            final_image_id=$(docker images --format "{{.ID}}" | head -1)
            final_created=$(docker images --format "{{.CreatedAt}}" | head -1 | cut -d' ' -f1,2)
        fi
        
        # Получаем версию RemnaNode из контейнера
        local node_version="N/A"
        if [ "$was_running" = true ]; then
            node_version=$(get_remnanode_version 2>/dev/null || echo "N/A")
        fi
        
        echo -e "\033[1;37m📋 Итог обновления:\033[0m"
        echo -e "\033[38;5;250m   RemnaNode: \033[38;5;15mv${node_version}\033[0m"
        echo -e "\033[38;5;250m   ID образа: \033[38;5;8m${final_image_id:-N/A}\033[0m"
        echo -e "\033[38;5;250m   Создан:    \033[38;5;15m${final_created:-N/A}\033[0m"
        echo -e "\033[38;5;250m   Скрипт:    \033[38;5;15mv$current_script_version\033[0m"
        
        if [ "$was_running" = true ]; then
            echo -e "\033[38;5;250m   Статус:    \033[1;32mработает\033[0m"
        else
            echo -e "\033[38;5;250m   Статус:    \033[1;33mостановлена\033[0m"
            echo -e "\033[38;5;8m   Запуск: '\033[38;5;15msudo $APP_NAME up\033[38;5;8m'\033[0m"
        fi
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        
    else
        echo -e "\033[1;32m✅ Уже последняя версия\033[0m"
        echo -e "\033[38;5;250m   Причина: \033[38;5;15m$(_update_reason_ru "$update_reason")\033[0m"
        echo
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
        echo -e "\033[1;37m📊 Текущее состояние:\033[0m"
        
        echo -e "\033[38;5;250m   Скрипт:    \033[38;5;15mv$current_script_version\033[0m"
        
        if is_remnanode_up; then
            echo -e "\033[38;5;250m   Контейнер: \033[1;32mработает ✅\033[0m"
        else
            echo -e "\033[38;5;250m   Контейнер: \033[1;33mостановлен ⏹️\033[0m"
            echo -e "\033[38;5;8m   Запуск: '\033[38;5;15msudo $APP_NAME up\033[38;5;8m'\033[0m"
        fi
        
        echo -e "\033[38;5;250m   Тег образа: \033[38;5;15m$current_tag\033[0m"
        echo -e "\033[38;5;250m   ID образа:  \033[38;5;15m$local_image_id\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    fi
}

identify_the_operating_system_and_architecture() {
    if [[ "$(uname)" == 'Linux' ]]; then
        case "$(uname -m)" in
            'i386' | 'i686') ARCH='32' ;;
            'amd64' | 'x86_64') ARCH='64' ;;
            'armv5tel') ARCH='arm32-v5' ;;
            'armv6l') ARCH='arm32-v6'; grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5' ;;
            'armv7' | 'armv7l') ARCH='arm32-v7a'; grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5' ;;
            'armv8' | 'aarch64') ARCH='arm64-v8a' ;;
            'mips') ARCH='mips32' ;;
            'mipsle') ARCH='mips32le' ;;
            'mips64') ARCH='mips64'; lscpu | grep -q "Little Endian" && ARCH='mips64le' ;;
            'mips64le') ARCH='mips64le' ;;
            'ppc64') ARCH='ppc64' ;;
            'ppc64le') ARCH='ppc64le' ;;
            'riscv64') ARCH='riscv64' ;;
            's390x') ARCH='s390x' ;;
            *) echo "Ошибка: архитектура не поддерживается."; exit 1 ;;
        esac
    else
        echo "Ошибка: эта операционная система не поддерживается."
        exit 1
    fi
}

# Функция для проверки, примонтирован ли Xray файл в контейнер
is_xray_mounted() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        return 1
    fi
    
    # Проверяем, есть ли активная (не закомментированная) строка с монтированием xray
    if grep -v "^[[:space:]]*#" "$COMPOSE_FILE" | grep -q "$XRAY_FILE"; then
        return 0
    else
        return 1
    fi
}

get_current_xray_core_version() {
    # Сначала проверяем, примонтирован ли Xray в контейнер
    if is_xray_mounted && [ -f "$XRAY_FILE" ]; then
        # Xray примонтирован, получаем версию из локального файла
        # Присваивание как условие if: при set -e «голое» version_output=$(...)
        # с ненулевым кодом завершило бы скрипт до проверки [ $? -eq 0 ].
        if version_output=$("$XRAY_FILE" -version 2>/dev/null); then
            version=$(echo "$version_output" | head -n1 | awk '{print $2}')
            echo "$version (внешний)"
            return 0
        fi
    fi
    
    # Если Xray не примонтирован или файл не работает, проверяем встроенную версию в контейнере
    local container_version=$(get_container_xray_version 2>/dev/null)
    if [ "$container_version" != "unknown" ] && [ -n "$container_version" ]; then
        echo "$container_version (встроенный)"
        return 0
    fi
    
    echo "Not installed"
    return 1
}

get_xray_core() {
    identify_the_operating_system_and_architecture
    clear
    
    validate_version() {
        local version="$1"
        local response=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/tags/$version")
        if echo "$response" | grep -q '"message": "Not Found"'; then
            echo "invalid"
        else
            echo "valid"
        fi
    }
    
    print_menu() {
        clear
        
        # Заголовок в монохромном стиле
        echo -e "\033[1;37m⚡ Установщик Xray-core\033[0m \033[38;5;8mвыбор версии\033[0m \033[38;5;244mv$SCRIPT_VERSION\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
        echo
        
        # Текущая версия
        # || true: функция возвращает 1, когда Xray не установлен (контейнер
        # остановлен / не примонтирован). Без защиты set -e (стр. 3) молча убил
        # бы скрипт прямо здесь — баннер уже показан, а меню не появляется.
        current_version=$(get_current_xray_core_version || true)
        echo -e "\033[1;37m🌐 Текущее состояние:\033[0m"
        printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Версия Xray:   " "${current_version/#Not installed/Не установлен}"
        printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Архитектура:   " "$ARCH"
        
        # Показываем путь установки только если Xray примонтирован
        if is_xray_mounted; then
            printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Путь установки:" "$XRAY_FILE"
            printf "   \033[38;5;15m%s\033[0m \033[1;32m%s\033[0m\n" "Монтирование:  " "✅ Подключён к контейнеру"
        else
            printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Монтирование:  " "⚪ Встроенная версия"
        fi
        echo
        
        # Показываем режим выбора релизов
        echo -e "\033[1;37m🎯 Какие релизы показывать:\033[0m"
        if [ "$show_prereleases" = true ]; then
            printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m \033[38;5;244m(включая pre-release)\033[0m\n" "Сейчас:        " "Все релизы"
        else
            printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m \033[1;37m(только стабильные)\033[0m\n" "Сейчас:        " "Стабильные релизы"
        fi
        echo
        
        # Доступные версии с метками
        echo -e "\033[1;37m🚀 Доступные версии:\033[0m"
        for ((i=0; i<${#versions[@]}; i++)); do
            local version_num=$((i + 1))
            local version_name="${versions[i]}"
            local is_prerelease="${prereleases[i]}"
            
            # Определяем тип релиза и используем echo вместо printf
            if [ "$is_prerelease" = "true" ]; then
                echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[38;5;244m(pre-release)\033[0m"
            elif [ $i -eq 0 ] && [ "$is_prerelease" = "false" ]; then
                echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[1;37m(последняя стабильная)\033[0m"
            else
                echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[38;5;8m(стабильная)\033[0m"
            fi
        done
        echo
        
        # Опции
        echo -e "\033[1;37m🔧 Действия:\033[0m"
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "M:" "📝 Ввести версию вручную"
        if [ "$show_prereleases" = true ]; then
            printf "   \033[38;5;15m%-3s\033[0m %s\n" "S:" "🔒 Только стабильные релизы"
        else
            printf "   \033[38;5;15m%-3s\033[0m %s\n" "A:" "🧪 Все релизы (включая pre-release)"
        fi
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "R:" "🔄 Обновить список версий"
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "D:" "🏠 Вернуть встроенный в контейнер Xray"
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "Q:" "❌ Выйти из установщика"
        echo
        
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
        echo -e "\033[1;37m📖 Как выбрать:\033[0m"
        echo -e "   Выберите номер \033[38;5;15m(1-${#versions[@]})\033[0m, \033[38;5;15mM\033[0m — ввести вручную, \033[38;5;15mA/S\033[0m — все/стабильные, \033[38;5;15mD\033[0m — встроенный Xray, \033[38;5;15mQ\033[0m — выход"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 70))\033[0m"
    }
    
    fetch_versions() {
        local include_prereleases="$1"
        echo -e "\033[1;37m🔍 Получаю список версий Xray-core...\033[0m"
        
        if [ "$include_prereleases" = true ]; then
            echo -e "\033[38;5;8m   Включая pre-release...\033[0m"
            latest_releases=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=8")
        else
            echo -e "\033[38;5;8m   Только стабильные...\033[0m"
            latest_releases=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=15")
        fi
        
        if [ -z "$latest_releases" ] || echo "$latest_releases" | grep -q '"message":'; then
            echo -e "\033[1;31m❌ Не удалось получить список версий. Проверьте подключение к интернету.\033[0m"
            return 1
        fi
        
        # Парсим JSON и извлекаем нужную информацию
        versions=()
        prereleases=()
        
        # Извлекаем данные с помощью более надежного парсинга
        local temp_file=$(mktemp)
        echo "$latest_releases" | grep -E '"(tag_name|prerelease)"' > "$temp_file"
        
        local current_version=""
        local count=0
        local max_count=6
        
        while IFS= read -r line; do
            if [[ "$line" =~ \"tag_name\":[[:space:]]*\"([^\"]+)\" ]]; then
                current_version="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"prerelease\":[[:space:]]*(true|false) ]]; then
                local is_prerelease="${BASH_REMATCH[1]}"
                
                # Если не показываем pre-releases, пропускаем их
                if [ "$include_prereleases" = false ] && [ "$is_prerelease" = "true" ]; then
                    current_version=""
                    continue
                fi
                
                # Добавляем версию в массивы
                if [ -n "$current_version" ] && [ $count -lt $max_count ]; then
                    versions+=("$current_version")
                    prereleases+=("$is_prerelease")
                    ((count++)) || true
                fi
                current_version=""
            fi
        done < "$temp_file"
        
        rm "$temp_file"
        
        if [ ${#versions[@]} -eq 0 ]; then
            echo -e "\033[1;31m❌ Версии не найдены.\033[0m"
            return 1
        fi
        
        echo -e "\033[1;32m✅ Найдено версий: ${#versions[@]}\033[0m"
        return 0
    }
    
    # Инициализация
    local show_prereleases=false
    
    # Первоначальная загрузка версий
    if ! fetch_versions "$show_prereleases"; then
        exit 1
    fi
    
    while true; do
        print_menu
        echo -n -e "\033[1;37m> \033[0m"
        read choice
        
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#versions[@]}" ]; then
            choice=$((choice - 1))
            selected_version=${versions[choice]}
            local selected_prerelease=${prereleases[choice]}
            
            echo
            if [ "$selected_prerelease" = "true" ]; then
                echo -e "\033[1;33m⚠️  Выбрана предварительная версия: \033[1;37m$selected_version\033[0m"
                echo -e "\033[38;5;8m   В pre-release могут быть ошибки, для рабочих серверов их не советуют.\033[0m"
                read -p "Точно продолжить? (y/n): " -r confirm_prerelease
                if [[ ! $confirm_prerelease =~ ^[Yy]$ ]]; then
                    echo -e "\033[1;31m❌ Установка отменена.\033[0m"
                    continue
                fi
            else
                echo -e "\033[1;32m✅ Выбрана стабильная версия: \033[1;37m$selected_version\033[0m"
            fi
            break
            
        elif [ "$choice" == "M" ] || [ "$choice" == "m" ]; then
            echo
            echo -e "\033[1;37m📝 Ввод версии вручную:\033[0m"
            while true; do
                echo -n -e "\033[38;5;8mВведите версию (например, v1.8.4): \033[0m"
                read custom_version
                
                if [ -z "$custom_version" ]; then
                    echo -e "\033[1;31m❌ Версия не может быть пустой. Попробуйте ещё раз.\033[0m"
                    continue
                fi
                
                echo -e "\033[1;37m🔍 Проверяю версию $custom_version...\033[0m"
                if [ "$(validate_version "$custom_version")" == "valid" ]; then
                    selected_version="$custom_version"
                    echo -e "\033[1;32m✅ Версия $custom_version найдена!\033[0m"
                    break 2
                else
                    echo -e "\033[1;31m❌ Версия $custom_version не найдена. Попробуйте ещё раз.\033[0m"
                    echo -e "\033[38;5;8m   Подсказка: список на https://github.com/XTLS/Xray-core/releases\033[0m"
                    echo
                fi
            done
            
        elif [ "$choice" == "A" ] || [ "$choice" == "a" ]; then
            if [ "$show_prereleases" = false ]; then
                show_prereleases=true
                if ! fetch_versions "$show_prereleases"; then
                    show_prereleases=false
                    continue
                fi
            fi
            
        elif [ "$choice" == "S" ] || [ "$choice" == "s" ]; then
            if [ "$show_prereleases" = true ]; then
                show_prereleases=false
                if ! fetch_versions "$show_prereleases"; then
                    show_prereleases=true
                    continue
                fi
            fi
            
        elif [ "$choice" == "R" ] || [ "$choice" == "r" ]; then
            if ! fetch_versions "$show_prereleases"; then
                continue
            fi
            
        elif [ "$choice" == "D" ] || [ "$choice" == "d" ]; then
            echo
            echo -e "\033[1;33m🏠 Вернуть встроенный в контейнер Xray\033[0m"
            echo -e "\033[38;5;8m   Внешний Xray будет отключён, контейнер возьмёт свою встроенную версию.\033[0m"
            echo
            read -p "Точно вернуть встроенный Xray? (y/n): " -r confirm_restore
            if [[ $confirm_restore =~ ^[Yy]$ ]]; then
                restore_to_container_default
                echo
                echo -n -e "\033[38;5;8mНажмите Enter, чтобы продолжить...\033[0m"
                read
            else
                echo -e "\033[1;31m❌ Возврат отменён.\033[0m"
                echo
                echo -n -e "\033[38;5;8mНажмите Enter, чтобы продолжить...\033[0m"
                read
            fi
            
        elif [ "$choice" == "Q" ] || [ "$choice" == "q" ]; then
            echo
            echo -e "\033[1;31m❌ Установка отменена.\033[0m"
            exit 0
            
        else
            echo
            echo -e "\033[1;31m❌ Неверный выбор: '$choice'\033[0m"
            echo -e "\033[38;5;8m   Введите номер от 1 до ${#versions[@]}, M — вручную, A/S — все/стабильные, R — обновить список, D — встроенный Xray, Q — выход.\033[0m"
            echo
            echo -n -e "\033[38;5;8mНажмите Enter, чтобы продолжить...\033[0m"
            read
        fi
    done
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo -e "\033[1;37m🚀 Начинаю установку\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    
    # Проверка и установка unzip
    if ! dpkg -s unzip >/dev/null 2>&1; then
        echo -e "\033[1;37m📦 Устанавливаю нужные пакеты...\033[0m"
        detect_os
        install_package unzip
        echo -e "\033[1;32m✅ Пакеты установлены\033[0m"
    fi
    
    mkdir -p "$DATA_DIR"
    cd "$DATA_DIR"
    
    xray_filename="Xray-linux-$ARCH.zip"
    xray_download_url="https://github.com/XTLS/Xray-core/releases/download/${selected_version}/${xray_filename}"
    
    # Скачивание с прогрессом
    echo -e "\033[1;37m📥 Скачиваю Xray-core $selected_version...\033[0m"
    echo -e "\033[38;5;8m   URL: $xray_download_url\033[0m"
    
    if wget "${xray_download_url}" -q --show-progress; then
        echo -e "\033[1;32m✅ Скачано\033[0m"
    else
        echo -e "\033[1;31m❌ Скачать не удалось!\033[0m"
        echo -e "\033[38;5;8m   Проверьте подключение к интернету или выберите другую версию.\033[0m"
        exit 1
    fi
    
    # Извлечение
    echo -e "\033[1;37m📦 Распаковываю Xray-core...\033[0m"
    if unzip -o "${xray_filename}" -d "$DATA_DIR" >/dev/null 2>&1; then
        echo -e "\033[1;32m✅ Распаковано\033[0m"
    else
        echo -e "\033[1;31m❌ Распаковать не удалось!\033[0m"
        echo -e "\033[38;5;8m   Возможно, скачанный файл повреждён.\033[0m"
        exit 1
    fi
    
    # Очистка и настройка прав
    rm "${xray_filename}"
    chmod +x "$XRAY_FILE"
    
    # Финальное сообщение
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo -e "\033[1;37m🎉 Установка завершена!\033[0m"
    
    # Информация об установке
    echo -e "\033[1;37m📋 Подробности установки:\033[0m"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Версия:        " "$selected_version"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Архитектура:   " "$ARCH"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Путь установки:" "$XRAY_FILE"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Размер файла:  " "$(du -h "$XRAY_FILE" | cut -f1)"
    echo
    
    # Проверка версии
    echo -e "\033[1;37m🔍 Проверяю установку...\033[0m"
    if installed_version=$("$XRAY_FILE" -version 2>/dev/null | head -n1 | awk '{print $2}'); then
        echo -e "\033[1;32m✅ Xray-core работает\033[0m"
        printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s\033[0m\n" "Рабочая версия:" "$installed_version"
    else
        echo -e "\033[1;31m⚠️  Установка завершена, но проверка не прошла\033[0m"
        echo -e "\033[38;5;8m   Возможно, этот файл не подходит для вашей системы\033[0m"
    fi
}



# Функция для создания резервной копии файла
create_backup() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$file" ]; then
        cp "$file" "$backup_file"
        echo "$backup_file"
        return 0
    else
        return 1
    fi
}

# Функция для восстановления из резервной копии
restore_backup() {
    local backup_file="$1"
    local original_file="$2"
    
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$original_file"
        return 0
    else
        return 1
    fi
}

# Функция для проверки валидности docker-compose файла
validate_compose_file() {
    local compose_file="$1"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    

    local current_dir=$(pwd)
    

    cd "$(dirname "$compose_file")"
    

    if command -v docker >/dev/null 2>&1; then

        detect_compose
        
        # Проверяем синтаксис файла
        if $COMPOSE config >/dev/null 2>&1; then
            cd "$current_dir"
            return 0
        else

            colorized_echo red "Ошибки в Docker Compose:"
            $COMPOSE config 2>&1 | head -10
            cd "$current_dir"
            return 1
        fi
    else

        if grep -q "services:" "$compose_file" && grep -q "remnanode:" "$compose_file"; then
            cd "$current_dir"
            return 0
        else
            cd "$current_dir"
            return 1
        fi
    fi
}

# Функция для удаления старых резервных копий (оставляем только последние 5)
cleanup_old_backups() {
    local file_pattern="$1"
    local keep_count=5
    
    # Найти все файлы резервных копий и удалить старые
    ls -t ${file_pattern}.backup.* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -f 2>/dev/null || true
}

# Обновленная функция для определения отступов из docker-compose.yml
get_indentation_from_compose() {
    local compose_file="$1"
    local indentation=""
    
    if [ -f "$compose_file" ]; then
        # Сначала ищем строку с "remnanode:" (точное совпадение)
        local service_line=$(grep -n "remnanode:" "$compose_file" | head -1)
        if [ -n "$service_line" ]; then
            local line_content=$(echo "$service_line" | cut -d':' -f2-)
            indentation=$(echo "$line_content" | sed 's/remnanode:.*//' | grep -o '^[[:space:]]*')
        fi
        
        # Если не нашли точное совпадение, ищем любой сервис с "remna"
        if [ -z "$indentation" ]; then
            local remna_service_line=$(grep -E "^[[:space:]]*[a-zA-Z0-9_-]*remna[a-zA-Z0-9_-]*:" "$compose_file" | head -1)
            if [ -n "$remna_service_line" ]; then
                indentation=$(echo "$remna_service_line" | sed 's/[a-zA-Z0-9_-]*remna[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
            fi
        fi
        
        # Если не нашли сервис с "remna", пробуем найти любой сервис
        if [ -z "$indentation" ]; then
            local any_service_line=$(grep -E "^[[:space:]]*[a-zA-Z0-9_-]+:" "$compose_file" | head -1)
            if [ -n "$any_service_line" ]; then
                indentation=$(echo "$any_service_line" | sed 's/[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
            fi
        fi
    fi
    
    # Если ничего не нашли, используем 2 пробела по умолчанию
    if [ -z "$indentation" ]; then
        indentation="  "
    fi
    
    echo "$indentation"
}

# Обновленная функция для получения отступа для свойств сервиса
get_service_property_indentation() {
    local compose_file="$1"
    local base_indent=$(get_indentation_from_compose "$compose_file")
    local indent_type=""
    if [[ "$base_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local property_indent=""
    if [ -f "$compose_file" ]; then
        local in_remna_service=false
        local current_service=""
        
        while IFS= read -r line; do

            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$ ]]; then
                current_service=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/:[[:space:]]*$//')
                

                if [[ "$current_service" =~ remna ]]; then
                    in_remna_service=true
                else
                    in_remna_service=false
                fi
                continue
            fi
            

            if [ "$in_remna_service" = true ]; then
                local line_indent=$(echo "$line" | grep -o '^[[:space:]]*')
                

                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$ ]] && [ ${#line_indent} -le ${#base_indent} ]; then
                    break
                fi
                

                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                    property_indent=$(echo "$line" | sed 's/[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
                    break
                fi
            fi
        done < "$compose_file"
    fi
    
    # Если не нашли свойство, добавляем один уровень отступа к базовому
    if [ -z "$property_indent" ]; then
        property_indent="${base_indent}${indent_type}"
    fi
    
    echo "$property_indent"
}


escape_for_sed() {
    local text="$1"
    echo "$text" | sed 's/[]\.*^$()+?{|[]/\\&/g' | sed 's/\t/\\t/g'
}


update_core_command() {
    check_running_as_root
    get_xray_core
    colorized_echo blue "Добавляю том Xray-core в docker-compose.yml..."
    

    if [ ! -f "$COMPOSE_FILE" ]; then
        colorized_echo red "Файл Docker Compose не найден: $COMPOSE_FILE"
        exit 1
    fi
    

    colorized_echo blue "Делаю резервную копию docker-compose.yml..."
    backup_file=$(create_backup "$COMPOSE_FILE")
    if [ $? -eq 0 ]; then
        colorized_echo green "Резервная копия: $backup_file"
    else
        colorized_echo red "Не удалось сделать резервную копию"
        exit 1
    fi
    

    local service_indent=$(get_service_property_indentation "$COMPOSE_FILE")
    

    local indent_type=""
    if [[ "$service_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local volume_item_indent="${service_indent}${indent_type}"
    

    local escaped_service_indent=$(escape_for_sed "$service_indent")
    local escaped_volume_item_indent=$(escape_for_sed "$volume_item_indent")

    if grep -q "^${escaped_service_indent}volumes:" "$COMPOSE_FILE"; then
        # Remove existing xray-related volumes using # as delimiter to avoid issues with / in paths
        sed -i "\#$XRAY_FILE#d" "$COMPOSE_FILE"
        sed -i "\#geoip\.dat#d" "$COMPOSE_FILE"
        sed -i "\#geosite\.dat#d" "$COMPOSE_FILE"
        
        # Create temporary file with volume mounts
        temp_volumes=$(mktemp)
        echo "${volume_item_indent}- $XRAY_FILE:/usr/local/bin/xray" > "$temp_volumes"
        if [ -f "$GEOIP_FILE" ]; then
            echo "${volume_item_indent}- $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$temp_volumes"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "${volume_item_indent}- $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$temp_volumes"
        fi
        
        # Insert volumes after the volumes: line
        sed -i "/^${escaped_service_indent}volumes:/r $temp_volumes" "$COMPOSE_FILE"
        rm "$temp_volumes"
        colorized_echo green "Тома Xray обновлены в разделе volumes"
        
    elif grep -q "^${escaped_service_indent}# volumes:" "$COMPOSE_FILE"; then
        sed -i "s|^${escaped_service_indent}# volumes:|${service_indent}volumes:|g" "$COMPOSE_FILE"
        
        # Create temporary file with volume mounts
        temp_volumes=$(mktemp)
        echo "${volume_item_indent}- $XRAY_FILE:/usr/local/bin/xray" > "$temp_volumes"
        if [ -f "$GEOIP_FILE" ]; then
            echo "${volume_item_indent}- $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$temp_volumes"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "${volume_item_indent}- $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$temp_volumes"
        fi
        
        # Insert volumes after the volumes: line
        sed -i "/^${escaped_service_indent}volumes:/r $temp_volumes" "$COMPOSE_FILE"
        rm "$temp_volumes"
        colorized_echo green "Раздел volumes раскомментирован, тома Xray добавлены"
        
    else
        # Create temporary file with volumes section
        temp_volumes=$(mktemp)
        echo "${service_indent}volumes:" > "$temp_volumes"
        echo "${volume_item_indent}- $XRAY_FILE:/usr/local/bin/xray" >> "$temp_volumes"
        if [ -f "$GEOIP_FILE" ]; then
            echo "${volume_item_indent}- $GEOIP_FILE:/usr/local/share/xray/geoip.dat" >> "$temp_volumes"
        fi
        if [ -f "$GEOSITE_FILE" ]; then
            echo "${volume_item_indent}- $GEOSITE_FILE:/usr/local/share/xray/geosite.dat" >> "$temp_volumes"
        fi
        
        # Insert volumes section after restart: always
        sed -i "/^${escaped_service_indent}restart: always/r $temp_volumes" "$COMPOSE_FILE"
        rm "$temp_volumes"
        colorized_echo green "Добавлен раздел volumes с томами Xray"
    fi
    
    # Show what was mounted
    colorized_echo blue "Подключённые тома:"
    colorized_echo green "  ✅ xray → /usr/local/bin/xray"
    if [ -f "$GEOIP_FILE" ]; then
        colorized_echo green "  ✅ geoip.dat → /usr/local/share/xray/geoip.dat"
    fi
    if [ -f "$GEOSITE_FILE" ]; then
        colorized_echo green "  ✅ geosite.dat → /usr/local/share/xray/geosite.dat"
    fi
    

    colorized_echo blue "Проверяю docker-compose.yml..."
    if validate_compose_file "$COMPOSE_FILE"; then
        colorized_echo green "docker-compose.yml в порядке"
        
        colorized_echo blue "Перезапускаю RemnaNode..."

        restart_command -n
        
        colorized_echo green "Установка XRAY-CORE версии $selected_version завершена."
        

        read -p "Готово. Оставить резервную копию? (y/n): " -r keep_backup
        if [[ ! $keep_backup =~ ^[Yy]$ ]]; then
            rm "$backup_file"
            colorized_echo blue "Резервная копия удалена"
        else
            colorized_echo blue "Резервная копия оставлена: $backup_file"
        fi

        cleanup_old_backups "$COMPOSE_FILE"
        
    else
        colorized_echo red "docker-compose.yml не прошёл проверку! Восстанавливаю резервную копию..."
        if restore_backup "$backup_file" "$COMPOSE_FILE"; then
            colorized_echo green "Резервная копия восстановлена"
            colorized_echo red "Проверьте файл docker-compose.yml вручную"
        else
            colorized_echo red "Не удалось восстановить резервную копию! Исходный файл может быть повреждён"
            colorized_echo red "Резервная копия лежит здесь: $backup_file"
        fi
        exit 1
    fi
}


restore_to_container_default() {
    check_running_as_root
    colorized_echo blue "Возвращаю встроенный в контейнер Xray-core..."
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        colorized_echo red "Файл Docker Compose не найден: $COMPOSE_FILE"
        exit 1
    fi
    
    # Create backup before making changes
    colorized_echo blue "Делаю резервную копию docker-compose.yml..."
    backup_file=$(create_backup "$COMPOSE_FILE")
    if [ $? -eq 0 ]; then
        colorized_echo green "Резервная копия: $backup_file"
    else
        colorized_echo red "Не удалось сделать резервную копию"
        exit 1
    fi
    
    local service_indent=$(get_service_property_indentation "$COMPOSE_FILE")
    local escaped_service_indent=$(escape_for_sed "$service_indent")
    
    # Get the indent type for volume items
    local indent_type=""
    if [[ "$service_indent" =~ $'\t' ]]; then
        indent_type=$'\t'
    else
        indent_type="  "
    fi
    local volume_item_indent="${service_indent}${indent_type}"
    local escaped_volume_item_indent=$(escape_for_sed "$volume_item_indent")
    
    # Remove xray-related volume mounts using # as delimiter
    colorized_echo blue "Убираю внешние тома Xray..."
    sed -i "\#$XRAY_FILE#d" "$COMPOSE_FILE"
    sed -i "\#geoip\.dat#d" "$COMPOSE_FILE"
    sed -i "\#geosite\.dat#d" "$COMPOSE_FILE"
    
    # Check if volumes section is now empty and comment it out
    if grep -q "^${escaped_service_indent}volumes:" "$COMPOSE_FILE"; then
        # Count remaining volume items (lines starting with volume_item_indent and -)
        # We need to count lines between 'volumes:' and the next service-level property
        local temp_file=$(mktemp)
        local in_volumes=false
        local volume_count=0
        
        while IFS= read -r line; do
            # Check if we're entering the volumes section
            if [[ "$line" =~ ^${service_indent}volumes:[[:space:]]*$ ]]; then
                in_volumes=true
                continue
            fi
            
            # If we're in volumes section
            if [ "$in_volumes" = true ]; then
                # Check if this is a volume item
                if [[ "$line" =~ ^${volume_item_indent}-[[:space:]] ]]; then
                    ((volume_count++))
                # Check if we've exited the volumes section (found another service property or service)
                elif [[ "$line" =~ ^${service_indent}[a-zA-Z_] ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*:[[:space:]]*$ ]]; then
                    break
                fi
            fi
        done < "$COMPOSE_FILE"
        
        rm -f "$temp_file"
        
        if [ "$volume_count" -eq 0 ]; then
            colorized_echo blue "Томов не осталось, комментирую раздел volumes..."
            sed -i "s|^${escaped_service_indent}volumes:|${service_indent}# volumes:|g" "$COMPOSE_FILE"
        fi
    fi
    
    # Validate the docker-compose file
    colorized_echo blue "Проверяю docker-compose.yml..."
    if validate_compose_file "$COMPOSE_FILE"; then
        colorized_echo green "docker-compose.yml в порядке"
        
        colorized_echo blue "Перезапускаю RemnaNode со встроенным Xray..."
        restart_command -n
        
        colorized_echo green "✅ Встроенный в контейнер Xray-core возвращён"
        colorized_echo blue "Теперь контейнер использует свою версию Xray"
        
        # Ask about backup
        read -p "Готово. Оставить резервную копию? (y/n): " -r keep_backup
        if [[ ! $keep_backup =~ ^[Yy]$ ]]; then
            rm "$backup_file"
            colorized_echo blue "Резервная копия удалена"
        else
            colorized_echo blue "Резервная копия оставлена: $backup_file"
        fi

        cleanup_old_backups "$COMPOSE_FILE"
        
    else
        colorized_echo red "docker-compose.yml не прошёл проверку! Восстанавливаю резервную копию..."
        if restore_backup "$backup_file" "$COMPOSE_FILE"; then
            colorized_echo green "Резервная копия восстановлена"
            colorized_echo red "Проверьте файл docker-compose.yml вручную"
        else
            colorized_echo red "Не удалось восстановить резервную копию! Исходный файл может быть повреждён"
            colorized_echo red "Резервная копия лежит здесь: $backup_file"
        fi
        exit 1
    fi
}


check_editor() {
    if [ -z "$EDITOR" ]; then
        if command -v nano >/dev/null 2>&1; then
            EDITOR="nano"
        elif command -v vi >/dev/null 2>&1; then
            EDITOR="vi"
        else
            detect_os
            install_package nano
            EDITOR="nano"
        fi
    fi
}

xray_log_out() {
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлена!"
        exit 1
    fi
    detect_compose

    if ! is_remnanode_up; then
        colorized_echo red "RemnaNode не запущена. Сначала запустите: 'remnanode up'"
        exit 1
    fi

    # Check if log file exists
    if ! docker exec $APP_NAME test -f /var/log/supervisor/xray.out.log 2>/dev/null; then
        colorized_echo yellow "⚠️  Лог вывода Xray пока не создан."
        colorized_echo gray "   Файл появится, когда Xray начнёт что-то писать."
        colorized_echo gray "   Попробуйте позже или посмотрите логи контейнера: $APP_NAME logs"
        return 0
    fi

    colorized_echo blue "📤 Показываю лог вывода Xray (выход — Ctrl+C)..."
    echo
    docker exec -it $APP_NAME tail -n 100 -f /var/log/supervisor/xray.out.log
}

xray_log_err() {
    if ! is_remnanode_installed; then
        colorized_echo red "RemnaNode не установлена!"
        exit 1
    fi
    
    detect_compose
 
    if ! is_remnanode_up; then
        colorized_echo red "RemnaNode не запущена. Сначала запустите: 'remnanode up'"
        exit 1
    fi

    # Check if log file exists
    if ! docker exec $APP_NAME test -f /var/log/supervisor/xray.err.log 2>/dev/null; then
        colorized_echo yellow "⚠️  Лог ошибок Xray пока не создан."
        colorized_echo gray "   Файл появится, когда у Xray будут ошибки."
        colorized_echo green "   ✅ Нет ошибок — это хорошо!"
        return 0
    fi

    # Check if log file is empty
    local log_size=$(docker exec $APP_NAME stat -c%s /var/log/supervisor/xray.err.log 2>/dev/null || echo "0")
    if [ "$log_size" = "0" ]; then
        colorized_echo green "✅ Лог ошибок Xray пуст — ошибок нет!"
        return 0
    fi

    colorized_echo blue "📥 Показываю лог ошибок Xray (выход — Ctrl+C)..."
    echo
    docker exec -it $APP_NAME tail -n 100 -f /var/log/supervisor/xray.err.log
}

edit_command() {
    detect_os
    check_editor
    if [ -f "$COMPOSE_FILE" ]; then
        $EDITOR "$COMPOSE_FILE"
    else
        colorized_echo red "Файл compose не найден: $COMPOSE_FILE"
        exit 1
    fi
}

edit_env_command() {
    detect_os
    check_editor
    
    local env_type=$(check_env_configuration)
    
    if [ "$env_type" = "env_file" ]; then
        if [ -f "$ENV_FILE" ]; then
            $EDITOR "$ENV_FILE"
        else
            colorized_echo red "Файл окружения не найден: $ENV_FILE"
            exit 1
        fi
    elif [ "$env_type" = "inline" ]; then
        colorized_echo yellow "⚠️  Переменные окружения хранятся в docker-compose.yml"
        colorized_echo blue "💡 Совет: перенесите их в файл .env — так безопаснее"
        echo
        read -p "Перенести в файл .env сейчас? (y/n): " -r migrate_choice
        
        if [[ $migrate_choice =~ ^[Yy]$ ]]; then
            migrate_to_env_file
            colorized_echo green "✅ Миграция завершена! Открываю .env для редактирования..."
            sleep 1
            $EDITOR "$ENV_FILE"
        else
            colorized_echo blue "Открываю docker-compose.yml для редактирования..."
            sleep 1
            $EDITOR "$COMPOSE_FILE"
        fi
    else
        colorized_echo red "❌ Не удалось определить, где хранятся переменные окружения"
        colorized_echo yellow "⚠️  Нет ни файла .env, ни переменных в docker-compose.yml"
        echo
        read -p "Создать файл .env? (y/n): " -r create_choice
        
        if [[ $create_choice =~ ^[Yy]$ ]]; then
            colorized_echo blue "Создаю шаблон файла .env..."
            cat > "$ENV_FILE" <<EOL
### NODE ###
NODE_PORT=3000

### XRAY ###
SECRET_KEY=
EOL
            colorized_echo green "✅ Файл .env создан: $ENV_FILE"
            colorized_echo blue "Открываю для редактирования..."
            sleep 1
            $EDITOR "$ENV_FILE"
        else
            exit 1
        fi
    fi
}

# Show ports configuration command
ports_command() {
    echo
    echo -e "\033[1;37m🔌 Настройки портов\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    
    if ! is_remnanode_installed; then
        colorized_echo red "❌ RemnaNode не установлена"
        colorized_echo gray "   Сначала выполните 'sudo $APP_NAME install'"
        exit 1
    fi
    
    # External port
    echo
    echo -e "\033[1;37m🌐 Внешний порт:\033[0m"
    local node_port=$(get_env_variable "NODE_PORT")
    if [ -z "$node_port" ]; then
        node_port=$(get_env_variable "APP_PORT")
    fi
    printf "   \033[38;5;15m%-22s\033[0m \033[38;5;250m%s\033[0m\n" "NODE_PORT:" "${node_port:-3000 (по умолчанию)}"
    
    # Internal port (only XTLS_API_PORT is configurable since node v2.5.0)
    echo
    echo -e "\033[1;37m🔧 Внутренний порт:\033[0m"
    
    local xtls_port=$(get_env_variable "XTLS_API_PORT")
    
    printf "   \033[38;5;15m%-22s\033[0m \033[38;5;250m%s\033[0m\n" "XTLS_API_PORT:" "${xtls_port:-$DEFAULT_XTLS_API_PORT (по умолчанию)}"
    
    # Check for deprecated ports and show warning
    local rest_port=$(get_env_variable "INTERNAL_REST_PORT")
    local supervisord_port=$(get_env_variable "SUPERVISORD_PORT")
    
    if [ -n "$rest_port" ] || [ -n "$supervisord_port" ]; then
        echo
        colorized_echo yellow "   ⚠️  В .env остались устаревшие порты:"
        if [ -n "$rest_port" ]; then
            colorized_echo yellow "      • INTERNAL_REST_PORT (теперь unix-сокет)"
        fi
        if [ -n "$supervisord_port" ]; then
            colorized_echo yellow "      • SUPERVISORD_PORT (теперь unix-сокет)"
        fi
        colorized_echo gray "   Убрать их: '$APP_NAME migrate'"
    fi
    
    # Unix sockets info
    echo
    echo -e "\033[1;37m🔗 Внутренняя связь (unix-сокеты):\033[0m"
    colorized_echo gray "   С node v2.5.0 внутренние сервисы общаются через unix-сокеты:"
    printf "   \033[38;5;244m%-22s\033[0m \033[38;5;250m%s\033[0m\n" "Supervisord:" "/run/supervisord.sock"
    printf "   \033[38;5;244m%s\033[0m \033[38;5;250m%s\033[0m\n" "Внутренний REST:      " "/run/remnawave-internal.sock"
    
    # Show connection info
    echo
    echo -e "\033[1;37m📋 Данные для подключения:\033[0m"
    printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s:%s\033[0m\n" "Адрес ноды:           " "$NODE_IP" "${node_port:-3000}"
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
    colorized_echo gray "💡 Изменить порты: $APP_NAME edit-env"
    echo
}


autorestart_command() {
    local cron_file="/etc/cron.d/${APP_NAME}-autorestart"
    local cron_log="/var/log/${APP_NAME}-autorestart.log"

    get_autorestart_schedule() {
        if [ -f "$cron_file" ]; then
            grep -v '^#' "$cron_file" | grep -v '^$' | grep -v '^[A-Z]' | awk '{print $1" "$2" "$3" "$4" "$5}' | head -1
        fi
    }

    is_node_really_running() {
        docker inspect --format='{{.State.Running}}' "$APP_NAME" 2>/dev/null | grep -q "^true$"
    }

    local subcmd="${AUTORESTART_SUBCOMMAND:-}"

    if [ -z "$subcmd" ]; then
        echo -e "\033[1;37m⏰ Настройка автоперезапуска\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 50))\033[0m"
        echo
        echo -e "\033[1;37m📖 Использование:\033[0m"
        echo -e "   \033[38;5;15m$APP_NAME auto-restart\033[0m \033[38;5;244m<подкоманда> [опции]\033[0m"
        echo
        echo -e "\033[1;37m🔧 Подкоманды:\033[0m"
        printf "   \033[38;5;15m%-12s\033[0m %s\n" "enable"  "Создать или обновить cron-задачу перезапуска по расписанию"
        printf "   \033[38;5;15m%-12s\033[0m %s\n" "disable" "Удалить cron-задачу перезапуска"
        printf "   \033[38;5;15m%-12s\033[0m %s\n" "status"  "Показать расписание и состояние ноды"
        printf "   \033[38;5;15m%-12s\033[0m %s\n" "test"    "Тестовый перезапуск с проверкой, что нода поднялась"
        echo
        echo -e "\033[1;37m⚙️  Опции для enable:\033[0m"
        printf "   \033[38;5;244m%-20s\033[0m %s\n" "--hour=N"         "Час ежедневного перезапуска (0-23), минута по умолчанию 0"
        printf "   \033[38;5;244m%-20s\033[0m %s\n" "--minute=N"       "Минута (0-59), только вместе с --hour"
        printf "   \033[38;5;244m%-20s\033[0m %s\n" "--schedule=EXPR"  "Полное cron-выражение из 5 полей (вместо --hour/--minute)"
        echo
        echo -e "\033[1;37m📋 Примеры:\033[0m"
        echo -e "\033[38;5;244m   sudo $APP_NAME auto-restart enable --hour=3\033[0m"
        echo -e "\033[38;5;244m   sudo $APP_NAME auto-restart enable --hour=3 --minute=30\033[0m"
        echo -e "\033[38;5;244m   sudo $APP_NAME auto-restart enable --schedule=\"30 2 * * 0\"\033[0m"
        echo -e "\033[38;5;244m   $APP_NAME auto-restart status\033[0m"
        echo -e "\033[38;5;244m   sudo $APP_NAME auto-restart disable\033[0m"
        echo -e "\033[38;5;244m   sudo $APP_NAME auto-restart test\033[0m"
        echo
        return 0
    fi

    case "$subcmd" in
        enable)
            check_running_as_root

            if ! is_remnanode_installed; then
                colorized_echo red "Ошибка: RemnaNode не установлена. Сначала установите её, потом включайте автоперезапуск."
                exit 1
            fi

            if ! docker compose version >/dev/null 2>&1; then
                colorized_echo red "Ошибка: нужен Docker Compose v2 (плагин). Сначала установите его."
                exit 1
            fi
            local compose_cmd="docker compose"

            local hour="${AUTORESTART_HOUR:-}"
            local minute="${AUTORESTART_MINUTE:-}"
            local schedule="${AUTORESTART_SCHEDULE:-}"

            if [ -n "$schedule" ]; then
                # Validate: must be exactly 5 fields
                local field_count
                field_count=$(echo "$schedule" | awk '{print NF}')
                if [ "$field_count" -ne 5 ]; then
                    colorized_echo red "Ошибка: --schedule должен быть cron-выражением из 5 полей (например, \"0 3 * * *\")."
                    exit 1
                fi
                # Reject newlines and control characters
                if [[ "$schedule" == *$'\n'* || "$schedule" == *$'\r'* ]]; then
                    colorized_echo red "Ошибка: в --schedule не должно быть переводов строки."
                    exit 1
                fi
                # Allow only safe cron characters: digits, space, * / , -
                if [[ ! "$schedule" =~ ^[0-9\ \*/,\-]+$ ]]; then
                    colorized_echo red "Ошибка: в --schedule недопустимые символы. Можно: цифры, пробел, * / , -"
                    exit 1
                fi
            elif [ -n "$hour" ] || [ -n "$minute" ]; then
                # Validate hour
                if [ -z "$hour" ]; then
                    colorized_echo red "Ошибка: --minute работает только вместе с --hour."
                    exit 1
                fi
                if ! [[ "$hour" =~ ^[0-9]+$ ]] || [ "$hour" -lt 0 ] || [ "$hour" -gt 23 ]; then
                    colorized_echo red "Ошибка: --hour должен быть целым числом от 0 до 23."
                    exit 1
                fi
                if [ -z "$minute" ]; then
                    minute=0
                fi
                if ! [[ "$minute" =~ ^[0-9]+$ ]] || [ "$minute" -lt 0 ] || [ "$minute" -gt 59 ]; then
                    colorized_echo red "Ошибка: --minute должен быть целым числом от 0 до 59."
                    exit 1
                fi
                schedule="${minute} ${hour} * * *"
            else
                # Interactive mode
                echo -e "\033[1;37m⏰ Расписание автоперезапуска\033[0m"
                echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 45))\033[0m"
                local current_schedule
                current_schedule=$(get_autorestart_schedule)
                if [ -n "$current_schedule" ]; then
                    echo -e "\033[38;5;244mТекущее расписание: \033[38;5;15m$current_schedule\033[0m"
                else
                    echo -e "\033[38;5;244mРасписание пока не задано.\033[0m"
                fi
                echo
                read -rp "$(echo -e "\033[38;5;15mЧас (0-23) [3]: \033[0m")" hour
                hour="${hour:-3}"
                if ! [[ "$hour" =~ ^[0-9]+$ ]] || [ "$hour" -lt 0 ] || [ "$hour" -gt 23 ]; then
                    colorized_echo red "Ошибка: час должен быть целым числом от 0 до 23."
                    exit 1
                fi
                read -rp "$(echo -e "\033[38;5;15mМинута (0-59) [0]: \033[0m")" minute
                minute="${minute:-0}"
                if ! [[ "$minute" =~ ^[0-9]+$ ]] || [ "$minute" -lt 0 ] || [ "$minute" -gt 59 ]; then
                    colorized_echo red "Ошибка: минута должна быть целым числом от 0 до 59."
                    exit 1
                fi
                schedule="${minute} ${hour} * * *"
            fi

            # Write cron file
            cat > "$cron_file" <<EOF
# ${APP_NAME} auto-restart - managed by ${APP_NAME} script
# To disable: sudo ${APP_NAME} auto-restart disable
${schedule} root cd ${APP_DIR} && ${compose_cmd} -f ${COMPOSE_FILE} -p ${APP_NAME} down >/dev/null 2>&1 && ${compose_cmd} -f ${COMPOSE_FILE} -p ${APP_NAME} up -d >/dev/null 2>&1 && echo "\$(date '+\%Y-\%m-\%d \%H:\%M:\%S'): [OK] ${APP_NAME} restarted" >> ${cron_log} || echo "\$(date '+\%Y-\%m-\%d \%H:\%M:\%S'): [FAIL] ${APP_NAME} restart failed" >> ${cron_log}
EOF
            chmod 644 "$cron_file"

            local autorestart_logrotate="/etc/logrotate.d/${APP_NAME}-autorestart"
            cat > "$autorestart_logrotate" <<EOF
${cron_log} {
    size 10M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOF
            chmod 644 "$autorestart_logrotate"

            echo -e "\033[1;32m✅ Автоперезапуск включён!\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 45))\033[0m"
            printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Расписание:         " "$schedule"
            printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Файл cron:          " "$cron_file"
            printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Файл лога:          " "$cron_log"
            printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Конфиг logrotate:   " "$autorestart_logrotate"
            echo
            ;;

        disable)
            check_running_as_root
            if [ ! -f "$cron_file" ]; then
                colorized_echo yellow "Автоперезапуск сейчас не включён (файл cron не найден)."
                return 0
            fi
            rm -f "$cron_file"
            local autorestart_logrotate="/etc/logrotate.d/${APP_NAME}-autorestart"
            [ -f "$autorestart_logrotate" ] && rm -f "$autorestart_logrotate"
            colorized_echo green "✅ Автоперезапуск выключен. Файл cron удалён."
            ;;

        status)
            echo -e "\033[1;37m⏰ Состояние автоперезапуска\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 45))\033[0m"
            echo
            local current_schedule
            current_schedule=$(get_autorestart_schedule)
            if [ -f "$cron_file" ] && [ -n "$current_schedule" ]; then
                printf "   \033[38;5;15m%s\033[0m \033[1;32m%s\033[0m\n" "Автоперезапуск:   " "Включён"
                printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Расписание:       " "$current_schedule"
                printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Файл cron:        " "$cron_file"
                printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Файл лога:        " "$cron_log"
            else
                printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Автоперезапуск:   " "Выключен (нет файла cron)"
            fi
            echo
            if is_remnanode_installed; then
                if is_node_really_running; then
                    printf "   \033[38;5;15m%s\033[0m \033[1;32m%s\033[0m\n" "Состояние ноды:   " "Работает"
                else
                    printf "   \033[38;5;15m%s\033[0m \033[1;31m%s\033[0m\n" "Состояние ноды:   " "Остановлена"
                fi
            else
                printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Состояние ноды:   " "Не установлена"
            fi
            echo
            if [ -f "$cron_log" ]; then
                echo -e "\033[1;37m📋 Последние записи лога:\033[0m"
                tail -5 "$cron_log" | while IFS= read -r line; do
                    echo -e "   \033[38;5;244m$line\033[0m"
                done
                echo
            fi
            ;;

        test)
            check_running_as_root
            detect_compose

            if ! is_remnanode_installed; then
                colorized_echo red "Ошибка: RemnaNode не установлена."
                exit 1
            fi
            if ! is_node_really_running; then
                colorized_echo red "Ошибка: RemnaNode сейчас не запущена. Сначала запустите её."
                exit 1
            fi

            echo -e "\033[1;37m🧪 Проверка автоперезапуска\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 45))\033[0m"
            echo -e "\033[1;33m⚠️  RemnaNode будет ненадолго остановлена и запущена снова.\033[0m"
            echo
            read -rp "$(echo -e "\033[38;5;15mПродолжить? [y/N]: \033[0m")" confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                colorized_echo yellow "Проверка отменена."
                return 0
            fi

            echo
            echo -e "\033[38;5;250m⏹️  Останавливаю RemnaNode...\033[0m"
            down_remnanode >/dev/null 2>&1

            echo -e "\033[38;5;250m▶️  Запускаю RemnaNode...\033[0m"
            $COMPOSE -f "$COMPOSE_FILE" -p "$APP_NAME" up -d --remove-orphans >/dev/null 2>&1

            echo -e "\033[38;5;250m⏳ Жду, пока нода поднимется (до 30 с)...\033[0m"
            local elapsed=0
            local came_up=false
            while [ "$elapsed" -lt 30 ]; do
                sleep 2
                elapsed=$((elapsed + 2))
                if is_node_really_running; then
                    came_up=true
                    break
                fi
            done

            if [ "$came_up" = true ]; then
                colorized_echo green "✅ Проверка пройдена! RemnaNode перезапустилась и поднялась примерно за ${elapsed} с."
            else
                colorized_echo red "❌ Проверка не пройдена: RemnaNode не поднялась за 30 секунд."
                exit 1
            fi
            ;;

        *)
            colorized_echo red "Неизвестная подкоманда auto-restart: $subcmd"
            echo -e "Доступные подкоманды: \033[38;5;15menable disable status test\033[0m"
            exit 1
            ;;
    esac
}


usage() {
    clear

    echo -e "\033[1;37m⚡ $APP_NAME\033[0m \033[38;5;8mкомандная строка\033[0m \033[38;5;244mv$SCRIPT_VERSION\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    echo
    echo -e "\033[1;37m📖 Использование:\033[0m"
    echo -e "   \033[38;5;15m$APP_NAME\033[0m \033[38;5;8m<команда>\033[0m \033[38;5;244m[опции]\033[0m"
    echo

    echo -e "\033[1;37m🚀 Основные команды:\033[0m"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "install" "🛠️  Установить RemnaNode"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "update" "⬆️  Обновить до последней версии (можно с --tag)"
    printf "   \033[38;5;15m%-18s\033[0m %s\n" "uninstall" "🗑️  Полностью удалить RemnaNode"
    echo

    echo -e "\033[1;33m⚠️  Требование к версии панели:\033[0m"
    echo -e "\033[38;5;244m      Панель 3.3.0+ нужна только нодам версий 3.3.0 .. 3.3.2\033[0m"
    echo -e "\033[38;5;244m      (они требуют производный SNI при TLS-рукопожатии). С node\033[0m"
    echo -e "\033[38;5;244m      3.4.0 проверка включается по желанию (SNI_VERIFICATION, по умолчанию\033[0m"
    echo -e "\033[38;5;244m      выключена), так что последняя нода снова работает со старой панелью.\033[0m"
    echo

    echo -e "\033[1;37m🎯 Опции установки:\033[0m"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--force, -f" "Без вопросов (пропустить подтверждения)"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--secret-key=KEY" "SECRET_KEY из панели"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--port=PORT" "NODE_PORT (по умолчанию 3000)"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--xtls-port=PORT" "Устаревший XTLS_API_PORT (node 2.8.0+ его игнорирует)"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--xray" "Установить последний Xray-core"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--no-xray" "Без Xray-core (по умолчанию в режиме --force)"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--name NAME" "Своё имя установки"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--dev" "Образ для разработки (dev)"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "--tag TAG" "Закрепить версию образа ноды (например, 3.4.1)"
    echo
    echo -e "\033[38;5;244m   💡 --tag оставляет ноду на старой версии, если панель ещё\033[0m"
    echo -e "\033[38;5;244m      не обновлена. Указывайте ТОЧНУЮ версию — у remnawave/node есть\033[0m"
    echo -e "\033[38;5;244m      только точные теги (2.8.0, 3.0.0, ...), плавающих '2'/'3' нет.\033[0m"
    echo -e "\033[38;5;244m      Закреплённая нода остаётся на своей версии: 'update' её не сдвинет,\033[0m"
    echo -e "\033[38;5;244m      а 'update --tag X' перезакрепит установку на X.\033[0m"
    echo

    echo -e "\033[1;37m⚙️  Управление сервисами:\033[0m"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "up" "▶️  Запустить сервисы"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "down" "⏹️  Остановить сервисы"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "restart" "🔄 Перезапустить сервисы"
    printf "   \033[38;5;250m%-18s\033[0m %s\n" "status" "📊 Статус сервисов"
    echo

    echo -e "\033[1;37m📊 Мониторинг и логи:\033[0m"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "logs" "📋 Логи контейнера"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "xray-log-out" "📤 Лог вывода Xray"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "xray-log-err" "📥 Лог ошибок Xray"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "setup-logs" "🗂️  Настроить ротацию логов"
    echo

    echo -e "\033[1;37m⚙️  Обновления и настройки:\033[0m"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "update" "🔄 Обновить RemnaNode"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "core-update" "⬆️  Обновить Xray-core"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "migrate" "🔄 Миграция переменных окружения"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "edit" "📝 Редактировать docker-compose.yml"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "edit-env" "🔐 Редактировать окружение (.env)"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "ports" "🔌 Показать настройки портов"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "enable-socket" "🔗 Открыть доступ к сокету selfsteal"
    printf "   \033[38;5;178m%-18s\033[0m %s\n" "auto-restart" "⏰ Автоперезапуск по расписанию"
    echo

    echo -e "\033[1;37m📊 Управление скриптом:\033[0m"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "install-script" "📥 Установить/обновить сам CLI (контейнеры не трогает)"
    printf "   \033[38;5;244m%-18s\033[0m %s\n" "uninstall-script" "📤 Удалить CLI из /usr/local/bin"
    echo
    echo -e "\033[38;5;244m   💡 'install-script' ставит только этот CLI — контейнер ноды он не\033[0m"
    echo -e "\033[38;5;244m      ставит и не обновляет. Пригодится на сервере, где ноды ещё нет,\033[0m"
    echo -e "\033[38;5;244m      или чтобы прямо сейчас получить свежий CLI:\033[0m"
    echo -e "\033[38;5;244m         sudo $APP_NAME install-script\033[0m"
    echo -e "\033[38;5;244m      Скачивание идёт с GitHub, затем с зеркал jsDelivr. 'update' тоже\033[0m"
    echo -e "\033[38;5;244m      сначала сам обновляет CLI, а потом всё остальное.\033[0m"
    echo

    echo -e "\033[1;37m📋 Информация:\033[0m"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "help" "📖 Эта справка"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "version" "📋 Версия"
    printf "   \033[38;5;117m%-18s\033[0m %s\n" "menu" "🎛️  Интерактивное меню"
    echo

    if is_remnanode_installed; then
        local node_port=$(get_env_variable "NODE_PORT")
        # Fallback to old variable for backward compatibility
        if [ -z "$node_port" ]; then
            node_port=$(get_env_variable "APP_PORT")
        fi
        if [ -n "$node_port" ]; then
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
            echo -e "\033[1;37m🌐 Доступ к ноде:\033[0m \033[38;5;117m$NODE_IP:$node_port\033[0m"
        fi
    fi

    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
    echo -e "\033[1;37m📖 Примеры:\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME install\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME install --force --secret-key=\"eyJ...\"\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME install -f --secret-key=\"KEY\" --port=3001 --xray\033[0m"
    echo -e "\033[38;5;244m   sudo $APP_NAME core-update\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME logs\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME menu           # интерактивное меню\033[0m"
    echo -e "\033[38;5;244m   $APP_NAME                # то же, что menu\033[0m"
    echo
    echo -e "\033[1;37m📡 Установка одной командой без вопросов:\033[0m"
    echo -e "\033[38;5;117m   bash <(curl -Ls URL) @ install --force --secret-key=\"KEY\"\033[0m"
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
    echo -e "\033[38;5;8m📚 Проект:    \033[38;5;250mhttps://gig.ovh\033[0m"
    echo -e "\033[38;5;8m🐛 Ошибки:    \033[38;5;250mhttps://github.com/gorecvpn/Remnawave-Panel-Install\033[0m"
    echo -e "\033[38;5;8m💬 Поддержка: \033[38;5;250mhttps://t.me/remnawave\033[0m"
    echo -e "\033[38;5;8m👨‍💻 Автор:     \033[38;5;250mDigneZzZ\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
}

# Функция для версии
show_version() {
    echo -e "\033[1;37m🚀 RemnaNode — CLI управления\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
    echo -e "\033[38;5;250mВерсия:    \033[38;5;15m$SCRIPT_VERSION\033[0m"
    echo -e "\033[38;5;250mАвтор:     \033[38;5;15mDigneZzZ\033[0m"
    echo -e "\033[38;5;250mGitHub:    \033[38;5;15mhttps://github.com/gorecvpn/Remnawave-Panel-Install\033[0m"
    echo -e "\033[38;5;250mПроект:    \033[38;5;15mhttps://gig.ovh\033[0m"
    echo -e "\033[38;5;250mПоддержка: \033[38;5;15mhttps://t.me/remnawave\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 40))\033[0m"
}

autorestart_menu() {
    local cron_file="/etc/cron.d/${APP_NAME}-autorestart"
    local cron_log="/var/log/${APP_NAME}-autorestart.log"

    _ar_get_schedule() {
        if [ -f "$cron_file" ]; then
            grep -v '^#' "$cron_file" | grep -v '^$' | grep -v '^[A-Z]' | awk '{print $1" "$2" "$3" "$4" "$5}' | head -1
        fi
    }

    _ar_is_running() {
        docker inspect --format='{{.State.Running}}' "$APP_NAME" 2>/dev/null | grep -q "^true$"
    }

    while true; do
        clear
        echo -e "\033[1;37m⏰ Расписание автоперезапуска\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo

        # Current status block
        local current_schedule
        current_schedule=$(_ar_get_schedule)
        if [ -f "$cron_file" ] && [ -n "$current_schedule" ]; then
            printf "   \033[38;5;15m%s\033[0m \033[1;32m%s\033[0m\n" "Автоперезапуск:   " "Включён"
            printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Расписание:       " "$current_schedule"
        else
            printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Автоперезапуск:   " "Выключен"
        fi

        if is_remnanode_installed; then
            if _ar_is_running; then
                printf "   \033[38;5;15m%s\033[0m \033[1;32m%s\033[0m\n" "Состояние ноды:   " "Работает"
            else
                printf "   \033[38;5;15m%s\033[0m \033[1;31m%s\033[0m\n" "Состояние ноды:   " "Остановлена"
            fi
        else
            printf "   \033[38;5;15m%s\033[0m \033[38;5;244m%s\033[0m\n" "Состояние ноды:   " "Не установлена"
        fi
        echo

        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        if [ -f "$cron_file" ] && [ -n "$current_schedule" ]; then
            echo -e "   \033[38;5;15m1)\033[0m ✏️  Изменить расписание"
            echo -e "   \033[38;5;15m2)\033[0m 🚫 Выключить автоперезапуск"
        else
            echo -e "   \033[38;5;15m1)\033[0m ✅ Включить автоперезапуск"
            echo -e "   \033[38;5;244m   2) Выключить (не активен)\033[0m"
        fi
        echo -e "   \033[38;5;15m3)\033[0m 📊 Состояние и логи"
        echo -e "   \033[38;5;15m4)\033[0m 🧪 Тестовый перезапуск"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo -e "\033[38;5;15m   0)\033[0m 🔙 Назад в главное меню"
        echo
        read -p "$(echo -e "\033[1;37mВыберите пункт [0-4]:\033[0m ")" ar_choice

        case "$ar_choice" in
            1)
                AUTORESTART_SUBCOMMAND="enable"
                AUTORESTART_HOUR=""
                AUTORESTART_MINUTE=""
                AUTORESTART_SCHEDULE=""
                autorestart_command
                read -p "Нажмите Enter, чтобы продолжить..."
                ;;
            2)
                if [ ! -f "$cron_file" ]; then
                    echo -e "\033[1;33m⚠️  Автоперезапуск сейчас не включён.\033[0m"
                    read -p "Нажмите Enter, чтобы продолжить..."
                else
                    AUTORESTART_SUBCOMMAND="disable"
                    autorestart_command
                    read -p "Нажмите Enter, чтобы продолжить..."
                fi
                ;;
            3)
                AUTORESTART_SUBCOMMAND="status"
                autorestart_command
                read -p "Нажмите Enter, чтобы продолжить..."
                ;;
            4)
                AUTORESTART_SUBCOMMAND="test"
                autorestart_command
                read -p "Нажмите Enter, чтобы продолжить..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "\033[1;31m❌ Неверный пункт!\033[0m"
                sleep 1
                ;;
        esac
    done
}

main_menu() {
    # Pull in a newer script before showing the menu. Applied without asking and
    # re-exec'd in place: every menu action below assumes the current migrations
    # and generators, which only exist in the current script.
    ensure_latest_script

    while true; do
        clear
        echo -e "\033[1;37m🚀 $APP_NAME — управление нодой\033[0m \033[38;5;244mv$SCRIPT_VERSION\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo
        
        # Проверка статуса узла
        local menu_status="Not installed"
        local status_color="\033[38;5;244m"
        local node_port=""
        local xray_version=""
        
        if is_remnanode_installed; then
            # Получаем порт через универсальную функцию
            node_port=$(get_env_variable "NODE_PORT")
            # Fallback to old variable for backward compatibility
            if [ -z "$node_port" ]; then
                node_port=$(get_env_variable "APP_PORT")
            fi
            
            if is_remnanode_up; then
                menu_status="Running"
                status_color="\033[1;32m"
                echo -e "${status_color}✅ Состояние ноды: РАБОТАЕТ\033[0m"
                
                # Показываем информацию о подключении
                if [ -n "$node_port" ]; then
                    echo
                    echo -e "\033[1;37m🌐 Данные для подключения:\033[0m"
                    printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "IP-адрес:   " "$NODE_IP"
                    printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s\033[0m\n" "Порт:       " "$node_port"
                    printf "   \033[38;5;15m%s\033[0m \033[38;5;117m%s:%s\033[0m\n" "Адрес:      " "$NODE_IP" "$node_port"
                fi
                
                # Проверяем Xray-core и версию RemnaNode
                xray_version=$(get_current_xray_core_version 2>/dev/null || echo "Not installed")
                local node_version=$(get_remnanode_version 2>/dev/null || echo "unknown")
                
                echo
                echo -e "\033[1;37m⚙️  Компоненты:\033[0m"
                
                # Версия RemnaNode
                printf "   \033[38;5;15m%-12s\033[0m " "RemnaNode:"
                if [ "$node_version" != "unknown" ]; then
                    echo -e "\033[1;32m✅ v$node_version\033[0m"
                else
                    echo -e "\033[38;5;244m❓ версия неизвестна\033[0m"
                fi
                
                # Версия Xray Core
                printf "   \033[38;5;15m%-12s\033[0m " "Xray Core:"
                if [ "$xray_version" != "Not installed" ]; then
                    echo -e "\033[1;32m✅ $xray_version\033[0m"
                else
                    echo -e "\033[1;33m⚠️  Не установлен\033[0m"
                fi
                
                # Показываем использование ресурсов
                echo
                echo -e "\033[1;37m💾 Ресурсы:\033[0m"
                
                local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
                local mem_info=$(free -h | grep "Mem:" 2>/dev/null)
                local mem_used=$(echo "$mem_info" | awk '{print $3}' 2>/dev/null || echo "N/A")
                local mem_total=$(echo "$mem_info" | awk '{print $2}' 2>/dev/null || echo "N/A")
                
                printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s%%\033[0m\n" "Процессор:  " "$cpu_usage"
                printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s / %s\033[0m\n" "Память:     " "$mem_used" "$mem_total"
                
                local disk_usage=$(df -h "$APP_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "N/A")
                local disk_available=$(df -h "$APP_DIR" 2>/dev/null | tail -1 | awk '{print $4}' 2>/dev/null || echo "N/A")
                
                printf "   \033[38;5;15m%s\033[0m \033[38;5;250mзанято %s%%, свободно %s\033[0m\n" "Диск:       " "$disk_usage" "$disk_available"
                
                # Проверяем логи
                if [ -d "$LOG_DIR" ]; then
                    local log_files=$(find "$LOG_DIR" -name "*.log" 2>/dev/null | wc -l)
                    if [ "$log_files" -gt 0 ]; then
                        local total_log_size=$(du -sh "$LOG_DIR"/*.log 2>/dev/null | awk '{total+=$1} END {print total"K"}' | sed 's/KK/K/')
                        printf "   \033[38;5;15m%s\033[0m \033[38;5;250m%s файлов (%s)\033[0m\n" "Логи:       " "$log_files" "$total_log_size"
                    fi
                fi
                
            else
                menu_status="Stopped"
                status_color="\033[1;31m"
                echo -e "${status_color}❌ Состояние ноды: ОСТАНОВЛЕНА\033[0m"
                echo -e "\033[38;5;244m   Сервисы установлены, но не запущены\033[0m"
                echo -e "\033[38;5;244m   Запустить ноду — пункт 2\033[0m"
            fi
        else
            echo -e "${status_color}📦 Состояние ноды: НЕ УСТАНОВЛЕНА\033[0m"
            echo -e "\033[38;5;244m   Установить RemnaNode — пункт 1\033[0m"
        fi
        
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo
        echo -e "\033[1;37m🚀 Установка и управление:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m 🛠️  Установить RemnaNode"
        echo -e "   \033[38;5;15m2)\033[0m ▶️  Запустить ноду"
        echo -e "   \033[38;5;15m3)\033[0m ⏹️  Остановить ноду"
        echo -e "   \033[38;5;15m4)\033[0m 🔄 Перезапустить ноду"
        echo -e "   \033[38;5;15m5)\033[0m 🗑️  Удалить RemnaNode"
        echo
        echo -e "\033[1;37m📊 Мониторинг и логи:\033[0m"
        echo -e "   \033[38;5;15m6)\033[0m 📊 Состояние ноды"
        echo -e "   \033[38;5;15m7)\033[0m 📋 Логи контейнера"
        echo -e "   \033[38;5;15m8)\033[0m 📤 Лог вывода Xray"
        echo -e "   \033[38;5;15m9)\033[0m 📥 Лог ошибок Xray"
        echo
        echo -e "\033[1;37m⚙️  Обновления и настройки:\033[0m"
        echo -e "   \033[38;5;15m10)\033[0m 🔄 Обновить RemnaNode"
        echo -e "   \033[38;5;15m11)\033[0m ⬆️  Обновить Xray-core"
        echo -e "   \033[38;5;15m12)\033[0m 🔄 Миграция переменных окружения"
        echo -e "   \033[38;5;15m13)\033[0m 📝 Редактировать docker-compose.yml"
        echo -e "   \033[38;5;15m14)\033[0m 🔐 Редактировать окружение (.env)"
        echo -e "   \033[38;5;15m15)\033[0m 🔌 Настройки портов"
        echo -e "   \033[38;5;15m16)\033[0m 🗂️  Настроить ротацию логов"
        echo -e "   \033[38;5;15m17)\033[0m ⏰ Автоперезапуск по расписанию"
        echo
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo -e "\033[38;5;15m   0)\033[0m 🚪 Выйти в терминал"
        echo
        
        # Показываем подсказки в зависимости от состояния
        case "$menu_status" in
            "Not installed")
                echo -e "\033[1;34m💡 Совет: начните с пункта 1 — установка RemnaNode\033[0m"
                ;;
            "Stopped")
                echo -e "\033[1;34m💡 Совет: запустите ноду пунктом 2\033[0m"
                ;;
            "Running")
                if [ "$xray_version" = "Not installed" ]; then
                    echo -e "\033[1;34m💡 Совет: поставьте Xray-core пунктом 11 — так будет быстрее\033[0m"
                else
                    echo -e "\033[1;34m💡 Совет: логи — пункты 7-9, ротация логов — пункт 16\033[0m"
                fi
                ;;
        esac
        
        echo -e "\033[38;5;8mRemnaNode CLI v$SCRIPT_VERSION • автор DigneZzZ • перевод Gorec\033[0m"
        echo
        read -p "$(echo -e "\033[1;37mВыберите пункт [0-17]:\033[0m ")" choice

        case "$choice" in
            1) install_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            2) up_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            3) down_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            4) restart_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            5) uninstall_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            6) status_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            7) logs_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            8) xray_log_out; read -p "Нажмите Enter, чтобы продолжить..." ;;
            9) xray_log_err; read -p "Нажмите Enter, чтобы продолжить..." ;;
            10) update_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            11) update_core_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            12) migrate_env_variables; read -p "Нажмите Enter, чтобы продолжить..." ;;
            13) edit_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            14) edit_env_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            15) ports_command; read -p "Нажмите Enter, чтобы продолжить..." ;;
            16) setup_log_rotation; read -p "Нажмите Enter, чтобы продолжить..." ;;
            17) autorestart_menu ;;
            0) clear; exit 0 ;;
            *) 
                echo -e "\033[1;31m❌ Неверный пункт!\033[0m"
                sleep 1
                ;;
        esac
    done
}

# Главная обработка команд
case "${COMMAND:-menu}" in
    install) install_command ;;
    install-script) install_script_command ;;
    uninstall) uninstall_command ;;
    uninstall-script) uninstall_script_command ;;
    up) up_command ;;
    down) down_command ;;
    restart) restart_command ;;
    status) status_command ;;
    logs) logs_command ;;
    xray-log-out) xray_log_out ;;
    xray-log-err) xray_log_err ;;
    update) update_command ;;
    core-update) update_core_command ;;
    migrate) migrate_env_variables; migrate_deprecated_ports; migrate_cap_add; migrate_log_volumes; audit_compose_file ;;
    edit) edit_command ;;
    edit-env) edit_env_command ;;
    ports) ports_command ;;
    setup-logs) setup_log_rotation ;;
    enable-socket) enable_socket_command ;;
    auto-restart) autorestart_command ;;
    help|--help|-h) usage ;;
    version|--version|-v) show_version ;;
    menu) main_menu ;;
    "") main_menu ;;
    *) 
        echo -e "\033[1;31m❌ Неизвестная команда: $COMMAND\033[0m"
        echo -e "\033[38;5;244mСписок команд: '\033[38;5;15m$APP_NAME help\033[38;5;244m'\033[0m"
        exit 1
        ;;
esac
