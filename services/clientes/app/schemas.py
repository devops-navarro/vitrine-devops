from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, BeforeValidator, ConfigDict, EmailStr, Field

from app.validacao import normalizar_cep, normalizar_cpf

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


Cep = Annotated[
    str,
    BeforeValidator(lambda v: normalizar_cep(v) if isinstance(v, str) else v),
    Field(examples=["01310-100"], description="Com ou sem máscara. Gravado só com dígitos."),
]
Uf = Literal[
    "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
    "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO",
]  # fmt: skip


class EnderecoEntrada(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    apelido: Annotated[str, Field(max_length=50, examples=["Casa"])] | None = None
    cep: Cep
    logradouro: Annotated[str, Field(min_length=1, max_length=200, examples=["Av. Paulista"])]
    numero: Annotated[str, Field(min_length=1, max_length=20, examples=["1000"])]
    complemento: Annotated[str, Field(max_length=100, examples=["Apto 12"])] | None = None
    bairro: Annotated[str, Field(min_length=1, max_length=100, examples=["Bela Vista"])]
    cidade: Annotated[str, Field(min_length=1, max_length=100, examples=["São Paulo"])]
    uf: Annotated[Uf, BeforeValidator(lambda v: v.strip().upper() if isinstance(v, str) else v)]
    principal: bool = False


class EnderecoSaida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    cliente_id: int
    apelido: str | None
    cep: str
    logradouro: str
    numero: str
    complemento: str | None
    bairro: str
    cidade: str
    uf: str
    principal: bool
    criado_em: datetime
    atualizado_em: datetime
