from functools import lru_cache

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

MIN_TAMANHO_CHAVE = 32


class Settings(BaseSettings):
    """Configuração lida só de variáveis de ambiente, para rodar igual em qualquer lugar."""

    # Sem isso, um erro de validação imprime o valor recebido no log de
    # subida, incluindo senha e chave.
    model_config = SettingsConfigDict(extra="ignore", hide_input_in_errors=True)

    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_user: str
    postgres_password: SecretStr
    postgres_db: str
    log_level: str = "INFO"
    # Mais de uma chave, separadas por vírgula, permite rodízio sem parar
    # ninguém: entra a nova, os clientes migram, sai a antiga.
    api_keys: SecretStr

    @field_validator("api_keys")
    @classmethod
    def _chaves_fortes(cls, valor: SecretStr) -> SecretStr:
        chaves = [c.strip() for c in valor.get_secret_value().split(",") if c.strip()]
        if not chaves:
            raise ValueError("defina ao menos uma chave em API_KEYS")
        if any(len(c) < MIN_TAMANHO_CHAVE for c in chaves):
            raise ValueError(f"cada chave precisa de ao menos {MIN_TAMANHO_CHAVE} caracteres")
        return valor

    @property
    def chaves_validas(self) -> list[str]:
        return [c.strip() for c in self.api_keys.get_secret_value().split(",") if c.strip()]

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+psycopg://{self.postgres_user}:"
            f"{self.postgres_password.get_secret_value()}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
