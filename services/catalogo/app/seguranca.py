import hmac
from typing import Annotated

from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

from app.config import get_settings

# auto_error=False para devolver 401 com mensagem nossa, e não o 403 padrão
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def exigir_api_key(chave: Annotated[str | None, Security(api_key_header)]) -> None:
    # compare_digest leva o mesmo tempo acertando ou errando, então a demora
    # da resposta não ajuda ninguém a descobrir a chave caractere por caractere
    if chave and any(
        hmac.compare_digest(chave.encode(), valida.encode())
        for valida in get_settings().chaves_validas
    ):
        return
    raise HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        "API key ausente ou inválida",
        headers={"WWW-Authenticate": "ApiKey"},
    )
