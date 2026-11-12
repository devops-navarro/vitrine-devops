from datetime import datetime

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
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
