import os
from typing import Any, Optional

import yaml
from dotenv import load_dotenv
from fastapi_mail import ConnectionConfig, FastMail
from pydantic_settings import BaseSettings

from .bow_config import BowConfig, generate_fernet_key
from .brand_config import BrandConfig


def _parse_bool(value: Optional[str]) -> Optional[bool]:
    if value is None:
        return None
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return None


def _resolve_env_vars(config: Any) -> Any:
    if isinstance(config, dict):
        return {k: _resolve_env_vars(v) for k, v in config.items()}
    if isinstance(config, list):
        return [_resolve_env_vars(i) for i in config]
    if isinstance(config, str) and config.startswith("${") and config.endswith("}"):
        env_var_name = config[2:-1]
        env_value = os.environ.get(env_var_name)
        if env_value:
            return env_value
        if env_var_name == "BOW_ENCRYPTION_KEY":
            new_key = generate_fernet_key()
            os.environ["BOW_ENCRYPTION_KEY"] = new_key
            return new_key
        return config
    return config


def _looks_like_unresolved_env_placeholder(value: Any) -> bool:
    return isinstance(value, str) and value.startswith("${") and value.endswith("}")


class Settings(BaseSettings):
    PROJECT_NAME: str = "Alfa Analyst"
    PROJECT_VERSION: str = open("../VERSION").read().strip()
    API_PREFIX: str = "/api"
    DEBUG: bool = True
    TESTING: bool = False
    TEST_DATABASE_URL: str = "sqlite:///db/test_{}.db".format(os.getpid())
    ENVIRONMENT: str = os.environ.get("ENVIRONMENT", "development")
    bow_config: BowConfig | None = None
    brand_config: BrandConfig | None = None
    email_client: FastMail | None = None

    @property
    def version(self) -> str:
        return self.PROJECT_VERSION

    @classmethod
    def load(cls):
        environment = os.environ.get("ENVIRONMENT", "development")
        print("Loading settings for environment:", environment)

        if environment == "development":
            dotenv_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
                ".env",
            )
            print(f"Loading .env from: {dotenv_path}")
            load_dotenv(dotenv_path)

        yaml_path = os.environ.get("BOW_CONFIG_PATH")
        if not yaml_path:
            yaml_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))),
                "configs/bow-config.dev.yaml" if environment == "development" else "bow-config.yaml",
            )

        print(f"Loading config from: {yaml_path}")

        with open(yaml_path, "r") as yaml_file:
            raw_yaml_config = yaml.safe_load(yaml_file) or {}
            resolved_yaml_config = _resolve_env_vars(raw_yaml_config)
            bow_config = BowConfig(**resolved_yaml_config)

        brand_config = BrandConfig.load()

        intercom_config = resolved_yaml_config.get("intercom", {}) if isinstance(resolved_yaml_config, dict) else {}
        telemetry_config = resolved_yaml_config.get("telemetry", {}) if isinstance(resolved_yaml_config, dict) else {}

        intercom_enabled = bool(intercom_config.get("enabled", brand_config.intercom.enabled))
        intercom_app_id = intercom_config.get("app_id", brand_config.intercom.app_id)
        if isinstance(intercom_app_id, str):
            if intercom_app_id.startswith("${"):
                intercom_app_id = None
            else:
                intercom_app_id = intercom_app_id.strip() or None

        telemetry_enabled = bool(telemetry_config.get("enabled", brand_config.telemetry.enabled))
        telemetry_provider = str(telemetry_config.get("provider", brand_config.telemetry.provider or "posthog")).strip().lower()
        telemetry_host = str(telemetry_config.get("host", brand_config.telemetry.host or "https://us.i.posthog.com")).strip()
        telemetry_api_key = telemetry_config.get("posthog_api_key")
        if telemetry_provider.startswith("${"):
            telemetry_provider = brand_config.telemetry.provider
        if telemetry_host.startswith("${"):
            telemetry_host = brand_config.telemetry.host
        if isinstance(telemetry_api_key, str) and telemetry_api_key.startswith("${"):
            telemetry_api_key = None

        env_intercom_enabled = _parse_bool(os.environ.get("BOW_INTERCOM_ENABLED"))
        if env_intercom_enabled is not None:
            intercom_enabled = env_intercom_enabled
        env_intercom_app_id = os.environ.get("BOW_INTERCOM_APP_ID")
        if env_intercom_app_id is not None:
            intercom_app_id = env_intercom_app_id.strip() or None

        env_telemetry_enabled = _parse_bool(os.environ.get("BOW_TELEMETRY_ENABLED"))
        if env_telemetry_enabled is not None:
            telemetry_enabled = env_telemetry_enabled
        env_telemetry_provider = os.environ.get("BOW_TELEMETRY_PROVIDER")
        if env_telemetry_provider:
            telemetry_provider = env_telemetry_provider.strip().lower()
        env_posthog_host = os.environ.get("BOW_POSTHOG_HOST")
        if env_posthog_host:
            telemetry_host = env_posthog_host.strip()
        env_posthog_api_key = os.environ.get("BOW_POSTHOG_API_KEY")
        if env_posthog_api_key is not None:
            telemetry_api_key = env_posthog_api_key.strip() or None

        bow_config.intercom.enabled = intercom_enabled
        bow_config.intercom.app_id = intercom_app_id
        bow_config.telemetry.enabled = telemetry_enabled
        bow_config.telemetry.provider = telemetry_provider or "posthog"
        bow_config.telemetry.host = telemetry_host or "https://us.i.posthog.com"
        bow_config.telemetry.posthog_api_key = telemetry_api_key

        brand_config.intercom.enabled = intercom_enabled
        brand_config.intercom.app_id = intercom_app_id
        brand_config.telemetry.enabled = telemetry_enabled
        brand_config.telemetry.provider = bow_config.telemetry.provider
        brand_config.telemetry.host = bow_config.telemetry.host

        if environment == "development":
            from .development import Development

            settings = Development(bow_config=bow_config, brand_config=brand_config)
        elif environment == "staging":
            from .staging import Staging

            settings = Staging(bow_config=bow_config, brand_config=brand_config)
        elif environment == "production":
            from .production import Production

            settings = Production(bow_config=bow_config, brand_config=brand_config)
        else:
            raise ValueError(f"Unknown environment: {environment}")

        settings.PROJECT_NAME = brand_config.product_name

        if bow_config.smtp_settings:
            smtp = bow_config.smtp_settings

            # Avoid crashing at import time when config contains unresolved ${ENV} placeholders.
            # This is particularly important for CI/tests where we don't want to require real SMTP secrets.
            if any(
                _looks_like_unresolved_env_placeholder(v)
                for v in (smtp.host, smtp.username, smtp.password, smtp.from_email)
            ):
                print("SMTP settings contain unresolved env placeholders; skipping email client init.")
            else:
                try:
                    email_config = ConnectionConfig(
                        MAIL_USERNAME=smtp.username,
                        MAIL_PASSWORD=smtp.password,
                        MAIL_FROM_NAME=smtp.from_name,
                        MAIL_FROM=smtp.from_email,
                        MAIL_PORT=smtp.port,
                        MAIL_SERVER=smtp.host,
                        MAIL_STARTTLS=smtp.use_tls,
                        MAIL_SSL_TLS=smtp.use_ssl,
                        USE_CREDENTIALS=smtp.use_credentials,
                        VALIDATE_CERTS=smtp.validate_certs,
                        TEMPLATE_FOLDER=None,
                    )
                    settings.email_client = FastMail(email_config)
                except Exception as e:
                    # Keep the app usable even if SMTP is misconfigured.
                    print(f"SMTP settings invalid; skipping email client init: {e}")

        return settings


settings = Settings.load()
