#!/usr/bin/env bats

# Um servidor HTTP de verdade, numa porta livre, para os testes inteiros.
setup_file() {
  export SITE="$(mktemp -d)"
  echo "Hello World" > "$SITE/index.html"
  export PORTA="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 -m http.server "$PORTA" --bind 127.0.0.1 --directory "$SITE" >/dev/null 2>&1 &
  export SERVIDOR_PID=$!
  for _ in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:$PORTA/" && break
    sleep 0.1
  done
}

teardown_file() {
  kill "$SERVIDOR_PID" 2>/dev/null || true
  rm -rf "$SITE"
}

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../healthcheck.sh"
}

@test "URL saudável sai com 0" {
  run "$SCRIPT" "http://127.0.0.1:$PORTA/" --tentativas 1

  [ "$status" -eq 0 ]
  [[ "$output" == "ok: http://127.0.0.1:$PORTA/ respondeu 200 (tentativa 1)" ]]
}

@test "confere o texto esperado no corpo" {
  run "$SCRIPT" "http://127.0.0.1:$PORTA/" --texto "Hello World" --tentativas 1
  [ "$status" -eq 0 ]

  run "$SCRIPT" "http://127.0.0.1:$PORTA/" --texto "Outro texto" --tentativas 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"status 200, mas sem o texto esperado"* ]]
}

@test "404 não é saudável" {
  run "$SCRIPT" "http://127.0.0.1:$PORTA/nao-existe" --tentativas 1

  [ "$status" -eq 1 ]
  [[ "$output" == *"status 404"* ]]
}

@test "porta sem ninguém ouvindo: falha depois de todas as tentativas" {
  fechada="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"

  run "$SCRIPT" "http://127.0.0.1:$fechada/" --tentativas 2 --intervalo 1

  [ "$status" -eq 1 ]
  [[ "$output" == *"tentativa 1/2: sem resposta"* ]]
  [[ "$output" == *"tentativa 2/2: sem resposta"* ]]
  [[ "$output" == *"falhou: http://127.0.0.1:$fechada/"* ]]
}

@test "argumentos errados saem com 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]

  run "$SCRIPT" "http://127.0.0.1:$PORTA/" --tentativas abc
  [ "$status" -eq 2 ]

  run "$SCRIPT" "http://127.0.0.1:$PORTA/" --texto
  [ "$status" -eq 2 ]
}
