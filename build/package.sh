#!/usr/bin/env bash
set -e

SOURCE="${1?You must provide the repo root as the first argument}"
DEST="${2?You must provide the destination directory as the second argument}"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

echo "Preparing temporary build directory"
mkdir -p "${WORKDIR}/tailscale" "${WORKDIR}/on_boot.d"
cp "${SOURCE}/package/on-boot.sh" "${WORKDIR}/on_boot.d/10-tailscaled.sh"
cp "${SOURCE}/package/manage.sh" "${WORKDIR}/tailscale/manage.sh"
cp "${SOURCE}/package/unios_"*".sh" "${WORKDIR}/tailscale/"
cp "${SOURCE}/package/tailscale-env" "${WORKDIR}/tailscale/tailscale-env"
cp "${SOURCE}/package/tailscale-install.service" "${WORKDIR}/tailscale/tailscale-install.service"
cp "${SOURCE}/package/tailscale-install.timer" "${WORKDIR}/tailscale/tailscale-install.timer"
cp "${SOURCE}/LICENSE" "${WORKDIR}/tailscale/LICENSE"
cp "${SOURCE}/package/failover_monitor.sh" "${WORKDIR}/tailscale/"
cp "${SOURCE}/package/tailscale-monitor.service" "${WORKDIR}/tailscale/"

mkdir -p "${WORKDIR}/on_boot.d"
mv "${WORKDIR}/tailscale/on-boot.sh" "${WORKDIR}/on_boot.d/10-tailscaled.sh"

echo ""
echo "Package Contents:"
ls -l "$WORKDIR"/*
echo ""

echo "Building tailscale-udm package"
mkdir -p "${DEST}"
# Assuming GNU tar with the --owner and --group args
tar czf "${DEST}/tailscale-udm.tgz" -C "${WORKDIR}" tailscale on_boot.d --owner=0 --group=0
