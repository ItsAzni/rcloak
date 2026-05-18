#!/usr/bin/env bash

notify_discord() {
    local title="$1" message="$2" status="${3:-info}"
    local webhook_url
    webhook_url=$(config_get '.notifications.discord.webhook_url' 2>/dev/null || echo "")
    [[ -z "$webhook_url" || "$webhook_url" == "null" ]] && return 0

    local color
    case "$status" in
        success)  color=5763719 ;;
        error)    color=15548997 ;;
        warn)     color=16705372 ;;
        progress) color=5793266 ;;
        *)        color=5793266 ;;
    esac

    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$message" \
        --argjson color "$color" \
        --arg ts "$(date -Iseconds)" \
        --arg footer "⚡ rcloak · $(hostname 2>/dev/null || echo server)" \
        '{embeds: [{title: $title, description: $desc, color: $color, timestamp: $ts, footer: {text: $footer}}]}' 2>/dev/null) || return 0

    curl -s -o /dev/null -H "Content-Type: application/json" -d "$payload" "$webhook_url" &>/dev/null || true
    return 0
}

_should_notify() {
    local status="$1"
    local on_success on_failure
    on_success=$(config_get '.notifications.on_success' 2>/dev/null || echo "true")
    on_failure=$(config_get '.notifications.on_failure' 2>/dev/null || echo "true")
    [[ "$status" == "success" && "$on_success" != "true" ]] && return 1
    [[ "$status" == "error" && "$on_failure" != "true" ]] && return 1
    return 0
}

notify_send() {
    local discord_title="$1" discord_msg="$2" status="${3:-info}"
    _should_notify "$status" || return 0

    local discord_enabled
    discord_enabled=$(config_get '.notifications.discord.enabled' 2>/dev/null || echo "false")

    if [[ "$discord_enabled" == "true" ]]; then
        notify_discord "$discord_title" "$discord_msg" "$status" || true
    fi
    return 0
}

_now_time() { date '+%H:%M' 2>/dev/null || echo ""; }
_now_date() { date '+%d/%m %H:%M' 2>/dev/null || echo ""; }
_host()     { hostname 2>/dev/null || echo "server"; }

notify_backup_start() {
    local total_jobs="$1"; shift
    local job_names=("$@")

    local dc_jobs=""
    for j in "${job_names[@]}"; do dc_jobs+="› \`${j}\`
"; done

    local dc="${dc_jobs}
Started at $(_now_time) · ${total_jobs} job(s)"

    notify_send "🔄 Backup Started" "$dc" "progress" || true
    return 0
}

notify_job_start() {
    local job_name="$1" source="$2" dest="$3" job_index="$4" total_jobs="$5"

    local dc="\`${job_name}\` → \`${dest}\`
\`\`\`
${source}
\`\`\`"

    notify_send "🔄 Syncing [${job_index}/${total_jobs}]" "$dc" "progress" || true
    return 0
}

notify_job_done() { return 0; }

notify_backup_summary() {
    local total_jobs="$1" success_count="$2" fail_count="$3"
    local total_duration="$4" total_size="${5:-unknown}"
    shift 5
    local job_results=("$@")

    local overall_status="success" status_icon="💾" status_text="All backups completed"
    if [[ $fail_count -gt 0 && $success_count -gt 0 ]]; then
        overall_status="warn" status_icon="⚠️" status_text="Partial failure"
    elif [[ $success_count -eq 0 ]]; then
        overall_status="error" status_icon="❌" status_text="All backups failed"
    fi

    local dc_jobs=""
    for r in "${job_results[@]}"; do
        local rname rstatus rdur rsize
        rname=$(echo "$r" | cut -d'|' -f1)
        rstatus=$(echo "$r" | cut -d'|' -f2)
        rdur=$(echo "$r" | cut -d'|' -f3)
        rsize=$(echo "$r" | cut -d'|' -f4)
        if [[ "$rstatus" == "success" ]]; then
            dc_jobs+="✅ \`${rname}\` — ${rsize} in ${rdur}
"
        else
            dc_jobs+="❌ \`${rname}\` — failed after ${rdur}
"
        fi
    done

    local dc="${dc_jobs}
${success_count} passed · ${fail_count} failed
${total_duration} · ${total_size}"

    notify_send "${status_icon} ${status_text}" "$dc" "$overall_status" || true
    return 0
}
