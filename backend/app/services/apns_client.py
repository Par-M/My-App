import logging
import os
from datetime import datetime
from datetime import timedelta
from datetime import timezone

logger = logging.getLogger(__name__)


class APNsPushSender:
    """Real Apple Push Notification service transport.

    Requires an APNs provider authentication key (``.p8``) plus key id, team id
    and bundle id. The HTTP/2 call needs the ``h2`` package and JWT signing
    needs ``PyJWT``. Until those credentials/packages are available this sender
    logs the attempt and reports a failed delivery instead of crashing.
    """

    def __init__(
        self,
        *,
        key_id: str = "",
        team_id: str = "",
        bundle_id: str = "",
        key_path: str = "",
        environment: str = "sandbox",
    ) -> None:
        self.key_id = key_id
        self.team_id = team_id
        self.bundle_id = bundle_id
        self.key_path = key_path
        self.enabled = bool(
            key_id and team_id and bundle_id and key_path and os.path.isfile(key_path)
        )
        self.environment = environment

    def _provider_token(self) -> str | None:
        try:
            import jwt  # PyJWT
        except ImportError:
            logger.warning(
                "PyJWT is required for APNs; install it and set APNS_* settings."
            )
            return None
        try:
            now = int(datetime.now(timezone.utc).timestamp())
            headers = {"alg": "ES256", "kid": self.key_id}
            payload = {"iss": self.team_id, "iat": now, "exp": now + 3600}
            with open(self.key_path, "r", encoding="utf-8") as handle:
                key = handle.read()
            return jwt.encode(payload, key, algorithm="ES256", headers=headers)
        except Exception:  # pragma: no cover - defensive
            logger.exception("Failed to build APNs provider token")
            return None

    def send(self, *, token: str, title: str, body: str, data: dict) -> bool:
        if not self.enabled:
            logger.info(
                "APNs not configured (key/team/bundle/key_path missing); "
                "skipping push to %s",
                token[-8:],
            )
            return False
        provider_token = self._provider_token()
        if provider_token is None:
            return False
        host = (
            "https://api.sandbox.push.apple.com"
            if self.environment == "sandbox"
            else "https://api.push.apple.com"
        )
        url = f"{host}/3/device/{token}"
        headers = {
            "authorization": f"bearer {provider_token}",
            "apns-topic": self.bundle_id,
            "apns-push-type": "alert",
        }
        payload = {
            "aps": {"alert": {"title": title, "body": body}},
            "data": data,
        }
        try:
            import httpx

            with httpx.Client(http2=True, timeout=10.0) as client:
                response = client.post(url, json=payload, headers=headers)
            return 200 <= response.status_code < 300
        except ImportError:
            logger.warning(
                "The 'h2' package is required for APNs HTTP/2; skipping push."
            )
            return False
        except Exception:  # pragma: no cover - defensive
            logger.exception("APNs send failed")
            return False
