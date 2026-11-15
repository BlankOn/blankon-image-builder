FROM ghcr.io/blankon/blankon-nightly@sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
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
        ca-certificates \
        python3 \
        live-build \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workdir

COPY libexec/blankon-image-builder/build-iso-runtime /usr/local/libexec/blankon-image-builder/build-iso-runtime
COPY purge-iso /usr/local/bin/purge-iso
