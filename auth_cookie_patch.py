from __future__ import annotations

import json
import os
from http.cookies import SimpleCookie
from urllib.parse import urlparse

from jaclang.runtimelib.server import AuthHandler, JacAPIServer
from jaclang.runtimelib.transport import HTTPTransport, Meta, TransportResponse

_PATCHED = False
_ORIG_HTTP_SEND = HTTPTransport.send
_ORIG_AUTH_LOGIN = AuthHandler.login
_ORIG_CREATE_HANDLER = JacAPIServer.create_handler


def _apply_cors_headers(handler) -> None:
    origin = str(handler.headers.get("Origin", "") or "").strip()
    if origin:
        handler.send_header("Access-Control-Allow-Origin", origin)
        handler.send_header("Vary", "Origin")
        handler.send_header("Access-Control-Allow-Credentials", "true")
    else:
        handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")


def _cookie_name() -> str:
    return os.getenv("CALORECEIPT_AUTH_COOKIE_NAME", "caloreceipt_session")


def _cookie_max_age() -> int:
    try:
        return max(0, int(os.getenv("CALORECEIPT_AUTH_COOKIE_MAX_AGE", "2592000")))
    except Exception:
        return 2592000


def _cookie_same_site() -> str:
    value = str(os.getenv("CALORECEIPT_AUTH_COOKIE_SAMESITE", "Lax")).strip() or "Lax"
    return value


def _cookie_secure() -> bool:
    raw = str(os.getenv("CALORECEIPT_AUTH_COOKIE_SECURE", "true")).strip().lower()
    return raw not in {"0", "false", "no", "off"}


def _build_auth_cookie(token: str) -> str:
    parts = [
        f"{_cookie_name()}={token}",
        "Path=/",
        f"Max-Age={_cookie_max_age()}",
        f"SameSite={_cookie_same_site()}",
        "HttpOnly",
    ]
    if _cookie_secure():
        parts.append("Secure")
    return "; ".join(parts)


def _build_clear_cookie() -> str:
    parts = [
        f"{_cookie_name()}=",
        "Path=/",
        "Max-Age=0",
        f"SameSite={_cookie_same_site()}",
        "HttpOnly",
    ]
    if _cookie_secure():
        parts.append("Secure")
    return "; ".join(parts)


def _cookie_token_from_header(cookie_header: str | None) -> str | None:
    if not cookie_header:
        return None
    jar = SimpleCookie()
    try:
        jar.load(cookie_header)
    except Exception:
        return None
    morsel = jar.get(_cookie_name())
    if morsel is None:
        return None
    token = str(morsel.value or "").strip()
    return token or None


def _patched_http_send(self: HTTPTransport, data: object) -> None:
    if not isinstance(data, TransportResponse):
        _ORIG_HTTP_SEND(self, data)
        return

    extra = {}
    if getattr(getattr(data, "meta", None), "extra", None):
        extra = dict(data.meta.extra)
    status = int(extra.pop("http_status", 200 if data.ok else 500))
    set_auth_cookie = extra.pop("set_auth_cookie", None)
    clear_auth_cookie = extra.pop("clear_auth_cookie", None)
    custom_headers = extra.pop("headers", {}) or {}

    response_body = {
        "ok": data.ok,
        "type": data.type,
        "data": data.data,
        "error": None,
    }
    if not data.ok and data.error:
        error_obj = {}
        if getattr(data.error, "code", None):
            error_obj["code"] = data.error.code
        if getattr(data.error, "message", None):
            error_obj["message"] = data.error.message
        if getattr(data.error, "details", None) is not None:
            error_obj["details"] = data.error.details
        response_body["error"] = error_obj

    if data.meta:
        meta_dict = {}
        if getattr(data.meta, "request_id", None):
            meta_dict["request_id"] = data.meta.request_id
        if getattr(data.meta, "trace_id", None):
            meta_dict["trace_id"] = data.meta.trace_id
        if getattr(data.meta, "timestamp", None):
            meta_dict["timestamp"] = data.meta.timestamp
        if extra:
            meta_dict["extra"] = extra
        if meta_dict:
            response_body["meta"] = meta_dict

    self.handler.send_response(status)
    self.handler.send_header("Content-Type", "application/json")
    _apply_cors_headers(self.handler)
    if set_auth_cookie:
        self.handler.send_header("Set-Cookie", str(set_auth_cookie))
    if clear_auth_cookie:
        self.handler.send_header("Set-Cookie", str(clear_auth_cookie))
    if isinstance(custom_headers, dict):
        for key, value in custom_headers.items():
            if isinstance(value, (list, tuple)):
                for item in value:
                    self.handler.send_header(str(key), str(item))
            elif value is not None:
                self.handler.send_header(str(key), str(value))
    self.handler.end_headers()
    self.handler.wfile.write(json.dumps(response_body).encode())
    self.response_data = response_body
    if self.on_message:
        self.on_message(data)


