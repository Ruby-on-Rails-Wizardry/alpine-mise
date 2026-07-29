#!/usr/bin/env bash
# Install PostgreSQL client tools and libpq development headers (for the pg gem).
#
# Alpine packages major versions as postgresqlN-client / postgresqlN-dev.
#
# Expected environment (Docker build ARG / ENV):
#   POSTGRESQL_VERSION  major version (e.g. 15, 16, 17).
#                       Empty / unset → no install (exit 0).
#
# Installs when version is set:
#   postgresql${POSTGRESQL_VERSION}-client  — psql and related CLI tools
#   postgresql${POSTGRESQL_VERSION}-dev     — headers/libs for native pg gem builds

set -euo pipefail

POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-}"

log() {
  printf 'setup-postgresql: %s\n' "$*"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "setup-postgresql: must run as root" >&2
    exit 1
  fi
}

install_client_and_dev() {
  local client_pkg="postgresql${POSTGRESQL_VERSION}-client"
  local dev_pkg="postgresql${POSTGRESQL_VERSION}-dev"

  log "installing ${client_pkg} and ${dev_pkg}"
  apk add --no-cache "${client_pkg}" "${dev_pkg}"

  log "psql: $(psql --version 2>/dev/null || echo 'not on PATH')"
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libpq 2>/dev/null; then
    log "libpq: $(pkg-config --modversion libpq)"
  else
    log "${dev_pkg} installed"
  fi
}

main() {
  require_root

  if [[ -z "${POSTGRESQL_VERSION}" ]]; then
    log "POSTGRESQL_VERSION unset — skipping PostgreSQL client install"
    exit 0
  fi

  if ! [[ "${POSTGRESQL_VERSION}" =~ ^[0-9]+$ ]]; then
    echo "setup-postgresql: POSTGRESQL_VERSION must be a major number (got: ${POSTGRESQL_VERSION})" >&2
    exit 1
  fi

  log "POSTGRESQL_VERSION=${POSTGRESQL_VERSION}"
  install_client_and_dev
  log "done"
}

main "$@"
