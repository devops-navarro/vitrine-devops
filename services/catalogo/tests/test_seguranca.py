import pytest
from pydantic import ValidationError

from app.config import Settings
from tests.conftest import CHAVE, CHAVE_ANTIGA

ROTAS_PROTEGIDAS = [
    ("get", "/produtos"),
    ("post", "/produtos"),
    ("get", "/produtos/1"),
    ("put", "/produtos/1"),
    ("delete", "/produtos/1"),
]


@pytest.mark.parametrize(("metodo", "rota"), ROTAS_PROTEGIDAS)
def test_sem_chave_devolve_401(anonimo, metodo, rota):
    resposta = anonimo.request(metodo, rota, json={})

    assert resposta.status_code == 401
    assert resposta.json() == {"detail": "API key ausente ou inválida"}
    assert resposta.headers["WWW-Authenticate"] == "ApiKey"


@pytest.mark.parametrize("chave", ["errada", "", CHAVE[:-1], CHAVE + "x", CHAVE.upper()])
def test_chave_invalida_devolve_401(anonimo, chave):
    resposta = anonimo.get("/produtos", headers={"X-API-Key": chave})

    assert resposta.status_code == 401


@pytest.mark.parametrize("chave", [CHAVE, CHAVE_ANTIGA])
def test_qualquer_chave_configurada_e_aceita(anonimo, chave):
    # as duas valem ao mesmo tempo durante um rodízio de chave
    assert anonimo.get("/produtos", headers={"X-API-Key": chave}).status_code == 200


@pytest.mark.parametrize("rota", ["/health", "/docs", "/openapi.json"])
def test_rotas_de_infra_e_documentacao_ficam_abertas(anonimo, rota):
    assert anonimo.get(rota).status_code == 200


def test_openapi_declara_a_chave_para_o_botao_authorize(anonimo):
    esquemas = anonimo.get("/openapi.json").json()["components"]["securitySchemes"]

    assert esquemas["APIKeyHeader"] == {"type": "apiKey", "in": "header", "name": "X-API-Key"}


def _settings(api_keys: str) -> Settings:
    return Settings(postgres_user="u", postgres_password="p", postgres_db="d", api_keys=api_keys)


@pytest.mark.parametrize("api_keys", ["", " , ", "curta", f"{CHAVE},curta"])
def test_servico_nao_sobe_com_chave_fraca_ou_vazia(api_keys):
    with pytest.raises(ValidationError, match="API_KEYS|caracteres"):
        _settings(api_keys)


def test_chaves_sao_separadas_por_virgula_e_sem_espacos():
    assert _settings(f" {CHAVE} ,{CHAVE_ANTIGA},").chaves_validas == [CHAVE, CHAVE_ANTIGA]


def test_chave_nao_aparece_quando_a_config_e_impressa():
    assert CHAVE not in repr(_settings(CHAVE))


def test_erro_de_configuracao_nao_vaza_a_chave_nem_a_senha():
    chave_curta = "segredo-curto-que-nao-pode-vazar"[:31]
    with pytest.raises(ValidationError) as erro:
        Settings(
            postgres_user="u",
            postgres_password="senha-que-nao-pode-vazar",
            postgres_db="d",
            api_keys=chave_curta,
        )

    assert chave_curta not in str(erro.value)
    assert "senha-que-nao-pode-vazar" not in str(erro.value)
