#!/usr/bin/env bash

_server_name() {
    local name
    name=$(config_get '.server_name // empty' 2>/dev/null || echo "")
    if [[ -n "$name" && "$name" != "null" && "$name" != "empty" ]]; then
        echo "$name"
    else
        hostname 2>/dev/null || echo "server"
    fi
}

_discord_payload() {
    local title="$1" color="$2" description="$3" fields="${4:-[]}"

    jq -n \
        --arg title "$title" \
        --argjson color "$color" \
        --arg desc "$description" \
        --argjson fields "$fields" \
        --arg ts "$(date -Iseconds)" \
        '{embeds: [{
            title: $title,
            color: $color,
            description: $desc,
            fields: $fields,
            footer: {text: "rcloak"},
            timestamp: $ts
        }]}' 2>/dev/null
}

_discord_send() {
    local payload="$1"
    local webhook_url
    webhook_url=$(config_get '.notifications.discord.webhook_url' 2>/dev/null || echo "")
    [[ -z "$webhook_url" || "$webhook_url" == "null" ]] && return 0
    curl -s -o /dev/null -H "Content-Type: application/json" -d "$payload" "$webhook_url" &>/dev/null || true
    return 0
}

_should_notify() {
    local status="$1"
    local on_success on_failure
    on_success=$(config_get '.notifications.on_success' 2>/dev/null || echo "true")
    on_failure=$(config_get '.notifications.on_failure' 2>/dev/null || echo "true")
    [[ "$status" == "success" && "$on_success" != "true" ]] && return 1
    [[ "$status" == "error"   && "$on_failure" != "true" ]] && return 1
    return 0
}

notify_send_payload() {
    local status="$1" payload="$2"
    _should_notify "$status" || return 0

    local discord_enabled
    discord_enabled=$(config_get '.notifications.discord.enabled' 2>/dev/null || echo "false")
    [[ "$discord_enabled" == "true" ]] && _discord_send "$payload" || true
    return 0
}

notify_backup_start() {
    local total_jobs="$1"; shift
    local job_names=("$@")
    local server
    server=$(_server_name)

    local jobs_value="" bt='`'
    for j in "${job_names[@]}"; do
        [[ -n "$jobs_value" ]] && jobs_value+=$'\n'
        jobs_value+="${bt}${j}${bt}"
    done

    local fields
    fields=$(jq -n --arg jobs "$jobs_value" \
        '[{name: "Jobs", value: $jobs, inline: false}]' 2>/dev/null || echo "[]")

    local payload
    payload=$(_discord_payload \
        "Backup Started" \
        5793266 \
        "Running **${total_jobs}** job(s) on **${server}**" \
        "$fields")

    [[ -n "$payload" ]] && notify_send_payload "progress" "$payload" || true
    return 0
}

notify_job_start() { return 0; }
notify_job_done()  { return 0; }

notify_backup_summary() {
    local total_jobs="$1" success_count="$2" fail_count="$3"
    local total_duration="$4" total_size="${5:-unknown}"
    shift 5
    local job_results=("$@")
    local server
    server=$(_server_name)

    local title color desc overall_status
    if [[ $fail_count -eq 0 ]]; then
        title="Backup Complete"
        color=5763719       # green
        desc="All **${success_count}** job(s) completed on **${server}**"
        overall_status="success"
    elif [[ $success_count -eq 0 ]]; then
        title="Backup Failed"
        color=15548997      # red
        desc="All **${fail_count}** job(s) failed on **${server}**"
        overall_status="error"
    else
        title="Partial Failure"
        color=16705372      # yellow/orange
        desc="**${success_count}** succeeded, **${fail_count}** failed on **${server}**"
        overall_status="warn"
    fi

    local results_json="["
    local first=true
    for r in "${job_results[@]}"; do
        local rname rstatus rdur rsize
        rname=$(echo "$r"  | cut -d'|' -f1)
        rstatus=$(echo "$r" | cut -d'|' -f2)
        rdur=$(echo "$r"   | cut -d'|' -f3)
        rsize=$(echo "$r"  | cut -d'|' -f4)
        [[ "$first" == "true" ]] && first=false || results_json+=","
        results_json+=$(jq -n \
            --arg name "$rname" --arg status "$rstatus" \
            --arg dur "$rdur"   --arg size "$rsize" \
            '{name:$name,status:$status,dur:$dur,size:$size}' 2>/dev/null)
    done
    results_json+="]"

    local fields
    fields=$(echo "$results_json" | jq \
        --arg tdur "$total_duration" \
        --arg tsize "$total_size" \
        '
        map(
            if .status == "success" then
                {name: .name, value: (.size + " · " + .dur), inline: true}
            else
                {name: .name, value: ("Failed after " + .dur), inline: true}
            end
        ) + [{name: "Total", value: ($tdur + " · " + $tsize), inline: false}]
        ' 2>/dev/null || echo "[]")

    local payload
    payload=$(_discord_payload "$title" "$color" "$desc" "$fields")
    [[ -n "$payload" ]] && notify_send_payload "$overall_status" "$payload" || true
    return 0
}
