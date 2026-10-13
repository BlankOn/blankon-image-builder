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
        live-build=1:20250814+git531cdb9854e04d08c3c3770463454d8a5e91b129+blankon1 \
    && test "$(dpkg-query -W -f='${Version}' live-build)" = '1:20250814+git531cdb9854e04d08c3c3770463454d8a5e91b129+blankon1' \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workdir

COPY build-iso /usr/local/bin/build-iso
COPY purge-iso /usr/local/bin/purge-iso
