#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

export PROJECT_ROOT
export PM_FLOW_ROOT="$SCRIPT_DIR"
export PYTHONUTF8=1

if [[ -d "$PROJECT_ROOT/.venv" && -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
  export VIRTUAL_ENV="$PROJECT_ROOT/.venv"
  export PATH="$PROJECT_ROOT/.venv/bin:$PATH"
fi

if [[ -f "$SCRIPT_DIR/local_env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/local_env.sh"
fi

cd "$PROJECT_ROOT"
exec "$@"
