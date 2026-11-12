from typing import Annotated

from fastapi import Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_session

SessionDep = Annotated[Session, Depends(get_session)]


def salvar(session: Session, objeto: object, conflitos: dict[str, str]) -> None:
    """Faz o commit e traduz a constraint violada em 409.

    A regra de unicidade fica no banco, não num SELECT antes do INSERT:
    duas requisições simultâneas passariam juntas pela checagem.
    """
    try:
        session.commit()
    except IntegrityError as erro:
        session.rollback()
        constraint = getattr(getattr(erro.orig, "diag", None), "constraint_name", None)
        if constraint in conflitos:
            raise HTTPException(status.HTTP_409_CONFLICT, conflitos[constraint]) from erro
        raise
    session.refresh(objeto)
