from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, BeforeValidator, ConfigDict, EmailStr, Field

from app.validacao import normalizar_cpf

# Os limites espelham as colunas do banco: o erro aparece como 422 na API,
# antes de virar um erro de constraint no PostgreSQL.
Nome = Annotated[str, Field(min_length=1, max_length=150, examples=["Ana Souza"])]
Cpf = Annotated[
    str,
    BeforeValidator(lambda v: normalizar_cpf(v) if isinstance(v, str) else v),
    Field(examples=["529.982.247-25"], description="Com ou sem máscara. Gravado só com dígitos."),
]
# O banco já trata e-mail sem diferenciar maiúsculas (índice em lower(email)).
# Gravar em minúsculas mantém a busca e a exibição coerentes com essa regra.
Email = Annotated[
    EmailStr,
    Field(max_length=254, examples=["ana@exemplo.com"]),
    AfterValidator(str.lower),
]
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
