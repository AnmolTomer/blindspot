#!/usr/bin/env bash
# Runs gird-check.sh against a fake home folder and checks what it finds, what
# it must never print or send, and how it handles hostile file names. It runs
# the script under every bash it can find: /bin/bash (3.2 on macOS) and the
# bash on PATH.
# shellcheck disable=SC2088  # the patterns match the literal ~ the script prints for home paths
set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT=$PWD/gird-check.sh
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t blindspot)
MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
has()    { if grep -aqE -- "$2" "$3"; then ok "$1"; else bad "$1"; printf '        wanted: %s\n' "$2"; fi; }
hasnot() { if grep -aqE -- "$2" "$3"; then bad "$1"; printf '        found: %s\n' "$2"; else ok "$1"; fi; }

bash tests/make-fixture.sh "$WORK/home" "$WORK/keys.txt"

BASHES=/bin/bash
OTHER=$(command -v bash)
if [ -n "$OTHER" ] && [ "$("$OTHER" -c 'echo "$BASH_VERSION"')" != "$(/bin/bash -c 'echo "$BASH_VERSION"')" ]; then BASHES="$BASHES $OTHER"; fi

for B in $BASHES; do
  V=$("$B" -c 'echo "${BASH_VERSINFO[0]}"')
  echo "bash $V ($B)"
  if "$B" -n "$SCRIPT"; then ok "parses"; else bad "parses"; fi
  OUT=$WORK/out-$V.txt
  HOME="$WORK/home" "$B" "$SCRIPT" --offline > "$OUT" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "exits 0"; else bad "exits 0, got $RC"; fi
  has    "finds keys in the shell profile"       '~/\.zshrc +Anthropic, OpenAI' "$OUT"
  has    "finds keys in shell history"           '~/\.zsh_history +GitHub' "$OUT"
  has    "finds keys in a project .env file"     '~/code/app/\.env +AWS, Groq' "$OUT"
  hasnot "ignores placeholders in .env.example"  'env\.example' "$OUT"
  has    "counts Claude Code MCP servers"        'Claude Code +~/\.claude\.json +3 servers' "$OUT"
  has    "counts Codex MCP servers"              '~/\.codex/config\.toml +2 servers' "$OUT"
  has    "spots a token in an MCP config"        'token in the file' "$OUT"
  has    "flags a key in a Claude allow list"    'code/app/\.claude/settings\.local\.json' "$OUT"
  has    "warns an npm publish would ship it"    'npm publish from this folder would include it' "$OUT"
  hasnot "ignores placeholder allow lists"       'code/lib/\.claude' "$OUT"
  has    "sees an agent that is installed but idle" 'Codex +installed, not used in 30 days' "$OUT"
  has    "finds LiteLLM malware markers"         'signs of the malware found' "$OUT"
  has    "finds the bad package in the uv cache" 'uv cache holds the 1\.107\.0 package' "$OUT"
  has    "counts SSH keys with no passphrase"    '2 SSH private keys, 1 with no passphrase' "$OUT"
  has    "gives a grade"                         'GRADE [ABCDF]' "$OUT"
  if grep -aqF -f "$WORK/keys.txt" "$OUT"; then bad "never prints a planted key"; else ok "never prints a planted key"; fi
  if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "plain output has no escape codes"; else ok "plain output has no escape codes"; fi
done

echo "hostile file names"
EVIL="$WORK/home/code/evil$(printf '\033[2J\033]0;pwned\007\302\233')31m"
mkdir -p "$EVIL"
printf 'AWS_ACCESS_KEY_ID=AK%s\n' "IA$(LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c 16)" > "$EVIL/.env"
HOME="$WORK/home" bash "$SCRIPT" --offline > "$WORK/evil.txt" 2>&1
if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')\|$(printf '\302\233')" "$WORK/evil.txt"; then bad "control characters in file names never reach the terminal"; else ok "control characters in file names never reach the terminal"; fi
has "the hostile folder is still reported" 'code/evil\?' "$WORK/evil.txt"
rm -rf "$EVIL"

echo "saving the report"
mkdir -p "$WORK/cwd"
(cd "$WORK/cwd" && HOME="$WORK/home" bash "$SCRIPT" --offline --save > "$WORK/save.txt" 2>&1)
SAVED=$(ls "$WORK"/cwd/gird-ai-key-check-*.txt 2>/dev/null | head -n 1)
if [ -n "$SAVED" ]; then ok "--save writes a report"; else bad "--save writes a report"; fi
if [ -n "$SAVED" ] && [ -n "$(find "$SAVED" -perm 600)" ]; then ok "the report is readable only by you"; else bad "the report is readable only by you"; fi
if [ -n "$SAVED" ] && ! grep -aqF -f "$WORK/keys.txt" "$SAVED"; then ok "the report holds no planted key"; else bad "the report holds no planted key"; fi

echo "shared counts"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$WORK/received.log" "$WORK/port" <<'PY' &
import http.server, sys
log, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('content-length') or 0)
        with open(log, 'ab') as f: f.write(self.rfile.read(n) + b'\n')
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
with open(portfile, 'w') as f: f.write(str(srv.server_address[1]))
srv.serve_forever()
PY
  MOCK_PID=$!
  i=0; while [ ! -s "$WORK/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  API="http://127.0.0.1:$(cat "$WORK/port")/api/check"
  : > "$WORK/received.log"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" --offline > /dev/null 2>&1
  HOME="$WORK/home" GIRD_CHECK_API="$API" DO_NOT_TRACK=1 bash "$SCRIPT" > /dev/null 2>&1
  if [ ! -s "$WORK/received.log" ]; then ok "--offline and DO_NOT_TRACK=1 send nothing"; else bad "--offline and DO_NOT_TRACK=1 send nothing"; fi
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > /dev/null 2>&1
  if [ "$(grep -c . "$WORK/received.log")" -eq 1 ]; then ok "a normal run sends one report"; else bad "a normal run sends one report"; fi
  if python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$WORK/received.log" 2>/dev/null; then ok "the report is valid JSON"; else bad "the report is valid JSON"; fi
  has "the device ID is a 64-character hash or empty" '"device_id":"([0-9a-f]{64})?"' "$WORK/received.log"
  hasnot "the report holds no path"     '/(Users|home|private|tmp)/|~/' "$WORK/received.log"
  if grep -aqF -f "$WORK/keys.txt" "$WORK/received.log"; then bad "the report holds no planted key"; else ok "the report holds no planted key"; fi
  if grep -aqF "\"$(id -un)\"" "$WORK/received.log"; then bad "the report holds no username"; else ok "the report holds no username"; fi
else
  echo "  skip  python3 not installed"
fi

echo "help"
if bash "$SCRIPT" --help | grep -q -- '--offline'; then ok "--help lists the options"; else bad "--help lists the options"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
