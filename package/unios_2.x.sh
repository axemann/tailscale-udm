#!/bin/sh
export TAILSCALE_ROOT="${TAILSCALE_ROOT:-/data/tailscale}"
export TAILSCALE="tailscale"
export TAILSCALE_DEFAULTS="/etc/default/tailscaled"
export TS_OVERRIDE_DIR="/etc/systemd/system/tailscaled.service.d"

_tailscale_is_running() {
    systemctl is-active --quiet tailscaled
}

_tailscale_is_installed() {
    command -v tailscale >/dev/null 2>&1
}

_tailscale_start() {
    systemctl start tailscaled

    # Wait a few seconds for the daemon to start
    sleep 5

    if _tailscale_is_running; then
        echo "Tailscaled started successfully"
    else
        echo "Tailscaled failed to start"
        exit 1
    fi

    echo "Run 'tailscale up' to configure the interface."
}

_tailscale_stop() {
    systemctl stop tailscaled
}

_tailscale_install() {
    # shellcheck source=tests/os-release
    . "${OS_RELEASE_FILE:-/etc/os-release}"

    # Load the tailscale-env file to discover the flags which are required to be set
    # shellcheck source=package/tailscale-env
    . "${TAILSCALE_ROOT}/tailscale-env"

    TAILSCALE_VERSION="${1:-$(curl -sSLq --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/?mode=json" | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"

    echo "Installing latest Tailscale package repository..."
    if [ "${VERSION_CODENAME}" = "stretch" ]; then
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.gpg" | apt-key add -
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.list" | tee /etc/apt/sources.list.d/tailscale.list
    else
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
    fi

    echo "Updating package lists..."
    apt update

    echo "Installing Tailscale ${TAILSCALE_VERSION}..."
    apt install -y tailscale="${TAILSCALE_VERSION}"

    echo "Configuring Tailscale port..."
    if [ ! -e "${TAILSCALE_DEFAULTS}" ]; then
        echo "Failed to configure Tailscale port"
        echo "Check that the file ${TAILSCALE_DEFAULTS} exists and contains the line PORT=\"${PORT:-41641}\"."
        exit 1
    else
        sed -i "s/PORT=\"[^\"]*\"/PORT=\"${PORT:-41641}\"/" $TAILSCALE_DEFAULTS
        echo "Done"
    fi

    echo "Configuring Tailscaled startup flags..."
    if [ ! -e "${TAILSCALE_DEFAULTS}" ]; then
        echo "Failed to configure Tailscaled startup flags"
        echo "Check that the file ${TAILSCALE_DEFAULTS} exists and contains the line FLAGS=\"--state /data/tailscale/tailscale.state ${TAILSCALED_FLAGS}\"."
        exit 1
    else
        echo "Flags from environment file are: ${TAILSCALED_FLAGS}"
        sed -i "s/FLAGS=\"[^\"]*\"/FLAGS=\"--state \/data\/tailscale\/tailscaled.state ${TAILSCALED_FLAGS}\"/" $TAILSCALE_DEFAULTS
        echo "Done"
    fi

    echo "Installing SystemD override to clean up service parameters..."
    if [ ! -d "${TS_OVERRIDE_DIR}" ]; then
        mkdir -p "${TS_OVERRIDE_DIR}"
    fi
    # From https://github.com/jasonwbarnett in https://github.com/SierraSoftworks/tailscale-udm/discussions/51#discussioncomment-7912433
    tee "${TS_OVERRIDE_DIR}/override.conf" <<- "EOF" > /dev/null
		[Service]
		ExecStart=
		ExecStart=/usr/sbin/tailscaled --port=${PORT} $FLAGS
		EOF

        systemctl daemon-reload

    echo "Restarting Tailscale daemon to detect new configuration..."
    systemctl restart tailscaled.service || {
        echo "Failed to restart Tailscale daemon"
        echo "The daemon might not be running with userspace networking enabled, you can restart it manually using 'systemctl restart tailscaled'."
        exit 1
    }

    echo "Enabling Tailscale to start on boot..."
    systemctl enable tailscaled.service || {
        echo "Failed to enable Tailscale to start on boot"
        echo "You can enable it manually using 'systemctl enable tailscaled'."
        exit 1
    }

    if [ ! -L "/etc/systemd/system/tailscale-install.service" ]; then
        if [ ! -e "${TAILSCALE_ROOT}/tailscale-install.service" ]; then
            rm -f /etc/systemd/system/tailscale-install.service
        fi

        echo "Installing pre-start script to install Tailscale on firmware updates."
        ln -s "${TAILSCALE_ROOT}/tailscale-install.service" /etc/systemd/system/tailscale-install.service

        systemctl daemon-reload
        systemctl enable tailscale-install.service
    fi

    if [ ! -L "/etc/systemd/system/tailscale-install.timer" ]; then
        if [ ! -e "${TAILSCALE_ROOT}/tailscale-install.timer" ]; then
            rm -f /etc/systemd/system/tailscale-install.timer
        fi

        echo "Installing auto-update timer to ensure that Tailscale is kept installed and up to date."
        ln -s "${TAILSCALE_ROOT}/tailscale-install.timer" /etc/systemd/system/tailscale-install.timer

        systemctl daemon-reload
        systemctl enable --now tailscale-install.timer
    fi

}

