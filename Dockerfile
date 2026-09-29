FROM ghcr.io/blankon/blankon-nightly:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN printf '%s\n' 'deb http://arsip-dev.blankonlinux.id/sinambung sinambung main restricted extras restricted-firmware' > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        live-build \
        debootstrap \
        coreutils \
        mount \
        util-linux \
        procps \
        make \
        git \
        apt-utils \
        blankon-keyring \
        zsync \
        curl \
        jq \
        tar \
        sudo \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workdir
