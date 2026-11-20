#!/bin/bash
# FreeLLMAPI auto-setup for this codespace. Runs on every codespace start.
cd "$(dirname "$0")/.." || exit 1
if [ ! -f .env ]; then
  {
    echo "PORT=3001"
    echo "HOST=0.0.0.0"
    echo "NODE_ENV=production"
    echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
  } > .env
fi
# Always install (idempotent): a previous run may have been cut short.
npm install >> setup.log 2>&1 || npm install >> setup.log 2>&1 || true
# Build ONLY the server first (fast) so the API comes up quickly.
if [ ! -f server/dist/index.js ]; then
  npm run build -w server >> setup.log 2>&1 || npm run build -w server >> setup.log 2>&1 || true
fi
if [ -f server/dist/index.js ] && ! pgrep -f "server/dist/index.js" > /dev/null; then
  nohup env NODE_ENV=production node server/dist/index.js > server.log 2>&1 &
fi
# If the server still isn't up, rebuild + start in the background and retry.
(
  for i in 1 2 3; do
    sleep 20
    if curl -sf --max-time 2 http://127.0.0.1:3001/api/ping > /dev/null 2>&1; then exit 0; fi
    if [ ! -f server/dist/index.js ]; then npm run build -w server >> setup.log 2>&1 || true; fi
    if [ -f server/dist/index.js ] && ! pgrep -f "server/dist/index.js" > /dev/null; then
      nohup env NODE_ENV=production node server/dist/index.js > server.log 2>&1 &
    fi
  done
) >> setup.log 2>&1 &
# Build the dashboard UI in the background (slow); the server picks it up when ready.
if [ ! -d client/dist ]; then
  nohup npm run build -w client >> client-build.log 2>&1 &
fi
# Wait for the server, then make port 3001 public so phones/Claude Code
# can reach it without a GitHub login.
for i in $(seq 1 30); do
  if curl -sf --max-time 2 http://127.0.0.1:3001/api/ping > /dev/null 2>&1; then
    break
  fi
  sleep 2
done
if command -v gh >/dev/null 2>&1 && [ -n "$CODESPACE_NAME" ]; then
  gh codespace ports visibility 3001:public -c "$CODESPACE_NAME" >> server.log 2>&1 || true
fi
echo "FreeLLMAPI setup done"
