import logging
import time
from typing import Any

import httpx2
from fastapi import status
from prometheus_client import Histogram

from app.observabilidade import request_id

logger = logging.getLogger("vitrine.pedidos.integracoes")

# Quanto tempo cada vizinho leva e como terminou. É o que mostra, no Grafana,
# se a lentidão do pedidos vem dele mesmo ou de clientes/catalogo.
DURACAO_CHAMADA = Histogram(
    "integracao_duracao_segundos",
    "Duração das chamadas HTTP a outros serviços",
    ["servico", "resultado"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)


class FalhaIntegracao(Exception):
    """Outro serviço não conseguiu responder. Vira 503 (transitório) ou 502."""

    def __init__(self, servico: str, motivo: str, status_code: int) -> None:
        super().__init__(f"Serviço {servico} {motivo}")
        self.status_code = status_code


class ServicoExterno:
    def __init__(
        self,
        nome: str,
        base_url: str,
        api_key: str,
        timeout: float,
        transport: httpx2.BaseTransport | None = None,
    ) -> None:
        self.nome = nome
        self._http = httpx2.Client(
            base_url=base_url,
            headers={"X-API-Key": api_key},
            timeout=httpx2.Timeout(timeout, connect=min(timeout, 1.0)),
            # retries só repete falha de conexão: o pedido nem chegou ao outro
            # lado, então repetir não duplica nada
            transport=transport or httpx2.HTTPTransport(retries=2),
        )

    def buscar(self, caminho: str) -> dict[str, Any] | None:
        """GET que devolve o JSON, None para 404, ou levanta FalhaIntegracao."""
        inicio = time.perf_counter()
        resultado = "erro"
        try:
            resposta = self._get(caminho)
            if resposta.status_code == status.HTTP_200_OK:
                resultado = "ok"
                return resposta.json()
            if resposta.status_code == status.HTTP_404_NOT_FOUND:
                resultado = "nao_encontrado"
                return None
            resultado = f"http_{resposta.status_code}"
            if resposta.status_code >= 500:
                raise self._falha(
                    f"respondeu {resposta.status_code}", status.HTTP_503_SERVICE_UNAVAILABLE
                )
            # 401 ou 422 aqui é erro nosso (chave ou chamada errada), não do usuário
            raise self._falha(f"respondeu {resposta.status_code}", status.HTTP_502_BAD_GATEWAY)
        except httpx2.TimeoutException as erro:
            resultado = "timeout"
            raise self._falha(
                "não respondeu a tempo", status.HTTP_503_SERVICE_UNAVAILABLE
            ) from erro
        except httpx2.TransportError as erro:
            resultado = "fora_do_ar"
            raise self._falha("está fora do ar", status.HTTP_503_SERVICE_UNAVAILABLE) from erro
        finally:
            duracao = time.perf_counter() - inicio
            DURACAO_CHAMADA.labels(self.nome, resultado).observe(duracao)
            if resultado not in ("ok", "nao_encontrado"):
                logger.warning(
                    "chamada a %s falhou: %s",
                    self.nome,
                    resultado,
                    extra={
                        "upstream": self.nome,
                        "result": resultado,
                        "duration_ms": round(duracao * 1000, 1),
                    },
                )

    def _get(self, caminho: str) -> httpx2.Response:
        # repassa o request id para o log do outro serviço ter o mesmo id
        rid = request_id.get()
        return self._http.get(caminho, headers={"X-Request-ID": rid} if rid else None)

    def fechar(self) -> None:
        self._http.close()

    def _falha(self, motivo: str, status_code: int) -> FalhaIntegracao:
        return FalhaIntegracao(self.nome, motivo, status_code)
