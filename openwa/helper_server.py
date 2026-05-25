#!/usr/bin/env python3
"""Simple helper API and status UI for the OpenWA Home Assistant add-on."""

from __future__ import annotations

import html
import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

OPTIONS_PATH = Path("/data/options.json")
OPENWA_BASE_URL = "http://127.0.0.1:2785"
HELPER_PORT = 2786


def load_options() -> dict[str, Any]:
    """Load add-on options."""
    try:
        return json.loads(OPTIONS_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def get_master_key() -> str:
    """Retrieve the master API key from options or a persistent file, generating one if needed."""
    options = load_options()
    key = options.get("api_master_key", "")

    # Use the key from options if it's set and not the default
    if key and key != "CHANGE_ME_TO_A_LONG_RANDOM_SECRET":
        return key

    # Fallback to persistent file
    key_file = Path("/data/master_key.txt")
    if key_file.exists():
        return key_file.read_text().strip()

    # Generate a new secure random key
    import secrets
    import string
    alphabet = string.ascii_letters + string.digits
    new_key = "".join(secrets.choice(alphabet) for _ in range(32))

    # Persist the generated key
    try:
        key_file.write_text(new_key)
    except Exception as e:
        print(f"[OpenWA Helper] Warning: Could not persist master key: {e}")

    print(f"[OpenWA Helper] 🔑 Generated new Master Key: {new_key}")
    return new_key

def mask_value(value: str) -> str:
    """Mask sensitive values for display."""
    if not value:
        return ""
    if len(value) <= 10:
        return "***"
    return f"{value[:6]}...{value[-4:]}"


def get_recipient(options: dict[str, Any], name: str) -> str | None:
    """Get a recipient chat ID by alias."""
    recipients = options.get("recipients", [])
    if not isinstance(recipients, list):
        return None

    for recipient in recipients:
        if not isinstance(recipient, dict):
            continue
        if recipient.get("name") == name:
            return recipient.get("chat_id")

    return None


def openwa_request(
    method: str,
    path: str,
    api_key: str | None = None,
    body: dict[str, Any] | None = None,
    timeout: int = 20,
) -> tuple[int, dict[str, str], bytes]:
    """Proxy a request to OpenWA."""
    url = f"{OPENWA_BASE_URL}{path}"
    data = None

    headers = {
        "Accept": "application/json",
    }

    if api_key:
        headers["X-API-Key"] = api_key

    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
            response_headers = {
                "Content-Type": response.headers.get("Content-Type", "application/json")
            }
            return response.status, response_headers, response_body
    except urllib.error.HTTPError as err:
        response_body = err.read()
        response_headers = {
            "Content-Type": err.headers.get("Content-Type", "application/json")
        }
        return err.code, response_headers, response_body
    except Exception as err:
        payload = {
            "error": "openwa_request_failed",
            "message": str(err),
        }
        return 502, {"Content-Type": "application/json"}, json.dumps(payload).encode("utf-8")


class HelperHandler(BaseHTTPRequestHandler):
    """HTTP handler for helper API."""

    server_version = "OpenWAHelper/0.1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        """Log requests."""
        print(f"[OpenWA Helper] {self.address_string()} - {fmt % args}")

    def send_bytes(self, status: int, content_type: str, body: bytes) -> None:
        """Send bytes response."""
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status: int, payload: dict[str, Any] | list[Any]) -> None:
        """Send JSON response."""
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_bytes(status, "application/json; charset=utf-8", body)

    def read_json_body(self) -> dict[str, Any]:
        """Read JSON request body."""
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}

        raw = self.rfile.read(length)
        try:
            parsed = json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

        if isinstance(parsed, dict):
            return parsed

        return {}

    def verify_auth(self) -> bool:
        """Verify the request has a valid master API key."""
        master_key = get_master_key()

        if not master_key:
            return True

        key = self.headers.get("X-API-Key")
        if key == master_key:
            return True

        self.send_json(401, {"error": "unauthorized", "message": "Invalid or missing X-API-Key header."})
        return False

def start_session_if_needed() -> None:
    """Automatically start the configured session if it's not running."""
    options = load_options()
    api_key = options.get("openwa_api_key", "")
    session_id = options.get("session_id", "")

    if not api_key:
        print("[OpenWA Helper] No openwa_api_key configured. Skipping auto-start.")
        return

    if not session_id:
        print("[OpenWA Helper] No session_id configured. Please follow the Quick Start Guide to create a session.")
        return

    try:
        status, _, body = openwa_request("GET", f"/api/sessions/{session_id}", api_key=api_key)
        if status == 200:
            payload = json.loads(body.decode("utf-8"))
            current_status = payload.get("status")
            if current_status != "ready":
                print(f"[OpenWA Helper] Session {session_id} is {current_status}. Sending start request...")
                openwa_request("POST", f"/api/sessions/{session_id}/start", api_key=api_key)
                print(f"[OpenWA Helper] Session start request sent.")
            else:
                print(f"[OpenWA Helper] Session {session_id} is already ready.")
        else:
            print(f"[OpenWA Helper] Session {session_id} not found or error ({status}).")
    except Exception as e:
        print(f"[OpenWA Helper] Error during auto-start check: {e}")

class HelperHandler(BaseHTTPRequestHandler):
        """Handle GET."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/":
            self.handle_index()
            return

        if path == "/qr":
            self.handle_qr()
            return

        if not self.verify_auth():
            return

        if path == "/health":
            self.handle_health()
            return

        if path == "/sessions":
            self.handle_sessions()
            return

        self.send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        """Handle POST."""
        if not self.verify_auth():
            return

        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/send":
            self.handle_send()
            return

        if path.startswith("/send/"):
            alias = path.split("/", 2)[2]
            self.handle_send(alias=alias)
            return

        self.send_json(404, {"error": "not_found"})

    def handle_index(self) -> None:
        """Render simple status UI."""
        options = load_options()
        api_key = options.get("openwa_api_key", "")
        session_id = options.get("session_id", "")
        recipients = options.get("recipients", [])

        health_status, _, health_body = openwa_request("GET", "/api/health")

        try:
            health_text = health_body.decode("utf-8")
        except Exception:
            health_text = ""

        recipient_rows = ""
        if isinstance(recipients, list):
            for recipient in recipients:
                if not isinstance(recipient, dict):
                    continue
                name = html.escape(str(recipient.get("name", "")))
                chat_id = html.escape(str(recipient.get("chat_id", "")))
                recipient_rows += f"<tr><td>{name}</td><td>{chat_id}</td></tr>"

        body = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>OpenWA Add-on</title>
  <style>
    body {{
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      margin: 32px;
      line-height: 1.5;
      max-width: 980px;
    }}
    code, pre {{
      background: #f3f3f3;
      padding: 2px 4px;
      border-radius: 4px;
    }}
    pre {{
      padding: 12px;
      overflow-x: auto;
    }}
    table {{
      border-collapse: collapse;
      width: 100%;
      margin-top: 12px;
    }}
    th, td {{
      border: 1px solid #ddd;
      padding: 8px;
      text-align: left;
    }}
    th {{
      background: #f7f7f7;
    }}
  </style>
</head>
<body>
  <h1>OpenWA Add-on</h1>

  <h2>Status</h2>
  <p><strong>OpenWA health status:</strong> {health_status}</p>
  <pre>{html.escape(health_text)}</pre>

  <h2>Configuration</h2>
  <ul>
    <li><strong>OpenWA API:</strong> <code>{OPENWA_BASE_URL}</code></li>
    <li><strong>OpenWA API key configured:</strong> <code>{html.escape(mask_value(str(api_key)))}</code></li>
    <li><strong>Session ID:</strong> <code>{html.escape(str(session_id))}</code></li>
  </ul>

  <h2>Recipients</h2>
  <table>
    <thead>
      <tr><th>Name</th><th>Chat ID</th></tr>
    </thead>
    <tbody>
      {recipient_rows}
    </tbody>
  </table>

  <h2>Endpoints</h2>
  <ul>
    <li><a href="/health">GET /health</a></li>
    <li><a href="/sessions">GET /sessions</a></li>
    <li><a href="/qr">GET /qr</a></li>
    <li><code>POST /send</code></li>
    <li><code>POST /send/primary</code></li>
    <li><code>POST /send/secondary</code></li>
  </ul>

  <h2>Example rest_command</h2>
  <pre>rest_command:
  openwa_send_primary:
    url: "http://127.0.0.1:2786/send/primary"
    method: POST
    headers:
      Content-Type: "application/json"
      X-API-Key: "YOUR_MASTER_API_KEY"
    payload: >
      {{
        "message": "{{{{ message }}}}"
      }}</pre>
</body>
</html>
"""
        self.send_bytes(200, "text/html; charset=utf-8", body.encode("utf-8"))

    def handle_health(self) -> None:
        """Return helper and OpenWA health."""
        status, _, body = openwa_request("GET", "/api/health")

        try:
            openwa_health = json.loads(body.decode("utf-8"))
        except Exception:
            openwa_health = {"raw": body.decode("utf-8", errors="replace")}

        self.send_json(
            200,
            {
                "helper": "ok",
                "openwa_status_code": status,
                "openwa": openwa_health,
            },
        )

    def handle_sessions(self) -> None:
        """Return OpenWA sessions."""
        options = load_options()
        api_key = options.get("openwa_api_key", "")

        if not api_key:
            self.send_json(
                503,
                {
                    "error": "missing_openwa_api_key",
                    "message": "Set openwa_api_key in the add-on options.",
                },
            )
            return

        status, headers, body = openwa_request(
            "GET",
            "/api/sessions",
            api_key=api_key,
        )

        self.send_bytes(status, headers.get("Content-Type", "application/json"), body)

    def handle_qr(self) -> None:
        """Return or render QR for configured session."""
        options = load_options()
        api_key = options.get("openwa_api_key", "")
        session_id = options.get("session_id", "")

        if not api_key or not session_id:
            self.send_json(
                503,
                {
                    "error": "missing_configuration",
                    "message": "Set openwa_api_key and session_id in the add-on options.",
                },
            )
            return

        status, _, body = openwa_request(
            "GET",
            f"/api/sessions/{session_id}/qr",
            api_key=api_key,
        )

        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            self.send_bytes(status, "application/json", body)
            return

        qr_code = payload.get("qrCode")

        if not qr_code:
            self.send_json(status, payload)
            return

        html_body = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>OpenWA QR</title>
</head>
<body style="font-family: sans-serif; margin: 32px;">
  <h1>OpenWA QR</h1>
  <p>Scan with WhatsApp → Linked devices → Link a device.</p>
  <img src="{html.escape(qr_code)}" style="width:360px;height:360px;">
  <pre>{html.escape(json.dumps(payload, indent=2))}</pre>
</body>
</html>
"""
        self.send_bytes(status, "text/html; charset=utf-8", html_body.encode("utf-8"))

    def handle_send(self, alias: str | None = None) -> None:
        """Send a WhatsApp message."""
        options = load_options()
        api_key = options.get("openwa_api_key", "")
        session_id = options.get("session_id", "")

        if not api_key or not session_id:
            self.send_json(
                503,
                {
                    "error": "missing_configuration",
                    "message": "Set openwa_api_key and session_id in the add-on options.",
                },
            )
            return

        payload = self.read_json_body()
        message = payload.get("message") or payload.get("text")

        if not message:
            self.send_json(
                400,
                {
                    "error": "missing_message",
                    "message": "Request JSON must include message.",
                },
            )
            return

        if alias:
            chat_id = get_recipient(options, alias)
            if not chat_id:
                self.send_json(
                    404,
                    {
                        "error": "recipient_not_found",
                        "message": f"No recipient configured for alias: {alias}",
                    },
                )
                return
        else:
            chat_id = payload.get("chat_id") or payload.get("chatId")
            if not chat_id:
                self.send_json(
                    400,
                    {
                        "error": "missing_chat_id",
                        "message": "Request JSON must include chat_id when using /send.",
                    },
                )
                return

        status, headers, body = openwa_request(
            "POST",
            f"/api/sessions/{session_id}/messages/send-text",
            api_key=api_key,
            body={
                "chatId": chat_id,
                "text": message,
            },
        )

        self.send_bytes(status, headers.get("Content-Type", "application/json"), body)


def main() -> None:
    """Run helper server."""
    start_session_if_needed()

    address = ("0.0.0.0", HELPER_PORT)
    server = ThreadingHTTPServer(address, HelperHandler)
    print(f"[OpenWA Helper] Listening on port {HELPER_PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()