import httpx2
import pytest


@pytest.fixture
def loja(vizinhos):
    """Um cliente e três produtos, um deles inativo."""
    vizinhos.clientes[1] = {"id": 1, "nome": "Ana"}
    vizinhos.produto(10, preco=4990)
    vizinhos.produto(20, preco=2500)
    vizinhos.produto(30, preco=1000, ativo=False)
    return vizinhos


def pedido(cliente_id=1, **itens):
    return {
        "cliente_id": cliente_id,
        "itens": [{"produto_id": int(p[1:]), "quantidade": q} for p, q in itens.items()],
    }


def test_criar_calcula_total_e_copia_o_produto(client, loja):
    resposta = client.post("/pedidos", json=pedido(p10=2, p20=1))

    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["status"] == "criado"
    assert corpo["total_centavos"] == 2 * 4990 + 2500
    assert corpo["itens"][0] == {
        "produto_id": 10,
        "sku": "SKU-10",
        "nome": "Produto 10",
        "preco_unitario_centavos": 4990,
        "quantidade": 2,
        "subtotal_centavos": 9980,
    }
    assert resposta.headers["Location"] == f"/pedidos/{corpo['id']}"


def test_mudanca_de_preco_no_catalogo_nao_altera_pedido_existente(client, loja):
    criado = client.post("/pedidos", json=pedido(p10=1)).json()

    loja.produtos[10]["preco_centavos"] = 9999

    assert client.get(f"/pedidos/{criado['id']}").json()["total_centavos"] == 4990


def test_envia_a_chave_para_os_outros_servicos(client, loja):
    client.post("/pedidos", json=pedido(p10=1))

    assert [str(c.url) for c in loja.chamadas] == [
        "http://clientes/clientes/1",
        "http://catalogo/produtos/10",
    ]
    assert all(c.headers["X-API-Key"] == "chave" for c in loja.chamadas)


def test_cliente_inexistente_devolve_422_sem_consultar_produtos(client, loja):
    resposta = client.post("/pedidos", json=pedido(cliente_id=99, p10=1))

    assert resposta.status_code == 422
    assert resposta.json() == {"detail": "Cliente 99 não encontrado"}
    assert len(loja.chamadas) == 1


def test_lista_todos_os_produtos_com_problema_de_uma_vez(client, loja):
    resposta = client.post("/pedidos", json=pedido(p10=1, p30=1, p99=1))

    assert resposta.status_code == 422
    assert resposta.json() == {"detail": "Produto 30 está inativo; Produto 99 não encontrado"}


@pytest.mark.parametrize(
    "corpo",
    [
        {"cliente_id": 1, "itens": []},
        {"cliente_id": 0, "itens": [{"produto_id": 10, "quantidade": 1}]},
        {"cliente_id": 1, "itens": [{"produto_id": 10, "quantidade": 0}]},
        {"cliente_id": 1, "itens": [{"produto_id": 10, "quantidade": 1001}]},
        {"cliente_id": 1, "itens": [{"produto_id": 10, "quantidade": 1}] * 2},
        {"cliente_id": 1, "itens": [{"produto_id": i, "quantidade": 1} for i in range(1, 52)]},
    ],
)
def test_entrada_invalida_devolve_422_sem_chamar_ninguem(client, loja, corpo):
    assert client.post("/pedidos", json=corpo).status_code == 422
    assert loja.chamadas == []


@pytest.mark.parametrize(
    ("servico", "falha", "status", "trecho"),
    [
        ("clientes", httpx2.ReadTimeout("lento"), 503, "Serviço clientes não respondeu a tempo"),
        ("catalogo", httpx2.ConnectError("recusado"), 503, "Serviço catalogo está fora do ar"),
        ("catalogo", 500, 503, "Serviço catalogo respondeu 500"),
        ("clientes", 401, 502, "Serviço clientes respondeu 401"),
    ],
)
def test_falha_em_outro_servico_nao_vira_500(client, loja, session, servico, falha, status, trecho):
    from app.models import Pedido

    loja.falha[servico] = falha

    resposta = client.post("/pedidos", json=pedido(p10=1))

    assert resposta.status_code == status
    assert resposta.json() == {"detail": trecho}
    assert ("Retry-After" in resposta.headers) == (status == 503)
    assert session.query(Pedido).count() == 0


