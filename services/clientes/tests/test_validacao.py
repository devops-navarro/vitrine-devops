from typing import get_args

import pytest

from app.models import UFS
from app.schemas import Uf
from app.validacao import normalizar_cep, normalizar_cpf


@pytest.mark.parametrize(
    ("entrada", "esperado"),
    [
        ("52998224725", "52998224725"),
        ("529.982.247-25", "52998224725"),
        (" 111.444.777-35 ", "11144477735"),
        ("39053344705", "39053344705"),
        ("01234567890", "01234567890"),  # zero à esquerda é válido e precisa ser mantido
    ],
)
def test_cpf_valido_volta_so_com_digitos(entrada, esperado):
    assert normalizar_cpf(entrada) == esperado


@pytest.mark.parametrize(
    ("entrada", "mensagem"),
    [
        ("5299822472", "11 dígitos"),
        ("529982247250", "11 dígitos"),
        ("5299822472a", "11 dígitos"),
        ("", "11 dígitos"),
        ("11111111111", "CPF inválido"),
        ("00000000000", "CPF inválido"),
        ("52998224726", "dígito verificador"),  # último dígito errado
        ("52998224715", "dígito verificador"),  # penúltimo dígito errado
    ],
)
def test_cpf_invalido_explica_o_motivo(entrada, mensagem):
    with pytest.raises(ValueError, match=mensagem):
        normalizar_cpf(entrada)


@pytest.mark.parametrize("entrada", ["01310100", "01310-100", " 01310-100 "])
def test_cep_valido_volta_so_com_digitos(entrada):
    assert normalizar_cep(entrada) == "01310100"


@pytest.mark.parametrize("entrada", ["0131010", "013101000", "0131010a", ""])
def test_cep_invalido(entrada):
    with pytest.raises(ValueError, match="8 dígitos"):
        normalizar_cep(entrada)


def test_ufs_da_api_e_do_banco_sao_as_mesmas():
    # a lista existe no schema (OpenAPI) e no modelo (CHECK); este teste impede que divirjam
    assert set(get_args(Uf)) == set(UFS)
    assert len(UFS) == 27
