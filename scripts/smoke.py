"""Smoke test do ambiente no ar: os três serviços prontos e um pedido de ponta a ponta.

Só biblioteca padrão, para rodar em qualquer máquina com Python 3.12.
Uso: make smoke  (lê API_KEYS do ambiente)
"""

import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
import uuid

CLIENTES = os.environ.get("SMOKE_CLIENTES_URL", "http://localhost:8001")
CATALOGO = os.environ.get("SMOKE_CATALOGO_URL", "http://localhost:8002")
PEDIDOS = os.environ.get("SMOKE_PEDIDOS_URL", "http://localhost:8003")
CHAVE = os.environ["API_KEYS"].split(",")[0].strip()


def chamar(metodo: str, url: str, corpo: dict | None = None, chave: str | None = CHAVE):
    cabecalhos = {"Content-Type": "application/json", "X-Request-ID": RASTREIO}
    if chave:
        cabecalhos["X-API-Key"] = chave
    dados = json.dumps(corpo).encode() if corpo is not None else None
    pedido = urllib.request.Request(url, data=dados, headers=cabecalhos, method=metodo)
    try:
        with urllib.request.urlopen(pedido, timeout=5) as resposta:
            return resposta.status, json.loads(resposta.read() or b"null")
    except urllib.error.HTTPError as erro:
        return erro.code, json.loads(erro.read() or b"null")


def cpf_valido() -> str:
    base = [random.randint(0, 9) for _ in range(9)]
    for tamanho in (9, 10):
        soma = sum(d * p for d, p in zip(base, range(tamanho + 1, 1, -1), strict=True))
        base.append(soma * 10 % 11 % 10)
    return "".join(map(str, base))


def conferir(descricao: str, condicao: bool, detalhe: object = "") -> None:
    print(f"{'ok  ' if condicao else 'FALHOU'} {descricao}")
    if not condicao:
        print(f"      {detalhe}")
        sys.exit(1)


def esperar_pronto(nome: str, url: str, limite: float = 60) -> None:
    fim = time.monotonic() + limite
    while time.monotonic() < fim:
        try:
            if chamar("GET", f"{url}/ready", chave=None)[0] == 200:
                return conferir(f"{nome} pronto", True)
        except OSError:
            pass
        time.sleep(1)
    conferir(f"{nome} pronto", False, f"{url}/ready não respondeu 200 em {limite}s")


RASTREIO = f"smoke-{uuid.uuid4().hex[:8]}"

if __name__ == "__main__":
    for nome, url in (
        ("clientes", CLIENTES),
        ("catalogo", CATALOGO),
        ("pedidos", PEDIDOS),
    ):
        esperar_pronto(nome, url)

    status, _ = chamar("GET", f"{CLIENTES}/clientes", chave=None)
    conferir("rota de negócio sem chave devolve 401", status == 401, status)

    sufixo = uuid.uuid4().hex[:8]
    status, cliente = chamar(
        "POST",
        f"{CLIENTES}/clientes",
        {"nome": "Smoke", "cpf": cpf_valido(), "email": f"smoke-{sufixo}@exemplo.com"},
    )
    conferir("cria cliente", status == 201, cliente)

    status, produto = chamar(
        "POST",
        f"{CATALOGO}/produtos",
        {
            "sku": f"SMOKE-{sufixo}".upper(),
            "nome": "Produto smoke",
            "preco_centavos": 1990,
        },
    )
    conferir("cria produto", status == 201, produto)

    status, pedido = chamar(
        "POST",
        f"{PEDIDOS}/pedidos",
        {
            "cliente_id": cliente["id"],
            "itens": [{"produto_id": produto["id"], "quantidade": 2}],
        },
    )
    conferir("cria pedido validando cliente e produto", status == 201, pedido)
    conferir("total calculado", pedido["total_centavos"] == 3980, pedido)

    status, _ = chamar(
        "POST",
        f"{PEDIDOS}/pedidos",
        {
            "cliente_id": 999_999_999,
            "itens": [{"produto_id": produto["id"], "quantidade": 1}],
        },
    )
    conferir("cliente inexistente devolve 422", status == 422, status)

    print(f"smoke ok (request id {RASTREIO})")
