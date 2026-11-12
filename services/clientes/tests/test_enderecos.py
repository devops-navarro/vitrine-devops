import pytest
from fastapi.testclient import TestClient

from tests.test_clientes import ANA, BRUNO, criar

CASA = {
    "apelido": "Casa",
    "cep": "01310-100",
    "logradouro": "Av. Paulista",
    "numero": "1000",
    "complemento": "Apto 12",
    "bairro": "Bela Vista",
    "cidade": "São Paulo",
    "uf": "SP",
}
TRABALHO = {**CASA, "apelido": "Trabalho", "numero": "2000", "complemento": None}


def criar_endereco(client: TestClient, cliente_id: int, dados: dict) -> dict:
    resposta = client.post(f"/clientes/{cliente_id}/enderecos", json=dados)
    assert resposta.status_code == 201, resposta.text
    return resposta.json()


@pytest.fixture
def ana(client) -> dict:
    return criar(client, ANA)


def test_criar_devolve_201_normaliza_e_aponta_location(client, ana):
    resposta = client.post(f"/clientes/{ana['id']}/enderecos", json={**CASA, "uf": " sp"})

    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["cliente_id"] == ana["id"]
    assert corpo["cep"] == "01310100"
    assert corpo["uf"] == "SP"
    assert resposta.headers["Location"] == f"/clientes/{ana['id']}/enderecos/{corpo['id']}"


def test_primeiro_endereco_vira_principal(client, ana):
    primeiro = criar_endereco(client, ana["id"], CASA)
    segundo = criar_endereco(client, ana["id"], TRABALHO)

    assert primeiro["principal"] is True
    assert segundo["principal"] is False


def test_novo_principal_desmarca_o_anterior(client, ana):
    casa = criar_endereco(client, ana["id"], CASA)
    trabalho = criar_endereco(client, ana["id"], {**TRABALHO, "principal": True})

    lista = client.get(f"/clientes/{ana['id']}/enderecos").json()

    assert [(e["id"], e["principal"]) for e in lista] == [
        (trabalho["id"], True),
        (casa["id"], False),
    ]


def test_atualizar_para_principal_desmarca_o_anterior(client, ana):
    casa = criar_endereco(client, ana["id"], CASA)
    trabalho = criar_endereco(client, ana["id"], TRABALHO)

    resposta = client.put(
        f"/clientes/{ana['id']}/enderecos/{trabalho['id']}", json={**TRABALHO, "principal": True}
    )

    assert resposta.status_code == 200
    assert resposta.json()["principal"] is True
    casa_depois = client.get(f"/clientes/{ana['id']}/enderecos/{casa['id']}").json()
    assert casa_depois["principal"] is False


def test_principal_de_um_cliente_nao_afeta_outro(client, ana):
    bruno = criar(client, BRUNO)
    casa_ana = criar_endereco(client, ana["id"], CASA)

    criar_endereco(client, bruno["id"], {**CASA, "principal": True})

    assert client.get(f"/clientes/{ana['id']}/enderecos/{casa_ana['id']}").json()["principal"]


def test_listar_cliente_sem_endereco_devolve_lista_vazia(client, ana):
    resposta = client.get(f"/clientes/{ana['id']}/enderecos")

    assert resposta.status_code == 200
    assert resposta.json() == []


@pytest.mark.parametrize(
    "alteracao",
    [
        {"cep": "0131010"},
        {"cep": "01310-10a"},
        {"uf": "XX"},
        {"logradouro": ""},
        {"numero": "9" * 21},
    ],
)
def test_criar_com_dado_invalido_devolve_422(client, ana, alteracao):
    resposta = client.post(f"/clientes/{ana['id']}/enderecos", json={**CASA, **alteracao})

    assert resposta.status_code == 422


@pytest.mark.parametrize("metodo", ["get", "post"])
def test_cliente_inexistente_devolve_404(client, metodo):
    resposta = client.request(metodo, "/clientes/999999999/enderecos", json=CASA)

    assert resposta.status_code == 404
    assert resposta.json() == {"detail": "Cliente não encontrado"}


def test_endereco_de_outro_cliente_devolve_404(client, ana):
    bruno = criar(client, BRUNO)
    casa_bruno = criar_endereco(client, bruno["id"], CASA)
    url = f"/clientes/{ana['id']}/enderecos/{casa_bruno['id']}"

    assert client.get(url).status_code == 404
    assert client.put(url, json=CASA).status_code == 404
    assert client.delete(url).status_code == 404
    assert client.get(f"/clientes/{bruno['id']}/enderecos/{casa_bruno['id']}").status_code == 200


def test_endereco_inexistente_devolve_404(client, ana):
    resposta = client.get(f"/clientes/{ana['id']}/enderecos/999999999")

    assert resposta.status_code == 404
    assert resposta.json() == {"detail": "Endereço não encontrado"}


def test_remover_endereco(client, ana):
    casa = criar_endereco(client, ana["id"], CASA)
    url = f"/clientes/{ana['id']}/enderecos/{casa['id']}"

    assert client.delete(url).status_code == 204
    assert client.get(url).status_code == 404


def test_remover_cliente_remove_os_enderecos(client, ana, session):
    from app.models import Endereco

    criar_endereco(client, ana["id"], CASA)
    criar_endereco(client, ana["id"], TRABALHO)

    assert client.delete(f"/clientes/{ana['id']}").status_code == 204
    assert session.query(Endereco).filter_by(cliente_id=ana["id"]).count() == 0


def test_banco_recusa_dois_principais(session, client, ana):
    from sqlalchemy.exc import IntegrityError

    from app.models import Endereco

    # mesmo burlando a API, a regra se mantém: é o índice parcial que garante
    dados = {k: v for k, v in CASA.items()} | {"cep": "01310100"}
    session.add(Endereco(cliente_id=ana["id"], principal=True, **dados))
    session.flush()
    session.add(Endereco(cliente_id=ana["id"], principal=True, **dados))
    with pytest.raises(IntegrityError, match="endereco_principal_uk"):
        session.flush()
