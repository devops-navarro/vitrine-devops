from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator

Id = Annotated[int, Field(gt=0)]


class ItemEntrada(BaseModel):
    produto_id: Id
    quantidade: Annotated[int, Field(gt=0, le=1000, examples=[2])]


class PedidoEntrada(BaseModel):
    cliente_id: Id
    itens: Annotated[list[ItemEntrada], Field(min_length=1, max_length=50)]

    @field_validator("itens")
    @classmethod
    def _sem_produto_repetido(cls, itens: list[ItemEntrada]) -> list[ItemEntrada]:
        ids = [item.produto_id for item in itens]
        if len(ids) != len(set(ids)):
            raise ValueError("produto repetido; use a quantidade")
        return itens


class ItemSaida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    produto_id: int
    sku: str
    nome: str
    preco_unitario_centavos: int
    quantidade: int
    subtotal_centavos: int


class PedidoSaida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    cliente_id: int
    status: str
    total_centavos: int
    itens: list[ItemSaida]
    criado_em: datetime
    atualizado_em: datetime
