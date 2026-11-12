from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    ForeignKey,
    Identity,
    Index,
    String,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import CHAR, DateTime

from app.db import SCHEMA, Base

UFS = (
    "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
    "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO",
)  # fmt: skip


class Cliente(Base):
    __tablename__ = "cliente"
    __table_args__ = (
        UniqueConstraint("cpf", name="cliente_cpf_uk"),
        CheckConstraint("cpf ~ '^[0-9]{11}$'", name="cliente_cpf_digitos_ck"),
        CheckConstraint("position('@' in email) > 1", name="cliente_email_ck"),
        Index("cliente_email_uk", text("lower(email)"), unique=True),
        {"schema": SCHEMA},
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    nome: Mapped[str] = mapped_column(String(150))
    cpf: Mapped[str] = mapped_column(CHAR(11))
    email: Mapped[str] = mapped_column(String(254))
    telefone: Mapped[str | None] = mapped_column(String(20))
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    atualizado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Endereco(Base):
    __tablename__ = "endereco"
    __table_args__ = (
        CheckConstraint("cep ~ '^[0-9]{8}$'", name="endereco_cep_digitos_ck"),
        CheckConstraint(f"uf IN ({', '.join(repr(uf) for uf in UFS)})", name="endereco_uf_ck"),
        # a FK não cria índice sozinha no PostgreSQL, e toda busca é por cliente
        Index("endereco_cliente_idx", "cliente_id"),
        # no máximo um endereço principal por cliente, garantido pelo banco
        Index(
            "endereco_principal_uk",
            "cliente_id",
            unique=True,
            postgresql_where=text("principal"),
        ),
        {"schema": SCHEMA},
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    # o banco apaga os endereços junto com o cliente (ON DELETE CASCADE)
    cliente_id: Mapped[int] = mapped_column(
        ForeignKey(f"{SCHEMA}.cliente.id", ondelete="CASCADE", name="endereco_cliente_fk")
    )
    apelido: Mapped[str | None] = mapped_column(String(50))
    cep: Mapped[str] = mapped_column(CHAR(8))
    logradouro: Mapped[str] = mapped_column(String(200))
    numero: Mapped[str] = mapped_column(String(20))
    complemento: Mapped[str | None] = mapped_column(String(100))
    bairro: Mapped[str] = mapped_column(String(100))
    cidade: Mapped[str] = mapped_column(String(100))
    uf: Mapped[str] = mapped_column(CHAR(2))
    principal: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    atualizado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
