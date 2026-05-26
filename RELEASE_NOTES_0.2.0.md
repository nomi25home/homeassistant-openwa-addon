# OpenWA Home Assistant Add-on 0.2.0

Version 0.2.0 ties this add-on to the companion Home Assistant HACS integration:

- Companion integration: https://github.com/nomi25home/homeassistant-openwa-whatsapp
- Native OpenWA API: port 2785
- Helper API and QR/status UI: port 2786

Recommended setup:

1. Install and start this add-on.
2. Set `openwa_api_key` in the add-on options.
3. Leave `session_id` blank on first boot so the add-on can create one.
4. Open `http://homeassistant.local:2786/qr` and scan the QR code.
5. Install the companion HACS integration.
6. Configure the integration with:
   - OpenWA Base URL: `http://HOME_ASSISTANT_HOST:2785`
   - OpenWA API Key: the same `openwa_api_key`
   - OpenWA Session ID: the session shown by the add-on logs or `/sessions` endpoint.

This release includes the startup/session reliability fixes needed for the add-on and HACS integration to work together reliably.
