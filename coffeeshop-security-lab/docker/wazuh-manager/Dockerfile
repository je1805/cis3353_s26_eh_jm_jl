# =============================================================================
# Wazuh Manager (custom build) - CIS 3353 Security Lab
# =============================================================================
# Why a custom image instead of bind mounts?
#
# The stock wazuh/wazuh-manager:4.9.2 entrypoint includes a permanent-data
# seeding step that short-circuits any target directory that looks like a
# mount point. Docker's single-file bind mounts (e.g.
# `./ossec.conf:/var/ossec/etc/ossec.conf`) register the containing
# directory as mounted from the entrypoint's perspective, so the seeding
# skips `/var/ossec/etc/` entirely. That leaves critical image-shipped
# files like `/var/ossec/etc/shared/ar.conf` absent, and wazuh-analysisd
# refuses to start:
#   ERROR: (1103): Could not open file 'etc/shared/ar.conf'
#   CRITICAL: (1202): Configuration error at 'etc/ossec.conf'
#
# Baking our overrides into a derived image sidesteps the whole problem:
# the files land in /var/ossec/etc during image build, alongside the
# image's own shipped content. No bind mounts under /var/ossec/ at
# runtime means the seeder runs normally and everything is present.
# =============================================================================

FROM wazuh/wazuh-manager:4.9.2

# ---------------------------------------------------------------------------
# Pre-populate VOLUME-declared directories at build time
# ---------------------------------------------------------------------------
# The upstream image declares VOLUME /var/ossec/etc, /var/ossec/active-response/bin,
# /var/ossec/wodles, /var/ossec/integrations, /var/ossec/agentless, etc.
# At container runtime Docker creates anonymous volumes for each of these.
# Anonymous volumes register as mount points, which causes the image's
# entrypoint (permanent-data.sh) to report "already mounted" and SKIP the
# step that copies files from /var/ossec/data_tmp/permanent/... into the
# runtime paths. That's why /var/ossec/etc/shared/ ends up empty, so when
# wazuh-execd starts it can't write ar.conf there (and analysisd then
# crashes trying to read it).
#
# Workaround: do the copy ourselves at build time. Docker seeds each
# anonymous volume with the image's content at the VOLUME path, so once
# the directory is fully populated in the image layer, the runtime volume
# inherits everything — regardless of what the entrypoint does.
#
# NOTE: ar.conf itself is NOT shipped with the image. It's generated at
# runtime by wazuh-execd from the <active-response> blocks in ossec.conf.
# What we need to pre-seed is the shared/ directory (with its
# agent-template.conf and default/ subdir) so execd has somewhere to
# write. Same for the other VOLUME paths.
RUN set -eux; \
    for d in etc active-response/bin wodles integrations agentless "var/multigroups"; do \
        src="/var/ossec/data_tmp/permanent/var/ossec/$d"; \
        dst="/var/ossec/$d"; \
        if [ -d "$src" ]; then \
            mkdir -p "$dst"; \
            cp -au "$src/." "$dst/"; \
        fi; \
    done; \
    # /etc/filebeat is also a VOLUME in the base image.
    if [ -d /var/ossec/data_tmp/permanent/etc/filebeat ]; then \
        mkdir -p /etc/filebeat; \
        cp -au /var/ossec/data_tmp/permanent/etc/filebeat/. /etc/filebeat/; \
    fi; \
    # Sanity-checks: the things that MUST be present after build time for
    # the manager to start cleanly.
    #
    # Note on active-response/bin, wodles, integrations, agentless: these
    # are intentionally placeholder directories in the permanent/ staging
    # area — their actual script content is shipped separately under
    # data_tmp/exclusion/ and copied into place at RUNTIME by
    # apply_exclusion_data() in /etc/cont-init.d/0-wazuh-init. So we only
    # assert the directories exist, not their file contents.
    #
    # /var/ossec/etc/shared/ IS populated in permanent/ (with
    # agent-template.conf + default/), and shared/ must exist before
    # wazuh-execd runs or it can't write ar.conf → analysisd crashes.
    test -d /var/ossec/etc/shared; \
    test -f /var/ossec/etc/shared/agent-template.conf; \
    test -d /var/ossec/etc/shared/default; \
    test -d /var/ossec/active-response/bin; \
    test -d /var/ossec/wodles; \
    test -d /var/ossec/integrations; \
    test -d /var/ossec/agentless; \
    test -d /etc/filebeat

# Build context is the project root, so paths below are relative to there.

# Custom manager config (replaces the stock ossec.conf that we just seeded)
COPY configs/wazuh/ossec-manager.conf /var/ossec/etc/ossec.conf

# Custom rules and decoders (single-file overrides; other files in these
# directories are image-shipped and remain untouched)
COPY configs/wazuh/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml
COPY configs/wazuh/decoders/local_decoder.xml /var/ossec/etc/decoders/local_decoder.xml

# Tools the AR script depends on:
#   - jq:     parse the JSON Wazuh execd writes to the script's stdin
#   - docker: needed because block-ip-firewall.sh runs `docker exec
#             pfsense-firewall …` to invoke the firewall's handler.sh.
#             Pair this with a /var/run/docker.sock bind mount in
#             docker-compose.yml so the CLI inside the manager can talk
#             to the host's Docker daemon.
#
# Note: the base image is Amazon Linux 2023, which ships `curl-minimal`
# and a busybox `which`. Installing the full `curl` package conflicts
# with `curl-minimal` (RPM file conflicts on /usr/bin/curl), so we only
# install `jq`. `curl-minimal` is feature-complete for our needs (HTTPS
# download of the docker static tarball below).
RUN set -eux; \
    if command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y jq; \
    else \
        (yum install -y jq || dnf install -y jq); \
    fi; \
    # Install a static docker-cli without needing a repo. The Docker static
    # tarball is the smallest reliable way to get just the client binary
    # onto a non-Debian, non-Alpine base image.
    DOCKER_VER=24.0.7; \
    curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VER}.tgz" \
        -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    docker --version

# Active-response script used by our "block attacker at the firewall" rule.
# The base image already ships a full set of AR scripts (firewall-drop,
# host-deny, etc.) in /var/ossec/active-response/bin/; this adds ours
# alongside them.
COPY scripts/active-response/block-ip-firewall.sh /var/ossec/active-response/bin/block-ip-firewall.sh

# Ownership and permissions — Wazuh expects the manager's files to be owned
# by the wazuh user (UID 101 in the upstream image) and for AR scripts to
# be executable.
RUN chown root:wazuh \
        /var/ossec/etc/ossec.conf \
        /var/ossec/etc/rules/local_rules.xml \
        /var/ossec/etc/decoders/local_decoder.xml && \
    chmod 640 \
        /var/ossec/etc/ossec.conf \
        /var/ossec/etc/rules/local_rules.xml \
        /var/ossec/etc/decoders/local_decoder.xml && \
    chown root:wazuh /var/ossec/active-response/bin/block-ip-firewall.sh && \
    chmod 750 /var/ossec/active-response/bin/block-ip-firewall.sh

# SSL cert mounts remain at /etc/ssl/... (outside /var/ossec/) where they
# don't trigger the seeding short-circuit, so those stay in docker-compose.
