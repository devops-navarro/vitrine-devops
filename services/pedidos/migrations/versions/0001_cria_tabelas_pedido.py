"""cria tabelas pedido e item_pedido

Revision ID: 0001
Revises:
"""

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

SCHEMA = "pedidos"


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column(
            "criado_em", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "atualizado_em",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "pedido",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=True), primary_key=True),
        sa.Column("cliente_id", sa.BigInteger(), nullable=False),
        sa.Column("status", sa.String(20), server_default=sa.text("'criado'"), nullable=False),
        sa.Column("total_centavos", sa.BigInteger(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint("status IN ('criado', 'cancelado')", name="pedido_status_ck"),
        sa.CheckConstraint("total_centavos >= 0", name="pedido_total_ck"),
        schema=SCHEMA,
    )
    op.create_index("pedido_cliente_idx", "pedido", ["cliente_id"], schema=SCHEMA)

    op.create_table(
        "item_pedido",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=True), primary_key=True),
        sa.Column("pedido_id", sa.BigInteger(), nullable=False),
        sa.Column("produto_id", sa.BigInteger(), nullable=False),
        sa.Column("sku", sa.String(40), nullable=False),
        sa.Column("nome", sa.String(150), nullable=False),
        sa.Column("preco_unitario_centavos", sa.Integer(), nullable=False),
        sa.Column("quantidade", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["pedido_id"],
            [f"{SCHEMA}.pedido.id"],
            name="item_pedido_pedido_fk",
            ondelete="CASCADE",
        ),
        # a unique (pedido_id, produto_id) também serve de índice para a FK
        sa.UniqueConstraint("pedido_id", "produto_id", name="item_pedido_produto_uk"),
        sa.CheckConstraint("quantidade > 0", name="item_pedido_quantidade_ck"),
        sa.CheckConstraint("preco_unitario_centavos >= 0", name="item_pedido_preco_ck"),
        schema=SCHEMA,
    )


def downgrade() -> None:
    op.drop_table("item_pedido", schema=SCHEMA)
    op.drop_index("pedido_cliente_idx", table_name="pedido", schema=SCHEMA)
    op.drop_table("pedido", schema=SCHEMA)
