# Summary

You like having an AI assistant who has your life context, but you don't want to share your life context with the cloud LLM platforms.

# Local LLM stack (Ollama + Open WebUI)

ChatGPT-style local assistant with automatic cross-chat memory, running entirely
on your local laptop (tested on Mac Apple M4 Pro, 24 GB). Reachable from iPhone via Tailscale.

## Components

| Piece                | Detail                                                                                                                      |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Ollama               | Runs on the host at `:11434`                                                                                                |
| Open WebUI           | Docker container `open-webui`, published on `127.0.0.1:3000` → `8080`, image `ghcr.io/open-webui/open-webui:main` (v0.11.4) |
| Primary / chat model | `gemma4:e4b`                                                                                                                |
| Database             | SQLite at `/app/backend/data/webui.db` inside the container (Docker volume `open-webui`)                                    |
| Remote access        | Tailscale + `tailscale serve --bg 3000`                                                                                     |

## Setup (first-time install)

Prerequisite: install **[Docker Desktop](https://www.docker.com/products/docker-desktop/)**
and make sure it's running.

**1. Install and start Ollama** (the local model server):

```bash
brew install ollama        # or download from https://ollama.com/download
open -a Ollama             # starts the background server at :11434 (or: ollama serve)
```

**2. Pull the model:**

```bash
ollama pull gemma4:e4b
```

**3. Download & run Open WebUI** (pulls the image and starts it on port `3000`):

```bash
docker run -d \
  -p 127.0.0.1:3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart unless-stopped \
  ghcr.io/open-webui/open-webui:main
```

- `-p 127.0.0.1:3000:8080` — serves the UI at `localhost:3000` (loopback only).
- `-e OLLAMA_BASE_URL=http://host.docker.internal:11434` — lets the container reach Ollama on the host.
- `-v open-webui:/app/backend/data` — the volume where all data (chats, memories, settings) is persisted.
- `--restart unless-stopped` — auto-starts the container on reboot.

**4. Open it:** browse to <http://localhost:3000>, create the first account (it
becomes the admin), and confirm `gemma4:e4b` appears in the model picker. If it
doesn't, make sure Ollama is running (`ollama list`).

## Remote access from your phone (Tailscale)

The container is bound to `127.0.0.1` (your Mac only). Tailscale puts your Mac and
phone on a private, encrypted VPN (your "tailnet") so the phone can reach it — from
anywhere, with no port forwarding and nothing exposed to the public internet.

**1. On the Mac — install Tailscale, sign in, and bring it up:**

```bash
brew install --cask tailscale     # or https://tailscale.com/download
# open the Tailscale app and sign in, then:
tailscale up
```

**2. On the Mac — expose Open WebUI to your tailnet over HTTPS:**

```bash
tailscale serve --bg 3000         # proxies localhost:3000 to your tailnet (HTTPS)
tailscale serve status            # shows the https://<mac>.<tailnet>.ts.net URL
```

This keeps access **private** to your own devices. (Do *not* use `tailscale funnel`
— that would expose it to the public internet.) Undo with `tailscale serve reset`.

**3. On the iPhone:** install **Tailscale** from the App Store, sign in with the
**same account**, and leave it connected.

**4. Open it on the phone:** browse to the `https://<mac>.<tailnet>.ts.net` URL
from step 2 (find your Mac's name in `tailscale status`). In Safari, **Share → Add
to Home Screen** to get an app-like icon.

## Helper scripts

- `llm.sh` (also on PATH as `llm`) — health check for container / Ollama / Tailscale, with fix-it instructions if any piece is down.
- `backup-memories.sh` — daily DB backup (see **Backups** below).

---

## How automatic memory was enabled

Open WebUI 0.11.4 has a **native background memory reviewer** (ChatGPT-style:
auto-save durable facts after a turn, auto-inject them into future chats). It is
off by default.

These are **not** exposed in the admin UI, and the `ENABLE_MEMORY_BACKGROUND_REVIEW`
env var is ignored once the value is in the DB — so they must be set directly in
the `config` table. Values changed:

| Config key                          | Before    | After                                                   |
| ----------------------------------- | --------- | ------------------------------------------------------- |
| `memories.background_review.enable` | `'false'` | `'true'`                                                |
| `memories.review_interval_turns`    | `10`      | `1` (review every turn; raise to 3–5 for less overhead) |
| `memories.enable`                   | `'true'`  | (already on)                                            |
| `memories.system_context.enable`    | `'true'`  | (already on)                                            |

Apply with:

```bash
docker exec open-webui python3 -c "import sqlite3; c=sqlite3.connect('/app/backend/data/webui.db'); c.execute(\"update config set value='true' where key='memories.background_review.enable'\"); c.execute('update config set value=1 where key=\"memories.review_interval_turns\"'); c.commit(); print('done')"
docker restart open-webui
```

### Possible Weird Bug

Also, there may be a quirk in Open WebUI where you have to go into:

**Admin Panel → Settings → Models → `Your Model` → check "Memory" → Save.**

Even if "Memory" is already checked, just hit "Save" again.

This creates a row in the `model` table with `meta.capabilities.memory = true`.
Without it, the frontend never sends `features.memory=true`, and the reviewer
silently does nothing. (Bare Ollama models may not have a row until you edit + **Save**).

Repeat for any other model you want to use with memory.

## Backups

Memories/data live in the Docker volume. So the DB is exported to `~/localllm/backups/`
(a Time Machine-[Included] folder), and Time Machine then sweeps it to the external
drive.

- `backup-memories.sh` — consistent SQLite snapshot → `webui-<ts>.db` (full DB) +
  `memories-<ts>.json` (readable memories export); keeps newest `KEEP` of each.
- launchd agent runs it daily at 03:00; logs to
  `~/localllm/backups/backup.log`. A generic reference template lives at
  `~/localllm/openwebui-backup.plist.template` (replace `USERNAME`, then save a
  copy to `~/Library/LaunchAgents/com.USERNAME.openwebui-backup.plist`).

Commands:

```bash
launchctl start com.USERNAME.openwebui-backup     # run a backup now
launchctl list | grep openwebui-backup            # confirm it's scheduled
tail -f ~/localllm/backups/backup.log             # watch the log
```

To change the schedule: edit the plist's `Hour`/`Minute`, then
`launchctl unload <plist>` and `launchctl load -w <plist>`.

---

## Restore a DB backup

Each `webui-<timestamp>.db` is the **entire** database (memories _and_ chats,
settings, users). Restoring reverts everything to that snapshot.

```bash
# 1. Pick a snapshot
ls -lt ~/localllm/backups/webui-*.db

# 2. Stop Open WebUI first (graceful stop flushes & removes the DB's WAL
#    sidecar files, so the restored file loads cleanly)
docker stop open-webui

# 3. Copy the chosen backup over the live database
docker cp ~/localllm/backups/webui-20261007-235232.db \
  open-webui:/app/backend/data/webui.db

# 4. Start it back up
docker start open-webui
```

Verify:

```bash
docker exec open-webui python3 -c "import sqlite3; print('memories:', sqlite3.connect('/app/backend/data/webui.db').execute('select count(*) from memory').fetchone()[0])"
```

If memory _search_ seems stale after a restore, use the re-index option in
Settings (vector indexes rebuild from the restored content).

If you ever copied a backup in **without** stopping first and things look wrong,
clear the stale WAL sidecars and restart:

```bash
docker run --rm -v open-webui:/data alpine rm -f /data/webui.db-wal /data/webui.db-shm
docker restart open-webui
```

The `memories-<ts>.json` files are portable/readable reference exports; they are
not used by the restore above (which uses the full `.db`).
