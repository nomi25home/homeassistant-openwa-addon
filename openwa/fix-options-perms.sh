#!/bin/sh
set -e

# Supervisor writes /data/options.json mode 600, owned by root. The base
# image's own entrypoint drops privileges to the non-root `openwa` user
# before exec'ing our CMD (run.sh), so neither run.sh's read_option() nor
# helper_server.py's get_master_key() can ever read it as openwa — every
# auth check silently falls back to a freshly-generated random key on every
# request, so no configured key, correct or not, ever matches. This script
# runs as root (the container's initial user, before the base entrypoint's
# own gosu drop) to fix that, then hands off to the base image's entrypoint
# unchanged.
if [ -f /data/options.json ]; then
  chown :997 /data/options.json
  chmod 640 /data/options.json
fi

exec dumb-init -- /usr/local/bin/docker-entrypoint.sh "$@"
