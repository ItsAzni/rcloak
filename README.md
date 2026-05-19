# rcloak

Backup tool built on top of rclone. Manage jobs, schedule backups, get notified, restore anywhere.

```
    ██████╗  ██████╗██╗      ██████╗  █████╗ ██╗  ██╗
    ██╔══██╗██╔════╝██║     ██╔═══██╗██╔══██╗██║ ██╔╝
    ██████╔╝██║     ██║     ██║   ██║███████║█████╔╝
    ██╔══██╗██║     ██║     ██║   ██║██╔══██║██╔═██╗
    ██║  ██║╚██████╗███████╗╚██████╔╝██║  ██║██║  ██╗
    ╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
```

## Install & Uninstall

```bash
# install
curl -fsSL https://raw.githubusercontent.com/itsazni/rcloak/main/install.sh | bash
```

```bash
# uninstall
curl -fsSL https://raw.githubusercontent.com/itsazni/rcloak/main/install.sh | bash -s uninstall
```

### Update

```bash
# check and update to latest version
rcloak update

# force reinstall (even if on latest)
rcloak update --force

# force reinstall directly from installer
curl -fsSL https://raw.githubusercontent.com/itsazni/rcloak/main/install.sh | bash -s --force
```

## Usage

### Setup

First-time configuration. Walks you through remotes, notifications, and your first job.

```bash
rcloak setup
```

### Managing jobs

```bash
# add interactively
rcloak add

# add via flags
rcloak add --name mysite --source /var/www --dest gdrive:backups/web --compress --retention 7

# list all jobs
rcloak list

# edit a job (interactive menu: source, dest, compression, retention, enable/disable, rename)
rcloak edit

# remove a job
rcloak remove
```

### Running backups

```bash
# run all enabled jobs
rcloak run

# run specific job
rcloak run --job mysite

# simulate without uploading
rcloak run --dry-run
```

### Restore

Restore from any backup in the history database. Works across hosts.

```bash
# interactive picker (shows all backups from all hosts)
rcloak restore

# restore specific job (latest successful backup)
rcloak restore --job mysite --to /tmp/restored
```

### History

```bash
rcloak history
```

Shows all recorded backups with size, duration, status, and which host ran them.

### Scheduling

```bash
# interactive schedule picker
rcloak schedule

# set directly
rcloak schedule --cron "0 2 * * *"

# specific job only
rcloak schedule --cron "0 */6 * * *" --job database

# remove
rcloak schedule --remove
```

### Notifications

Discord webhook notifications on backup start, progress, and completion.

```bash
# configure
rcloak notify

# test delivery
rcloak test-notify
```

### Sync & restore across hosts

rcloak keeps a SQLite database of all backups. Sync it to your remote so you can restore from another machine.

```bash
# set default remote for sync
rcloak set-remote

# push config + db to remote
rcloak sync-db

# push to specific remote
rcloak sync-db --remote mydrive:

# pull db from remote (merges with local)
rcloak import-db

# pull from specific remote
rcloak import-db --remote mydrive:
```

Typical cross-host flow:

```bash
# host A
rcloak run          # backups + auto-syncs db

# host B
rcloak import-db    # pull backup history
rcloak restore      # pick and restore
```

### Other

```bash
rcloak config       # show raw json config
rcloak cleanup      # apply retention policy (delete old backups from remote)
rcloak status       # job status overview
rcloak --version
rcloak --verbose    # debug output
rcloak --no-color   # disable colors
```

## Config

Stored at `config/backup.json`. Managed through CLI — no manual editing needed.

## Project layout

```
rcloak/
├── rcloak           main cli
├── lib/
│   ├── backup.sh    backup execution
│   ├── config.sh    json config
│   ├── db.sh        sqlite history
│   ├── logger.sh    logging
│   ├── notify.sh    discord
│   ├── restore.sh   restore logic
│   └── utils.sh     ui & helpers
├── data/
│   └── rcloak.db    backup history
├── config/
│   └── backup.json  user config
├── logs/            execution logs
└── install.sh       installer
```

## Requirements

- bash 4+
- rclone (configured with at least one remote)
- jq, curl, sqlite3

## License

This project is licensed under the MIT License.
See [LICENSE](LICENSE) for details.
