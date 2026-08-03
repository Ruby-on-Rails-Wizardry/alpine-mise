# Minimal Alpine image: non-root user + mise + shared /cache.
# Layout: home at /home/$USER; shared caches at /cache
#   (Bundler, Yarn 1 + Berry, npm, pip/uv/poetry, mise).
# Login shells (bash, ksh/mksh, sh/ash, zsh, fish) activate mise via shell rc files.

FROM alpine:3.22

# Container login name (default "dev"). Pair with DEV_UID / DEV_GID for bind mounts.
ARG USER=dev
ARG DEV_UID=1000
ARG DEV_GID=1000
ARG MISE_VERSION=v2026.7.7
ARG CACHE_ROOT=/cache
# Optional major version (e.g. 15–18). Default 18 = current stable client.
ARG POSTGRESQL_VERSION=18

# Image/user layout + shared package/tool caches under CACHE_ROOT.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    USER=${USER} \
    CACHE_ROOT=${CACHE_ROOT} \
    POSTGRESQL_VERSION=${POSTGRESQL_VERSION} \
    MISE_DATA_DIR=${CACHE_ROOT}/mise \
    MISE_CONFIG_DIR=/home/${USER}/.config/mise \
    MISE_CACHE_DIR=${CACHE_ROOT}/mise-cache \
    # Alpine is musl: jdx/ruby prebuilts are glibc-linked and will not run here.
    # Always compile Ruby via ruby-build (toolchain is in the image).
    MISE_RUBY_COMPILE=true \
    MISE_TRUSTED_CONFIG_PATHS=/work \
    XDG_STATE_HOME=${CACHE_ROOT}/xdg-state \
    BUNDLE_PATH=${CACHE_ROOT}/bundle \
    BUNDLE_CACHE_PATH=${CACHE_ROOT}/rubygems \
    BUNDLE_CLEAN=false \
    YARN_CACHE_FOLDER=${CACHE_ROOT}/yarn-cache \
    YARN_OFFLINE_MIRROR=${CACHE_ROOT}/yarn \
    YARN_GLOBAL_FOLDER=${CACHE_ROOT}/yarn-global \
    YARN_ENABLE_GLOBAL_CACHE=true \
    NPM_CONFIG_CACHE=${CACHE_ROOT}/npm \
    npm_config_cache=${CACHE_ROOT}/npm \
    PIP_CACHE_DIR=${CACHE_ROOT}/pip \
    UV_CACHE_DIR=${CACHE_ROOT}/uv \
    POETRY_CACHE_DIR=${CACHE_ROOT}/poetry \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    PATH=/docker/bin:/home/${USER}/.local/bin:${CACHE_ROOT}/mise/shims:${PATH} \
    HOME=/home/${USER}

# Shells + compilers/headers so mise (ruby-build/python-build), native gems,
# and pip/npm extensions can compile when prebuilts are missing.
# shadow: useradd/usermod; sudo drop-in + wheel. ksh → mksh (no ksh93 package).
RUN apk add --no-cache \
        autoconf \
        bash \
        bison \
        build-base \
        bzip2-dev \
        ca-certificates \
        curl \
        fish \
        gdbm-dev \
        git \
        less \
        libffi-dev \
        libxml2-dev \
        libxslt-dev \
        linux-headers \
        lsb-release-minimal \
        mksh \
        ncurses-dev \
        neovim \
        openssl-dev \
        pkgconf \
        readline-dev \
        shadow \
        sqlite-dev \
        sudo \
        tzdata \
        unzip \
        vim \
        wget \
        xz-dev \
        yaml-dev \
        zlib-dev \
        zsh \
    && ln -sf /bin/mksh /usr/bin/ksh

# /docker: build setup-* scripts + runtime tools under /docker/bin (on PATH).
COPY --chmod=755 docker/ /docker/

# Non-root user (name / UID / GID overridable). See docker/setup-user.sh.
RUN USER="${USER}" DEV_UID="${DEV_UID}" DEV_GID="${DEV_GID}" /docker/setup-user.sh

# Seed image-user home (gem/npm/yarn/pip/… globals). Owned by build UID/GID.
# Source tree: ./home/ → /home/$USER/ (dotfiles included).
COPY --chown=${DEV_UID}:${DEV_GID} home/ /home/${USER}/

# Shared /cache tree + profile.d + helpers. See docker/setup-cache.sh.
RUN USER="${USER}" CACHE_ROOT="${CACHE_ROOT}" FLAVOR=alpine-mise /docker/setup-cache.sh

# Optional PostgreSQL client + dev headers (no-op when POSTGRESQL_VERSION is empty).
#   docker build --build-arg POSTGRESQL_VERSION=17 …
RUN POSTGRESQL_VERSION="${POSTGRESQL_VERSION}" /docker/setup-postgresql.sh

USER ${USER}
WORKDIR /home/${USER}

# Install mise (https://mise.jdx.dev) for the image user.
# The installer detects musl and pulls the Alpine-compatible binary.
# Tools install into MISE_DATA_DIR (/cache/mise); binary stays in ~/.local/bin.
RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" sh \
    && ~/.local/bin/mise --version \
    && ~/.local/bin/mise reshim

# Verify home/ shell defaults + mise (rc files are seeded from home/, not rewritten).
RUN /docker/setup-mise-shell.sh

# Self-checks (on PATH via /docker/bin):
#   docker run --rm --entrypoint verify-login-shells IMAGE
#   docker run --rm --entrypoint verify-caches IMAGE
#   task verify

# Runtime entrypoint is user-independent (/docker/bin; USER baked at build).
ENTRYPOINT ["/docker/bin/docker-entrypoint"]
# Default to an interactive login shell so profile-based mise setup always runs.
CMD ["bash", "-l"]
