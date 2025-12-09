#!/bin/bash

set -euo pipefail

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    echo "Cannot detect OS: /etc/os-release missing"
    exit 1
fi

mkdir -p /etc/oke/
mkdir -p /etc/kubernetes/

version_ge() {
    local v1="$1"
    local v2="$2"

    [[ -n "$v1" ]] || return 1
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | tail -n1)" == "$v1" ]]
}

# Fix for CRI-O short name mode not being disabled for Kubernetes versions >= 1.34
configure_crio_defaults() {
    local version="$1"

    if version_ge "$version" "v1.34"; then
        echo "Configuring CRI-O defaults for Kubernetes version $version"
        mkdir -p /etc/crio/crio.conf.d
        cat >/etc/crio/crio.conf.d/11-default.conf <<'EOF'
[crio.image]
short_name_mode = "disabled"
EOF
    fi
}

kubernetes_version="${1-}"

if command -v oke >/dev/null 2>&1; then
    echo "[Ubuntu] oke binary already present, running bootstrap only"
    configure_crio_defaults "$kubernetes_version"
    oke bootstrap --label corrino/pool-shared-any=true --label corrino=ai-accelerator
else
    echo "[Ubuntu] oke binary not found, installing package"
    oke_package_version="${kubernetes_version:1}"
    oke_package_repo_version="${oke_package_version:0:4}"
    oke_package_name="oci-oke-node-all-$oke_package_version"
    oke_package_repo="https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-$VERSION_CODENAME/kubernetes-$oke_package_repo_version"

    tee /etc/apt/sources.list.d/oke-node-client.sources > /dev/null <<EOF
Enabled: yes
Types: deb
URIs: $oke_package_repo
Suites: stable
Components: main
Trusted: yes
EOF

    # Wait for apt lock and install the package
    while fuser /var/{lib/{dpkg/{lock,lock-frontend},apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
        echo "Waiting for dpkg/apt lock"
        sleep 1
    done

    apt-get -y update
    apt-get -y install "$oke_package_name"

    echo "[Ubuntu] Running bootstrap"
    configure_crio_defaults "$kubernetes_version"
    oke bootstrap --label corrino/pool-shared-any=true --label corrino=ai-accelerator

fi

echo "OKE setup completed successfully."