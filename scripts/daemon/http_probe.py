#!/usr/bin/env python3
"""
Tiny HTTP sidecar exposing /metrics and /health for AO.

Environment:
  METRICS_PROM_PATH   - path to Prometheus text file (default: metrics/metrics.prom)
  AO_HTTP_PORT        - listen port (default: 9100)
  AO_HTTP_BIND        - bind address (default: 127.0.0.1)
  AO_HTTP_BEARER_TOKEN- optional bearer token required for access
  AO_HTTP_BASIC_USER  - optional basic auth user (requires AO_HTTP_BASIC_PASS)
  AO_HTTP_BASIC_PASS  - optional basic auth password
  AO_HEALTH_CMD       - optional shell command to run for health (e.g., lua scripts/verify/health.lua)
  AO_HEALTH_TIMEOUT_SEC - timeout for health command (default: 10)
  AO_HEALTH_CACHE_SECS  - cache health output for this many seconds (default: 10)
  AO_HTTP_AUTH_TOKEN  - deprecated alias for AO_HTTP_BEARER_TOKEN
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import base64
import json
import os
import subprocess
import time

PROM_PATH = Path(os.getenv("METRICS_PROM_PATH", "metrics/metrics.prom"))
PORT = int(os.getenv("AO_HTTP_PORT", "9100"))
BIND = os.getenv("AO_HTTP_BIND", "127.0.0.1")
BEARER = os.getenv("AO_HTTP_BEARER_TOKEN") or os.getenv("AO_HTTP_AUTH_TOKEN")
BASIC_USER = os.getenv("AO_HTTP_BASIC_USER")
BASIC_PASS = os.getenv("AO_HTTP_BASIC_PASS")
TOKEN_HEADER = os.getenv("AO_HTTP_TOKEN_HEADER", "X-AO-Token")
HEALTH_CMD = os.getenv("AO_HEALTH_CMD")
HEALTH_TIMEOUT = int(os.getenv("AO_HEALTH_TIMEOUT_SEC", "10"))
HEALTH_CACHE = int(os.getenv("AO_HEALTH_CACHE_SECS", "10"))

_cache = {"ts": 0, "payload": None}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        # keep logs quiet; systemd/journal will capture stdout prints
        return

    def _respond(self, code: int, body, content_type: str):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if isinstance(body, str):
            body = body.encode()
        self.wfile.write(body)

    def do_GET(self):
        if not self._check_auth():
            return
        if self.path.startswith("/metrics"):
            return self.handle_metrics()
        if self.path.startswith("/health"):
            return self.handle_health()
        self._respond(
            404, json.dumps({"status": "not_found", "path": self.path}), "application/json"
        )

    def handle_metrics(self):
        if PROM_PATH.exists():
            self._respond(200, PROM_PATH.read_bytes(), "text/plain; version=0.0.4")
        else:
            self._respond(503, b"# metrics path missing\n", "text/plain; version=0.0.4")

    def handle_health(self):
        now = time.time()
        payload = {
            "status": "ok",
            "metrics_path": str(PROM_PATH),
            "cached": False,
        }
        if HEALTH_CMD:
            if _cache["payload"] and now - _cache["ts"] < HEALTH_CACHE:
                payload.update(_cache["payload"])
                payload["cached"] = True
            else:
                try:
                    proc = subprocess.run(
                        HEALTH_CMD,
                        shell=True,
                        capture_output=True,
                        text=True,
                        timeout=HEALTH_TIMEOUT,
                    )
                    payload.update(
                        probe_exit=proc.returncode,
                        probe_stdout=proc.stdout,
                        probe_stderr=proc.stderr,
                    )
                    payload["status"] = "ok" if proc.returncode == 0 else "degraded"
                except Exception as exc:  # pragma: no cover - defensive
                    payload["status"] = "error"
                    payload["probe_error"] = str(exc)
                _cache["payload"] = dict(payload)
                _cache["ts"] = now
        code = 200 if payload.get("status") == "ok" else 503
        self._respond(code, json.dumps(payload), "application/json")

    def _check_auth(self) -> bool:
        if not (BEARER or BASIC_USER):
            return True

        authz = self.headers.get("Authorization", "")
        if BEARER:
            token = None
            if authz.lower().startswith("bearer "):
                token = authz.split(" ", 1)[1].strip()
            if not token:
                token = (self.headers.get(TOKEN_HEADER, "") or "").strip()
            if token and token == BEARER:
                return True

        if BASIC_USER and authz.lower().startswith("basic "):
            try:
                decoded = base64.b64decode(authz.split(" ", 1)[1]).decode()
                user, pwd = decoded.split(":", 1)
            except Exception:
                user, pwd = None, None
            if user == BASIC_USER and pwd == (BASIC_PASS or ""):
                return True

        self._unauthorized()
        return False

    def _unauthorized(self):
        self.send_response(401)
        if BASIC_USER:
            self.send_header("WWW-Authenticate", 'Basic realm="ao-http"')
        elif BEARER:
            self.send_header("WWW-Authenticate", 'Bearer realm="ao-http"')
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b'{"status":"unauthorized"}')


def main():
    server = HTTPServer((BIND, PORT), Handler)
    print(f"[ao-http] serving /metrics and /health on {BIND}:{PORT} (prom={PROM_PATH})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
