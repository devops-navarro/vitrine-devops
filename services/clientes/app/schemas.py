from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

# Os limites espelham as colunas do banco: o erro aparece como 422 na API,
# antes de virar um erro de constraint no PostgreSQL.
Nome = Annotated[str, Field(min_length=1, max_length=150, examples=["Ana Souza"])]
Cpf = Annotated[str, Field(pattern=r"^[0-9]{11}$", examples=["52998224725"])]
Email = Annotated[str, Field(min_length=3, max_length=254, examples=["ana@exemplo.com"])]
Telefone = Annotated[str, Field(max_length=20, examples=["+55 11 91234-5678"])]


class ClienteEntrada(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    nome: Nome
    cpf: Cpf
    email: Email
    telefone: Telefone | None = None


class ClienteSaida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nome: str
    cpf: str
    email: str
    telefone: str | None
    criado_em: datetime
    atualizado_em: datetime
