#!/usr/bin/env bash

backup_run_job() {
    local job_name="$1" dry_run="${2:-false}" job_index="${3:-1}" total_jobs="${4:-1}"

    local job
    job=$(config_get_job "$job_name")
    if [[ -z "$job" || "$job" == "null" ]]; then
        log_error "Job '${job_name}' not found"
        return 1
    fi

    local source dest compress retention
    source=$(echo "$job" | jq -r '.source')
    dest=$(echo "$job" | jq -r '.dest')
    compress=$(echo "$job" | jq -r '.compress')
    retention=$(echo "$job" | jq -r '.retention_days')

    if [[ ! -e "$source" ]]; then
        log_error "Source not found: ${source}"
        config_update_job_status "$job_name" "failed"
        return 1
    fi

    notify_job_start "$job_name" "$source" "$dest" "$job_index" "$total_jobs" &

    log_header "$job_name [${job_index}/${total_jobs}]"
    log_step "Source" "$source"
    log_step "Dest" "$dest"

    local start_time actual_source tmp_archive="" compressed_flag=0
    start_time=$(date +%s)
    actual_source="$source"

    if [[ "$compress" == "true" ]]; then
        compressed_flag=1
        local archive_name="${job_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        tmp_archive="/tmp/rcloak_${archive_name}"
        log_step "Compress" "Creating archive..."
        if ! tar -czf "$tmp_archive" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null; then
            log_error "Compression failed"
            config_update_job_status "$job_name" "failed"
            return 1
        fi
        actual_source="$tmp_archive"
        log_step "Archive" "$archive_name"
    fi

    local rclone_args=()
    if [[ -d "$actual_source" ]]; then
        rclone_args=(sync "$actual_source" "$dest" --progress --stats-one-line)
    else
        rclone_args=(copy "$actual_source" "$dest" --progress --stats-one-line)
    fi
    [[ "$dry_run" == "true" ]] && { rclone_args+=(--dry-run); log_step "Mode" "${_CLR_YELLOW}dry-run${_CLR_RESET}"; }

    local log_file="${RCLOAK_LOG_DIR}/${job_name}_$(date +%Y%m%d_%H%M%S).log"
    log_info "Syncing..."

    local exit_code=0
    rclone "${rclone_args[@]}" > "$log_file" 2>&1 || exit_code=$?

    local end_time duration_secs duration_str size_bytes=0 size_str="unknown"
    end_time=$(date +%s)
    duration_secs=$((end_time - start_time))
    duration_str=$(elapsed_time $duration_secs)

    if [[ -f "$actual_source" ]]; then
        size_bytes=$(stat -c%s "$actual_source" 2>/dev/null || echo "0")
    elif [[ -d "$actual_source" ]]; then
        size_bytes=$(du -sb "$actual_source" 2>/dev/null | cut -f1 || echo "0")
    fi
    size_str=$(human_size "$size_bytes")

    [[ -n "$tmp_archive" && -f "$tmp_archive" ]] && rm -f "$tmp_archive"

    local archive_used=""
    [[ $compressed_flag -eq 1 ]] && archive_used=$(basename "${tmp_archive:-}")

    if [[ $exit_code -eq 0 ]]; then
        config_update_job_status "$job_name" "success"
        log_footer "${_CLR_GREEN}✓${_CLR_RESET} Done in ${duration_str} · ${size_str}"
        db_record_backup "$job_name" "$source" "$dest" "$dest" \
            "$size_bytes" "$size_str" "$duration_secs" "$duration_str" \
            "$compressed_flag" "$archive_used" "success" "" \
            "$(date -Iseconds -d @$start_time 2>/dev/null || date -Iseconds)" "$(date -Iseconds)"
        echo "${job_name}|success|${duration_str}|${size_str}" >> "/tmp/rcloak_results.$$"

        # Auto-cleanup: delete old backups from remote and DB based on retention
        if [[ "$retention" != "null" && "$retention" != "0" && -n "$retention" ]]; then
            rclone delete "$dest" --min-age "${retention}d" 2>/dev/null || true
            db_delete_expired "$job_name" "$retention"
        fi
    else
        config_update_job_status "$job_name" "failed"
        local error_detail
        error_detail=$(tail -3 "$log_file" 2>/dev/null | tr '\n' ' ')
        log_footer "${_CLR_RED}✗${_CLR_RESET} Failed after ${duration_str}"
        db_record_backup "$job_name" "$source" "$dest" "$dest" \
            "0" "$size_str" "$duration_secs" "$duration_str" \
            "$compressed_flag" "$archive_used" "failed" "$error_detail" \
            "$(date -Iseconds -d @$start_time 2>/dev/null || date -Iseconds)" "$(date -Iseconds)"
        echo "${job_name}|failed|${duration_str}|${size_str}" >> "/tmp/rcloak_results.$$"
    fi

    return $exit_code
}

