from __future__ import annotations

import html
import json
import os
import secrets
import time
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx
import jwt
from fastapi import Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi_sso.sso.google import GoogleSSO

BASE_DIR = Path(__file__).resolve().parent
SUPPORTED_SSO_PLATFORMS = ("google", "apple")
SUPPORTED_SSO_OPERATIONS = ("login", "register")
APPLE_AUTH_URL = "https://appleid.apple.com/auth/authorize"
APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"


def _read_sso_config() -> dict[str, Any]:
    config_path = BASE_DIR / "jac.toml"
    if not config_path.exists():
        return {}
    with config_path.open("rb") as config_file:
        raw = tomllib.load(config_file)
    plugins = raw.get("plugins", {}) or {}
    scale = plugins.get("scale", {}) or {}
    return scale.get("sso", {}) or {}


def _read_scale_config() -> dict[str, Any]:
    config_path = BASE_DIR / "jac.toml"
    if not config_path.exists():
        return {}
    with config_path.open("rb") as config_file:
        raw = tomllib.load(config_file)
    plugins = raw.get("plugins", {}) or {}
    return plugins.get("scale", {}) or {}


def _normalized_text(raw: Any) -> str:
    return str(raw or "").strip()


def _env_or_config(env_key: str, config_value: Any = "", default: str = "") -> str:
    env_value = _normalized_text(os.getenv(env_key))
    if env_value:
        return env_value
    config_text = _normalized_text(config_value)
    if config_text:
        return config_text
    return default


def _bool_env(name: str, default: bool = True) -> bool:
    raw = _normalized_text(os.getenv(name))
    if not raw:
        return default
    return raw.lower() not in {"0", "false", "no", "off"}


def get_jwt_settings() -> dict[str, Any]:
    config = _read_scale_config()
    jwt_config = config.get("jwt", {}) or {}
    return {
        "secret": _env_or_config("JWT_SECRET", jwt_config.get("secret"), "supersecretkey_for_testing_only!"),
        "algorithm": _env_or_config("JWT_ALGORITHM", jwt_config.get("algorithm"), "HS256"),
        "exp_delta_days": int(_env_or_config("JWT_EXP_DELTA_DAYS", jwt_config.get("exp_delta_days"), "7")),
    }


def create_app_jwt(username: str) -> str:
    settings = get_jwt_settings()
    now = int(time.time())
    payload = {
        "username": username,
        "exp": now + (settings["exp_delta_days"] * 24 * 60 * 60),
        "iat": now,
    }
    return jwt.encode(payload, settings["secret"], algorithm=settings["algorithm"])


def validate_app_jwt(token: str) -> str | None:
    settings = get_jwt_settings()
    try:
        payload = jwt.decode(token, settings["secret"], algorithms=[settings["algorithm"]])
    except Exception:
        return None
    return _normalized_text(payload.get("username")) or None


def refresh_app_jwt(token: str) -> str | None:
    username = validate_app_jwt(token)
    if not username:
        return None
    return create_app_jwt(username)


def _cookie_name() -> str:
    return _env_or_config("CALORECEIPT_AUTH_COOKIE_NAME", default="caloreceipt_session")


def _cookie_same_site() -> str:
    return _env_or_config("CALORECEIPT_AUTH_COOKIE_SAMESITE", default="Lax")


def _cookie_max_age() -> int:
    raw = _env_or_config("CALORECEIPT_AUTH_COOKIE_MAX_AGE", default="2592000")
    try:
        return max(0, int(raw))
    except Exception:
        return 2592000


def _cookie_secure_for_request(request: Request | None) -> bool:
    configured = _bool_env("CALORECEIPT_AUTH_COOKIE_SECURE", True)
    if request is None:
        return configured
    if request.url.scheme != "https":
        return False
    return configured


