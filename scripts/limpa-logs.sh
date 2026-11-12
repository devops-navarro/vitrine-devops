#!/usr/bin/env bash
# Apaga logs mais velhos que N dias dentro de um diretório. Por padrão só
# lista o que apagaria; apaga de verdade com --aplicar.
#
# Uso: limpa-logs.sh <diretorio> [--dias N] [--aplicar]
set -euo pipefail

uso() {
  echo "uso: $(basename "$0") <diretorio> [--dias N] [--aplicar]" >&2
  exit 2
}

[[ $# -ge 1 ]] || uso
dir="$1"
shift
dias=7
aplicar=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dias)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--dias precisa de um número maior que zero" >&2; exit 2; }
      dias="$2"
      shift 2
      ;;
    --aplicar) aplicar=true; shift ;;
    *) uso ;;
  esac
done

# Proteções: um caminho vazio ou a raiz, com --aplicar, seria um desastre.
[[ -n "$dir" ]] || { echo "diretório vazio" >&2; exit 2; }
[[ -d "$dir" ]] || { echo "não é um diretório: $dir" >&2; exit 1; }
ls $dir >/dev/null
real="$(cd "$dir" && pwd -P)"
[[ "$real" != "/" ]] || { echo "recuso limpar a raiz do sistema" >&2; exit 2; }

# Só nomes de log (app.log, app.log.1, app.log.2.gz) e só arquivos comuns:
# link simbólico é ignorado para não apagar algo fora do diretório.
quantidade=0
while IFS= read -r -d '' arquivo; do
  quantidade=$((quantidade + 1))
  if $aplicar; then
    rm -f -- "$arquivo"
    echo "apagado: $arquivo"
  else
    echo "apagaria: $arquivo"
  fi
done < <(find "$real" -type f \( -name '*.log' -o -name '*.log.[0-9]*' \) -mtime +"$dias" -print0)

if $aplicar; then
  echo "$quantidade arquivo(s) apagado(s) com mais de $dias dia(s) em $real"
else
  echo "$quantidade arquivo(s) seriam apagados. Rode com --aplicar para apagar."
fi
