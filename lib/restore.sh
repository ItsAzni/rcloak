#!/usr/bin/env bash

restore_interactive() {
    echo ""
    echo -e "  ${_CLR_BOLD}Restore Backup${_CLR_RESET}"

    local count
    count=$(db_count)
    if [[ "$count" -eq 0 ]]; then
        log_warn "No backup records found. Run a backup first, or import from remote."
        return 1
    fi

    local entries=() display=()
    while IFS='|' read -r id job_name hostname dest remote_path size archive compressed completed; do
        entries+=("${id}|${job_name}|${hostname}|${dest}|${remote_path}|${size}|${archive}|${compressed}")
        display+=("${job_name} · ${size} · ${completed} · from ${hostname}")
    done < <(db_list_restorable 15)

    if [[ ${#display[@]} -eq 0 ]]; then
        log_warn "No successful backups available to restore."
        return 1
    fi

    ui_select "Choose backup to restore" "${display[@]}"

    local selected_entry=""
    for i in "${!display[@]}"; do
        [[ "${display[$i]}" == "$__UI_RESULT" ]] && { selected_entry="${entries[$i]}"; break; }
    done
    [[ -z "$selected_entry" ]] && { log_error "Selection not found"; return 1; }

    local sel_job sel_host sel_dest sel_remote sel_size sel_archive sel_compressed
    sel_job=$(echo "$selected_entry" | cut -d'|' -f2)
    sel_host=$(echo "$selected_entry" | cut -d'|' -f3)
    sel_dest=$(echo "$selected_entry" | cut -d'|' -f4)
    sel_remote=$(echo "$selected_entry" | cut -d'|' -f5)
    sel_size=$(echo "$selected_entry" | cut -d'|' -f6)
    sel_archive=$(echo "$selected_entry" | cut -d'|' -f7)
    sel_compressed=$(echo "$selected_entry" | cut -d'|' -f8)

    ui_prompt "Restore to path" "/tmp/restore-${sel_job}"
    local restore_path="$__UI_RESULT"

    echo ""
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET} ${_CLR_BOLD}Restore Summary${_CLR_RESET}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET}   Job:    ${sel_job}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET}   From:   ${sel_dest}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET}   To:     ${restore_path}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET}   Size:   ${sel_size}"
    echo -e "  ${_CLR_CYAN}┃${_CLR_RESET}   Host:   ${sel_host}"

    if ! ui_confirm "Proceed with restore?" "y"; then
        log_info "Restore cancelled"
        return 0
    fi

    restore_execute "$sel_dest" "$restore_path" "$sel_compressed" "$sel_archive"
}

restore_execute() {
    local remote_path="$1" restore_path="$2" compressed="${3:-0}" archive_name="${4:-}"

    mkdir -p "$restore_path"
    local start_time
    start_time=$(date +%s)

    log_header "Restoring"
    log_step "From" "$remote_path"
    log_step "To" "$restore_path"

    if [[ "$compressed" == "1" && -n "$archive_name" ]]; then
        log_info "Downloading archive..."
        local tmp_dir="/tmp/rcloak_restore_$$"
        mkdir -p "$tmp_dir"

        if ! rclone copy "${remote_path}" "$tmp_dir/" --include "${archive_name}" 2>/dev/null; then
            log_error "Download failed"
            rm -rf "$tmp_dir"
            return 1
        fi

        local tmp_file="${tmp_dir}/${archive_name}"
        if [[ ! -f "$tmp_file" ]]; then
            log_error "Archive not found on remote"
            rm -rf "$tmp_dir"
            return 1
        fi

        log_info "Extracting..."
        if ! tar -xzf "$tmp_file" -C "$restore_path" 2>/dev/null; then
            log_error "Extraction failed"
            rm -rf "$tmp_dir"
            return 1
        fi
        rm -rf "$tmp_dir"
    else
        log_info "Syncing from remote..."
        if ! rclone sync "$remote_path" "$restore_path" --progress 2>&1 | tail -1; then
            log_error "Restore failed"
            return 1
        fi
    fi

    local duration_str
    duration_str=$(elapsed_time $(($(date +%s) - start_time)))
    log_footer "${_CLR_GREEN}✓${_CLR_RESET} Restored in ${duration_str}"
    log_success "Files at: ${restore_path}"
}

restore_by_job() {
    local job_name="$1" restore_path="${2:-}"

    local entry
    entry=$(db_get_latest_backup "$job_name")
    [[ -z "$entry" ]] && { log_error "No backup found for '${job_name}'"; return 1; }

    local sel_source sel_dest sel_size sel_archive sel_compressed
    sel_source=$(echo "$entry" | cut -d'|' -f4)
    sel_dest=$(echo "$entry" | cut -d'|' -f5)
    sel_size=$(echo "$entry" | cut -d'|' -f7)
    sel_archive=$(echo "$entry" | cut -d'|' -f8)
    sel_compressed=$(echo "$entry" | cut -d'|' -f9)

    [[ -z "$restore_path" ]] && restore_path="$sel_source"

    echo ""
    echo -e "  ${_CLR_BOLD}Restore:${_CLR_RESET} ${job_name} (latest)"
    echo -e "  ${_CLR_DIM}From: ${sel_dest}${_CLR_RESET}"
    echo -e "  ${_CLR_DIM}To:   ${restore_path}${_CLR_RESET}"
    echo -e "  ${_CLR_DIM}Size: ${sel_size}${_CLR_RESET}"
    echo ""

    ui_confirm "Proceed?" "y" || return 0
    restore_execute "$sel_dest" "$restore_path" "$sel_compressed" "$sel_archive"
}
