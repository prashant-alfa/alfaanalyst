import os
from typing import Any, Optional

import yaml
from pydantic import BaseModel, Field


def _resolve_env_vars(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _resolve_env_vars(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_resolve_env_vars(v) for v in value]
    if isinstance(value, str) and value.startswith("${") and value.endswith("}"):
        env_var_name = value[2:-1]
        return os.environ.get(env_var_name, value)
    return value


class BrandIntercom(BaseModel):
    enabled: bool = False
    app_id: Optional[str] = None


class BrandTelemetry(BaseModel):
    enabled: bool = False
    provider: str = "posthog"
    host: str = "https://us.i.posthog.com"


class BrandConfig(BaseModel):
    product_name: str = "Alfa Analyst"
    company_name: str = "Alfastack"
    primary_domain: str = "https://analyst.alfastack.cloud"
    docs_url: str = "https://analyst.alfastack.cloud/docs"
    terms_url: str = "https://analyst.alfastack.cloud/terms"
    privacy_url: str = "https://analyst.alfastack.cloud/privacy"
    mcp_server_display_name: str = "Alfa Analyst MCP Server"
    mcp_client_key_name: str = "alfastack"
    show_powered_by_default: bool = False
    intercom: BrandIntercom = Field(default_factory=BrandIntercom)
    telemetry: BrandTelemetry = Field(default_factory=BrandTelemetry)

    @classmethod
    def load(cls, path: Optional[str] = None) -> "BrandConfig":
        config_path = path or os.environ.get("BOW_BRAND_CONFIG_PATH")
        if not config_path:
            config_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))),
                "branding",
                "brand.config.yaml",
            )

        if not os.path.exists(config_path):
            return cls()

        with open(config_path, "r") as file:
            raw = yaml.safe_load(file) or {}

        return cls(**_resolve_env_vars(raw))
