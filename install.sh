#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
ROOT="$HOME/.codex-manager"

mkdir -p "$BIN_DIR" "$ROOT"

# If v1 is already installed, prefer codex_real from its config so we do not
# accidentally register our own wrapper as the real Codex.
REAL_CODEX=""
if [[ -f "$ROOT/manager.json" ]]; then
  REAL_CODEX="$(python3 - "$ROOT/manager.json" <<'PY' || true
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("codex_real") or "")
except Exception:
    pass
PY
)"
fi

if [[ -z "$REAL_CODEX" || ! -x "$REAL_CODEX" ]]; then
  REAL_CODEX="$(command -v codex || true)"
fi

if [[ -z "$REAL_CODEX" ]]; then
  echo "ERRO: codex não está no PATH e não há codex_real válido no manager.json." >&2
  exit 1
fi

REAL_CODEX="$(readlink -f "$REAL_CODEX")"

install -m 700 "$PKG_DIR/codex-account" "$BIN_DIR/codex-account"
install -m 700 "$PKG_DIR/codex-wrapper" "$BIN_DIR/codex"

python3 - "$ROOT/manager.json" "$REAL_CODEX" "$BIN_DIR/codex-account" <<'PY'
import json, sys
from pathlib import Path

p=Path(sys.argv[1]); real=sys.argv[2]; manager=sys.argv[3]
old={}
if p.exists():
    try:
        old=json.loads(p.read_text())
    except Exception:
        pass

defaults={
  "codex_real": real,
  "manager_bin": manager,
  "default_cooldown_minutes": 30,
  "no_daemon": True,
  "auto_schedule": True,
  "schedule_grace_seconds": 20,
  "continuation_prompt": (
    "A sessão anterior foi interrompida apenas por limite de uso da conta. "
    "Continue a execução do último pedido do usuário a partir do último estado válido. "
    "Antes de prosseguir, verifique o estado atual do repositório e arquivos modificados; "
    "não reverta alterações já aplicadas, não repita trabalho concluído e use o histórico "
    "desta sessão como fonte de contexto."
  )
}
defaults.update(old)
defaults["codex_real"]=real
defaults["manager_bin"]=manager
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(defaults,indent=2,ensure_ascii=False)+"\n")
PY

systemctl --user daemon-reload || true

cat <<EOF
Codex Account Manager v1.1 instalado/atualizado.

  manager:    $BIN_DIR/codex-account
  wrapper:    $BIN_DIR/codex
  codex real: $REAL_CODEX

Garanta que ~/.local/bin vem antes no PATH:
  export PATH="\$HOME/.local/bin:\$PATH"

Se ainda não migrou:
  codex-account bootstrap principal
  codex-account add secundaria

Validação:
  codex-account doctor
  codex-account list
  codex-account pending
EOF
