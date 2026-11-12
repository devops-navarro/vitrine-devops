"""A ADR 0001 em forma de teste: cada serviço só alcança o próprio schema."""

import pytest
from sqlalchemy import text

from app.db import SCHEMA

SERVICOS = {"clientes", "catalogo", "pedidos"}


def _consulta(session, sql: str, **params):
    return session.scalar(text(sql), params)


def test_conecta_com_o_usuario_do_proprio_servico(session):
    usuario = _consulta(session, "SELECT current_user")

    assert usuario == SCHEMA, (
        f"Conectado como {usuario!r}. Rode os testes com make {SCHEMA}-test, "
        "que usa o usuário do serviço e não o administrador."
    )
    assert _consulta(session, "SELECT rolsuper FROM pg_roles WHERE rolname = current_user") is False


def test_e_dono_do_proprio_schema(session):
    dono = _consulta(
        session,
        "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = :s",
        s=SCHEMA,
    )

    assert dono == SCHEMA


@pytest.mark.parametrize("outro", sorted(SERVICOS - {SCHEMA}))
def test_nao_alcanca_o_schema_de_outro_servico(session, outro):
    assert _consulta(session, "SELECT has_schema_privilege(:s, 'USAGE')", s=outro) is False


def test_nao_cria_banco_schema_nem_tabela_no_public(session):
    assert (
        _consulta(session, "SELECT has_database_privilege(current_database(), 'CREATE')") is False
    )
    assert _consulta(session, "SELECT has_schema_privilege('public', 'CREATE')") is False
    assert (
        _consulta(session, "SELECT rolcreatedb FROM pg_roles WHERE rolname = current_user") is False
    )
