from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import Cliente
from app.schemas import ClienteEntrada, ClienteSaida

router = APIRouter(prefix="/clientes", tags=["clientes"])

SessionDep = Annotated[Session, Depends(get_session)]

NAO_ENCONTRADO = {404: {"description": "Cliente não encontrado"}}
CONFLITO = {409: {"description": "CPF ou e-mail já cadastrado"}}

# A unicidade é garantida pelo banco, não por um SELECT antes do INSERT:
# duas requisições simultâneas passariam juntas pela checagem. Aqui só
# traduzimos a constraint violada em uma resposta clara.
DUPLICADOS = {
    "cliente_cpf_uk": "CPF já cadastrado",
    "cliente_email_uk": "E-mail já cadastrado",
}


def _buscar_ou_404(session: Session, cliente_id: int) -> Cliente:
    cliente = session.get(Cliente, cliente_id)
    if cliente is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Cliente não encontrado")
    return cliente


def _salvar(session: Session, cliente: Cliente) -> None:
    try:
        session.commit()
    except IntegrityError as erro:
        session.rollback()
        constraint = getattr(getattr(erro.orig, "diag", None), "constraint_name", None)
        if constraint in DUPLICADOS:
            raise HTTPException(status.HTTP_409_CONFLICT, DUPLICADOS[constraint]) from erro
        raise
    session.refresh(cliente)


@router.get("", response_model=list[ClienteSaida])
def listar(
    session: SessionDep,
    # limite máximo para uma chamada nunca trazer a tabela inteira
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[Cliente]:
    consulta = select(Cliente).order_by(Cliente.id).limit(limit).offset(offset)
    return list(session.scalars(consulta))


@router.get("/{cliente_id}", response_model=ClienteSaida, responses=NAO_ENCONTRADO)
def buscar(cliente_id: int, session: SessionDep) -> Cliente:
    return _buscar_ou_404(session, cliente_id)


@router.post(
    "", response_model=ClienteSaida, status_code=status.HTTP_201_CREATED, responses=CONFLITO
)
def criar(dados: ClienteEntrada, session: SessionDep, response: Response) -> Cliente:
    cliente = Cliente(**dados.model_dump())
    session.add(cliente)
    _salvar(session, cliente)
    response.headers["Location"] = f"/clientes/{cliente.id}"
    return cliente


@router.put("/{cliente_id}", response_model=ClienteSaida, responses={**NAO_ENCONTRADO, **CONFLITO})
def atualizar(cliente_id: int, dados: ClienteEntrada, session: SessionDep) -> Cliente:
    cliente = _buscar_ou_404(session, cliente_id)
    for campo, valor in dados.model_dump().items():
        setattr(cliente, campo, valor)
    _salvar(session, cliente)
    return cliente


@router.delete("/{cliente_id}", status_code=status.HTTP_204_NO_CONTENT, responses=NAO_ENCONTRADO)
def remover(cliente_id: int, session: SessionDep) -> None:
    cliente = _buscar_ou_404(session, cliente_id)
    session.delete(cliente)
    session.commit()
