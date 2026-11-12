#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../backup.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/dados/sub"
  echo "conteúdo" > "$TMP/dados/a.txt"
  echo "outro" > "$TMP/dados/sub/b.txt"
}

teardown() {
  rm -rf "$TMP"
}

@test "cria um tar.gz com o conteúdo do diretório" {
  run "$SCRIPT" "$TMP/dados" "$TMP/bk"

  [ "$status" -eq 0 ]
  [[ "$output" == "backup criado: $TMP/bk/dados-"*"-00.tar.gz" ]]
  arquivo="$(ls "$TMP"/bk/dados-*.tar.gz)"
  tar -tzf "$arquivo" | grep -qx "dados/a.txt"
  tar -tzf "$arquivo" | grep -qx "dados/sub/b.txt"
}

@test "mantém só os N mais recentes, mesmo com vários no mesmo segundo" {
  criados=()
  for _ in 1 2 3 4 5; do
    saida="$("$SCRIPT" "$TMP/dados" "$TMP/bk" --manter 2 | head -1)"
    criados+=("${saida#backup criado: }")
  done

  # os que ficam são os dois últimos criados (as 5 execuções podem cruzar a
  # virada de um segundo, então o teste compara caminhos, não sufixos fixos)
  run ls "$TMP/bk"
  [ "${#lines[@]}" -eq 2 ]
  [ -e "${criados[3]}" ]
  [ -e "${criados[4]}" ]
}

@test "remove primeiro os backups de datas mais antigas" {
  mkdir -p "$TMP/bk"
  touch "$TMP/bk/dados-20200101-000000-00.tar.gz" "$TMP/bk/dados-20210101-000000-00.tar.gz"

  run "$SCRIPT" "$TMP/dados" "$TMP/bk" --manter 2

  [ "$status" -eq 0 ]
  [[ "$output" == *"removido (mais de 2 backups): $TMP/bk/dados-20200101-000000-00.tar.gz"* ]]
  [ ! -e "$TMP/bk/dados-20200101-000000-00.tar.gz" ]
  [ -e "$TMP/bk/dados-20210101-000000-00.tar.gz" ]
}

@test "não mexe em backups de outro diretório no mesmo destino" {
  mkdir -p "$TMP/bk"
  touch "$TMP/bk/outro-20200101-000000-00.tar.gz"

  "$SCRIPT" "$TMP/dados" "$TMP/bk" --manter 1 >/dev/null

  [ -e "$TMP/bk/outro-20200101-000000-00.tar.gz" ]
}

@test "não deixa arquivo pela metade se o tar falhar" {
  mkdir -p "$TMP/bk"
  # sem permissão de leitura, o tar falha no meio
  chmod 000 "$TMP/dados/sub"

  run "$SCRIPT" "$TMP/dados" "$TMP/bk"
  chmod 755 "$TMP/dados/sub"

  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$TMP/bk")" ]
}

@test "ignora o lost+found do ext4" {
  mkdir -p "$TMP/dados/lost+found"
  touch "$TMP/dados/lost+found/x"
  chmod 000 "$TMP/dados/lost+found"

  run "$SCRIPT" "$TMP/dados" "$TMP/bk"
  chmod 755 "$TMP/dados/lost+found"

  [ "$status" -eq 0 ]
  ! tar -tzf "$(ls "$TMP"/bk/dados-*.tar.gz)" | grep -q "lost+found"
}

@test "origem inexistente sai com 1" {
  run "$SCRIPT" "$TMP/nao-existe" "$TMP/bk"

  [ "$status" -eq 1 ]
  [[ "$output" == *"origem não existe"* ]]
}

@test "argumentos errados saem com 2 e mostram o uso" {
  run "$SCRIPT" "$TMP/dados"
  [ "$status" -eq 2 ]
  [[ "$output" == *"uso:"* ]]

  run "$SCRIPT" "$TMP/dados" "$TMP/bk" --manter 0
  [ "$status" -eq 2 ]
}
