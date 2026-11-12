from fastapi import FastAPI

app = FastAPI(
    title="Vitrine · clientes",
    version="0.1.0",
    description="Cadastro de clientes e endereços.",
)


@app.get("/health", tags=["infra"])
def health() -> dict[str, str]:
    return {"status": "ok"}
