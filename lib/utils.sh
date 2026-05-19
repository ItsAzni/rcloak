#!/usr/bin/env bash

readonly RCLOAK_VERSION="1.0.2"
readonly RCLOAK_DIR="${RCLOAK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ $EUID -eq 0 ]]; then
    readonly RCLOAK_DATA_DIR="${RCLOAK_DATA_DIR:-/etc/rcloak}"
else
    readonly RCLOAK_DATA_DIR="${RCLOAK_DATA_DIR:-${HOME}/.config/rcloak}"
fi

readonly RCLOAK_CONFIG_DIR="${RCLOAK_DATA_DIR}"
readonly RCLOAK_CONFIG_FILE="${RCLOAK_CONFIG_DIR}/backup.json"
readonly RCLOAK_LOG_DIR="${RCLOAK_DATA_DIR}/logs"
readonly RCLOAK_LOCK_FILE="/tmp/rcloak.lock"

__UI_RESULT=""

ui_banner() {
    echo ""
    echo -e "  ${_CLR_CYAN}  ██████╗  ██████╗██╗      ██████╗  █████╗ ██╗  ██╗${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}  ██╔══██╗██╔════╝██║     ██╔═══██╗██╔══██╗██║ ██╔╝${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}  ██████╔╝██║     ██║     ██║   ██║███████║█████╔╝ ${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}  ██╔══██╗██║     ██║     ██║   ██║██╔══██║██╔═██╗ ${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}  ██║  ██║╚██████╗███████╗╚██████╔╝██║  ██║██║  ██╗${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}  ╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝${_CLR_RESET}"
    echo -e "  ${_CLR_DIM}  v${RCLOAK_VERSION} • smart backup powered by rclone${_CLR_RESET}"
    echo ""
}

ui_spinner() {
    local pid=$1 msg="${2:-Processing...}"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r  ${_CLR_CYAN}${frames[$i]}${_CLR_RESET} ${msg}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    echo -ne "\r\033[K"
}

ui_prompt() {
    local label="$1" default="${2:-}" hint=""
    [[ -n "$default" ]] && hint=" ${_CLR_DIM}[${default}]${_CLR_RESET}"
    echo ""
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_BOLD}${label}${_CLR_RESET}${hint}"
    echo -ne "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_GREEN}▸${_CLR_RESET} "
    read -r __UI_RESULT
    [[ -z "$__UI_RESULT" && -n "$default" ]] && __UI_RESULT="$default"
    [[ -n "$__UI_RESULT" ]] && echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_DIM}→ ${__UI_RESULT}${_CLR_RESET}"
}

ui_confirm() {
    local prompt="$1" default="${2:-y}" hint
    if [[ "$default" == "y" ]]; then
        hint="${_CLR_GREEN}${_CLR_BOLD}Y${_CLR_RESET}${_CLR_DIM}/n${_CLR_RESET}"
    else
        hint="${_CLR_DIM}y/${_CLR_RESET}${_CLR_RED}${_CLR_BOLD}N${_CLR_RESET}"
    fi
    echo ""
    echo -ne "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_BOLD}${prompt}${_CLR_RESET} [${hint}] ${_CLR_GREEN}▸${_CLR_RESET} "
    read -r answer
    answer="${answer:-$default}"
    if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
        echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_DIM}→ Yes${_CLR_RESET}"
        return 0
    else
        echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_DIM}→ No${_CLR_RESET}"
        return 1
    fi
}

ui_select() {
    local prompt="$1"; shift
    local options=("$@")
    local count=${#options[@]} selected=0 key=""

    echo ""
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_BOLD}${prompt}${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_DIM}↑/↓ arrow keys to move, Enter to select${_CLR_RESET}"
    echo ""

    tput civis 2>/dev/null || true

    _ui_select_draw() {
        [[ ${1:-0} -eq 1 ]] && for ((i=0; i<count; i++)); do echo -ne "\033[A"; done
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "\033[K  ${_CLR_CYAN}┃${_CLR_RESET}   ${_CLR_CYAN}❯ ${_CLR_BOLD}${options[$i]}${_CLR_RESET}"
            else
                echo -e "\033[K  ${_CLR_CYAN}┃${_CLR_RESET}     ${_CLR_DIM}${options[$i]}${_CLR_RESET}"
            fi
        done
    }

    _ui_select_draw 0

    while true; do
        read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') selected=$(( (selected - 1 + count) % count )); _ui_select_draw 1 ;;
                    '[B') selected=$(( (selected + 1) % count )); _ui_select_draw 1 ;;
                esac ;;
            '') break ;;
            [1-9]) [[ "$key" -le "$count" ]] && { selected=$((key - 1)); _ui_select_draw 1; break; } ;;
        esac
    done

    tput cnorm 2>/dev/null || true
    __UI_RESULT="${options[$selected]}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_DIM}→ ${__UI_RESULT}${_CLR_RESET}"
}

ui_step() {
    local step_num="$1" total="$2" title="$3"
    echo ""
    echo -e "  ${_CLR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_DIM}Step ${step_num}/${total}${_CLR_RESET}  ${_CLR_BOLD}${title}${_CLR_RESET}"
}

check_dependency() {
    local cmd="$1" hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "'${cmd}' not installed.${hint:+ Install: $hint}"
        return 1
    fi
    return 0
}

check_dependencies() {
    local missing=0
    check_dependency "rclone" "https://rclone.org/install/" || missing=$((missing + 1))
    check_dependency "jq" "apt install jq" || missing=$((missing + 1))
    check_dependency "curl" "apt install curl" || missing=$((missing + 1))
    check_dependency "sqlite3" "apt install sqlite3" || missing=$((missing + 1))
    return $missing
}

acquire_lock() {
    if [[ -f "$RCLOAK_LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$RCLOAK_LOCK_FILE" 2>/dev/null)
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another instance running (PID: ${lock_pid})"
            return 1
        fi
        rm -f "$RCLOAK_LOCK_FILE"
    fi
    echo $$ > "$RCLOAK_LOCK_FILE"
}

release_lock() { rm -f "$RCLOAK_LOCK_FILE"; }

human_size() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then echo "$(( bytes / 1024 )) KB"
    elif [[ $bytes -lt 1073741824 ]]; then echo "$(echo "scale=1; $bytes / 1048576" | bc 2>/dev/null || echo "$(( bytes / 1048576 ))") MB"
    else echo "$(echo "scale=2; $bytes / 1073741824" | bc 2>/dev/null || echo "$(( bytes / 1073741824 ))") GB"
    fi
}

elapsed_time() {
    local s=$1
    if [[ $s -lt 60 ]]; then echo "${s}s"
    elif [[ $s -lt 3600 ]]; then echo "$(( s / 60 ))m $(( s % 60 ))s"
    else echo "$(( s / 3600 ))h $(( (s % 3600) / 60 ))m"
    fi
}

ensure_dirs() { mkdir -p "$RCLOAK_CONFIG_DIR" "$RCLOAK_LOG_DIR"; }
