# OpenWA Home Assistant Add-on

A secure, persistent wrapper for the OpenWA WhatsApp API gateway, specifically designed for Home Assistant.

## Overview

This add-on bundles the [OpenWA](https://github.com/rmyndharis/OpenWA) API with a dedicated helper server that provides simplified endpoints for Home Assistant `rest_command` integrations and a web-based status UI.

- **Native OpenWA API (Port 2785)**: Full access to the WhatsApp gateway.
- **Helper Server (Port 2786)**: Simplified API for sending messages and a status dashboard.

---

## 🚀 Deployment & Setup Guide

### 1. Install and Configure
Install the add-on and enter the following in the **Options** tab:
- `openwa_api_key`: A secret key for the native API.
- `api_master_key`: A secret key for the helper API.
- `session_id`: (Leave empty for now).

**Restart the add-on** after saving these options.

### 2. One-Time Session Setup
Since this is a new installation, you must create and link your WhatsApp account. 

**Step A: Create a Session**
Run this command from your terminal (replace `[YOUR_API_KEY]` and `[YOUR_IP]`):
```bash
curl -X POST -H "X-API-Key: [YOUR_API_KEY]" -H "Content-Type: application/json" -d '{"name": "homeassistant"}' http://[YOUR_IP]:2785/api/sessions
```
**Copy the `id` from the JSON response.**

**Step B: Start the Session**
Replace `[SESSION_ID]` with the ID from the previous step:
```bash
curl -X POST -H "X-API-Key: [YOUR_API_KEY]" http://[YOUR_IP]:2785/api/sessions/[SESSION_ID]/start
```

**Step C: Link your Phone**
Visit the QR page in your browser:
👉 `http://[YOUR_IP]:2786/qr`
Scan the code using **WhatsApp $\rightarrow$ Linked Devices $\rightarrow$ Link a Device**.

**Step D: Finalize Configuration**
1. Copy the **Session ID** you created in Step A.
2. Paste it into the `session_id` field in the add-on **Options**.
3. **Restart the add-on**.

---

## 🛠️ Helper API Usage

All helper endpoints require the `api_master_key` in the `X-API-Key` header.

### Send a Message
**Endpoint**: `POST /send`
**Payload**: `{"chat_id": "123456789@c.us", "message": "Hello!"}`

**Example `curl`**:
```bash
curl -X POST -H "X-API-Key: [MASTER_KEY]" -H "Content-Type: application/json" -d '{"chat_id": "123456789@c.us", "message": "Hello!"}' http://[YOUR_IP]:2786/send
```

### Home Assistant `rest_command` Example
Add this to your `configuration.yaml`:
```yaml
rest_command:
  openwa_send:
    url: "http://[YOUR_IP]:2786/send"
    method: POST
    headers:
      Content-Type: "application/json"
      X-API-Key: "YOUR_MASTER_API_KEY"
    payload: '{"chat_id": "{{ chat_id }}@c.us", "message": "{{ message }}"}'
```

---

## 📖 Troubleshooting

- **Blank API Docs Page**: If `http://[YOUR_IP]:2785/api/docs` is blank, ensure you have correctly set the `openwa_api_key` in options and restarted.
- **401 Unauthorized**: Ensure you are using the correct key. `dev-admin-key` is for the native API; your `api_master_key` is for the helper server.
- **QR Code Not Showing**: Ensure you have called the `/start` endpoint for your session.
- **Session Lost on Restart**: This add-on implements full persistence. If you are asked to scan the QR code after every restart, ensure you have a valid `session_id` configured in the options.
`