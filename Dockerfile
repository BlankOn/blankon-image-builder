FROM ghcr.io/blankon/blankon-nightly:latest

ENV DEBIAN_FRONTEND=noninteractive

COPY tools/patch-live-build-sysfs.py /usr/local/bin/patch-live-build-sysfs.py

RUN apt-get update \
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
        ca-certificates \
        python3 \
    && python3 /usr/local/bin/patch-live-build-sysfs.py \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workdir

COPY tools/generate_seccomp_profile.py /usr/local/bin/generate-seccomp-profile.py
COPY build-iso /usr/local/bin/build-iso
COPY purge-iso /usr/local/bin/purge-iso
