# Pinned to a released tag for reproducible builds (was :latest, which drifts silently).
ARG BUILD_FROM=ghcr.io/rmyndharis/openwa:0.7.2
FROM ${BUILD_FROM}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      python3 \
      ca-certificates \
      curl \
      procps \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
COPY helper_server.py /usr/local/bin/helper_server.py

RUN chmod a+x /run.sh \
    && chmod a+x /usr/local/bin/helper_server.py

# Override the upstream ENTRYPOINT (dumb-init -> docker-entrypoint.sh -> `gosu openwa`) so run.sh
# controls startup and actually runs as root — it must create the /app/data persistence symlink and
# write under /data. run.sh replicates the entrypoint's Chromium setup (XDG dirs, stale lock cleanup).
# `init: true` in config.yaml provides an init (PID 1) for signal handling and zombie reaping.
ENTRYPOINT ["/run.sh"]