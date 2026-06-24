# OpenWA Home Assistant Add-on Repository

Home Assistant add-on repository for running a self-hosted OpenWA WhatsApp API gateway.

## Add-ons

### OpenWA

Runs OpenWA inside Home Assistant OS/Supervised and exposes:

- OpenWA API on port `2785`
- Helper API/UI on port `2786`

The status/QR UI is also available through the Home Assistant Ingress panel (no extra auth needed). When the helper API is accessed directly on port `2786`, all endpoints require the `api_master_key` in the `X-API-Key` header:

- `GET /`
- `GET /health`
- `GET /sessions`
- `GET /qr`
- `POST /send`
- `POST /send/primary`
- `POST /send/secondary`

## Installation

1. Open Home Assistant.
2. Go to **Settings → Add-ons → Add-on Store**.
3. Open the three-dot menu.
4. Choose **Repositories**.
5. Add this repository URL.
6. Install the **OpenWA** add-on.
7. Configure the add-on options.
8. Start the add-on.

## Security

Do not expose OpenWA directly to the public internet without proper authentication, TLS, and network controls.