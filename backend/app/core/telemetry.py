import asyncio
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from typing import Any, Mapping, Optional

from app.settings.config import settings


logger = logging.getLogger(__name__)

try:
    from posthog import Posthog  # type: ignore
except Exception:  # pragma: no cover - safe import guard
    Posthog = None  # type: ignore

_DEFAULT_POSTHOG_HOST = "https://us.i.posthog.com"
_telemetry_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="telemetry")


def _parse_bool(value: Optional[str]) -> Optional[bool]:
    if value is None:
        return None
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return None


def _resolve_runtime_config() -> dict:
    telemetry_cfg = getattr(settings.bow_config, "telemetry", None)
    enabled = bool(getattr(telemetry_cfg, "enabled", False))
    provider = str(getattr(telemetry_cfg, "provider", "posthog") or "posthog").strip().lower()
    host = str(getattr(telemetry_cfg, "host", _DEFAULT_POSTHOG_HOST) or _DEFAULT_POSTHOG_HOST).strip()
    api_key = getattr(telemetry_cfg, "posthog_api_key", None)

    env_enabled = _parse_bool(os.getenv("BOW_TELEMETRY_ENABLED"))
    if env_enabled is not None:
        enabled = env_enabled

    env_provider = os.getenv("BOW_TELEMETRY_PROVIDER")
    if env_provider:
        provider = env_provider.strip().lower()

    env_host = os.getenv("BOW_POSTHOG_HOST")
    if env_host:
        host = env_host.strip()

    env_api_key = os.getenv("BOW_POSTHOG_API_KEY")
    if env_api_key is not None:
        api_key = env_api_key.strip() or None

    if settings.TESTING:
        enabled = False

    if enabled and provider != "posthog":
        logger.warning("Telemetry provider '%s' is not supported. Disabling telemetry.", provider)
        enabled = False

    if enabled and not api_key:
        logger.warning("Telemetry is enabled but BOW_POSTHOG_API_KEY is missing. Disabling telemetry.")
        enabled = False

    return {
        "enabled": enabled,
        "provider": provider,
        "host": host or _DEFAULT_POSTHOG_HOST,
        "api_key": api_key,
    }


def _init_posthog_client(runtime: dict):
    if not runtime["enabled"]:
        return None
    if Posthog is None:
        logger.warning("Telemetry is enabled but posthog package is unavailable. Disabling telemetry.")
        return None
    try:
        return Posthog(runtime["api_key"], host=runtime["host"])
    except Exception:
        logger.exception("Failed to initialize PostHog client")
        return None


_telemetry_runtime = _resolve_runtime_config()
_posthog = _init_posthog_client(_telemetry_runtime)


def _do_capture(
    distinct_id: str,
    event: str,
    properties: dict,
    timestamp: Optional[datetime],
    groups: Optional[dict],
) -> None:
    try:
        _posthog.capture(
            distinct_id=distinct_id,
            event=event,
            properties=properties,
            timestamp=timestamp,
            groups=groups,
        )
    except Exception:
        logger.exception("telemetry._do_capture failed")


def _do_identify(distinct_id: str, properties: dict) -> None:
    try:
        _posthog.identify(distinct_id=distinct_id, properties=properties)
    except Exception:
        logger.exception("telemetry._do_identify failed")


class Telemetry:
    """Minimal server-side telemetry helper backed by PostHog."""

    @staticmethod
    def _enabled() -> bool:
        return bool(_telemetry_runtime["enabled"] and _posthog is not None)

    @classmethod
    async def capture(
        cls,
        event: str,
        properties: Optional[Mapping[str, Any]] = None,
        user_id: Optional[str] = None,
        org_id: Optional[str] = None,
        occurred_at: Optional[datetime] = None,
    ) -> None:
        if not cls._enabled():
            return
        try:
            props = dict(properties or {})
            if org_id is not None:
                props["org_id"] = str(org_id)

            loop = asyncio.get_running_loop()
            loop.run_in_executor(
                _telemetry_executor,
                _do_capture,
                str(user_id or "anonymous"),
                event,
                props,
                occurred_at,
                {"organization": str(org_id)} if org_id else None,
            )
        except Exception:
            logger.exception("telemetry.capture failed")

    @classmethod
    async def identify(
        cls,
        user_id: str,
        traits: Optional[Mapping[str, Any]] = None,
    ) -> None:
        if not cls._enabled():
            return
        try:
            loop = asyncio.get_running_loop()
            loop.run_in_executor(
                _telemetry_executor,
                _do_identify,
                str(user_id),
                dict(traits or {}),
            )
        except Exception:
            logger.exception("telemetry.identify failed")


telemetry = Telemetry
