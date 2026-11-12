"""Popula a Vitrine com dados de exemplo chamando as próprias APIs.

Declarativo, como o Terraform: o script descreve o estado desejado e converge
para ele. O que falta é criado, o que está diferente é atualizado e o que já
está certo não é tocado. Por isso pode rodar quantas vezes quiser.

Só biblioteca padrão. Uso: make seed   (lê API_KEYS do ambiente)
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from typing import Any

# --- estado desejado --------------------------------------------------------


def _cpf(base: str) -> str:
    """Completa 9 dígitos com os 2 verificadores, para os dados serem CPFs válidos."""
    digitos = [int(d) for d in base]
    for tamanho in (9, 10):
        soma = sum(
            d * p for d, p in zip(digitos, range(tamanho + 1, 1, -1), strict=True)
        )
        digitos.append(soma * 10 % 11 % 10)
    return "".join(map(str, digitos))


CLIENTES = [
    {
        "nome": "Ana Souza",
        "cpf": _cpf("100200300"),
        "email": "ana.souza@exemplo.com",
        "telefone": "+55 11 91234-0001",
        "enderecos": [
            {
                "apelido": "Casa",
                "cep": "01310-100",
                "logradouro": "Av. Paulista",
                "numero": "1000",
                "complemento": "Apto 12",
                "bairro": "Bela Vista",
                "cidade": "São Paulo",
                "uf": "SP",
                "principal": True,
            },
            {
                "apelido": "Trabalho",
                "cep": "04538-133",
                "logradouro": "Av. Brigadeiro Faria Lima",
                "numero": "3477",
                "bairro": "Itaim Bibi",
                "cidade": "São Paulo",
                "uf": "SP",
            },
        ],
    },
    {
        "nome": "Bruno Lima",
        "cpf": _cpf("200300400"),
        "email": "bruno.lima@exemplo.com",
        "enderecos": [
            {
                "apelido": "Casa",
                "cep": "20040-020",
                "logradouro": "Rua da Assembleia",
                "numero": "10",
                "bairro": "Centro",
                "cidade": "Rio de Janeiro",
                "uf": "RJ",
                "principal": True,
            }
        ],
    },
    {
        "nome": "Carla Mendes",
        "cpf": _cpf("300400500"),
        "email": "carla.mendes@exemplo.com",
        "telefone": "+55 31 99876-0003",
        "enderecos": [
            {
                "apelido": "Casa",
                "cep": "30130-010",
                "logradouro": "Av. Afonso Pena",
                "numero": "1500",
                "bairro": "Centro",
                "cidade": "Belo Horizonte",
                "uf": "MG",
                "principal": True,
            }
        ],
    },
    {
        "nome": "Diego Rocha",
        "cpf": _cpf("400500600"),
        "email": "diego.rocha@exemplo.com",
        "enderecos": [],
    },
]

PRODUTOS = [
    {"sku": "CAMISETA-BRANCA-M", "nome": "Camiseta branca M", "preco_centavos": 4990},
    {"sku": "CAMISETA-PRETA-G", "nome": "Camiseta preta G", "preco_centavos": 4990},
    {"sku": "CANECA-VITRINE", "nome": "Caneca Vitrine", "preco_centavos": 3500},
    {"sku": "MOUSE-SEM-FIO", "nome": "Mouse sem fio", "preco_centavos": 8990},
    {
        "sku": "TECLADO-MECANICO",
        "nome": "Teclado mecânico",
        "descricao": "Switch marrom, layout ABNT2",
        "preco_centavos": 34990,
    },
    {"sku": "MONITOR-24", "nome": "Monitor 24 polegadas", "preco_centavos": 89900},
    # fora de linha: aparece no catálogo como inativo e não entra em pedido novo
    {
        "sku": "PENDRIVE-8GB",
        "nome": "Pendrive 8 GB",
        "preco_centavos": 1990,
        "ativo": False,
    },
]

PEDIDOS = [
    {"cliente": "Ana Souza", "itens": {"CAMISETA-BRANCA-M": 2, "CANECA-VITRINE": 1}},
    {"cliente": "Ana Souza", "itens": {"TECLADO-MECANICO": 1}},
    {"cliente": "Bruno Lima", "itens": {"MONITOR-24": 2, "MOUSE-SEM-FIO": 1}},
    {"cliente": "Carla Mendes", "itens": {"CAMISETA-PRETA-G": 3}, "cancelado": True},
]

# --- cliente HTTP -----------------------------------------------------------


class ErroApi(Exception):
    pass


class Api:
    def __init__(self, nome: str, base_url: str, chave: str) -> None:
        self.nome = nome
        self.base_url = base_url.rstrip("/")
        self.chave = chave

    def chamar(
        self,
        metodo: str,
        caminho: str,
        corpo: dict | None = None,
        params: dict | None = None,
        esperado: tuple[int, ...] = (200, 201, 204),
        tentativas: int = 4,
    ) -> Any:
        url = self.base_url + caminho
        if params:
            url += "?" + urllib.parse.urlencode(params)
        dados = json.dumps(corpo).encode() if corpo is not None else None
        cabecalhos = {"Content-Type": "application/json", "X-API-Key": self.chave}

        for tentativa in range(1, tentativas + 1):
            requisicao = urllib.request.Request(
                url, data=dados, headers=cabecalhos, method=metodo
            )
            try:
                with urllib.request.urlopen(requisicao, timeout=10) as resposta:
                    status, conteudo = resposta.status, resposta.read()
            except urllib.error.HTTPError as erro:
                status, conteudo = erro.code, erro.read()
                # 503 é transitório: espera o que o serviço pediu e tenta de novo
                if status == 503 and tentativa < tentativas:
                    time.sleep(min(int(erro.headers.get("Retry-After", "2")), 10))
                    continue
            except urllib.error.URLError as erro:
                if tentativa < tentativas:
                    time.sleep(2)
                    continue
                raise ErroApi(
                    f"{self.nome} fora do ar ({url}): {erro.reason}"
                ) from erro

            resultado = json.loads(conteudo) if conteudo else None
            if status not in esperado:
                raise ErroApi(f"{metodo} {url} -> {status}: {resultado}")
            return resultado
        raise ErroApi(f"{metodo} {url}: sem resposta após {tentativas} tentativas")


# --- convergência -----------------------------------------------------------


class Semeador:
    def __init__(self, clientes: Api, catalogo: Api, pedidos: Api) -> None:
        self.clientes = clientes
        self.catalogo = catalogo
        self.pedidos = pedidos
        self.resultado: Counter[tuple[str, str]] = Counter()

    def _registrar(self, tipo: str, acao: str, descricao: str) -> None:
        self.resultado[(tipo, acao)] += 1
        if acao != "sem mudança":
            print(f"  {acao:<10} {tipo}: {descricao}")

    def _convergir(
        self,
        tipo: str,
        api: Api,
        colecao: str,
        atual: dict | None,
        desejado: dict,
        nome: str,
    ) -> dict:
        """Cria, atualiza ou mantém um recurso, comparando só os campos declarados."""
        if atual is None:
            criado = api.chamar("POST", colecao, desejado)
            self._registrar(tipo, "criado", nome)
            return criado
        # PUT troca o recurso inteiro, então compara com os opcionais preenchidos
        diferente = {k: v for k, v in desejado.items() if atual.get(k) != v}
        if not diferente:
            self._registrar(tipo, "sem mudança", nome)
            return atual
        atualizado = api.chamar("PUT", f"{colecao}/{atual['id']}", desejado)
        self._registrar(tipo, "atualizado", f"{nome} ({', '.join(sorted(diferente))})")
        return atualizado

    def produtos(self) -> dict[str, dict]:
        por_sku = {}
        for item in PRODUTOS:
            desejado = {"descricao": None, "ativo": True, **item}
            achados = self.catalogo.chamar(
                "GET", "/produtos", params={"sku": item["sku"]}
            )
            atual = achados[0] if achados else None
            por_sku[item["sku"]] = self._convergir(
                "produto", self.catalogo, "/produtos", atual, desejado, item["sku"]
            )
        return por_sku

    def clientes_e_enderecos(self) -> dict[str, dict]:
        por_nome = {}
        for item in CLIENTES:
            desejado = {
                "telefone": None,
                **{k: v for k, v in item.items() if k != "enderecos"},
            }
            achados = self.clientes.chamar(
                "GET", "/clientes", params={"cpf": item["cpf"]}
            )
            atual = achados[0] if achados else None
            cliente = self._convergir(
                "cliente", self.clientes, "/clientes", atual, desejado, item["nome"]
            )
            por_nome[item["nome"]] = cliente

            colecao = f"/clientes/{cliente['id']}/enderecos"
            existentes = {e["apelido"]: e for e in self.clientes.chamar("GET", colecao)}
            for endereco in item["enderecos"]:
                desejado_end = {"complemento": None, "principal": False, **endereco}
                # a API grava o CEP só com dígitos
                desejado_end["cep"] = endereco["cep"].replace("-", "")
                self._convergir(
                    "endereço",
                    self.clientes,
                    colecao,
                    existentes.get(endereco["apelido"]),
                    desejado_end,
                    f"{item['nome']} / {endereco['apelido']}",
                )
        return por_nome

    def pedidos_(self, clientes: dict[str, dict], produtos: dict[str, dict]) -> None:
        # Pedido não tem chave natural: é reconhecido pelo cliente e pelos itens.
        for item in PEDIDOS:
            cliente = clientes[item["cliente"]]
            itens = {produtos[sku]["id"]: qtd for sku, qtd in item["itens"].items()}
            nome = f"{item['cliente']}: " + ", ".join(
                f"{qtd}x {sku}" for sku, qtd in item["itens"].items()
            )
            existentes = self.pedidos.chamar(
                "GET", "/pedidos", params={"cliente_id": cliente["id"], "limit": 100}
            )
            pedido = next(
                (
                    p
                    for p in existentes
                    if {i["produto_id"]: i["quantidade"] for i in p["itens"]} == itens
                ),
                None,
            )
            if pedido is None:
                pedido = self.pedidos.chamar(
                    "POST",
                    "/pedidos",
                    {
                        "cliente_id": cliente["id"],
                        "itens": [
                            {"produto_id": p, "quantidade": q} for p, q in itens.items()
                        ],
                    },
                )
                self._registrar(
                    "pedido", "criado", f"{nome} (total {pedido['total_centavos']})"
                )
            else:
                self._registrar("pedido", "sem mudança", nome)

            if item.get("cancelado") and pedido["status"] != "cancelado":
                self.pedidos.chamar("POST", f"/pedidos/{pedido['id']}/cancelar")
                self._registrar("pedido", "cancelado", nome)

    def rodar(self) -> None:
        print("Catálogo")
        produtos = self.produtos()
        print("Clientes e endereços")
        clientes = self.clientes_e_enderecos()
        print("Pedidos")
        self.pedidos_(clientes, produtos)

    def mudancas(self) -> int:
        return sum(
            n for (_, acao), n in self.resultado.items() if acao != "sem mudança"
        )

    def resumo(self) -> str:
        tipos = dict.fromkeys(tipo for tipo, _ in self.resultado)
        partes = []
        for tipo in tipos:
            contagem = {a: n for (t, a), n in self.resultado.items() if t == tipo}
            partes.append(
                f"{tipo}: " + ", ".join(f"{n} {a}" for a, n in sorted(contagem.items()))
            )
        return "\n".join(partes)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--sem-mudancas",
        action="store_true",
        help="falha se precisar criar ou alterar algo (prova de idempotência no CI)",
    )
    args = parser.parse_args()

    chave = os.environ["API_KEYS"].split(",")[0].strip()
    semeador = Semeador(
        Api(
            "clientes",
            os.environ.get("SEED_CLIENTES_URL", "http://localhost:8001"),
            chave,
        ),
        Api(
            "catalogo",
            os.environ.get("SEED_CATALOGO_URL", "http://localhost:8002"),
            chave,
        ),
        Api(
            "pedidos",
            os.environ.get("SEED_PEDIDOS_URL", "http://localhost:8003"),
            chave,
        ),
    )
    try:
        semeador.rodar()
    except ErroApi as erro:
        print(f"erro: {erro}", file=sys.stderr)
        return 1

    print("\nResumo\n" + semeador.resumo())
    if args.sem_mudancas and semeador.mudancas():
        print(
            f"\nesperava nenhuma mudança e houve {semeador.mudancas()}", file=sys.stderr
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
