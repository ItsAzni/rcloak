#!/usr/bin/env bash

readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

_CLR_RESET="\033[0m"
_CLR_DIM="\033[2m"
_CLR_BOLD="\033[1m"
_CLR_RED="\033[31m"
_CLR_GREEN="\033[32m"
_CLR_YELLOW="\033[33m"
_CLR_CYAN="\033[36m"

RCLOAK_LOG_LEVEL="${RCLOAK_LOG_LEVEL:-$LOG_LEVEL_INFO}"
RCLOAK_NO_COLOR="${RCLOAK_NO_COLOR:-false}"

_disable_colors() {
    _CLR_RESET="" _CLR_DIM="" _CLR_BOLD=""
    _CLR_RED="" _CLR_GREEN="" _CLR_YELLOW="" _CLR_CYAN=""
}

_init_logger() {
    if [[ "$RCLOAK_NO_COLOR" == "true" ]] || [[ ! -t 1 ]]; then
        _disable_colors
    fi
}

log_debug() { [[ "$RCLOAK_LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]] && echo -e "  ${_CLR_DIM}[debug] $*${_CLR_RESET}" >&2; return 0; }
log_info()  { [[ "$RCLOAK_LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]]  && echo -e "  ${_CLR_CYAN}●${_CLR_RESET} $*"; return 0; }
log_success() { [[ "$RCLOAK_LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]] && echo -e "  ${_CLR_GREEN}✓${_CLR_RESET} $*"; return 0; }
log_warn()  { [[ "$RCLOAK_LOG_LEVEL" -le "$LOG_LEVEL_WARN" ]]  && echo -e "  ${_CLR_YELLOW}⚠${_CLR_RESET} $*" >&2; return 0; }
log_error() { [[ "$RCLOAK_LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]] && echo -e "  ${_CLR_RED}✗${_CLR_RESET} $*" >&2; return 0; }

log_step()   { echo -e "  ${_CLR_CYAN}│${_CLR_RESET} ${_CLR_BOLD}${1}:${_CLR_RESET} ${*:2}"; }
log_header() { echo ""; echo -e "  ${_CLR_CYAN}┌${_CLR_RESET} ${_CLR_BOLD}$*${_CLR_RESET}"; }
log_footer() { echo -e "  ${_CLR_CYAN}└${_CLR_RESET} $*"; echo ""; }
log_separator() { echo -e "  ${_CLR_DIM}─────────────────────────────────────${_CLR_RESET}"; }