def _patched_auth_login(self: AuthHandler, username: str, password: str) -> TransportResponse:
    response = _ORIG_AUTH_LOGIN(self, username, password)
    if getattr(response, "ok", False) and isinstance(getattr(response, "data", None), dict):
        token = str(response.data.get("token", "")).strip()
        if token:
            extra = {}
            if getattr(getattr(response, "meta", None), "extra", None):
                extra = dict(response.meta.extra)
            extra["set_auth_cookie"] = _build_auth_cookie(token)
            if getattr(response, "meta", None) is None:
                response.meta = Meta(extra=extra)
            else:
                response.meta.extra = extra
    return response


def _patched_create_handler(self: JacAPIServer):
    handler_cls = _ORIG_CREATE_HANDLER(self)
    original_do_get = handler_cls.do_GET
    original_do_options = handler_cls.do_OPTIONS
    original_do_post = handler_cls.do_POST

    def _get_auth_token(handler_self):
        auth_header = handler_self.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header[7:].strip()
            if token:
                return token
        return _cookie_token_from_header(handler_self.headers.get("Cookie"))

    def do_GET(handler_self):
        parsed_path = urlparse(handler_self.path)
        if parsed_path.path == "/user/info":
            token = handler_self._get_auth_token()
            if not token:
                handler_self._send_response(
                    TransportResponse.fail(
                        code="UNAUTHORIZED",
                        message="Unauthorized - Authentication required",
                        meta=Meta(extra={"http_status": 401}),
                    )
                )
                return
            response = self.auth_handler.get_user_info(token)
            handler_self._send_response(response)
            return
        return original_do_get(handler_self)

    def do_OPTIONS(handler_self):
        parsed_path = urlparse(handler_self.path)
        if (
            parsed_path.path.startswith("/user/")
            or parsed_path.path.startswith("/walker/")
            or parsed_path.path.startswith("/function/")
        ):
            handler_self.send_response(200)
            _apply_cors_headers(handler_self)
            handler_self.end_headers()
            return
        return original_do_options(handler_self)

    def do_POST(handler_self):
        parsed_path = urlparse(handler_self.path)
        if parsed_path.path == "/user/logout":
            handler_self._send_response(
                TransportResponse.success(
                    data={"logged_out": True},
                    meta=Meta(
                        extra={
                            "http_status": 200,
                            "clear_auth_cookie": _build_clear_cookie(),
                        }
                    ),
                )
            )
            return
        return original_do_post(handler_self)

    handler_cls._get_auth_token = _get_auth_token
    handler_cls.do_GET = do_GET
    handler_cls.do_OPTIONS = do_OPTIONS
    handler_cls.do_POST = do_POST
    return handler_cls


def install_cookie_auth_patch() -> bool:
    global _PATCHED
    if _PATCHED:
        return True
    HTTPTransport.send = _patched_http_send
    AuthHandler.login = _patched_auth_login
    JacAPIServer.create_handler = _patched_create_handler
    _PATCHED = True
    return True
