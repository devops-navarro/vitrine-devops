#!/usr/bin/env bash
# Testa uma URL e sai com 0 se ela responder 2xx (e, opcionalmente, com um
# texto esperado no corpo). Feito para cron, CI e scripts de deploy.
#
# Uso: healthcheck.sh <url> [--texto TEXTO] [--tentativas N] [--intervalo S] [--timeout S]
#
# Saída: 0 saudável, 1 não saudável, 2 uso incorreto.
set -euo pipefail

uso() {
  echo "uso: $(basename "$0") <url> [--texto TEXTO] [--tentativas N] [--intervalo S] [--timeout S]" >&2
  exit 2
}

numero() {
  [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "$1 precisa de um número maior que zero" >&2; exit 2; }
}

[[ $# -ge 1 ]] || uso
url="$1"
shift
texto=""
tentativas=3
intervalo=2
timeout=5

while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || uso
  case "$1" in
    --texto) texto="$2" ;;
    --tentativas) numero "$1" "$2"; tentativas="$2" ;;
    --intervalo) numero "$1" "$2"; intervalo="$2" ;;
    --timeout) numero "$1" "$2"; timeout="$2" ;;
    *) uso ;;
  esac
  shift 2
done

corpo="$(mktemp)"
trap 'rm -f "$corpo"' EXIT

for (( tentativa = 1; tentativa <= tentativas; tentativa++ )); do
  # sem -f: o status vem pelo -w, e erro de conexão vira "000"
  status="$(curl -s -o "$corpo" -w '%{http_code}' --max-time "$timeout" "$url" || true)"
  if [[ "$status" =~ ^2 ]]; then
    if [[ -z "$texto" ]] || grep -qF -- "$texto" "$corpo"; then
      echo "ok: $url respondeu $status (tentativa $tentativa)"
      exit 0
    fi
    motivo="status $status, mas sem o texto esperado"
  elif [[ "$status" == "000" ]]; then
    motivo="sem resposta (conexão recusada ou timeout de ${timeout}s)"
  else
    motivo="status $status"
  fi
  echo "tentativa $tentativa/$tentativas: $motivo" >&2
  (( tentativa < tentativas )) && sleep "$intervalo"
done

echo "falhou: $url" >&2
exit 1