def get_sso_settings() -> dict[str, Any]:
    config = _read_sso_config()
    host = _env_or_config("SSO_HOST", config.get("host"), "http://127.0.0.1:8000/sso")
    google_config = config.get("google", {}) or {}
    apple_config = config.get("apple", {}) or {}
    private_key = _env_or_config("SSO_APPLE_PRIVATE_KEY", apple_config.get("private_key"))
    if private_key:
        private_key = private_key.replace("\\n", "\n")
    return {
        "host": host.rstrip("/"),
        "google": {
            "client_id": _env_or_config("SSO_GOOGLE_CLIENT_ID", google_config.get("client_id")),
            "client_secret": _env_or_config("SSO_GOOGLE_CLIENT_SECRET", google_config.get("client_secret")),
        },
        "apple": {
            "client_id": _env_or_config("SSO_APPLE_CLIENT_ID", apple_config.get("client_id")),
            "client_secret": _env_or_config("SSO_APPLE_CLIENT_SECRET", apple_config.get("client_secret")),
            "team_id": _env_or_config("SSO_APPLE_TEAM_ID", apple_config.get("team_id")),
            "key_id": _env_or_config("SSO_APPLE_KEY_ID", apple_config.get("key_id")),
            "private_key_path": _env_or_config("SSO_APPLE_PRIVATE_KEY_PATH", apple_config.get("private_key_path")),
            "private_key": private_key,
        },
    }


def get_sso_redirect_uri(platform: str, operation: str) -> str:
    settings = get_sso_settings()
    host = _normalized_text(settings.get("host"))
    if not host:
        return ""
    return f"{host}/{platform}/{operation}/callback"


def _apple_client_secret_available(config: dict[str, Any]) -> bool:
    if _normalized_text(config.get("client_secret")):
        return True
    if (
        _normalized_text(config.get("client_id"))
        and _normalized_text(config.get("team_id"))
        and _normalized_text(config.get("key_id"))
        and (
            _normalized_text(config.get("private_key"))
            or _normalized_text(config.get("private_key_path"))
        )
    ):
        return True
    return False


def get_enabled_platforms() -> dict[str, dict[str, Any]]:
    settings = get_sso_settings()
    enabled: dict[str, dict[str, Any]] = {}
    google = settings.get("google", {})
    if _normalized_text(google.get("client_id")) and _normalized_text(google.get("client_secret")):
        enabled["google"] = google
    apple = settings.get("apple", {})
    if _normalized_text(apple.get("client_id")) and _apple_client_secret_available(apple):
        enabled["apple"] = apple
    return enabled


def get_provider_manifest() -> dict[str, Any]:
    enabled = get_enabled_platforms()
    providers = {}
    for platform in SUPPORTED_SSO_PLATFORMS:
        providers[platform] = {
            "configured": platform in enabled,
            "login_path": f"/sso/{platform}/login",
            "register_path": f"/sso/{platform}/register",
        }
    return {"providers": providers}


def _build_auth_cookie(token: str, request: Request | None = None) -> dict[str, Any]:
    return {
        "key": _cookie_name(),
        "value": token,
        "httponly": True,
        "max_age": _cookie_max_age(),
        "path": "/",
        "samesite": _cookie_same_site(),
        "secure": _cookie_secure_for_request(request),
    }


def _build_status_page(title: str, message: str, status_code: int = 200) -> HTMLResponse:
    body = f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{html.escape(title)}</title>
    <style>
      body {{
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%);
        font-family: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;
        color: #10243f;
        padding: 24px;
      }}
      .card {{
        width: min(560px, 100%);
        background: rgba(255, 255, 255, 0.92);
        border: 1px solid #d2e3f5;
        border-radius: 18px;
        padding: 22px;
        display: grid;
        gap: 14px;
      }}
      a {{
        color: #10243f;
        font-weight: 700;
      }}
    </style>
  </head>
  <body>
    <div class="card">
      <h1 style="margin:0;font-size:1.8rem;">{html.escape(title)}</h1>
      <p style="margin:0;line-height:1.5;">{html.escape(message)}</p>
      <a href="/">Return to CaloReceipt</a>
    </div>
  </body>
