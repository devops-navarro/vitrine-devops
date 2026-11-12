from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select

from app.deps import SessionDep, buscar_cliente_ou_404, salvar
from app.models import Cliente
from app.schemas import ClienteEntrada, ClienteSaida
from app.validacao import normalizar_cpf

router = APIRouter(prefix="/clientes", tags=["clientes"])

NAO_ENCONTRADO = {404: {"description": "Cliente não encontrado"}}
CONFLITO = {409: {"description": "CPF ou e-mail já cadastrado"}}

DUPLICADOS = {
    "cliente_cpf_uk": "CPF já cadastrado",
    "cliente_email_uk": "E-mail já cadastrado",
}


@router.get("", response_model=list[ClienteSaida])
def listar(
    session: SessionDep,
    cpf: Annotated[
        str | None,
        Query(description="Busca pelo CPF, com ou sem máscara.", examples=["529.982.247-25"]),
    ] = None,
    # limite máximo para uma chamada nunca trazer a tabela inteira
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[Cliente]:
    consulta = select(Cliente).order_by(Cliente.id).limit(limit).offset(offset)
    if cpf is not None:
        try:
            consulta = consulta.where(Cliente.cpf == normalizar_cpf(cpf))
        except ValueError as erro:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(erro)) from erro
    return list(session.scalars(consulta))


@router.get("/{cliente_id}", response_model=ClienteSaida, responses=NAO_ENCONTRADO)
def buscar(cliente_id: int, session: SessionDep) -> Cliente:
    return buscar_cliente_ou_404(session, cliente_id)


@router.post(
    "", response_model=ClienteSaida, status_code=status.HTTP_201_CREATED, responses=CONFLITO
)
def criar(dados: ClienteEntrada, session: SessionDep, response: Response) -> Cliente:
    cliente = Cliente(**dados.model_dump())
    session.add(cliente)
    salvar(session, cliente, DUPLICADOS)
    response.headers["Location"] = f"/clientes/{cliente.id}"
    return cliente


@router.put("/{cliente_id}", response_model=ClienteSaida, responses={**NAO_ENCONTRADO, **CONFLITO})
def atualizar(cliente_id: int, dados: ClienteEntrada, session: SessionDep) -> Cliente:
    cliente = buscar_cliente_ou_404(session, cliente_id)
    for campo, valor in dados.model_dump().items():
        setattr(cliente, campo, valor)
    salvar(session, cliente, DUPLICADOS)
    return cliente


@router.delete("/{cliente_id}", status_code=status.HTTP_204_NO_CONTENT, responses=NAO_ENCONTRADO)
def remover(cliente_id: int, session: SessionDep) -> None:
    cliente = buscar_cliente_ou_404(session, cliente_id)
    session.delete(cliente)
    session.commit()
