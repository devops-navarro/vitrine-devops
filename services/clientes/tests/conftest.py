import os
from collections.abc import Iterator
from pathlib import Path

import psycopg
import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

# Os testes usam um banco separado, para nunca apagar dados de desenvolvimento.
# Precisa vir antes de importar o app, porque o engine é criado no import.
os.environ["POSTGRES_DB"] = f"{os.environ.get('POSTGRES_DB', 'vitrine')}_test"
# Duas chaves, como no meio de um rodízio. Nunca as do .env.
CHAVE = "chave-de-teste-" + "a" * 32
CHAVE_ANTIGA = "chave-antiga-de-teste-" + "b" * 32
os.environ["API_KEYS"] = f"{CHAVE}, {CHAVE_ANTIGA}"

from app.config import get_settings  # noqa: E402
from app.db import SessionLocal, engine, get_session  # noqa: E402
from app.main import app  # noqa: E402

SERVICO = Path(__file__).resolve().parents[1]


def _conferir_banco_de_teste() -> None:
    # O banco de teste e os usuários vêm do make db-bootstrap; o usuário do
    # serviço não tem permissão para criar banco.
    cfg = get_settings()
    try:
        psycopg.connect(
            host=cfg.postgres_host,
            port=cfg.postgres_port,
            user=cfg.postgres_user,
            password=cfg.postgres_password.get_secret_value(),
            dbname=cfg.postgres_db,
        ).close()
    except psycopg.OperationalError as erro:
        pytest.exit(f"Sem acesso ao banco {cfg.postgres_db}. Rode make db-bootstrap. ({erro})")


@pytest.fixture(scope="session", autouse=True)
def banco() -> None:
    _conferir_banco_de_teste()
    command.upgrade(Config(str(SERVICO / "alembic.ini")), "head")


@pytest.fixture
def session() -> Iterator[Session]:
    # Cada teste roda dentro de uma transação desfeita no final. Os commits da
    # API viram savepoints, então nenhum teste enxerga o dado de outro.
    conexao = engine.connect()
    transacao = conexao.begin()
    # mesma fábrica da aplicação: teste com configuração diferente esconde bug
    sessao = SessionLocal(bind=conexao, join_transaction_mode="create_savepoint")
    try:
        yield sessao
    finally:
        sessao.close()
        transacao.rollback()
        conexao.close()


@pytest.fixture
def anonimo(session: Session) -> Iterator[TestClient]:
    """Cliente HTTP sem API key."""
    app.dependency_overrides[get_session] = lambda: session
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def client(anonimo: TestClient) -> TestClient:
    """Cliente HTTP autenticado, usado pela maioria dos testes."""
    anonimo.headers["X-API-Key"] = CHAVE
    return anonimo
