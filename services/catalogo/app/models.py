from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Identity,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime

from app.db import SCHEMA, Base


class Produto(Base):
    __tablename__ = "produto"
    __table_args__ = (
        UniqueConstraint("sku", name="produto_sku_uk"),
        CheckConstraint("sku ~ '^[A-Z0-9][A-Z0-9-]*$'", name="produto_sku_formato_ck"),
        CheckConstraint("preco_centavos >= 0", name="produto_preco_ck"),
        {"schema": SCHEMA},
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    sku: Mapped[str] = mapped_column(String(40))
    nome: Mapped[str] = mapped_column(String(150))
    descricao: Mapped[str | None] = mapped_column(Text)
    # dinheiro em inteiro: float não representa 0,10 exatamente e soma erro
    preco_centavos: Mapped[int] = mapped_column(Integer)
    ativo: Mapped[bool] = mapped_column(Boolean, server_default="true")
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    atualizado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
