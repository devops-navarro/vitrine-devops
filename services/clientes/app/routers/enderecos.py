from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import exists, select, update
from sqlalchemy.orm import Session

from app.deps import SessionDep, buscar_cliente_ou_404, salvar
from app.models import Endereco
from app.schemas import EnderecoEntrada, EnderecoSaida

router = APIRouter(prefix="/clientes/{cliente_id}/enderecos", tags=["endereços"])

NAO_ENCONTRADO = {404: {"description": "Cliente ou endereço não encontrado"}}
CONFLITOS = {"endereco_principal_uk": "O cliente já tem um endereço principal"}


def _buscar_ou_404(session: Session, cliente_id: int, endereco_id: int) -> Endereco:
    # filtrar pelo cliente impede ler o endereço de outro cliente trocando só o id
    endereco = session.scalar(
        select(Endereco).where(Endereco.id == endereco_id, Endereco.cliente_id == cliente_id)
    )
    if endereco is None:
        buscar_cliente_ou_404(session, cliente_id)
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Endereço não encontrado")
    return endereco


def _desmarcar_principal(session: Session, cliente_id: int, exceto_id: int | None = None) -> None:
    # Roda antes de alterar o objeto na sessão: assim o banco nunca vê dois
    # principais ao mesmo tempo, independente de quando o ORM faz o flush.
    consulta = update(Endereco).where(Endereco.cliente_id == cliente_id, Endereco.principal)
    if exceto_id is not None:
        consulta = consulta.where(Endereco.id != exceto_id)
    session.execute(consulta.values(principal=False))


@router.get("", response_model=list[EnderecoSaida], responses=NAO_ENCONTRADO)
def listar(cliente_id: int, session: SessionDep) -> list[Endereco]:
    buscar_cliente_ou_404(session, cliente_id)
    consulta = (
        select(Endereco)
        .where(Endereco.cliente_id == cliente_id)
        .order_by(Endereco.principal.desc(), Endereco.id)
    )
    return list(session.scalars(consulta))


@router.get("/{endereco_id}", response_model=EnderecoSaida, responses=NAO_ENCONTRADO)
def buscar(cliente_id: int, endereco_id: int, session: SessionDep) -> Endereco:
    return _buscar_ou_404(session, cliente_id, endereco_id)


@router.post(
    "",
    response_model=EnderecoSaida,
    status_code=status.HTTP_201_CREATED,
    responses=NAO_ENCONTRADO,
)
def criar(
    cliente_id: int, dados: EnderecoEntrada, session: SessionDep, response: Response
) -> Endereco:
    buscar_cliente_ou_404(session, cliente_id)
    endereco = Endereco(cliente_id=cliente_id, **dados.model_dump())
    # o primeiro endereço do cliente vira o principal, para sempre existir um padrão
    tem_endereco = session.scalar(select(exists().where(Endereco.cliente_id == cliente_id)))
    if not tem_endereco:
        endereco.principal = True
    elif endereco.principal:
        _desmarcar_principal(session, cliente_id)
    session.add(endereco)
    salvar(session, endereco, CONFLITOS)
    response.headers["Location"] = f"/clientes/{cliente_id}/enderecos/{endereco.id}"
    return endereco


@router.put("/{endereco_id}", response_model=EnderecoSaida, responses=NAO_ENCONTRADO)
def atualizar(
    cliente_id: int, endereco_id: int, dados: EnderecoEntrada, session: SessionDep
) -> Endereco:
    endereco = _buscar_ou_404(session, cliente_id, endereco_id)
    if dados.principal:
        _desmarcar_principal(session, cliente_id, exceto_id=endereco_id)
    for campo, valor in dados.model_dump().items():
        setattr(endereco, campo, valor)
    salvar(session, endereco, CONFLITOS)
    return endereco


@router.delete("/{endereco_id}", status_code=status.HTTP_204_NO_CONTENT, responses=NAO_ENCONTRADO)
def remover(cliente_id: int, endereco_id: int, session: SessionDep) -> None:
    endereco = _buscar_ou_404(session, cliente_id, endereco_id)
    session.delete(endereco)
    session.commit()
