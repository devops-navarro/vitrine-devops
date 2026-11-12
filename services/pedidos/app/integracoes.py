from typing import Any

import httpx2
from fastapi import status


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
        try:
            resposta = self._http.get(caminho)
        except httpx2.TimeoutException as erro:
            raise self._falha(
                "não respondeu a tempo", status.HTTP_503_SERVICE_UNAVAILABLE
            ) from erro
        except httpx2.TransportError as erro:
            raise self._falha("está fora do ar", status.HTTP_503_SERVICE_UNAVAILABLE) from erro

        if resposta.status_code == status.HTTP_404_NOT_FOUND:
            return None
        if resposta.status_code >= 500:
            raise self._falha(
                f"respondeu {resposta.status_code}", status.HTTP_503_SERVICE_UNAVAILABLE
            )
        if resposta.status_code != status.HTTP_200_OK:
            # 401 ou 422 aqui é erro nosso (chave ou chamada errada), não do usuário
            raise self._falha(f"respondeu {resposta.status_code}", status.HTTP_502_BAD_GATEWAY)
        return resposta.json()

    def fechar(self) -> None:
        self._http.close()

    def _falha(self, motivo: str, status_code: int) -> FalhaIntegracao:
        return FalhaIntegracao(self.nome, motivo, status_code)
