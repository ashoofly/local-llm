#!/usr/bin/env bash
#
# llm.sh — health check for the local LLM stack, with fix-it instructions.
# Checks: Open WebUI container, Ollama, Tailscale, Tailscale Serve.

# --- 1. Open WebUI container ---
echo '$ docker ps --filter name=open-webui'
docker ps --filter name=open-webui
if ! docker info >/dev/null 2>&1; then
  cat <<'EOF'

>>> FIX: Docker isn't running. Open Docker Desktop (or run: open -a Docker),
    wait for it to finish starting, then re-run this script.
EOF
elif ! docker ps --format '{{.Names}}' | grep -qx open-webui; then
  if docker ps -a --format '{{.Names}}' | grep -qx open-webui; then
    cat <<'EOF'

>>> FIX: The open-webui container exists but is stopped. Start it:
      docker start open-webui
EOF
  else
    cat <<'EOF'

>>> FIX: The open-webui container doesn't exist. Create it:
      docker run -d \
        -p 127.0.0.1:3000:8080 \
        -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
        -v open-webui:/app/backend/data \
        --name open-webui \
        --restart unless-stopped \
        ghcr.io/open-webui/open-webui:main
EOF
  fi
fi

# --- 2. Ollama ---
echo
echo '$ ollama list'
if ! command -v ollama >/dev/null 2>&1; then
  cat <<'EOF'
>>> FIX: Ollama isn't installed. Install it, start it, and pull your model:
      brew install ollama        # or download from https://ollama.com/download
      open -a Ollama             # starts the background server (or: ollama serve)
      ollama pull gemma4:e4b
EOF
elif ! ollama list >/dev/null 2>&1; then
  ollama list
  cat <<'EOF'

>>> FIX: Ollama is installed but the server isn't responding. Start it:
      open -a Ollama             # or run in a terminal: ollama serve
EOF
else
  ollama list
fi

# --- 3. Tailscale ---
echo
echo '$ tailscale status'
if ! command -v tailscale >/dev/null 2>&1; then
  cat <<'EOF'
>>> FIX: Tailscale isn't installed / not on PATH. Install and sign in:
      brew install --cask tailscale   # or https://tailscale.com/download
    Open the app, sign in. (App Store version: enable the CLI from the app menu.)
EOF
elif ! tailscale status >/dev/null 2>&1; then
  tailscale status
  cat <<'EOF'

>>> FIX: Tailscale is installed but not connected. Bring it up and sign in:
      tailscale up
EOF
else
  tailscale status
fi

# --- 4. Tailscale Serve (exposes Open WebUI to your phone over HTTPS) ---
echo
echo '$ tailscale serve status'
if ! command -v tailscale >/dev/null 2>&1; then
  echo '(tailscale not installed — see the fix above)'
elif [ -z "$(tailscale serve status 2>/dev/null)" ]; then
  echo '(no serve config)'
  cat <<'EOF'

>>> FIX: Not serving yet. Expose Open WebUI (port 3000) to your tailnet over HTTPS:
      tailscale serve --bg 3000
    Then on your iPhone open:  https://<this-mac>.<your-tailnet>.ts.net
    (get the exact hostname from `tailscale status`). Undo with: tailscale serve reset
EOF
else
  tailscale serve status
fi
