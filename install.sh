#!/usr/bin/env bash
set -euo pipefail

readonly RCLOAK_REPO="${RCLOAK_REPO:-https://github.com/itsazni/rcloak}"
readonly RCLOAK_BRANCH="${RCLOAK_BRANCH:-main}"

if [[ $EUID -eq 0 ]]; then
    readonly INSTALL_DIR="${RCLOAK_INSTALL_DIR:-/opt/rcloak}"
    readonly BIN_LINK="/usr/local/bin/rcloak"
else
    readonly INSTALL_DIR="${RCLOAK_INSTALL_DIR:-${HOME}/.local/share/rcloak}"
    readonly BIN_LINK="${HOME}/.local/bin/rcloak"
fi

C="\033[36m" G="\033[32m" R="\033[31m" Y="\033[33m"
B="\033[1m" D="\033[2m" X="\033[0m"

info()    { echo -e "  ${C}●${X} $*"; }
success() { echo -e "  ${G}✓${X} $*"; }
warn()    { echo -e "  ${Y}⚠${X} $*"; }
error()   { echo -e "  ${R}✗${X} $*" >&2; }

banner() {
    echo ""
    echo -e "  ${C}  ██████╗  ██████╗██╗      ██████╗  █████╗ ██╗  ██╗${X}"
    echo -e "  ${C}  ██╔══██╗██╔════╝██║     ██╔═══██╗██╔══██╗██║ ██╔╝${X}"
    echo -e "  ${C}  ██████╔╝██║     ██║     ██║   ██║███████║█████╔╝ ${X}"
    echo -e "  ${C}  ██╔══██╗██║     ██║     ██║   ██║██╔══██║██╔═██╗ ${X}"
    echo -e "  ${C}  ██║  ██║╚██████╗███████╗╚██████╔╝██║  ██║██║  ██╗${X}"
    echo -e "  ${C}  ╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝${X}"
    echo -e "  ${D}  installer${X}"
    echo ""
}

is_root() { [[ $EUID -eq 0 ]]; }
run_cmd() {
    if is_root; then
        "$@"
    elif [[ "$1" == "mkdir" || "$1" == "cp" || "$1" == "chmod" || "$1" == "ln" || "$1" == "rm" || "$1" == "git" ]]; then
        # For file ops in user-writable dirs, no sudo needed
        "$@"
    else
        sudo "$@"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-linux}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

install_pkg() {
    local pkg="$1" os
    os=$(detect_os)
    case "$os" in
        ubuntu|debian|pop|linuxmint) sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg" ;;
        centos|rhel|fedora|rocky|alma) sudo yum install -y -q "$pkg" 2>/dev/null || sudo dnf install -y -q "$pkg" ;;
        arch|manjaro) sudo pacman -S --noconfirm "$pkg" ;;
        alpine) sudo apk add --quiet "$pkg" ;;
        macos) brew install "$pkg" ;;
        *) error "Cannot install ${pkg} automatically."; return 1 ;;
    esac
}

ensure_cmd() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        success "${cmd} $(${cmd} --version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1 || echo '')"
        return 0
    fi
    info "Installing ${cmd}..."
    if install_pkg "$cmd"; then
        success "${cmd} installed"
    else
        error "Failed to install ${cmd}"
        return 1
    fi
}

install_rclone() {
    if command -v rclone &>/dev/null; then
        success "rclone $(rclone version 2>/dev/null | head -1 | grep -oP '[\d.]+' || echo '')"
        return 0
    fi
    info "Installing rclone..."
    if curl -fsSL https://rclone.org/install.sh | sudo bash &>/dev/null; then
        success "rclone installed"
    else
        error "Failed to install rclone. Visit https://rclone.org/install/"
        return 1
    fi
}

get_script_dir() {
    local src="${BASH_SOURCE[0]:-}"
    if [[ -n "$src" && -f "$src" ]]; then
        cd "$(dirname "$src")" && pwd
    else
        echo ""
    fi
}

