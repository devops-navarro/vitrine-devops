from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request, status
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.deps import get_catalogo, get_clientes
from app.integracoes import FalhaIntegracao
from app.observabilidade import configurar_logs, observar
from app.observabilidade import router as infra
from app.routers import pedidos
from app.seguranca import exigir_api_key


@asynccontextmanager
async def ciclo_de_vida(_: FastAPI) -> AsyncIterator[None]:
    yield
    # fecha as conexões abertas com os outros serviços ao desligar
    for criado in (get_clientes, get_catalogo):
        if criado.cache_info().currsize:
            criado().fechar()


configurar_logs(get_settings().log_level)

app = FastAPI(
    title="Vitrine · pedidos",
    version="0.1.0",
    description="Pedidos de clientes, validados contra os serviços de clientes e catálogo.",
    lifespan=ciclo_de_vida,
)


@app.exception_handler(FalhaIntegracao)
def falha_integracao(_: Request, erro: FalhaIntegracao) -> JSONResponse:
    headers = (
        {"Retry-After": "5"} if erro.status_code == status.HTTP_503_SERVICE_UNAVAILABLE else {}
    )
    return JSONResponse({"detail": str(erro)}, status_code=erro.status_code, headers=headers)


app.middleware("http")(observar)
app.include_router(infra)

# Rotas de negócio exigem a chave. As de infraestrutura (/health, /ready e
# /metrics) ficam abertas para o orquestrador e o Prometheus.
protegido = [Depends(exigir_api_key)]
NAO_AUTENTICADO = {401: {"description": "API key ausente ou inválida"}}
app.include_router(pedidos.router, dependencies=protegido, responses=NAO_AUTENTICADO)
