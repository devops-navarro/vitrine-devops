from fastapi import Depends, FastAPI

from app.config import get_settings
from app.observabilidade import configurar_logs, observar
from app.observabilidade import router as infra
from app.routers import produtos
from app.seguranca import exigir_api_key

configurar_logs(get_settings().log_level)

app = FastAPI(
    title="Vitrine · catálogo",
    version="0.1.0",
    description="Catálogo de produtos.",
)


app.middleware("http")(observar)
app.include_router(infra)

# Rotas de negócio exigem a chave. As de infraestrutura (/health, /ready e
# /metrics) ficam abertas para o orquestrador e o Prometheus.
protegido = [Depends(exigir_api_key)]
NAO_AUTENTICADO = {401: {"description": "API key ausente ou inválida"}}
app.include_router(produtos.router, dependencies=protegido, responses=NAO_AUTENTICADO)
