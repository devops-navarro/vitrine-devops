from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field

# Os limites espelham as colunas do banco: o erro aparece como 422 na API,
# antes de virar um erro de constraint no PostgreSQL.
Sku = Annotated[
    str,
    BeforeValidator(lambda v: v.strip().upper() if isinstance(v, str) else v),
    Field(
        pattern=r"^[A-Z0-9][A-Z0-9-]*$",
        max_length=40,
        examples=["CAM-BRANCA-M"],
        description="Código único do produto. Letras, números e hífen; gravado em maiúsculas.",
    ),
]


class ProdutoEntrada(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    sku: Sku
    nome: Annotated[str, Field(min_length=1, max_length=150, examples=["Camiseta branca M"])]
    descricao: Annotated[str, Field(max_length=5000)] | None = None
    # strict: "19.90" ou 19.9 são recusados em vez de convertidos em silêncio
    preco_centavos: Annotated[
        int,
        Field(ge=0, le=100_000_000, strict=True, examples=[4990], description="R$ 49,90 = 4990"),
    ]
    ativo: bool = True


class ProdutoSaida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    sku: str
    nome: str
    descricao: str | None
    preco_centavos: int
    ativo: bool
    criado_em: datetime
    atualizado_em: datetime
