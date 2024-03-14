#!/bin/sh
export TAILSCALE_ROOT="${TAILSCALE_ROOT:-/data/tailscale}"
export TAILSCALE="tailscale"
export TAILSCALE_DEFAULTS="/etc/default/tailscaled"

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
        sed -i "s/FLAGS=\"[^\"]*\"/FLAGS=\"--state \/data\/tailscale\/tailscaled.state ${TAILSCALED_FLAGS}\"/" $TAILSCALE_DEFAULTS
        echo "Done"
    fi

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
    rm -f /lib/systemd/system/tailscale-install.service || true
}

_tailscale_route() {
    # Load the tailscale-env file to discover the flags which are required to be set
    # shellcheck source=package/tailscale-env
    . "${TAILSCALE_ROOT}/tailscale-env"

    echo "This will enable you to expose Tailnet devices to machines on your network."
    echo "WARNING: It is currently an ALPHA feature, and may break your system."
    yes_or_no "Do you wish to proceed?" && {
        # IF_CHOICE=${IF_CHOICE:-N}
        # echo "${IF_CHOICE}" # Remove before submitting PR
        echo ${yn} # Remove before submitting PR
        sleep 5s # Remove before submitting PR
        # if [[ ${IF_CHOICE} == [Nn]* ]]; then
        #     echo "Tailnet routing NOT enabled."
        #     exit 1
        # else
        case $2 in
            "enable")
                export TAILSCALED_INTERFACE="true"
                echo "${TAILSCALED_INTERFACE}" # Remove before submitting PR
                sleep 5s # Remove before submitting PR
                sed -i "s/TAILSCALED_INTERFACE=\"[^\"]*\"/TAILSCALED_INTERFACE=\"true\"/" ${TAILSCALE_ROOT}/tailscale-env
                export TAILSCALED_FLAGS="--socket \/var\/run\/tailscale\/tailscaled.sock --state \/data\/tailscale\/tailscaled.state"
                ;;
            "disable")
                export TAILSCALED_INTERFACE="false"
                echo "${TAILSCALED_INTERFACE}" # Remove before submitting PR
                sleep 5s # Remove before submitting PR
                sed -i "s/TAILSCALED_INTERFACE=\"[^\"]*\"/TAILSCALED_INTERFACE=\"false\"/" ${TAILSCALE_ROOT}/tailscale-env
                export TAILSCALED_FLAGS="--state \/data\/tailscale\/tailscaled.state --tun userspace-networking"
                ;;
        esac
        # fi

        # if [ "${TAILSCALED_INTERFACE}" = 'false' ]; then
        #     export TAILSCALED_FLAGS="--state \/data\/tailscale\/tailscaled.state --tun userspace-networking"
        # else
        #     export TAILSCALED_FLAGS="--socket \/var\/run\/tailscale\/tailscaled.sock --state \/data\/tailscale\/tailscaled.state"
        # fi

        echo "Updating ${TAILSCALE_DEFAULTS} to ${1} Tailnet routing..."
        if [ ! -e "${TAILSCALE_DEFAULTS}" ]; then
            echo "Failed to configure Tailscaled startup flags"
            echo "Check that the file ${TAILSCALE_DEFAULTS} exists and contains the line FLAGS=\"--state /data/tailscale/tailscale.state ${TAILSCALED_FLAGS}\"."
            exit 1
        else
            echo "${TAILSCALED_FLAGS}" # Remove before submitting PR
            sed -i "s/FLAGS=\"[^\"]*\"/FLAGS=\"${TAILSCALED_FLAGS}\"/" $TAILSCALE_DEFAULTS
            echo "Done"
        fi

        echo "Restarting Tailscale daemon to detect new configuration..."
        systemctl restart tailscaled.service || {
            echo "Failed to restart Tailscale daemon"
            echo "The daemon might not be running with userspace networking enabled, you can restart it manually using 'systemctl restart tailscaled'."
            exit 1
            }
        } || exit 1
    }
yes_or_no() {
    while true; do
        read -p "$* [y/N]: " yn
        yn=${yn:-N}
        case $yn in
            [Yy]*) return 0  ;;
            [Nn]*) echo "Aborted" ; return  1 ;;
        esac
    done
}
