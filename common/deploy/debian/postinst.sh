#!/bin/bash
#
# Generic Debian postinst for Webitel Go services.
#
# Managed centrally in webitel/reusable-configs and synced verbatim into each
# service repo at deploy/debian/postinst.sh — DO NOT edit per-repo.
#
# It is service-agnostic:
#   * the systemd units to manage are discovered at runtime from the package
#     itself, so it works for single- and multi-unit packages alike;
#   * service-specific setup (e.g. creating data dirs or certificates) is
#     provided by the package as drop-in hooks (see run_postinst_hooks).
#
# Services run as the unprivileged system account $USER_NAME. Hooks use
# $USER_NAME/$GROUP_NAME for file ownership and migrate_legacy_owner to take
# over data created by $LEGACY_USER_NAME.

set -e

USER_NAME="webitel-svc"
GROUP_NAME="webitel-svc"
# Services keep state in $HOME (e.g. go-micro creates its directories there).
HOME_DIR="/var/lib/webitel"

# Account the services ran as before. Customers may use it as a support user
# with sudo rights, so it is never modified or removed, only its files under
# the paths handed to migrate_legacy_owner change owner.
LEGACY_USER_NAME="webitel"
LEGACY_GROUP_NAME="webitel"

have_systemctl() {
    command -v systemctl >/dev/null 2>&1
}

# systemd unit files shipped by THIS package, as basenames
# (e.g. "webitel-engine.service"). Empty if the package ships no units.
package_units() {
    dpkg-query -L "$DPKG_MAINTSCRIPT_PACKAGE" 2>/dev/null \
        | grep -E '/systemd/system/[^/]+\.service$' \
        | sed 's:.*/::'
}

create_user() {
    if ! getent group "$GROUP_NAME" >/dev/null 2>&1; then
        echo "Creating group: $GROUP_NAME"
        addgroup --system "$GROUP_NAME"
    fi

    if ! getent passwd "$USER_NAME" >/dev/null 2>&1; then
        echo "Creating user: $USER_NAME"
        adduser --system --ingroup "$GROUP_NAME" \
                --home "$HOME_DIR" \
                --disabled-password --disabled-login \
                --shell /usr/sbin/nologin \
                --gecos "Webitel service user" \
                "$USER_NAME"
    fi

    assert_system_user

    # adduser leaves an existing home untouched; a legacy system "webitel"
    # account was created with the same home.
    migrate_legacy_owner "$HOME_DIR"
}

# Refuse to run the services as a login account, e.g. one an operator created
# by hand under the same name. System accounts have a UID below 1000 (the
# Debian adduser default) and no login shell.
assert_system_user() {
    local uid shell
    uid=$(id -u "$USER_NAME")
    shell=$(getent passwd "$USER_NAME" | cut -d: -f7)

    if [ "$uid" -ge 1000 ]; then
        echo "ERROR: $USER_NAME (uid $uid) is not a system account." >&2
        echo "Rename or remove it so the package can create a system account." >&2
        exit 1
    fi

    case "$shell" in
        */nologin|*/false) ;;
        *)
            echo "ERROR: $USER_NAME has login shell '$shell'." >&2
            echo "Set it to /usr/sbin/nologin: usermod -s /usr/sbin/nologin $USER_NAME" >&2
            exit 1
            ;;
    esac
}

# Hand the files of the legacy service account under the given paths over to
# $USER_NAME. Hooks call it for the data their service writes (e.g. storage
# recordings), so each package migrates its own data in the upgrade that
# switches its units to $USER_NAME. A chown that fails (e.g. a root-squashed
# NFS mount) is reported but does not abort the install.
migrate_legacy_owner() {
    local path
    for path in "$@"; do
        [ -e "$path" ] || continue

        if getent passwd "$LEGACY_USER_NAME" >/dev/null 2>&1; then
            find "$path" -user "$LEGACY_USER_NAME" \
                -exec chown -h "$USER_NAME" {} + \
                || echo "WARNING: could not change owner of some files under $path" >&2
        fi

        if getent group "$LEGACY_GROUP_NAME" >/dev/null 2>&1; then
            find "$path" -group "$LEGACY_GROUP_NAME" \
                -exec chgrp -h "$GROUP_NAME" {} + \
                || echo "WARNING: could not change group of some files under $path" >&2
        fi
    done
}

# Run service-specific setup shipped by the package, BEFORE any unit is
# enabled or started. Hooks are sourced (they see the script's environment)
# and run under `set -e`: a failing hook aborts the install, which is the
# correct behaviour when e.g. a required certificate cannot be generated.
run_postinst_hooks() {
    local hook_dir="/usr/lib/webitel/$DPKG_MAINTSCRIPT_PACKAGE/deb/postinst.d"
    [ -d "$hook_dir" ] || return 0

    local hook
    for hook in "$hook_dir"/*; do
        [ -f "$hook" ] || continue
        echo "Running postinst hook: $hook"
        # shellcheck disable=SC1090
        . "$hook"
    done
}

if [ "$1" = "configure" ]; then
    echo "Configuring $DPKG_MAINTSCRIPT_PACKAGE..."

    create_user
    run_postinst_hooks

    if have_systemctl; then
        systemctl daemon-reload

        units=$(package_units)

        if [ -z "$2" ]; then
            # Fresh install: enable units for boot but do NOT start them.
            # The shipped configuration usually contains placeholder values,
            # so the operator must review it before the first start.
            for unit in $units; do
                systemctl enable "$unit" || true
            done

            echo "$DPKG_MAINTSCRIPT_PACKAGE installed and enabled (not started)."
            if [ -n "$units" ]; then
                echo ""
                echo "Next steps:"
                echo "1. Review configuration under /etc/systemd/system/ and /etc/default/"
                echo "2. Start:  sudo systemctl start $units"
                echo "3. Status: sudo systemctl status $units"
            fi
        else
            # Upgrade: restart only units that were running, so a deliberately
            # stopped service stays stopped while a running one picks up the
            # new binary.
            for unit in $units; do
                echo "Restarting $unit (if running)..."
                systemctl try-restart "$unit" || true
            done
        fi
    fi
fi

exit 0