_tailscale_uninstall() {
    apt remove -y tailscale
    rm -f /etc/apt/sources.list.d/tailscale.list || true

    systemctl disable tailscale-install.service || true
    rm -f /etc/systemd/system/tailscale-install.service || true

    systemctl disable tailscale-install.timer || true
    rm -f /etc/systemd/system/tailscale-install.timer || true

    systemctl daemon-reload
}

_tailscale_routing() {
    echo "This will enable you to expose Tailnet devices to machines on your network."
    echo "WARNING: This is currently an ALPHA feature, and may break your system."
    yes_or_no "Do you wish to proceed?" && {
        case $1 in
            "enable")
                ## Uncomment below once out of BETA
                # export TAILSCALED_INTERFACE="true"
                # sed -i "s/TAILSCALED_INTERFACE=\"[^\"]*\"/TAILSCALED_INTERFACE=\"true\"/" ${TAILSCALE_ROOT}/tailscale-env
                export TAILSCALED_FLAGS="--socket \/var\/run\/tailscale\/tailscaled.sock --state \/data\/tailscale\/tailscaled.state"
                _udm_set_tailnet_routes
                _enable_ip_forwarding
                ;;
            "disable")
                ## Uncomment below once out of BETA
                # export TAILSCALED_INTERFACE="false"
                # sed -i "s/TAILSCALED_INTERFACE=\"[^\"]*\"/TAILSCALED_INTERFACE=\"false\"/" ${TAILSCALE_ROOT}/tailscale-env
                export TAILSCALED_FLAGS="--state \/data\/tailscale\/tailscaled.state --tun userspace-networking"
                ;;
            *)
                echo "Something went wrong! :-("
        esac

        echo "Updating ${TAILSCALE_DEFAULTS} to ${1} Tailnet routing..."
        if [ ! -e "${TAILSCALE_DEFAULTS}" ]; then
            echo "Failed to configure Tailscaled startup flags"
            echo "Check that the file ${TAILSCALE_DEFAULTS} exists and contains the line FLAGS=\"--state /data/tailscale/tailscale.state ${TAILSCALED_FLAGS}\"."
            exit 1
        else
            sed -i "s/FLAGS=\"[^\"]*\"/FLAGS=\"${TAILSCALED_FLAGS}\"/" ${TAILSCALE_DEFAULTS}
            echo "Done"
        fi

        echo "Restarting Tailscale daemon to detect new configuration..."
        systemctl restart tailscaled.service || {
            echo "Failed to restart Tailscale daemon"
            echo "The daemon might not be running with userspace networking enabled, you can restart it manually using 'systemctl restart tailscaled'."
            exit 1
            }
        } || exit 1 && echo "No changes made to routing configuration."
    }

_udm_set_tailnet_routes() {
    # From https://github.com/FearNaBoinne in
    # https://github.com/SierraSoftworks/tailscale-udm/discussions/51#discussioncomment-6130392,
    # with edits
    ROUTES=$( /sbin/ip route | /bin/grep "dev br" | /usr/bin/cut -d " " -f 1-3 )
    echo "${ROUTES}" | while read -r route; do /sbin/ip route del ${route} table 52; done
    echo "${ROUTES}" | while read -r route; do /sbin/ip route add ${route} table 52; done
}

_enable_ip_forwarding() {
    # This may be needed in certain cases, per
    # https://github.com/SierraSoftworks/tailscale-udm/discussions/51#discussioncomment-5664351 and
    # https://tailscale.com/kb/1019/subnets/#enable-ip-forwarding
    if [ -d /etc/sysctl.d ]; then
        echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
        echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
        sysctl -p /etc/sysctl.d/99-tailscale.conf
    else
        echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
        echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
        sysctl -p /etc/sysctl.conf
    fi
}

yes_or_no() {
    # This function will go away once out of BETA
    while true; do
        read -p "$* [y/N]: " yn
        yn=${yn:-N}
        case $yn in
            [Yy]*) return 0  ;;
            [Nn]*) echo "Aborted" ; return  1 ;;
        esac
    done
}
