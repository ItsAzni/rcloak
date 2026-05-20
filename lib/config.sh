#!/usr/bin/env bash

config_exists() { [[ -f "$RCLOAK_CONFIG_FILE" ]]; }

config_init() {
    ensure_dirs
    config_exists && return 0
    cat > "$RCLOAK_CONFIG_FILE" << 'JSON'
{
  "version": "1.0.0",
  "server_name": "",
  "notifications": {
    "discord": {
      "enabled": false,
      "webhook_url": ""
    },
    "on_success": true,
    "on_failure": true
  },
  "defaults": {
    "compress": false,
    "retention_days": 30
  },
  "jobs": []
}
JSON
}

config_get() { jq -r "$1" "$RCLOAK_CONFIG_FILE" 2>/dev/null; }

config_set() {
    local tmp="${RCLOAK_CONFIG_FILE}.tmp"
    jq "$1 = $2" "$RCLOAK_CONFIG_FILE" > "$tmp" && mv "$tmp" "$RCLOAK_CONFIG_FILE"
}

config_set_str() {
    local tmp="${RCLOAK_CONFIG_FILE}.tmp"
    jq --arg val "$2" "$1 = \$val" "$RCLOAK_CONFIG_FILE" > "$tmp" && mv "$tmp" "$RCLOAK_CONFIG_FILE"
}

config_add_job() {
    local name="$1" source="$2" dest="$3"
    local compress="${4:-false}" retention="${5:-30}"

    [[ "$compress" != "true" ]] && compress="false"
    [[ ! "$retention" =~ ^[0-9]+$ ]] && retention=30

    local tmp="${RCLOAK_CONFIG_FILE}.tmp"
    local job
    job=$(jq -n \
        --arg name "$name" \
        --arg source "$source" \
        --arg dest "$dest" \
        --arg compress "$compress" \
        --arg retention "$retention" \
        --arg created "$(date -Iseconds)" \
        '{
            name: $name,
            source: $source,
            dest: $dest,
            compress: ($compress == "true"),
            retention_days: ($retention | tonumber),
            enabled: true,
            created: $created,
            last_run: null,
            last_status: null
        }')

    jq --argjson job "$job" '.jobs += [$job]' "$RCLOAK_CONFIG_FILE" > "$tmp" && mv "$tmp" "$RCLOAK_CONFIG_FILE"
    log_success "Job '${name}' added"
}

config_remove_job() {
    local name="$1"
    local tmp="${RCLOAK_CONFIG_FILE}.tmp"

    if ! jq -e --arg n "$name" '.jobs[] | select(.name == $n)' "$RCLOAK_CONFIG_FILE" &>/dev/null; then
        log_error "Job '${name}' not found"
        return 1
    fi

    jq --arg n "$name" '.jobs = [.jobs[] | select(.name != $n)]' "$RCLOAK_CONFIG_FILE" > "$tmp" && mv "$tmp" "$RCLOAK_CONFIG_FILE"
    log_success "Job '${name}' removed"
}

config_list_jobs() {
    if ! config_exists; then
        log_warn "No config found. Run 'rcloak setup' first."
        return 1
    fi

    local count
    count=$(jq '.jobs | length' "$RCLOAK_CONFIG_FILE")

    if [[ "$count" -eq 0 ]]; then
        log_info "No backup jobs configured. Use 'rcloak add' to create one."
        return 0
    fi

    echo ""
    echo -e "  ${_CLR_BOLD}Backup Jobs${_CLR_RESET} ${_CLR_DIM}(${count} total)${_CLR_RESET}"
    echo ""

    jq -r '.jobs[] | "\(.name)|\(.source)|\(.dest)|\(.enabled)|\(.last_status // "never")"' "$RCLOAK_CONFIG_FILE" | \
    while IFS='|' read -r name source dest enabled status; do
        local icon
        case "$status" in
            success) icon="${_CLR_GREEN}✓${_CLR_RESET}" ;;
            failed)  icon="${_CLR_RED}✗${_CLR_RESET}" ;;
            *)       icon="${_CLR_DIM}○${_CLR_RESET}" ;;
        esac
        [[ "$enabled" == "false" ]] && name="${name} ${_CLR_DIM}(disabled)${_CLR_RESET}"
        echo -e "  ${icon} ${_CLR_BOLD}${name}${_CLR_RESET}"
        echo -e "    ${_CLR_DIM}${source} → ${dest}${_CLR_RESET}"
    done
    echo ""
}

config_update_job_status() {
    local name="$1" status="$2"
    local tmp="${RCLOAK_CONFIG_FILE}.tmp"
    jq --arg n "$name" --arg s "$status" --arg now "$(date -Iseconds)" \
        '(.jobs[] | select(.name == $n)) |= (.last_run = $now | .last_status = $s)' \
        "$RCLOAK_CONFIG_FILE" > "$tmp" && mv "$tmp" "$RCLOAK_CONFIG_FILE"
}

config_get_job() {
    jq --arg n "$1" '.jobs[] | select(.name == $n)' "$RCLOAK_CONFIG_FILE" 2>/dev/null
}

config_get_all_jobs() {
    jq -r '.jobs[] | select(.enabled == true) | .name' "$RCLOAK_CONFIG_FILE" 2>/dev/null
}
