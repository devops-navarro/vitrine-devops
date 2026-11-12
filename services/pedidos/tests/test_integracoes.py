import socket
import time

import pytest

from app.integracoes import FalhaIntegracao, ServicoExterno


def _porta_fechada() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def test_servico_fora_do_ar_de_verdade_vira_503_rapido():
    # rede real, sem mock: ninguém escuta nesta porta
    servico = ServicoExterno("clientes", f"http://127.0.0.1:{_porta_fechada()}", "k", 1.0)
    inicio = time.monotonic()

    with pytest.raises(FalhaIntegracao, match="está fora do ar") as erro:
        servico.buscar("/clientes/1")

    assert erro.value.status_code == 503
    assert time.monotonic() - inicio < 2
    servico.fechar()


def test_servico_que_aceita_e_nao_responde_estoura_o_timeout():
    # aceita a conexão e nunca responde: só o timeout de leitura salva
    with socket.socket() as servidor:
        servidor.bind(("127.0.0.1", 0))
        servidor.listen()
        porta = servidor.getsockname()[1]
        servico = ServicoExterno("catalogo", f"http://127.0.0.1:{porta}", "k", 0.3)
        inicio = time.monotonic()

        with pytest.raises(FalhaIntegracao, match="não respondeu a tempo"):
            servico.buscar("/produtos/1")

        assert 0.3 <= time.monotonic() - inicio < 1.5
        servico.fechar()


def test_clientes_http_vem_da_configuracao():
    from app.deps import get_catalogo, get_clientes

    clientes, catalogo = get_clientes(), get_catalogo()

    assert str(clientes._http.base_url) == "http://clientes.invalid"
    assert str(catalogo._http.base_url) == "http://catalogo.invalid"
    assert clientes._http.headers["X-API-Key"] == "chave-entre-servicos"
    assert clientes._http.timeout.read == 3.0
    assert clientes._http.timeout.connect == 1.0
    # o mesmo objeto é reaproveitado entre requisições (pool de conexões)
    assert get_clientes() is clientes
