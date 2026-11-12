from functools import lru_cache
from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db import get_session
from app.integracoes import ServicoExterno

SessionDep = Annotated[Session, Depends(get_session)]


# Um cliente HTTP por serviço, reaproveitado entre requisições: o pool de
# conexões evita abrir TCP (e TLS, em produção) a cada chamada.
@lru_cache
def get_clientes() -> ServicoExterno:
    cfg = get_settings()
    return ServicoExterno(
        "clientes",
        cfg.clientes_url,
        cfg.clientes_api_key.get_secret_value(),
        cfg.http_timeout_segundos,
    )


@lru_cache
def get_catalogo() -> ServicoExterno:
    cfg = get_settings()
    return ServicoExterno(
        "catalogo",
        cfg.catalogo_url,
        cfg.catalogo_api_key.get_secret_value(),
        cfg.http_timeout_segundos,
    )


ClientesDep = Annotated[ServicoExterno, Depends(get_clientes)]
CatalogoDep = Annotated[ServicoExterno, Depends(get_catalogo)]
