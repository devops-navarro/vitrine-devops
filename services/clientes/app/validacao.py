import re


def _digito(base: str) -> str:
    # pesos decrescentes a partir de len(base) + 1, regra da Receita Federal
    soma = sum(int(d) * peso for d, peso in zip(base, range(len(base) + 1, 1, -1), strict=True))
    resto = soma * 10 % 11
    return "0" if resto == 10 else str(resto)


def normalizar_cpf(valor: str) -> str:
    """Aceita com ou sem máscara e devolve só os 11 dígitos, ou levanta ValueError."""
    digitos = re.sub(r"[.\-\s]", "", valor)
    if not re.fullmatch(r"[0-9]{11}", digitos):
        raise ValueError("CPF deve ter 11 dígitos")
    # 111.111.111-11 passa no cálculo, mas a Receita não emite
    if digitos == digitos[0] * 11:
        raise ValueError("CPF inválido")
    if digitos[9] != _digito(digitos[:9]) or digitos[10] != _digito(digitos[:10]):
        raise ValueError("CPF inválido: dígito verificador não confere")
    return digitos


def normalizar_cep(valor: str) -> str:
    digitos = re.sub(r"[.\-\s]", "", valor)
    if not re.fullmatch(r"[0-9]{8}", digitos):
        raise ValueError("CEP deve ter 8 dígitos")
    return digitos
