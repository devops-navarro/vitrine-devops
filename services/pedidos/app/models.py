from datetime import datetime

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    ForeignKey,
    Identity,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import DateTime

from app.db import SCHEMA, Base

STATUS = ("criado", "cancelado")


class Pedido(Base):
    __tablename__ = "pedido"
    __table_args__ = (
        CheckConstraint(
            f"status IN ({', '.join(repr(s) for s in STATUS)})", name="pedido_status_ck"
        ),
        CheckConstraint("total_centavos >= 0", name="pedido_total_ck"),
        Index("pedido_cliente_idx", "cliente_id"),
        {"schema": SCHEMA},
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    # Sem FK: o cliente mora em outro serviço e outro schema. Quem garante que
    # ele existe é a chamada HTTP no momento da criação.
    cliente_id: Mapped[int] = mapped_column(BigInteger)
    status: Mapped[str] = mapped_column(String(20), server_default=text("'criado'"))
    total_centavos: Mapped[int] = mapped_column(BigInteger)
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    atualizado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    itens: Mapped[list["ItemPedido"]] = relationship(
        cascade="all, delete-orphan", lazy="selectin", order_by="ItemPedido.id"
    )


class ItemPedido(Base):
    __tablename__ = "item_pedido"
    __table_args__ = (
        UniqueConstraint("pedido_id", "produto_id", name="item_pedido_produto_uk"),
        CheckConstraint("quantidade > 0", name="item_pedido_quantidade_ck"),
        CheckConstraint("preco_unitario_centavos >= 0", name="item_pedido_preco_ck"),
        {"schema": SCHEMA},
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    pedido_id: Mapped[int] = mapped_column(
        ForeignKey(f"{SCHEMA}.pedido.id", ondelete="CASCADE", name="item_pedido_pedido_fk")
    )
    produto_id: Mapped[int] = mapped_column(BigInteger)
    # Cópia do produto no momento da compra. Se o preço mudar no catálogo
    # amanhã, o pedido de hoje continua com o valor que o cliente pagou.
    sku: Mapped[str] = mapped_column(String(40))
    nome: Mapped[str] = mapped_column(String(150))
    preco_unitario_centavos: Mapped[int] = mapped_column(Integer)
    quantidade: Mapped[int] = mapped_column(Integer)

    @property
    def subtotal_centavos(self) -> int:
        return self.preco_unitario_centavos * self.quantidade
