from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import Cliente
from app.schemas import ClienteEntrada, ClienteSaida

router = APIRouter(prefix="/clientes", tags=["clientes"])

SessionDep = Annotated[Session, Depends(get_session)]

NAO_ENCONTRADO = {404: {"description": "Cliente não encontrado"}}


def _buscar_ou_404(session: Session, cliente_id: int) -> Cliente:
    cliente = session.get(Cliente, cliente_id)
    if cliente is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Cliente não encontrado")
    return cliente


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


@router.post("", response_model=ClienteSaida, status_code=status.HTTP_201_CREATED)
def criar(dados: ClienteEntrada, session: SessionDep, response: Response) -> Cliente:
    cliente = Cliente(**dados.model_dump())
    session.add(cliente)
    session.commit()
    session.refresh(cliente)
    response.headers["Location"] = f"/clientes/{cliente.id}"
    return cliente


@router.put("/{cliente_id}", response_model=ClienteSaida, responses=NAO_ENCONTRADO)
def atualizar(cliente_id: int, dados: ClienteEntrada, session: SessionDep) -> Cliente:
    cliente = _buscar_ou_404(session, cliente_id)
    for campo, valor in dados.model_dump().items():
        setattr(cliente, campo, valor)
    session.commit()
    session.refresh(cliente)
    return cliente


@router.delete("/{cliente_id}", status_code=status.HTTP_204_NO_CONTENT, responses=NAO_ENCONTRADO)
def remover(cliente_id: int, session: SessionDep) -> None:
    cliente = _buscar_ou_404(session, cliente_id)
    session.delete(cliente)
    session.commit()
