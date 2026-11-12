import json
import logging
import sys
import time

import pytest
from sqlalchemy import create_engine

from app.db import SCHEMA, get_engine
from app.main import app
from app.observabilidade import FormatadorJson
from tests.conftest import CHAVE


def _rota_com_id() -> str:
    """Primeira rota GET com um parâmetro, como /clientes/{cliente_id}."""
    caminhos = app.openapi()["paths"]
    return next(p for p, ops in caminhos.items() if "get" in ops and p.count("{") == 1)


def _caminho_concreto(modelo: str, valor: int) -> str:
    inicio, fim = modelo.index("{"), modelo.index("}")
    return modelo[:inicio] + str(valor) + modelo[fim + 1 :]


def test_health_nao_depende_do_banco(anonimo):
    app.dependency_overrides[get_engine] = lambda: pytest.fail("health não pode tocar o banco")

    assert anonimo.get("/health").json() == {"status": "ok"}


def test_ready_com_banco_no_ar(anonimo):
    resposta = anonimo.get("/ready")

    assert resposta.status_code == 200
    assert resposta.json() == {"status": "ok", "checks": {"banco": "ok"}}


def test_ready_com_banco_fora_do_ar_devolve_503_rapido(anonimo):
    # porta 1 em localhost: conexão recusada de verdade, sem mock
    fora = create_engine(
        "postgresql+psycopg://x:y@127.0.0.1:1/z", connect_args={"connect_timeout": 3}
    )
    app.dependency_overrides[get_engine] = lambda: fora
    inicio = time.monotonic()

    resposta = anonimo.get("/ready")

    assert resposta.status_code == 503
    assert resposta.json() == {"status": "indisponivel", "checks": {"banco": "falhou"}}
    assert time.monotonic() - inicio < 3


def test_rotas_de_infra_ficam_fora_da_documentacao_de_negocio(anonimo):
    caminhos = anonimo.get("/openapi.json").json()["paths"]

    assert {"/health", "/ready"} <= caminhos.keys()
    assert "/metrics" not in caminhos


def test_metrics_no_formato_prometheus(anonimo):
    anonimo.get("/health")

    resposta = anonimo.get("/metrics")

    assert resposta.status_code == 200
    assert resposta.headers["content-type"].startswith("text/plain")
    assert "# TYPE http_requests_total counter" in resposta.text
    assert "# TYPE http_request_duration_seconds histogram" in resposta.text
    assert 'http_requests_total{method="GET",route="/health",status="200"}' in resposta.text


def test_metrica_usa_o_modelo_da_rota_e_nao_o_id(client):
    modelo = _rota_com_id()
    client.get(_caminho_concreto(modelo, 987654321))

    texto = client.get("/metrics").text

    assert f'route="{modelo}",status="404"' in texto
    assert "987654321" not in texto


def test_rota_inexistente_nao_cria_serie_nova(anonimo):
    anonimo.get("/nao/existe/123")

    texto = anonimo.get("/metrics").text

    assert 'route="nao_mapeada",status="404"' in texto
    assert "/nao/existe" not in texto


def test_request_id_gerado_quando_nao_vem(anonimo):
    rid = anonimo.get("/health").headers["X-Request-ID"]

    assert len(rid) == 32
    int(rid, 16)


def test_request_id_recebido_e_devolvido(anonimo):
    resposta = anonimo.get("/health", headers={"X-Request-ID": "abc-123"})

    assert resposta.headers["X-Request-ID"] == "abc-123"


@pytest.mark.parametrize("forjado", ["a" * 65, "abc def", 'x"}\n{"level":"ERROR'])
def test_request_id_invalido_e_trocado(anonimo, forjado):
    resposta = anonimo.get("/health", headers={"X-Request-ID": forjado})

    assert resposta.headers["X-Request-ID"] != forjado


def test_log_de_acesso_com_rota_status_duracao_e_request_id(client, caplog):
    modelo = _rota_com_id()
    with caplog.at_level(logging.INFO, logger=f"vitrine.{SCHEMA}.acesso"):
        client.get(_caminho_concreto(modelo, 5), headers={"X-Request-ID": "rastreio-1"})

    registro = next(r for r in caplog.records if r.name.endswith(".acesso"))
    linha = json.loads(FormatadorJson().format(registro))
    assert linha["service"] == SCHEMA
    assert linha["level"] == "INFO"
    assert linha["request_id"] == "rastreio-1"
    assert linha["route"] == modelo
    assert linha["status"] == 404
    assert isinstance(linha["duration_ms"], float)


def test_probes_nao_poluem_o_log_em_info(anonimo, caplog):
    with caplog.at_level(logging.INFO, logger=f"vitrine.{SCHEMA}.acesso"):
        anonimo.get("/health")
        anonimo.get("/ready")

    assert [r for r in caplog.records if r.name.endswith(".acesso")] == []


def test_log_nunca_contem_a_api_key(client, caplog):
    with caplog.at_level(logging.DEBUG):
        client.get(_rota_com_id().split("{")[0])

    tudo = "\n".join(FormatadorJson().format(r) for r in caplog.records)
    assert CHAVE not in tudo


def test_formatador_gera_uma_linha_json_com_erro():
    try:
        raise ValueError("falhou")
    except ValueError:
        registro = logging.getLogger("teste").makeRecord(
            "teste", logging.ERROR, __file__, 1, "deu %s", ("ruim",), sys.exc_info()
        )

    linha = FormatadorJson().format(registro)

    assert "\n" not in linha
    dados = json.loads(linha)
    assert dados["message"] == "deu ruim"
    assert "ValueError: falhou" in dados["exception"]