</html>"""
    return HTMLResponse(content=body, status_code=status_code)


def build_sso_error_response(message: str, status_code: int = 400) -> HTMLResponse:
    return _build_status_page("Sign-In Error", message, status_code)


def build_sso_success_response(
    token: str,
    email: str,
    status_text: str,
    display_name: str,
    request: Request | None = None,
) -> HTMLResponse:
    payload = {
        "token": token,
        "email": email,
        "status": status_text,
        "display_name": display_name,
    }
    payload_json = json.dumps(payload)
    body = f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Signing You In</title>
    <style>
      body {{
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%);
        font-family: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;
        color: #10243f;
        padding: 24px;
      }}
      .card {{
        width: min(560px, 100%);
        background: rgba(255, 255, 255, 0.92);
        border: 1px solid #d2e3f5;
        border-radius: 18px;
        padding: 22px;
        display: grid;
        gap: 14px;
      }}
    </style>
  </head>
  <body>
    <div class="card">
      <h1 style="margin:0;font-size:1.8rem;">Signing You In</h1>
      <p style="margin:0;line-height:1.5;">Returning to your CaloReceipt workspace.</p>
    </div>
    <script>
      const payload = {payload_json};
      try {{
        localStorage.setItem("jac_token", payload.token);
        localStorage.setItem("caloreceipt:auth_user_key", payload.email.toLowerCase());
        sessionStorage.setItem("caloreceipt:sso_status", payload.status);
        if (payload.display_name && payload.display_name.trim().length > 0) {{
          sessionStorage.setItem("caloreceipt:sso_display_name", payload.display_name.trim());
        }}
      }} catch (_error) {{
        0;
      }}
      window.location.replace("/");
    </script>
  </body>
</html>"""
    response = HTMLResponse(content=body, status_code=200)
    cookie = _build_auth_cookie(token, request)
    response.set_cookie(**cookie)
    response.delete_cookie("sso_state", path="/")
    return response


def _load_private_key(config: dict[str, Any]) -> str:
    inline_key = _normalized_text(config.get("private_key"))
    if inline_key:
        return inline_key
    key_path = _normalized_text(config.get("private_key_path"))
    if not key_path:
        raise RuntimeError("Apple SSO requires either client_secret or private_key/private_key_path.")
    resolved_path = Path(key_path)
    if not resolved_path.is_absolute():
        resolved_path = (BASE_DIR / resolved_path).resolve()
    return resolved_path.read_text(encoding="utf-8")


def _apple_client_secret(config: dict[str, Any]) -> str:
    configured_secret = _normalized_text(config.get("client_secret"))
    if configured_secret:
        return configured_secret
    team_id = _normalized_text(config.get("team_id"))
    key_id = _normalized_text(config.get("key_id"))
    client_id = _normalized_text(config.get("client_id"))
    if not team_id or not key_id or not client_id:
        raise RuntimeError("Apple SSO requires client_id, team_id, and key_id when client_secret is not provided.")
    now = int(time.time())
    payload = {
        "iss": team_id,
        "iat": now,
        "exp": now + (60 * 60 * 24 * 180),
        "aud": APPLE_ISSUER,
        "sub": client_id,
    }
    headers = {"kid": key_id}
    return jwt.encode(payload, _load_private_key(config), algorithm="ES256", headers=headers)


def _truthy(raw: Any) -> bool:
    if isinstance(raw, bool):
        return raw
    text = _normalized_text(raw).lower()
    return text in {"1", "true", "yes", "y"}


def _extract_display_name(raw: Any) -> str:
    if isinstance(raw, dict):
        name = raw.get("name")
        if isinstance(name, dict):
            parts = [str(name.get("firstName") or "").strip(), str(name.get("lastName") or "").strip()]
            display = " ".join(part for part in parts if part)
            if display:
                return display
        return str(raw.get("name") or "").strip()
    return ""


def _user_payload_from_request_data(data: Any) -> dict[str, Any]:
    if isinstance(data, dict):
        return data
    text = _normalized_text(data)
    if not text:
        return {}
    try:
        parsed = json.loads(text)
    except Exception:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _build_google_provider(config: dict[str, Any], redirect_uri: str) -> "GoogleProvider":
    return GoogleProvider(config=config, redirect_uri=redirect_uri)


def _build_apple_provider(config: dict[str, Any], redirect_uri: str) -> "AppleProvider":
    return AppleProvider(config=config, redirect_uri=redirect_uri)


