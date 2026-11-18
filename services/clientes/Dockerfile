# Imagem provisória para o docker compose. Na Fase 4 ganha scan, assinatura e digest fixo.

FROM ghcr.io/astral-sh/uv:0.13.7 AS uv

FROM python:3.12.16-slim-bookworm AS build
COPY --from=uv /uv /usr/local/bin/uv
# bytecode compilado no build, para o container não compilar a cada partida
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
# dependências antes do código: mudar só o código reaproveita esta camada do cache
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev --no-install-project
COPY alembic.ini ./
COPY migrations ./migrations
COPY app ./app

FROM python:3.12.16-slim-bookworm
RUN useradd --system --uid 10001 --no-create-home app
WORKDIR /app
# arquivos do root e só leitura para o processo: ele não altera o próprio código
COPY --from=build /app /app
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER 10001
EXPOSE 8000
# forma de lista: o uvicorn é o PID 1 e recebe o SIGTERM para desligar com calma
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
