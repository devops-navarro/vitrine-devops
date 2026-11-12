from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.deps import SessionDep, salvar
from app.models import Produto
from app.schemas import ProdutoEntrada, ProdutoSaida

router = APIRouter(prefix="/produtos", tags=["produtos"])

NAO_ENCONTRADO = {404: {"description": "Produto não encontrado"}}
CONFLITO = {409: {"description": "SKU já cadastrado"}}
DUPLICADOS = {"produto_sku_uk": "SKU já cadastrado"}


def _buscar_ou_404(session: Session, produto_id: int) -> Produto:
    produto = session.get(Produto, produto_id)
    if produto is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Produto não encontrado")
    return produto


@router.get("", response_model=list[ProdutoSaida])
def listar(
    session: SessionDep,
    ativo: Annotated[
        bool | None, Query(description="Filtra por situação. Vazio traz todos.")
    ] = None,
    # limite máximo para uma chamada nunca trazer a tabela inteira
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[Produto]:
    consulta = select(Produto).order_by(Produto.id).limit(limit).offset(offset)
    if ativo is not None:
        consulta = consulta.where(Produto.ativo == ativo)
    return list(session.scalars(consulta))


@router.get("/{produto_id}", response_model=ProdutoSaida, responses=NAO_ENCONTRADO)
def buscar(produto_id: int, session: SessionDep) -> Produto:
    # produto inativo continua legível: pedidos antigos precisam consultá-lo
    return _buscar_ou_404(session, produto_id)


@router.post(
    "", response_model=ProdutoSaida, status_code=status.HTTP_201_CREATED, responses=CONFLITO
)
def criar(dados: ProdutoEntrada, session: SessionDep, response: Response) -> Produto:
    produto = Produto(**dados.model_dump())
    session.add(produto)
    salvar(session, produto, DUPLICADOS)
    response.headers["Location"] = f"/produtos/{produto.id}"
    return produto


@router.put("/{produto_id}", response_model=ProdutoSaida, responses={**NAO_ENCONTRADO, **CONFLITO})
def atualizar(produto_id: int, dados: ProdutoEntrada, session: SessionDep) -> Produto:
    produto = _buscar_ou_404(session, produto_id)
    for campo, valor in dados.model_dump().items():
        setattr(produto, campo, valor)
    salvar(session, produto, DUPLICADOS)
    return produto


@router.delete("/{produto_id}", status_code=status.HTTP_204_NO_CONTENT, responses=NAO_ENCONTRADO)
def desativar(produto_id: int, session: SessionDep) -> None:
    """Desativa o produto. Ele some da venda, mas o histórico de pedidos continua válido."""
    produto = _buscar_ou_404(session, produto_id)
    produto.ativo = False
    session.commit()