def create_sso_provider(platform: str, config: dict[str, Any], redirect_uri: str) -> Any:
    if platform == "google":
        return _build_google_provider(config, redirect_uri)
    if platform == "apple":
        return _build_apple_provider(config, redirect_uri)
    return None


class _MockURL:
    """Minimal duck-typed URL that exposes .scheme/.netloc/.path and str() like Starlette URL."""

    def __init__(self, url_str: str) -> None:
        from urllib.parse import urlparse as _urlparse
        _p = _urlparse(url_str)
        self.scheme = _p.scheme or "http"
        self.netloc = _p.netloc or "localhost:8000"
        self.path = _p.path or "/"
        self._full = url_str

    def __str__(self) -> str:
        return self._full


class _MockSSORequest:
    """Minimal duck-typed request for fastapi_sso callback handling (no starlette needed)."""

    def __init__(self, query_params: dict, cookies: dict | None = None, url: str = "") -> None:
        self.query_params = query_params
        self.cookies = cookies or {}
        self.url = _MockURL(url)
        self.headers = {}


def initiate_sso_redirect_url(platform: str, operation: str) -> str:
    """Return the OAuth redirect URL for the given platform/operation, or '' on error."""
    import asyncio

    enabled = get_enabled_platforms()
    if platform not in enabled:
        return ""
    redirect_uri = get_sso_redirect_uri(platform, operation)
    provider = create_sso_provider(platform, enabled[platform], redirect_uri)
    if provider is None:
        return ""
    redirect_resp = asyncio.run(provider.initiate_auth(operation))
    location = redirect_resp.headers.get("location", "")
    return location


def handle_sso_callback(
    platform: str,
    operation: str,
    query_params: dict,
    cookies: dict | None = None,
    callback_url: str = "",
) -> tuple[str, int]:
    """
    Handle OAuth callback.  Returns (html_body_str, http_status).
    Caller is responsible for creating the user if needed; this returns the
    HTML page that stores the JWT in localStorage and redirects to /.
    """
    import asyncio

    enabled = get_enabled_platforms()
    if platform not in enabled:
        resp = build_sso_error_response(f"SSO for '{platform}' is not configured.", 501)
        return resp.body.decode("utf-8"), 501

    redirect_uri = get_sso_redirect_uri(platform, operation)
    provider = create_sso_provider(platform, enabled[platform], redirect_uri)
    if provider is None:
        resp = build_sso_error_response("Unable to initialize SSO provider.", 500)
        return resp.body.decode("utf-8"), 500

    mock_req = _MockSSORequest(query_params=query_params, cookies=cookies or {}, url=callback_url)
    try:
        user_info = asyncio.run(provider.handle_callback(mock_req))
    except Exception as exc:
        resp = build_sso_error_response(f"Sign-in failed: {str(exc)}", 400)
        return resp.body.decode("utf-8"), 400

    ext_id = str(user_info.get("external_id", "")).strip()
    email = str(user_info.get("email", "")).strip().lower()
    display_name = str(user_info.get("display_name", "")).strip()

    if not email and not ext_id:
        resp = build_sso_error_response("SSO did not return a usable identifier.", 400)
        return resp.body.decode("utf-8"), 400
    if not email:
        email = f"{platform}_{ext_id}@sso.local"

    token = create_app_jwt(email)
    status_text = f"Signed in with {platform.title()}."
    html_resp = build_sso_success_response(token, email, status_text, display_name)
    return html_resp.body.decode("utf-8"), 200


@dataclass
class GoogleProvider:
    config: dict[str, Any]
    redirect_uri: str

    def _client(self) -> GoogleSSO:
        return GoogleSSO(
            client_id=_normalized_text(self.config.get("client_id")),
            client_secret=_normalized_text(self.config.get("client_secret")),
            redirect_uri=self.redirect_uri,
            allow_insecure_http=self.redirect_uri.startswith("http://"),
        )

    async def initiate_auth(self, _operation: str) -> RedirectResponse:
        async with self._client() as provider:
            state = secrets.token_urlsafe(24)
            return await provider.get_login_redirect(state=state)

    async def handle_callback(self, request: Request) -> dict[str, Any]:
        async with self._client() as provider:
            user = await provider.verify_and_process(request)
        display_name = _normalized_text(getattr(user, "display_name", ""))
        if not display_name:
            first_name = _normalized_text(getattr(user, "first_name", ""))
            last_name = _normalized_text(getattr(user, "last_name", ""))
            display_name = " ".join(part for part in [first_name, last_name] if part)
        verified_flag = getattr(user, "email_verified", False)
        return {
            "external_id": _normalized_text(getattr(user, "id", "")),
            "email": _normalized_text(getattr(user, "email", "")).lower(),
            "display_name": display_name,
            "email_verified": _truthy(verified_flag),
        }