def test_buscar_inexistente_devolve_404(client):
    resposta = client.get("/pedidos/999999999")

    assert resposta.status_code == 404
    assert resposta.json() == {"detail": "Pedido não encontrado"}


def test_listar_filtra_por_cliente_e_status(client, loja):
    loja.clientes[2] = {"id": 2}
    a = client.post("/pedidos", json=pedido(p10=1)).json()
    b = client.post("/pedidos", json=pedido(cliente_id=2, p20=1)).json()
    client.post(f"/pedidos/{b['id']}/cancelar")

    def ids(**params):
        return [p["id"] for p in client.get("/pedidos", params=params).json()]

    assert ids() == [a["id"], b["id"]]
    assert ids(cliente_id=2) == [b["id"]]
    assert ids(status="criado") == [a["id"]]
    assert ids(limit=1, offset=1) == [b["id"]]


@pytest.mark.parametrize("params", [{"status": "pago"}, {"cliente_id": 0}, {"limit": 101}])
def test_filtro_invalido_devolve_422(client, params):
    assert client.get("/pedidos", params=params).status_code == 422


def test_cancelar(client, loja):
    criado = client.post("/pedidos", json=pedido(p10=1)).json()

    resposta = client.post(f"/pedidos/{criado['id']}/cancelar")

    assert resposta.status_code == 200
    assert resposta.json()["status"] == "cancelado"


def test_cancelar_duas_vezes_devolve_409(client, loja):
    criado = client.post("/pedidos", json=pedido(p10=1)).json()
    client.post(f"/pedidos/{criado['id']}/cancelar")

    resposta = client.post(f"/pedidos/{criado['id']}/cancelar")

    assert resposta.status_code == 409
    assert resposta.json() == {"detail": "Pedido já está cancelado"}


def test_cancelar_inexistente_devolve_404(client):
    assert client.post("/pedidos/999999999/cancelar").status_code == 404


def test_pedido_nao_tem_put_nem_delete(client, loja):
    criado = client.post("/pedidos", json=pedido(p10=1)).json()

    assert client.put(f"/pedidos/{criado['id']}", json={}).status_code == 405
    assert client.delete(f"/pedidos/{criado['id']}").status_code == 405


def test_repassa_o_request_id_para_os_vizinhos(client, loja):
    resposta = client.post("/pedidos", json=pedido(p10=1), headers={"X-Request-ID": "compra-42"})

    assert resposta.headers["X-Request-ID"] == "compra-42"
    assert [c.headers["X-Request-ID"] for c in loja.chamadas] == ["compra-42", "compra-42"]


def test_mede_cada_chamada_por_servico_e_resultado(client, loja):
    client.post("/pedidos", json=pedido(p10=1))
    loja.falha["catalogo"] = httpx2.ReadTimeout("lento")
    client.post("/pedidos", json=pedido(p10=1))

    texto = client.get("/metrics").text

    # o Prometheus escreve os rótulos em ordem alfabética
    assert 'integracao_duracao_segundos_count{resultado="ok",servico="clientes"}' in texto
    assert 'integracao_duracao_segundos_count{resultado="timeout",servico="catalogo"}' in texto


def test_falha_de_integracao_gera_log_de_aviso(client, loja, caplog):
    import logging

    loja.falha["clientes"] = 503
    with caplog.at_level(logging.WARNING, logger="vitrine.pedidos.integracoes"):
        client.post("/pedidos", json=pedido(p10=1), headers={"X-Request-ID": "falha-1"})

    registro = next(r for r in caplog.records if r.name == "vitrine.pedidos.integracoes")
    assert registro.upstream == "clientes"
    assert registro.result == "http_503"
    assert registro.request_id == "falha-1"
