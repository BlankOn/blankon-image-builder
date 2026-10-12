FROM ghcr.io/blankon/blankon-nightly@sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5 AS live-build-package

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        debhelper \
        devscripts \
        gettext \
        po4a \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY tools/live-build-sysfs-recursive-unmount.patch /tmp/live-build-sysfs-recursive-unmount.patch

RUN git init /tmp/live-build-source \
    && git -C /tmp/live-build-source fetch --depth=1 https://salsa.debian.org/live-team/live-build.git 531cdb9854e04d08c3c3770463454d8a5e91b129 \
    && git -C /tmp/live-build-source checkout --detach FETCH_HEAD \
    && test "$(git -C /tmp/live-build-source rev-parse HEAD)" = 531cdb9854e04d08c3c3770463454d8a5e91b129 \
    && git -C /tmp/live-build-source apply --check --whitespace=error /tmp/live-build-sysfs-recursive-unmount.patch \
    && git -C /tmp/live-build-source apply --whitespace=error /tmp/live-build-sysfs-recursive-unmount.patch \
    && (cd /tmp/live-build-source \
        && DEBEMAIL=builder@example.invalid DEBFULLNAME='BlankOn Image Builder' dch \
            --no-conf --preserve --no-auto-nmu \
            --newversion '1:20250814+git531cdb9854e04d08c3c3770463454d8a5e91b129+blankon1' \
            --distribution UNRELEASED \
            --force-distribution \
            'Apply recursive sysfs teardown for rootless container builds' \
        && dpkg-checkbuilddeps \
        && dpkg-buildpackage -b -us -uc) \
    && mv /tmp/live-build_*_all.deb /tmp/live-build.deb \
    && rm -rf /tmp/live-build-source /tmp/live-build-sysfs-recursive-unmount.patch

FROM ghcr.io/blankon/blankon-nightly@sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=live-build-package /tmp/live-build.deb /tmp/live-build.deb

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
        /tmp/live-build.deb \
    && test "$(dpkg-query -W -f='${Version}' live-build)" = '1:20250814+git531cdb9854e04d08c3c3770463454d8a5e91b129+blankon1' \
    && rm -f /tmp/live-build.deb \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workdir

COPY build-iso /usr/local/bin/build-iso
COPY purge-iso /usr/local/bin/purge-iso