backup_run_all() {
    local dry_run="${1:-false}"
    local total_start success_count=0 fail_count=0
    total_start=$(date +%s)

    rm -f "/tmp/rcloak_results.$$"

    local jobs
    mapfile -t jobs < <(config_get_all_jobs)
    local total_jobs=${#jobs[@]}

    if [[ $total_jobs -eq 0 ]]; then
        log_warn "No enabled jobs. Use 'rcloak add' to create one."
        return 0
    fi

    echo ""
    echo -e "  ${_CLR_BOLD}⚡ rcloak${_CLR_RESET} ${_CLR_DIM}— running ${total_jobs} backup job(s)${_CLR_RESET}"
    echo ""

    notify_backup_start "$total_jobs" "${jobs[@]}"

    local job_index=0
    for job_name in "${jobs[@]}"; do
        job_index=$((job_index + 1))
        if backup_run_job "$job_name" "$dry_run" "$job_index" "$total_jobs"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    local total_end total_duration
    total_end=$(date +%s)
    total_duration=$(elapsed_time $((total_end - total_start)))

    local job_results=()
    if [[ -f "/tmp/rcloak_results.$$" ]]; then
        mapfile -t job_results < "/tmp/rcloak_results.$$"
        rm -f "/tmp/rcloak_results.$$"
    fi

    # Calculate total size from actual job results
    local total_size="unknown" all_size_bytes=0
    for r in "${job_results[@]}"; do
        local rsize
        rsize=$(echo "$r" | cut -d'|' -f4)
        local num unit
        num=$(echo "$rsize" | grep -oP '[0-9.]+' || echo "0")
        unit=$(echo "$rsize" | grep -oP '[A-Z]+' || echo "B")
        case "$unit" in
            GB) all_size_bytes=$(echo "$all_size_bytes + $num * 1073741824" | bc 2>/dev/null | cut -d. -f1 || echo "$all_size_bytes") ;;
            MB) all_size_bytes=$(echo "$all_size_bytes + $num * 1048576" | bc 2>/dev/null | cut -d. -f1 || echo "$all_size_bytes") ;;
            KB) all_size_bytes=$(echo "$all_size_bytes + $num * 1024" | bc 2>/dev/null | cut -d. -f1 || echo "$all_size_bytes") ;;
            B)  all_size_bytes=$((all_size_bytes + ${num%.*})) ;;
        esac
    done
    [[ $all_size_bytes -gt 0 ]] && total_size=$(human_size $all_size_bytes)

    log_separator
    if [[ $fail_count -eq 0 ]]; then
        log_success "${success_count} job(s) completed · ${total_duration} · ${total_size}"
    else
        log_warn "${success_count} succeeded, ${fail_count} failed · ${total_duration}"
    fi

    notify_backup_summary "$total_jobs" "$success_count" "$fail_count" "$total_duration" "$total_size" "${job_results[@]}"

    _auto_sync_db &

    return $fail_count
}

_auto_sync_db() {
    local remote=""
    if config_exists; then
        remote=$(config_get '.sync_remote // empty' 2>/dev/null || echo "")
    fi
    [[ -z "$remote" || "$remote" == "null" ]] && remote=$(rclone listremotes 2>/dev/null | head -1 | tr -d ' ')
    [[ -z "$remote" ]] && return 0

    remote="${remote%/}"
    [[ "$remote" == *: ]] && remote="${remote}rcloak-sync/" || remote="${remote}/rcloak-sync/"

    [[ -f "$RCLOAK_DB_FILE" ]] && rclone copy "$RCLOAK_DB_FILE" "${remote}data/" 2>/dev/null
    [[ -f "$RCLOAK_CONFIG_FILE" ]] && rclone copy "$RCLOAK_CONFIG_FILE" "${remote}config/" 2>/dev/null
}

backup_cleanup_old() {
    local job_name="$1"
    local job retention dest
    job=$(config_get_job "$job_name")
    retention=$(echo "$job" | jq -r '.retention_days')
    dest=$(echo "$job" | jq -r '.dest')

    [[ "$retention" == "null" || "$retention" == "0" ]] && return 0

    log_info "Cleaning files older than ${retention} days from ${dest}..."
    rclone delete "$dest" --min-age "${retention}d" 2>/dev/null
    log_success "Cleanup complete for '${job_name}'"
}
