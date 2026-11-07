#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib/codex-manager"
WRAPPER_DIR="$LIB_DIR/bin"
RUNTIME="$LIB_DIR/codex-runtime"
ROOT="$HOME/.codex-manager"
PROFILE="$HOME/.bashrc"
OLD_WRAPPER="$BIN_DIR/codex"

mkdir -p "$BIN_DIR" "$WRAPPER_DIR" "$ROOT"

is_manager_wrapper() {
  local p="$1"
  [[ -f "$p" ]] || return 1
  grep -q 'CODEX_ACCOUNT_MANAGER_BIN' "$p" 2>/dev/null &&
    grep -q 'codex-account' "$p" 2>/dev/null
}

OLD_REAL=""
if [[ -f "$ROOT/manager.json" ]]; then
  OLD_REAL="$(python3 - "$ROOT/manager.json" <<'PY' || true
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("codex_real") or "")
except Exception:
    pass
PY
)"
fi

# Preserve the v1.1 real runtime target before replacing codex_real with the
# stable v1.3 launcher.
LEGACY_HINT=""
if [[ -n "$OLD_REAL" && -x "$OLD_REAL" ]] && ! is_manager_wrapper "$OLD_REAL"; then
  LEGACY_HINT="$OLD_REAL"
fi

# Remove only our legacy wrapper. Never remove an official Codex binary/symlink.
if is_manager_wrapper "$OLD_WRAPPER"; then
  rm -f "$OLD_WRAPPER"
fi

install -m 700 "$PKG_DIR/codex-account" "$BIN_DIR/codex-account"
install -m 700 "$PKG_DIR/codex-wrapper" "$WRAPPER_DIR/codex"
install -m 700 "$PKG_DIR/codex-runtime" "$RUNTIME"

python3 - "$ROOT/manager.json" "$RUNTIME" "$BIN_DIR/codex-account" "$LEGACY_HINT" <<'PY'
import json, sys
from pathlib import Path

p = Path(sys.argv[1])
runtime = sys.argv[2]
manager = sys.argv[3]
legacy = sys.argv[4]
old = {}

if p.exists():
    try:
        old = json.loads(p.read_text())
    except Exception:
        pass

defaults = {
    "codex_real": runtime,
    "codex_runtime_hints": [],
    "runtime_check_ttl_seconds": 300,
    "prerelease_policy": "stable",
    "usage_probe_ttl_seconds": 120,
    "account_scoring": True,
    "pending_retention_days": 30,
    "manager_bin": manager,
    "default_cooldown_minutes": 30,
    "no_daemon": True,
    "auto_schedule": True,
    "schedule_grace_seconds": 20,
    "continuation_prompt": (
        "A sessao anterior foi interrompida apenas por limite de uso da conta. "
        "Continue a execucao do ultimo pedido do usuario a partir do ultimo estado valido. "
        "Antes de prosseguir, verifique o estado atual do repositorio e arquivos modificados; "
        "nao reverta alteracoes ja aplicadas, nao repita trabalho concluido e use o historico "
        "desta sessao como fonte de contexto."
    ),
}

defaults.update(old)
hints = list(defaults.get("codex_runtime_hints") or [])
if legacy and legacy != runtime and legacy not in hints:
    hints.insert(0, legacy)

defaults["codex_real"] = runtime
defaults["codex_runtime_hints"] = hints
defaults["manager_bin"] = manager
defaults["runtime_check_ttl_seconds"] = int(defaults.get("runtime_check_ttl_seconds", 300))

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(defaults, indent=2, ensure_ascii=False) + "\n")
PY

# Install an idempotent PATH block. The manager wrapper is intentionally NOT
# stored in ~/.local/bin/codex, leaving that path free for official updates.
python3 - "$PROFILE" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
start = "# >>> codex-manager >>>"
end = "# <<< codex-manager <<<"
block = (
    start + "\n"
    + 'export PATH="$HOME/.local/lib/codex-manager/bin:$PATH"\n'
    + end + "\n"
)

text = p.read_text() if p.exists() else ""
if start in text and end in text:
    before = text.split(start, 1)[0].rstrip()
    after = text.split(end, 1)[1].lstrip("\n")
    text = (before + "\n\n" if before else "") + block + ("\n" + after if after else "")
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += ("\n" if text else "") + block

p.write_text(text)
PY

rm -f "$ROOT/runtime-cache.json"
systemctl --user daemon-reload || true

echo "Codex Account Manager v1.3 installed/upgraded."
echo
echo "  manager: $BIN_DIR/codex-account"
echo "  wrapper: $WRAPPER_DIR/codex"
echo "  runtime: $RUNTIME"
echo
echo "Runtime discovery:"
if "$RUNTIME" --manager-runtime-info; then
  :
else
  echo
  echo "WARNING: no official Codex runtime was discovered yet." >&2
  echo "Install/update official Codex, then run:" >&2
  echo "  $RUNTIME --manager-runtime-refresh" >&2
fi
echo
echo "Reload the current shell:"
echo "  source \"$PROFILE\""
echo
echo "Then validate:"
echo "  which codex"
echo "  $RUNTIME --manager-runtime-info"
echo "  codex-account doctor"
echo "  codex-account list"
echo
echo "Expected wrapper path:"
echo "  $WRAPPER_DIR/codex"
