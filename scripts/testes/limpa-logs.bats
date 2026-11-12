#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../limpa-logs.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/logs/sub"
  # touch -t funciona igual no macOS e no Linux
  touch -t 202001010000 "$TMP/logs/velho.log" "$TMP/logs/velho.log.1" "$TMP/logs/sub/velho.log.2.gz"
  touch -t 202001010000 "$TMP/logs/velho.txt"
  touch "$TMP/logs/novo.log"
}

teardown() {
  rm -rf "$TMP"
}

@test "por padrão só lista, não apaga" {
  run "$SCRIPT" "$TMP/logs"

  [ "$status" -eq 0 ]
  [[ "$output" == *"apagaria:"*"velho.log"* ]]
  [[ "$output" == *"3 arquivo(s) seriam apagados"* ]]
  [ -e "$TMP/logs/velho.log" ]
}

@test "com --aplicar apaga só logs velhos" {
  run "$SCRIPT" "$TMP/logs" --aplicar

  [ "$status" -eq 0 ]
  [ ! -e "$TMP/logs/velho.log" ]
  [ ! -e "$TMP/logs/velho.log.1" ]
  [ ! -e "$TMP/logs/sub/velho.log.2.gz" ]
  # recente fica, e arquivo que não é log fica mesmo sendo velho
  [ -e "$TMP/logs/novo.log" ]
  [ -e "$TMP/logs/velho.txt" ]
  [[ "$output" == *"3 arquivo(s) apagado(s) com mais de 7 dia(s)"* ]]
}

@test "respeita --dias" {
  touch -t "$(date +%Y%m%d)0000" "$TMP/logs/hoje.log"

  run "$SCRIPT" "$TMP/logs" --dias 100000 --aplicar

  [ "$status" -eq 0 ]
  [ -e "$TMP/logs/velho.log" ]
  [[ "$output" == *"0 arquivo(s) apagado(s)"* ]]
}

@test "não segue link simbólico para fora do diretório" {
  mkdir -p "$TMP/fora"
  touch -t 202001010000 "$TMP/fora/importante.log"
  ln -s "$TMP/fora/importante.log" "$TMP/logs/atalho.log"

  run "$SCRIPT" "$TMP/logs" --aplicar

  [ "$status" -eq 0 ]
  [ -e "$TMP/fora/importante.log" ]
}

@test "recusa a raiz do sistema" {
  run "$SCRIPT" / --aplicar

  [ "$status" -eq 2 ]
  [[ "$output" == *"recuso limpar a raiz"* ]]
}

@test "recusa caminho vazio e diretório inexistente" {
  run "$SCRIPT" ""
  [ "$status" -eq 2 ]

  run "$SCRIPT" "$TMP/nao-existe"
  [ "$status" -eq 1 ]
}

@test "--dias inválido sai com 2" {
  run "$SCRIPT" "$TMP/logs" --dias zero
  [ "$status" -eq 2 ]
}
