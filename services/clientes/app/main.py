from fastapi import Depends, FastAPI

from app.config import get_settings
from app.observabilidade import configurar_logs, observar
from app.observabilidade import router as infra
from app.routers import clientes, enderecos
from app.seguranca import exigir_api_key

configurar_logs(get_settings().log_level)

app = FastAPI(
    title="Vitrine · clientes",
    version="0.1.0",
    description="Cadastro de clientes e endereços.",
)


app.middleware("http")(observar)
app.include_router(infra)

# Rotas de negócio exigem a chave. As de infraestrutura (/health, /ready e
# /metrics) ficam abertas para o orquestrador e o Prometheus.
protegido = [Depends(exigir_api_key)]
NAO_AUTENTICADO = {401: {"description": "API key ausente ou inválida"}}
app.include_router(clientes.router, dependencies=protegido, responses=NAO_AUTENTICADO)
app.include_router(enderecos.router, dependencies=protegido, responses=NAO_AUTENTICADO)
