import logging
from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine, text

from app import models  # noqa: F401  registra as tabelas no metadata
from app.config import get_settings
from app.db import SCHEMA, Base

# Engine próprio das migrations. O usuário do banco tem o nome do schema, e o
# search_path padrão ("$user", public) faria do schema o padrão da sessão: o
# Alembic leria as tabelas como "sem schema" e o check acusaria todas como
# faltando. O SQLAlchemy guarda o schema padrão na primeira conexão, então o
# search_path precisa vir já na conexão, não num SET depois.
engine = create_engine(
    get_settings().database_url,
    connect_args={"options": "-c search_path=public", "connect_timeout": 3},
)

config = context.config
# Só configura o logging quando o Alembic roda sozinho (CLI). Dentro de um
# processo que já tem logging (os testes), fileConfig trocaria os handlers e
# desligaria em silêncio todos os loggers existentes.
if config.config_file_name is not None and not logging.getLogger().handlers:
    fileConfig(config.config_file_name)


def include_name(name, type_, parent_names):
    # cada serviço só enxerga o próprio schema
    if type_ == "schema":
        return name == SCHEMA
    return True


def run_migrations_online() -> None:
    with engine.connect() as connection:
        # O schema é criado pela infraestrutura (infra/postgres), não pelo
        # serviço: o usuário dele não tem permissão para criar schemas.
        existe = connection.scalar(
            text("SELECT 1 FROM pg_namespace WHERE nspname = :schema"), {"schema": SCHEMA}
        )
        if not existe:
            raise SystemExit(f"Schema '{SCHEMA}' não existe. Rode make db-bootstrap.")
        # A consulta acima abriu uma transação (autobegin). Sem este commit, o
        # Alembic não abre a dele, e a migration é desfeita ao fechar a conexão.
        connection.commit()
        context.configure(
            connection=connection,
            target_metadata=Base.metadata,
            version_table_schema=SCHEMA,
            include_schemas=True,
            include_name=include_name,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    raise SystemExit("Migrations offline não são usadas neste projeto.")

run_migrations_online()
