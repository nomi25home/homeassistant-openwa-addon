# Changelog

## 0.3.0

- Fixed a breaking auth mismatch with OpenWA 0.7.x: the engine seeds its native API key from
  `API_MASTER_KEY`, so the add-on now seeds it from `openwa_api_key` (the key the helper and the
  companion HACS integration send). Previously the helper's requests were rejected with 401.
- Removed the inert `.env.generated` `API_KEY=` write (OpenWA never reads that variable).
- Keys are now auto-generated and persisted on first boot when left blank, and printed in the log,
  so the add-on never ships with a guessable default secret. `api_master_key` no longer defaults to a
  placeholder.
- Session ID is now persisted to `/data/session_id.txt` instead of `options.json` (the Supervisor
  overwrites `options.json` on every start, which previously lost the linked session after a restart).
- Added `AUTO_START_SESSIONS=true` so a linked session resumes automatically after a restart.
- Removed env vars the current engine does not consume (`RATE_LIMIT_TTL`, `RATE_LIMIT_MAX`,
  `PLUGINS_ENABLED`, `REDIS_ENABLED`); pinned `MAIN_DATABASE_NAME` onto the persistent volume.
- Status and QR UI moved behind Home Assistant Ingress (sidebar panel); direct access to port 2786
  now requires the `X-API-Key` header, closing the unauthenticated QR-link exposure on the LAN.
- Added `aarch64` support (the upstream image is multi-arch), a `watchdog` health check, and pinned
  the base image to a released tag instead of `latest`.
- Overrode the container entrypoint so the startup script runs as root and replicates the upstream
  Chromium setup (XDG dirs, stale singleton-lock cleanup).
- The QR page now polls until the code is ready, detects an already-linked session, and surfaces an
  engine auth error clearly instead of a generic timeout.
- Upgrades from older versions reuse the engine's existing key automatically (no re-link) when
  `openwa_api_key` is left blank — the add-on falls back to the key the engine already seeded.
- Fixed the Ingress panel links (were absolute paths that escaped the Ingress base).

## 0.2.0

- Promoted the OpenWA Home Assistant add-on to version 0.2.0.
- Added recommended pairing with the OpenWA WhatsApp HACS integration 0.2.0.
- Fixed OpenWA startup order so the native API starts before the helper server.
- Added OpenWA health checks before helper session setup.
- Improved automatic session creation and startup handling.
- Added QR setup flow guidance for first-time WhatsApp linking.
- Documented companion HACS integration setup using the native OpenWA API on port 2785.
- Improved troubleshooting guidance for QR, session ID, and persistence issues.

## 0.1.0

- Initial Home Assistant add-on release.
- Added native OpenWA API exposure on port 2785.
- Added helper API and status UI on port 2786.
- Added configurable `openwa_api_key`, `api_master_key`, `session_id`, log level, and recipient aliases.
