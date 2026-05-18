#!/usr/bin/env bash

readonly RCLOAK_DB_FILE="${RCLOAK_DATA_DIR}/rcloak.db"

db_init() {
    mkdir -p "$(dirname "$RCLOAK_DB_FILE")"

    sqlite3 "$RCLOAK_DB_FILE" << 'SQL'
CREATE TABLE IF NOT EXISTS backups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_name TEXT NOT NULL,
    hostname TEXT NOT NULL,
    source TEXT NOT NULL,
    dest TEXT NOT NULL,
    remote_path TEXT NOT NULL,
    size_bytes INTEGER DEFAULT 0,
    size_human TEXT DEFAULT 'unknown',
    duration_secs INTEGER DEFAULT 0,
    duration_human TEXT DEFAULT '0s',
    compressed INTEGER DEFAULT 0,
    archive_name TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'success',
    error_msg TEXT DEFAULT '',
    started_at TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
INSERT OR IGNORE INTO meta (key, value) VALUES ('version', '1.0.0');
SQL
}

db_record_backup() {
    local job_name="$1" source="$2" dest="$3" remote_path="$4"
    local size_bytes="${5:-0}" size_human="${6:-unknown}"
    local duration_secs="${7:-0}" duration_human="${8:-0s}"
    local compressed="${9:-0}" archive_name="${10:-}"
    local status="${11:-success}" error_msg="${12:-}"
    local started_at="${13:-}" completed_at="${14:-}"
    local host
    host=$(hostname 2>/dev/null || echo "unknown")

    sqlite3 "$RCLOAK_DB_FILE" << SQL
INSERT INTO backups (
    job_name, hostname, source, dest, remote_path,
    size_bytes, size_human, duration_secs, duration_human,
    compressed, archive_name, status, error_msg,
    started_at, completed_at
) VALUES (
    $(printf "'%s'" "$job_name"), $(printf "'%s'" "$host"),
    $(printf "'%s'" "$source"), $(printf "'%s'" "$dest"),
    $(printf "'%s'" "$remote_path"), $size_bytes,
    $(printf "'%s'" "$size_human"), $duration_secs,
    $(printf "'%s'" "$duration_human"), $compressed,
    $(printf "'%s'" "$archive_name"), $(printf "'%s'" "$status"),
    $(printf "'%s'" "$error_msg"), $(printf "'%s'" "$started_at"),
    $(printf "'%s'" "$completed_at")
);
SQL
}

db_list_backups() {
    local job_name="${1:-}" limit="${2:-20}"
    local query="SELECT id, job_name, hostname, size_human, duration_human, status, completed_at FROM backups"
    [[ -n "$job_name" ]] && query+=" WHERE job_name='${job_name}'"
    query+=" ORDER BY completed_at DESC LIMIT ${limit}"
    sqlite3 -separator '|' "$RCLOAK_DB_FILE" "$query"
}

db_list_restorable() {
    local limit="${1:-20}"
    sqlite3 -separator '|' "$RCLOAK_DB_FILE" \
        "SELECT id, job_name, hostname, dest, remote_path, size_human, archive_name, compressed, completed_at FROM backups WHERE status='success' ORDER BY completed_at DESC LIMIT ${limit}"
}

db_get_backup() {
    sqlite3 -separator '|' "$RCLOAK_DB_FILE" \
        "SELECT id, job_name, hostname, source, dest, remote_path, size_human, archive_name, compressed, completed_at FROM backups WHERE id=$1"
}

db_get_latest_backup() {
    sqlite3 -separator '|' "$RCLOAK_DB_FILE" \
        "SELECT id, job_name, hostname, source, dest, remote_path, size_human, archive_name, compressed, completed_at FROM backups WHERE job_name='$1' AND status='success' ORDER BY completed_at DESC LIMIT 1"
}

db_count() { sqlite3 "$RCLOAK_DB_FILE" "SELECT COUNT(*) FROM backups;" 2>/dev/null || echo "0"; }

db_stats() {
    sqlite3 -separator '|' "$RCLOAK_DB_FILE" << 'SQL'
SELECT
    COUNT(*),
    SUM(CASE WHEN status='success' THEN 1 ELSE 0 END),
    SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END),
    COALESCE(SUM(size_bytes), 0),
    COUNT(DISTINCT hostname),
    COUNT(DISTINCT job_name)
FROM backups;
SQL
}

db_delete_backup() {
    sqlite3 "$RCLOAK_DB_FILE" "DELETE FROM backups WHERE id=$1;"
}

db_delete_expired() {
    local job_name="$1" retention_days="$2"
    [[ "$retention_days" == "0" || "$retention_days" == "null" ]] && return 0
    sqlite3 "$RCLOAK_DB_FILE" \
        "DELETE FROM backups WHERE job_name='${job_name}' AND completed_at < datetime('now', '-${retention_days} days');"
}
