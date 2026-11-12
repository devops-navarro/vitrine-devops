"""Health, readiness, métricas Prometheus e logs em JSON.

Igual nos três serviços (ver ADR 0001: código copiado, não compartilhado).
"""

import json
import logging
import re
import sys
import time
import uuid
from collections.abc import Awaitable, Callable
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request, Response, status
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from sqlalchemy import Engine, text
from sqlalchemy.exc import SQLAlchemyError

from app.db import SCHEMA, get_engine

SERVICO = SCHEMA

# --- request id -------------------------------------------------------------

request_id: ContextVar[str | None] = ContextVar("request_id", default=None)

# Aceito o id de quem chamou para seguir a mesma requisição entre serviços,
# mas só num formato seguro: um valor livre permitiria forjar linhas de log.
_REQUEST_ID_VALIDO = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _request_id_de(request: Request) -> str:
    recebido = request.headers.get("X-Request-ID", "")
    return recebido if _REQUEST_ID_VALIDO.match(recebido) else uuid.uuid4().hex


# --- logs -------------------------------------------------------------------

_CAMPOS_DO_LOGGING = set(vars(logging.LogRecord("", 0, "", 0, "", None, None))) | {
    "message",
    "asctime",
    "request_id",
}
_fabrica_original = logging.getLogRecordFactory()


def _registro_com_request_id(*args: Any, **kwargs: Any) -> logging.LogRecord:
    # gravado na criação do registro, enquanto a requisição ainda está ativa
    registro = _fabrica_original(*args, **kwargs)
    registro.request_id = request_id.get()
    return registro


class FormatadorJson(logging.Formatter):
    """Uma linha JSON por evento. Chaves em inglês, como Loki e CloudWatch esperam."""

    def format(self, record: logging.LogRecord) -> str:
        dados: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(
                timespec="milliseconds"
            ),
            "level": record.levelname,
            "service": SERVICO,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if getattr(record, "request_id", None):
            dados["request_id"] = record.request_id
        dados.update({k: v for k, v in vars(record).items() if k not in _CAMPOS_DO_LOGGING})
        if record.exc_info:
            dados["exception"] = self.formatException(record.exc_info)
        return json.dumps(dados, ensure_ascii=False, default=str)


def configurar_logs(nivel: str) -> None:
    logging.setLogRecordFactory(_registro_com_request_id)
    saida = logging.StreamHandler(sys.stdout)
    saida.setFormatter(FormatadorJson())
    raiz = logging.getLogger()
    raiz.handlers = [saida]
    raiz.setLevel(nivel.upper())
    # Os logs do uvicorn passam pelo mesmo formato. O de acesso dele é
    # desligado porque o middleware abaixo registra cada requisição com mais dados.
    for nome in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(nome).handlers = []
        logging.getLogger(nome).propagate = True
    logging.getLogger("uvicorn.access").disabled = True
    # o cliente HTTP registra cada chamada em INFO; a métrica e o log de
    # acesso do outro serviço já contam essa história
    logging.getLogger("httpx2").setLevel(logging.WARNING)


log_acesso = logging.getLogger(f"vitrine.{SERVICO}.acesso")

# --- métricas ---------------------------------------------------------------

REQUISICOES = Counter(
    "http_requests_total", "Requisições HTTP atendidas", ["method", "route", "status"]
)
DURACAO = Histogram(
    "http_request_duration_seconds",
    "Duração das requisições HTTP",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)

# Probes do Kubernetes e scrape do Prometheus chegam a cada poucos segundos:
# contam nas métricas, mas não poluem o log em nível INFO.
_ROTAS_DE_INFRA = {"/health", "/ready", "/metrics"}


def _rota(request: Request) -> str:
    # O modelo da rota (/clientes/{cliente_id}) e nunca o caminho real:
    # um rótulo por id criaria uma série nova no Prometheus a cada cliente.
    rota = request.scope.get("route")
    return getattr(rota, "path", "nao_mapeada")


async def observar(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    rid = _request_id_de(request)
    token = request_id.set(rid)
    inicio = time.perf_counter()
    codigo = status.HTTP_500_INTERNAL_SERVER_ERROR
    try:
        resposta = await call_next(request)
        codigo = resposta.status_code
        resposta.headers["X-Request-ID"] = rid
        return resposta
    finally:
        duracao = time.perf_counter() - inicio
        rota = _rota(request)
        REQUISICOES.labels(request.method, rota, str(codigo)).inc()
        DURACAO.labels(request.method, rota).observe(duracao)
        if codigo >= 500:
            nivel = logging.ERROR
        elif rota in _ROTAS_DE_INFRA:
            nivel = logging.DEBUG
        else:
            nivel = logging.INFO
        log_acesso.log(
            nivel,
            "%s %s %s",
            request.method,
            rota,
            codigo,
            extra={
                "method": request.method,
                "route": rota,
                "status": codigo,
                "duration_ms": round(duracao * 1000, 1),
            },
        )
        request_id.reset(token)


# --- rotas de infraestrutura -----------------------------------------------

router = APIRouter(tags=["infra"])


@router.get("/health")
def health() -> dict[str, str]:
    """Liveness: o processo está de pé. Não olha o banco, de propósito."""
    return {"status": "ok"}


@router.get("/ready", responses={503: {"description": "Banco indisponível"}})
def ready(response: Response, engine: Annotated[Engine, Depends(get_engine)]) -> dict:
    """Readiness: pronto para receber tráfego, ou seja, o banco responde."""
    try:
        with engine.connect() as conexao:
            conexao.execute(text("SELECT 1"))
    except SQLAlchemyError:
        logging.getLogger(f"vitrine.{SERVICO}").warning("readiness: banco indisponível")
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "indisponivel", "checks": {"banco": "falhou"}}
    return {"status": "ok", "checks": {"banco": "ok"}}


@router.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