@dataclass
class AppleProvider:
    config: dict[str, Any]
    redirect_uri: str

    @property
    def client_id(self) -> str:
        return _normalized_text(self.config.get("client_id"))

    @property
    def client_secret(self) -> str:
        return _apple_client_secret(self.config)

    async def initiate_auth(self, _operation: str) -> RedirectResponse:
        state = secrets.token_urlsafe(24)
        params = {
            "response_type": "code",
            "response_mode": "form_post",
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "scope": "name email",
            "state": state,
        }
        response = RedirectResponse(f"{APPLE_AUTH_URL}?{urlencode(params)}", status_code=303)
        response.set_cookie(
            "sso_state",
            state,
            httponly=True,
            secure=self.redirect_uri.startswith("https://"),
            samesite="lax",
            path="/",
            max_age=600,
        )
        return response

    def _validate_state(self, state: str, request: Request) -> None:
        cookie_state = _normalized_text(request.cookies.get("sso_state"))
        if not state:
            raise RuntimeError("State was not returned from Apple.")
        if not cookie_state:
            raise RuntimeError("State cookie is missing. Start the Apple login flow again.")
        if state != cookie_state:
            raise RuntimeError("State validation failed. Start the Apple login flow again.")

    async def _callback_payload(self, request: Request) -> dict[str, Any]:
        if request.method.upper() == "POST":
            try:
                form_data = await request.form()
                return {key: value for key, value in form_data.items()}
            except Exception:
                return {}
        return dict(request.query_params)

    def _verify_id_token(self, id_token: str) -> dict[str, Any]:
        jwk_client = jwt.PyJWKClient(APPLE_KEYS_URL)
        signing_key = jwk_client.get_signing_key_from_jwt(id_token).key
        return jwt.decode(
            id_token,
            signing_key,
            algorithms=["ES256"],
            audience=self.client_id,
            issuer=APPLE_ISSUER,
        )

    async def handle_callback(self, request: Request) -> dict[str, Any]:
        payload = await self._callback_payload(request)
        if payload.get("error"):
            error = _normalized_text(payload.get("error"))
            description = _normalized_text(payload.get("error_description"))
            detail = description or error or "Apple authentication was denied."
            raise RuntimeError(detail)
        state = _normalized_text(payload.get("state"))
        self._validate_state(state, request)
        code = _normalized_text(payload.get("code"))
        if not code:
            raise RuntimeError("Apple did not return an authorization code.")
        token_payload = {
            "grant_type": "authorization_code",
            "code": code,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "redirect_uri": self.redirect_uri,
        }
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                APPLE_TOKEN_URL,
                data=token_payload,
                headers={"Accept": "application/json"},
            )
        try:
            payload = response.json()
        except Exception as exc:
            raise RuntimeError("Apple token exchange returned an invalid response.") from exc
        if response.is_error or payload.get("error"):
            description = _normalized_text(payload.get("error_description"))
            detail = description or _normalized_text(payload.get("error")) or "Apple token exchange failed."
            raise RuntimeError(detail)
        id_token = _normalized_text(payload.get("id_token"))
        if not id_token:
            raise RuntimeError("Apple did not return an identity token.")
        claims = self._verify_id_token(id_token)
        display_name = _extract_display_name(
            _user_payload_from_request_data(payload.get("user"))
        )
        return {
            "external_id": _normalized_text(claims.get("sub")),
            "email": _normalized_text(claims.get("email")).lower(),
            "display_name": display_name,
            "email_verified": _truthy(claims.get("email_verified")),
        }
