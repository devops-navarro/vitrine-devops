import pytest
from fastapi.testclient import TestClient

ANA = {"nome": "Ana Souza", "cpf": "52998224725", "email": "ana@exemplo.com"}
BRUNO = {"nome": "Bruno Lima", "cpf": "11144477735", "email": "bruno@exemplo.com"}


def criar(client: TestClient, dados: dict) -> dict:
    resposta = client.post("/clientes", json=dados)
    assert resposta.status_code == 201, resposta.text
    return resposta.json()


def test_criar_devolve_201_com_location(client):
    resposta = client.post("/clientes", json={**ANA, "telefone": "+55 11 91234-5678"})

    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["id"] > 0
    assert corpo["cpf"] == ANA["cpf"]
    assert corpo["telefone"] == "+55 11 91234-5678"
    assert corpo["criado_em"]
    assert resposta.headers["Location"] == f"/clientes/{corpo['id']}"


def test_criar_remove_espacos_das_pontas(client):
    corpo = criar(client, {**ANA, "nome": "  Ana Souza  "})

    assert corpo["nome"] == "Ana Souza"


@pytest.mark.parametrize(
    "alteracao",
    [
        {"cpf": "1234567890"},  # 10 dígitos
        {"cpf": "52998224726"},  # dígito verificador errado
        {"cpf": "11111111111"},
        {"cpf": 52998224725},  # número em vez de texto
        {"email": "ana.exemplo.com"},
        {"email": "ana@"},
        {"nome": ""},
        {"nome": "x" * 151},
        {"telefone": "9" * 21},
    ],
)
def test_criar_com_dado_invalido_devolve_422(client, alteracao):
    resposta = client.post("/clientes", json={**ANA, **alteracao})

    assert resposta.status_code == 422


def test_criar_normaliza_cpf_e_email(client):
    corpo = criar(client, {**ANA, "cpf": "529.982.247-25", "email": "Ana@Exemplo.COM"})

    assert corpo["cpf"] == "52998224725"
    assert corpo["email"] == "ana@exemplo.com"


def test_cpf_invalido_devolve_mensagem_clara(client):
    resposta = client.post("/clientes", json={**ANA, "cpf": "52998224726"})

    erro = resposta.json()["detail"][0]
    assert erro["loc"] == ["body", "cpf"]
    assert "dígito verificador" in erro["msg"]


def test_cpf_duplicado_devolve_409(client):
    criar(client, ANA)

    resposta = client.post("/clientes", json={**BRUNO, "cpf": ANA["cpf"]})

    assert resposta.status_code == 409
    assert resposta.json() == {"detail": "CPF já cadastrado"}


def test_email_duplicado_ignora_maiusculas_e_devolve_409(client):
    criar(client, ANA)

    resposta = client.post("/clientes", json={**BRUNO, "email": "ANA@exemplo.com"})

    assert resposta.status_code == 409
    assert resposta.json() == {"detail": "E-mail já cadastrado"}


def test_atualizar_para_cpf_de_outro_cliente_devolve_409(client):
    criar(client, ANA)
    bruno = criar(client, BRUNO)

    resposta = client.put(f"/clientes/{bruno['id']}", json={**BRUNO, "cpf": ANA["cpf"]})

    assert resposta.status_code == 409
    # o conflito não pode deixar a sessão quebrada para a próxima operação
    assert client.get(f"/clientes/{bruno['id']}").json()["cpf"] == BRUNO["cpf"]


def test_criar_sem_campo_obrigatorio_devolve_422(client):
    resposta = client.post("/clientes", json={"nome": "Ana"})

    assert resposta.status_code == 422
    faltando = {erro["loc"][-1] for erro in resposta.json()["detail"]}
    assert faltando == {"cpf", "email"}


def test_buscar_por_id(client):
    criado = criar(client, ANA)

    resposta = client.get(f"/clientes/{criado['id']}")

    assert resposta.status_code == 200
    assert resposta.json() == criado


def test_buscar_inexistente_devolve_404(client):
    resposta = client.get("/clientes/999999999")

    assert resposta.status_code == 404
    assert resposta.json() == {"detail": "Cliente não encontrado"}


def test_listar_em_ordem_com_paginacao(client):
    ana = criar(client, ANA)
    bruno = criar(client, BRUNO)

    todos = client.get("/clientes").json()
    assert [c["id"] for c in todos] == [ana["id"], bruno["id"]]

    segunda_pagina = client.get("/clientes", params={"limit": 1, "offset": 1}).json()
    assert [c["id"] for c in segunda_pagina] == [bruno["id"]]


@pytest.mark.parametrize("params", [{"limit": 0}, {"limit": 101}, {"offset": -1}])
def test_listar_com_paginacao_invalida_devolve_422(client, params):
    assert client.get("/clientes", params=params).status_code == 422


def test_atualizar_substitui_os_dados(client):
    criado = criar(client, {**ANA, "telefone": "11999990000"})

    resposta = client.put(f"/clientes/{criado['id']}", json={**ANA, "nome": "Ana S. Lima"})

    assert resposta.status_code == 200
    assert resposta.json()["nome"] == "Ana S. Lima"
    # PUT troca o recurso inteiro: o telefone omitido volta a ser nulo
    assert resposta.json()["telefone"] is None


def test_atualizar_inexistente_devolve_404(client):
    assert client.put("/clientes/999999999", json=ANA).status_code == 404


def test_remover_devolve_204_e_some_da_busca(client):
    criado = criar(client, ANA)

    resposta = client.delete(f"/clientes/{criado['id']}")

    assert resposta.status_code == 204
    assert resposta.content == b""
    assert client.get(f"/clientes/{criado['id']}").status_code == 404


def test_remover_inexistente_devolve_404(client):
    assert client.delete("/clientes/999999999").status_code == 404
