#!/usr/bin/env bash
# Compacta um diretório em <destino>/<nome>-<AAAAMMDD-HHMMSS>-<NN>.tar.gz e mantém
# só os N backups mais recentes desse diretório.
#
# Uso: backup.sh <origem> <destino> [--manter N]
set -euo pipefail

uso() {
  echo "uso: $(basename "$0") <origem> <destino> [--manter N]" >&2
  exit 2
}

[[ $# -ge 2 ]] || uso
origem="${1%/}"
destino="${2%/}"
shift 2
manter=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manter)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--manter precisa de um número maior que zero" >&2; exit 2; }
      manter="$2"
      shift 2
      ;;
    *) uso ;;
  esac
done

[[ -d "$origem" ]] || { echo "origem não existe ou não é diretório: $origem" >&2; exit 1; }
mkdir -p "$destino"

nome="$(basename "$origem")"
carimbo="$(date +%Y%m%d-%H%M%S)"
# Sufixo sempre presente e com 2 dígitos: dois backups no mesmo segundo não se
# sobrescrevem, e a ordem alfabética continua sendo a ordem de idade. Sem ele,
# "x-1.tar.gz" ficaria antes de "x.tar.gz" ("-" vem antes de "." na tabela ASCII).
# O contador parte depois do maior sufixo existente: reaproveitar um número
# apagado faria o backup novo parecer o mais antigo e ser removido na hora.
n=0
for existente in "$destino/$nome-$carimbo"-[0-9][0-9].tar.gz; do
  [[ -e "$existente" ]] || continue
  sufixo="${existente%.tar.gz}"
  sufixo="${sufixo##*-}"
  (( 10#$sufixo >= n )) && n=$((10#$sufixo + 1))
done
arquivo="$destino/$nome-$carimbo-$(printf '%02d' "$n").tar.gz"
temporario="$(mktemp "$destino/.$nome.XXXXXX")"
# se algo falhar no meio, o arquivo pela metade não fica para trás
trap 'rm -f "$temporario"' EXIT

# lost+found é do ext4 (recuperação do fsck), só o root lê e não é dado de ninguém
tar -czf "$temporario" --exclude="$nome/lost+found" -C "$(dirname "$origem")" "$nome"
# o mv no mesmo disco é atômico: ou existe o backup inteiro, ou não existe
mv "$temporario" "$arquivo"
trap - EXIT
echo "backup criado: $arquivo"

# O nome tem a data em ordem crescente, então ordem alfabética é ordem de idade.
# Sem mapfile nem head -n -N: precisa rodar no Bash 3.2 do macOS e no GNU.
backups=()
while IFS= read -r b; do
  backups+=("$b")
done < <(find "$destino" -maxdepth 1 -type f -name "$nome-*.tar.gz" | sort)

excesso=$(( ${#backups[@]} - manter ))
i=0
while (( i < excesso )); do
  rm -f -- "${backups[i]}"
  echo "removido (mais de $manter backups): ${backups[i]}"
  i=$((i + 1))
done
