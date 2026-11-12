"""cria tabela cliente

Revision ID: 0001
Revises:
"""

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

SCHEMA = "clientes"


def upgrade() -> None:
    op.create_table(
        "cliente",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=True), primary_key=True),
        sa.Column("nome", sa.String(150), nullable=False),
        sa.Column("cpf", sa.CHAR(11), nullable=False),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column("telefone", sa.String(20), nullable=True),
        sa.Column(
            "criado_em", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "atualizado_em",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("cpf", name="cliente_cpf_uk"),
        sa.CheckConstraint("cpf ~ '^[0-9]{11}$'", name="cliente_cpf_digitos_ck"),
        sa.CheckConstraint("position('@' in email) > 1", name="cliente_email_ck"),
        schema=SCHEMA,
    )
    op.create_index(
        "cliente_email_uk", "cliente", [sa.text("lower(email)")], unique=True, schema=SCHEMA
    )


def downgrade() -> None:
    op.drop_index("cliente_email_uk", table_name="cliente", schema=SCHEMA)
    op.drop_table("cliente", schema=SCHEMA)
