FROM ghcr.io/blankon/blankon-nightly:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        live-build \
        debootstrap \
        coreutils \
        mount \
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
