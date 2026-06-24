# OpenWA Add-on Documentation

## Ports

| Port | Purpose | Description |
|---:|---|---|
| `2785` | OpenWA native API | The full WhatsApp API provided by the OpenWA engine. |
| `2786` | Helper API and status UI | Simplified API for Home Assistant and a web-based status dashboard. |

## Options

### `openwa_api_key`
The native OpenWA API key (port `2785`). On first boot OpenWA seeds this as its admin key, and it is the key used by both the helper and the companion HACS integration to talk to the engine. Leave it blank to have the add-on generate a strong key on first boot and print it in the log.

> The engine seeds its key only on the first boot. To change this value later, rotate the key from the OpenWA dashboard, or delete `/data/openwa/main.sqlite` and `/data/openwa/.api-key` (re-linking required).

### `api_master_key`
The Helper API key (port `2786`). Used only to authenticate requests to the helper. Leave it blank to have the add-on generate one and print it in the log.

**Usage:**
All requests to the Helper API (when accessed directly on port `2786`) must include this key in the `X-API-Key` header. Requests via the Home Assistant Ingress panel are already authenticated and do not need it.

Example:
```bash
curl -H "X-API-Key: YOUR_MASTER_KEY" http://localhost:2786/health
```

### `session_id`
The ID of the WhatsApp session to use for sending messages and generating QR codes.

### `recipients`
A list of named aliases for WhatsApp chat IDs.
- `name`: The alias (e.g., "primary", "admin").
- `chat_id`: The WhatsApp chat ID (e.g., `123456789@c.us`).

These allow using simplified endpoints like `/send/primary`.
