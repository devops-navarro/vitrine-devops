"""cria tabela endereco

Revision ID: 0002
Revises: 0001
"""

import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

SCHEMA = "clientes"
UFS = (
    "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
    "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO",
)  # fmt: skip


def upgrade() -> None:
    op.create_table(
        "endereco",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=True), primary_key=True),
        sa.Column("cliente_id", sa.BigInteger(), nullable=False),
        sa.Column("apelido", sa.String(50), nullable=True),
        sa.Column("cep", sa.CHAR(8), nullable=False),
        sa.Column("logradouro", sa.String(200), nullable=False),
        sa.Column("numero", sa.String(20), nullable=False),
        sa.Column("complemento", sa.String(100), nullable=True),
        sa.Column("bairro", sa.String(100), nullable=False),
        sa.Column("cidade", sa.String(100), nullable=False),
        sa.Column("uf", sa.CHAR(2), nullable=False),
        sa.Column("principal", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column(
            "criado_em", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "atualizado_em",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["cliente_id"],
            [f"{SCHEMA}.cliente.id"],
            name="endereco_cliente_fk",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint("cep ~ '^[0-9]{8}$'", name="endereco_cep_digitos_ck"),
        sa.CheckConstraint(f"uf IN ({', '.join(repr(uf) for uf in UFS)})", name="endereco_uf_ck"),
        schema=SCHEMA,
    )
    op.create_index("endereco_cliente_idx", "endereco", ["cliente_id"], schema=SCHEMA)
    op.create_index(
        "endereco_principal_uk",
        "endereco",
        ["cliente_id"],
        unique=True,
        schema=SCHEMA,
        postgresql_where=sa.text("principal"),
    )


def downgrade() -> None:
    op.drop_index("endereco_principal_uk", table_name="endereco", schema=SCHEMA)
    op.drop_index("endereco_cliente_idx", table_name="endereco", schema=SCHEMA)
    op.drop_table("endereco", schema=SCHEMA)
