# =============================================================================
# Wazuh Dashboard (custom build) - CIS 3353 Security Lab
# =============================================================================
# Why a custom image?
#
# The lab runs the Wazuh Indexer with `plugins.security.disabled: true` to
# keep classroom setup simple. That removes the /_plugins/_security/*
# endpoints from the indexer — so when the dashboard's bundled
# `securityDashboards` plugin calls GET /_plugins/_security/authinfo
# during login, the indexer answers:
#   "no handler found for uri [/_plugins/_security/authinfo]"
# and every login attempt dies with a 401.
#
# The obvious config-side fix — setting `opensearch_security.disabled: true`
# in opensearch_dashboards.yml — does NOT work against Wazuh's fork of the
# plugin, which has a strict config schema that rejects unknown keys:
#   ValidationError: [config validation of [opensearch_security].disabled]:
#   definition for this key is missing
# leaving the container in a CrashLoopBackOff state.
#
# So we remove the plugin from the image entirely. Once `securityDashboards`
# is gone, the dashboard stops calling the missing security endpoint, stops
# requiring credentials, and loads straight into the Wazuh app at
# /app/wz-home. The Wazuh UI itself is a separate plugin (`wazuh`) and is
# not affected.
#
# Lab-only. Do NOT use this image on any network where authentication
# matters.
# =============================================================================

FROM wazuh/wazuh-dashboard:4.9.2

# ---------------------------------------------------------------------------
# Remove the securityDashboards plugin
# ---------------------------------------------------------------------------
# `opensearch-dashboards-plugin remove` is the upstream OSD plugin manager.
# --allow-root is required because the base image's build user is root at
# image-build time, even though the container runs as the `wazuh-dashboard`
# user at runtime.
#
# We tolerate a non-zero exit (|| true) because if a future Wazuh base image
# ships without the plugin, we don't want the build to break — the goal is
# "plugin absent", not "plugin successfully removed by us".
USER root
RUN /usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin remove \
        securityDashboards --allow-root || true

# ---------------------------------------------------------------------------
# Drop in our lab opensearch_dashboards.yml
# ---------------------------------------------------------------------------
# Build context is the project root, so this path is relative to there.
# With the security plugin gone, this file no longer contains any
# `opensearch_security.*` keys (they'd be rejected by the dashboard's
# config schema in the same way that triggered this whole exercise).
COPY configs/wazuh/opensearch-dashboards.yml \
     /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml

RUN chown wazuh-dashboard:wazuh-dashboard \
        /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml && \
    chmod 640 \
        /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml

# Sanity check: confirm the plugin directory is gone. If the base image
# layout ever changes, we want the build to fail here rather than produce
# an image that silently still has the plugin.
RUN test ! -d /usr/share/wazuh-dashboard/plugins/securityDashboards

# ---------------------------------------------------------------------------
# Restore the runtime user
# ---------------------------------------------------------------------------
# We switched to `USER root` above so plugin removal + COPY + chown could
# run with the right permissions. That `USER root` directive persists into
# the runtime container unless we override it — and when the entrypoint
# runs `opensearch-dashboards` as root, the dashboard refuses to start:
#   "OpenSearch Dashboards should not be run as root. Use --allow-root to
#   continue."
# and the container crashloops. Switch back to the base image's default
# non-root user so the entrypoint's `su-exec wazuh-dashboard` path works
# as designed.
USER wazuh-dashboard
