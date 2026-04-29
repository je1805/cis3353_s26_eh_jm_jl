#!/bin/sh
# =============================================================================
# link-php-fpm-sock.sh — runtime helper for jokopi-app
# =============================================================================
# Ubuntu's php-fpm package creates its socket with a versioned name like
# /run/php/php8.1-fpm.sock. Our nginx.conf references the un-versioned
# /run/php/php-fpm.sock so the config doesn't have to know which PHP point
# release apt happened to install. Without a symlink between the two, every
# /api/*.php request returns 404 because nginx can't reach PHP-FPM.
#
# /run is a tmpfs that's wiped on container start, so we recreate the
# symlink at boot via supervisord (priority=15, before php-fpm at 20).
# =============================================================================

set -u

# Wait up to 10 seconds for php-fpm to create its versioned socket.
# `grep -v '/php-fpm.sock$'` filters out any pre-existing un-versioned link
# so we always pick a real *-fpm.sock to point at.
for i in 1 2 3 4 5 6 7 8 9 10; do
    SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null \
                | grep -v '/php-fpm.sock$' \
                | head -1)"
    if [ -n "${SOCK}" ]; then
        ln -sf "${SOCK}" /run/php/php-fpm.sock
        echo "[link-php-fpm-sock] linked ${SOCK} -> /run/php/php-fpm.sock"
        exit 0
    fi
    sleep 1
done

echo "[link-php-fpm-sock] WARN: no versioned php-fpm socket appeared after 10s"
ls -la /run/php/ >&2
exit 0   # don't block startup; nginx will surface the failure as a 502
