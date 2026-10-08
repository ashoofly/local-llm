#!/usr/bin/env bash
# backup-memories.sh — snapshot the Open WebUI database (your memories + all
# other data) into a Time Machine-covered folder, keeping the last N snapshots.
# Runs unattended via launchd, so PATH is set explicitly (launchd has a bare PATH).

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"

CONTAINER="open-webui"
DB="/app/backend/data/webui.db"
DEST="$HOME/localllm/backups"
KEEP=30                                   # snapshots to retain per type
ts="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DEST"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  log "ERROR: container '$CONTAINER' is not running; skipping backup."
  exit 1
fi

# Consistent snapshot via SQLite's backup API (safe while the app is running).
if docker exec "$CONTAINER" python3 -c "import sqlite3; s=sqlite3.connect('$DB'); d=sqlite3.connect('/tmp/webui-backup.db'); s.backup(d); d.close()"; then
  docker cp "$CONTAINER:/tmp/webui-backup.db" "$DEST/webui-$ts.db"
  docker exec "$CONTAINER" rm -f /tmp/webui-backup.db
else
  log "ERROR: failed to snapshot database."
  exit 1
fi

# Portable, human-readable export of just the memories table.
docker exec "$CONTAINER" python3 -c "
import sqlite3, json
con = sqlite3.connect('$DB'); con.row_factory = sqlite3.Row
print(json.dumps([dict(r) for r in con.execute('select * from memory')], indent=2, default=str))
" > "$DEST/memories-$ts.json"

count="$(docker exec "$CONTAINER" python3 -c "import sqlite3; print(sqlite3.connect('$DB').execute('select count(*) from memory').fetchone()[0])")"
log "OK: webui-$ts.db + memories-$ts.json ($count memories)."

# Rotate: keep only the newest $KEEP of each type.
ls -1t "$DEST"/webui-*.db      2>/dev/null | tail -n +$((KEEP+1)) | xargs -I{} rm -f {}
ls -1t "$DEST"/memories-*.json 2>/dev/null | tail -n +$((KEEP+1)) | xargs -I{} rm -f {}
