"""cria tabela produto

Revision ID: 0001
Revises:
"""

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

SCHEMA = "catalogo"


def upgrade() -> None:
    op.create_table(
        "produto",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=True), primary_key=True),
        sa.Column("sku", sa.String(40), nullable=False),
        sa.Column("nome", sa.String(150), nullable=False),
        sa.Column("descricao", sa.Text(), nullable=True),
        sa.Column("preco_centavos", sa.Integer(), nullable=False),
        sa.Column("ativo", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column(
            "criado_em", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "atualizado_em",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("sku", name="produto_sku_uk"),
        sa.CheckConstraint("sku ~ '^[A-Z0-9][A-Z0-9-]*$'", name="produto_sku_formato_ck"),
        sa.CheckConstraint("preco_centavos >= 0", name="produto_preco_ck"),
        schema=SCHEMA,
    )


def downgrade() -> None:
    op.drop_table("produto", schema=SCHEMA)
