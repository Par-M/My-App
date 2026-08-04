from pydantic_settings import BaseSettings
from pydantic_settings import SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    database_url: str
    jwt_secret: str
    gemini_api_key: str = ""

    google_client_id: str = ""

    enable_dev_auth: bool = False

    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = ""
    apns_key_path: str = ""
    apns_environment: str = "sandbox"


settings = Settings()
