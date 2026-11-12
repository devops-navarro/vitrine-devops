from fastapi import Depends, FastAPI

from app.routers import produtos
from app.seguranca import exigir_api_key

app = FastAPI(
    title="Vitrine · catálogo",
    version="0.1.0",
    description="Catálogo de produtos.",
)


@app.get("/health", tags=["infra"])
def health() -> dict[str, str]:
    return {"status": "ok"}


# Rotas de negócio exigem a chave. As de infraestrutura (/health e, depois,
# /ready e /metrics) ficam abertas para o orquestrador e o Prometheus.
protegido = [Depends(exigir_api_key)]
NAO_AUTENTICADO = {401: {"description": "API key ausente ou inválida"}}
app.include_router(produtos.router, dependencies=protegido, responses=NAO_AUTENTICADO)
