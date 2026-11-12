from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.deps import CatalogoDep, ClientesDep, SessionDep
from app.models import ItemPedido, Pedido
from app.schemas import PedidoEntrada, PedidoSaida

router = APIRouter(prefix="/pedidos", tags=["pedidos"])

NAO_ENCONTRADO = {404: {"description": "Pedido não encontrado"}}
INTEGRACAO = {
    502: {"description": "Outro serviço respondeu algo inesperado"},
    503: {"description": "Clientes ou catálogo fora do ar ou lento. Pode tentar de novo."},
}


def _buscar_ou_404(session: Session, pedido_id: int, *, travar: bool = False) -> Pedido:
    pedido = session.get(Pedido, pedido_id, with_for_update=travar)
    if pedido is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pedido não encontrado")
    return pedido


@router.get("", response_model=list[PedidoSaida])
def listar(
    session: SessionDep,
    cliente_id: Annotated[int | None, Query(gt=0)] = None,
    situacao: Annotated[Literal["criado", "cancelado"] | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[Pedido]:
    consulta = select(Pedido).order_by(Pedido.id).limit(limit).offset(offset)
    if cliente_id is not None:
        consulta = consulta.where(Pedido.cliente_id == cliente_id)
    if situacao is not None:
        consulta = consulta.where(Pedido.status == situacao)
    return list(session.scalars(consulta))


@router.get("/{pedido_id}", response_model=PedidoSaida, responses=NAO_ENCONTRADO)
def buscar(pedido_id: int, session: SessionDep) -> Pedido:
    return _buscar_ou_404(session, pedido_id)


@router.post(
    "",
    response_model=PedidoSaida,
    status_code=status.HTTP_201_CREATED,
    responses={422: {"description": "Dados inválidos, cliente ou produto inexistente"}}
    | INTEGRACAO,
)
def criar(
    dados: PedidoEntrada,
    session: SessionDep,
    clientes: ClientesDep,
    catalogo: CatalogoDep,
    response: Response,
) -> Pedido:
    # As chamadas HTTP vêm antes de qualquer acesso ao banco: nenhuma
    # transação fica aberta esperando a rede.
    if clientes.buscar(f"/clientes/{dados.cliente_id}") is None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, f"Cliente {dados.cliente_id} não encontrado"
        )

    problemas: list[str] = []
    itens: list[ItemPedido] = []
    for item in dados.itens:
        produto = catalogo.buscar(f"/produtos/{item.produto_id}")
        if produto is None:
            problemas.append(f"Produto {item.produto_id} não encontrado")
        elif not produto["ativo"]:
            problemas.append(f"Produto {item.produto_id} está inativo")
        else:
            itens.append(
                ItemPedido(
                    produto_id=item.produto_id,
                    sku=produto["sku"],
                    nome=produto["nome"],
                    preco_unitario_centavos=produto["preco_centavos"],
                    quantidade=item.quantidade,
                )
            )
    if problemas:
        # todos os problemas de uma vez, para não obrigar a corrigir um por tentativa
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "; ".join(problemas))

    pedido = Pedido(
        cliente_id=dados.cliente_id,
        total_centavos=sum(i.subtotal_centavos for i in itens),
        itens=itens,
    )
    session.add(pedido)
    session.commit()
    session.refresh(pedido)
    response.headers["Location"] = f"/pedidos/{pedido.id}"
    return pedido


@router.post(
    "/{pedido_id}/cancelar",
    response_model=PedidoSaida,
    responses=NAO_ENCONTRADO | {409: {"description": "Pedido já cancelado"}},
)
def cancelar(pedido_id: int, session: SessionDep) -> Pedido:
    # FOR UPDATE trava a linha: dois cancelamentos simultâneos não passam
    # juntos pela checagem de status
    pedido = _buscar_ou_404(session, pedido_id, travar=True)
    if pedido.status == "cancelado":
        session.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Pedido já está cancelado")
    pedido.status = "cancelado"
    session.commit()
    session.refresh(pedido)
    return pedido