do_install() {
    banner

    echo -e "  ${B}Dependencies${X}"
    echo ""

    ensure_cmd curl
    ensure_cmd jq
    ensure_cmd git
    ensure_cmd sqlite3
    install_rclone

    echo ""
    echo -e "  ${B}Download${X}"
    echo ""

    local local_dir
    local_dir=$(get_script_dir)

    if [[ -n "$local_dir" && -f "${local_dir}/rcloak" ]]; then
        local real_local real_install
        real_local=$(realpath "$local_dir" 2>/dev/null || echo "$local_dir")
        real_install=$(realpath "$INSTALL_DIR" 2>/dev/null || echo "$INSTALL_DIR")
        if [[ "$real_local" != "$real_install" ]]; then
            run_cmd mkdir -p "$INSTALL_DIR"
            run_cmd cp -a "${local_dir}/rcloak" "$INSTALL_DIR/"
            run_cmd cp -a "${local_dir}/lib" "$INSTALL_DIR/"
            run_cmd cp -a "${local_dir}/README.md" "$INSTALL_DIR/" 2>/dev/null || true
            run_cmd cp -a "${local_dir}/install.sh" "$INSTALL_DIR/" 2>/dev/null || true
            # data dirs created at runtime in user-writable location
        fi
        success "Installed from local source"
    elif [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        run_cmd git pull --quiet origin "$RCLOAK_BRANCH" 2>/dev/null || true
        success "Updated existing installation"
    else
        run_cmd git clone --quiet --depth 1 -b "$RCLOAK_BRANCH" "$RCLOAK_REPO" "$INSTALL_DIR"
        success "Cloned to ${INSTALL_DIR}"
    fi

    run_cmd chmod +x "${INSTALL_DIR}/rcloak"

    echo ""
    echo -e "  ${B}Link${X}"
    echo ""

    mkdir -p "$(dirname "$BIN_LINK")"
    run_cmd ln -sf "${INSTALL_DIR}/rcloak" "$BIN_LINK"
    success "${D}${BIN_LINK} → ${INSTALL_DIR}/rcloak${X}"

    echo ""
    if command -v rcloak &>/dev/null; then
        echo -e "  ${G}┌─────────────────────────────────────────┐${X}"
        echo -e "  ${G}│${X}  ${G}✓${X} ${B}Installation complete${X}                ${G}│${X}"
        echo -e "  ${G}└─────────────────────────────────────────┘${X}"
    else
        warn "Installed but 'rcloak' not in PATH"
        if ! is_root; then
            echo -e "  ${D}Add to your shell profile:${X}"
            echo -e "  ${D}export PATH=\"\${HOME}/.local/bin:\$PATH\"${X}"
        else
            echo -e "  ${D}export PATH=\"/usr/local/bin:\$PATH\"${X}"
        fi
    fi

    echo ""
    echo -e "  ${B}Get started:${X}"
    echo -e "    rcloak setup     ${D}first-time config${X}"
    echo -e "    rcloak --help    ${D}all commands${X}"
    echo ""
}

do_uninstall() {
    banner

    echo -e "  ${B}Uninstalling${X}"
    echo ""

    if [[ -L "$BIN_LINK" || -f "$BIN_LINK" ]]; then
        run_cmd rm -f "$BIN_LINK"
        success "Removed ${BIN_LINK}"
    fi

    if [[ -d "$INSTALL_DIR" ]]; then
        run_cmd rm -rf "$INSTALL_DIR"
        success "Removed ${INSTALL_DIR}"
    fi

    echo ""
    echo -e "  ${G}┌─────────────────────────────────────────┐${X}"
    echo -e "  ${G}│${X}  ${G}✓${X} ${B}Uninstall complete${X}                   ${G}│${X}"
    echo -e "  ${G}└─────────────────────────────────────────┘${X}"
    echo ""
}

case "${1:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    *) echo "Usage: install.sh [install|uninstall]"; exit 1 ;;
esac
