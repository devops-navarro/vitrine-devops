import pytest
from fastapi.testclient import TestClient

CAMISETA = {
    "sku": "CAM-BRANCA-M",
    "nome": "Camiseta branca M",
    "descricao": "Algodão, gola careca",
    "preco_centavos": 4990,
}
CANECA = {"sku": "CANECA-01", "nome": "Caneca", "preco_centavos": 2500}


def criar(client: TestClient, dados: dict) -> dict:
    resposta = client.post("/produtos", json=dados)
    assert resposta.status_code == 201, resposta.text
    return resposta.json()


def test_criar_devolve_201_ativo_por_padrao(client):
    resposta = client.post("/produtos", json=CAMISETA)

    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["preco_centavos"] == 4990
    assert corpo["ativo"] is True
    assert resposta.headers["Location"] == f"/produtos/{corpo['id']}"


def test_sku_e_gravado_em_maiusculas(client):
    assert criar(client, {**CAMISETA, "sku": " cam-branca-m "})["sku"] == "CAM-BRANCA-M"


@pytest.mark.parametrize(
    "alteracao",
    [
        {"preco_centavos": -1},
        {"preco_centavos": 49.9},  # float não vira centavo em silêncio
        {"preco_centavos": "4990"},  # nem texto
        {"preco_centavos": 100_000_001},
        {"sku": "-CAM"},
        {"sku": "CAM BRANCA"},
        {"sku": "CAMISETA_M"},
        {"sku": "X" * 41},
        {"nome": ""},
        {"descricao": "x" * 5001},
    ],
)
def test_dado_invalido_devolve_422(client, alteracao):
    assert client.post("/produtos", json={**CAMISETA, **alteracao}).status_code == 422


def test_preco_zero_e_aceito(client):
    assert criar(client, {**CANECA, "preco_centavos": 0})["preco_centavos"] == 0


def test_sku_duplicado_devolve_409(client):
    criar(client, CAMISETA)

    resposta = client.post("/produtos", json={**CANECA, "sku": "cam-branca-m"})

    assert resposta.status_code == 409
    assert resposta.json() == {"detail": "SKU já cadastrado"}


def test_atualizar_para_sku_de_outro_devolve_409(client):
    criar(client, CAMISETA)
    caneca = criar(client, CANECA)

    resposta = client.put(f"/produtos/{caneca['id']}", json={**CANECA, "sku": CAMISETA["sku"]})

    assert resposta.status_code == 409
    assert client.get(f"/produtos/{caneca['id']}").json()["sku"] == CANECA["sku"]


def test_buscar_e_atualizar(client):
    criado = criar(client, CAMISETA)

    resposta = client.put(f"/produtos/{criado['id']}", json={**CAMISETA, "preco_centavos": 3990})

    assert resposta.status_code == 200
    assert client.get(f"/produtos/{criado['id']}").json()["preco_centavos"] == 3990


@pytest.mark.parametrize("metodo", ["get", "put", "delete"])
def test_inexistente_devolve_404(client, metodo):
    resposta = client.request(metodo, "/produtos/999999999", json=CAMISETA)

    assert resposta.status_code == 404
    assert resposta.json() == {"detail": "Produto não encontrado"}


def test_delete_desativa_e_mantem_o_produto_legivel(client):
    criado = criar(client, CAMISETA)

    assert client.delete(f"/produtos/{criado['id']}").status_code == 204

    produto = client.get(f"/produtos/{criado['id']}")
    assert produto.status_code == 200
    assert produto.json()["ativo"] is False


def test_listar_filtra_por_situacao_e_pagina(client):
    camiseta = criar(client, CAMISETA)
    caneca = criar(client, CANECA)
    client.delete(f"/produtos/{caneca['id']}")

    def ids(**params):
        return [p["id"] for p in client.get("/produtos", params=params).json()]

    assert ids() == [camiseta["id"], caneca["id"]]
    assert ids(ativo=True) == [camiseta["id"]]
    assert ids(ativo=False) == [caneca["id"]]
    assert ids(limit=1, offset=1) == [caneca["id"]]


@pytest.mark.parametrize("params", [{"limit": 0}, {"limit": 101}, {"offset": -1}])
def test_paginacao_invalida_devolve_422(client, params):
    assert client.get("/produtos", params=params).status_code == 422


def test_busca_por_sku_sem_diferenciar_maiusculas(client):
    camiseta = criar(client, CAMISETA)
    criar(client, CANECA)

    resposta = client.get("/produtos", params={"sku": " cam-branca-m "})

    assert [p["id"] for p in resposta.json()] == [camiseta["id"]]
    assert client.get("/produtos", params={"sku": "NAO-EXISTE"}).json() == []
