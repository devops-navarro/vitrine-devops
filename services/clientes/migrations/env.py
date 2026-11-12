from logging.config import fileConfig

from alembic import context
from sqlalchemy import text

from app import models  # noqa: F401  registra as tabelas no metadata
from app.db import SCHEMA, Base, engine

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)


def include_name(name, type_, parent_names):
    # cada serviço só enxerga o próprio schema
    if type_ == "schema":
        return name == SCHEMA
    return True


def run_migrations_online() -> None:
    with engine.connect() as connection:
        connection.execute(text(f"CREATE SCHEMA IF NOT EXISTS {SCHEMA}"))
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
