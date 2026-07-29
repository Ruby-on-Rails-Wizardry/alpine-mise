#!/usr/bin/env bash
# Install PostgreSQL client tools and libpq development headers (for the pg gem).
#
# Alpine packages major versions as postgresqlN-client / postgresqlN-dev.
# Not every major is in a given Alpine release (e.g. 3.22 has 15–17, not 18).
# When POSTGRESQL_VERSION is missing from apk, we fall back (see resolve_major).
#
# Expected environment (Docker build ARG / ENV):
#   POSTGRESQL_VERSION  major version (e.g. 15, 16, 17, 18).
#                       Empty / unset → no install (exit 0).
#
# Installs when version is set:
#   postgresqlN-client  — psql and related CLI tools
#   postgresqlN-dev     — headers/libs for native pg gem builds

set -euo pipefail

POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-}"

log() {
  # stderr so command substitutions (resolve_major) only capture the version
  printf 'setup-postgresql: %s\n' "$*" >&2
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "setup-postgresql: must run as root" >&2
    exit 1
  fi
}

# Print available major versions (one per line), sorted ascending.
list_available_majors() {
  apk search -q 'postgresql*-client' 2>/dev/null \
    | sed -n 's/^postgresql\([0-9][0-9]*\)-client$/\1/p' \
    | sort -n -u
}

# Resolve requested major to a package major that exists in apk.
# Prefer exact match; else highest available ≤ requested; else highest available.
resolve_major() {
  local want="$1"
  local available majors m best_le=""

  available="$(list_available_majors)"
  if [[ -z "${available}" ]]; then
    echo "setup-postgresql: no postgresqlN-client packages in apk index" >&2
    exit 1
  fi

  while IFS= read -r m; do
    [[ -z "${m}" ]] && continue
    majors="${majors:+$majors }$m"
    if [[ "${m}" == "${want}" ]]; then
      printf '%s\n' "${m}"
      return 0
    fi
    if [[ "${m}" -le "${want}" ]]; then
      best_le="${m}"
    fi
  done <<< "${available}"

  if [[ -n "${best_le}" ]]; then
    log "postgresql${want}-client not in apk; using ${best_le} (highest available ≤ ${want}; have: ${majors})"
    printf '%s\n' "${best_le}"
    return 0
  fi

  # Requested older than every available major — use the lowest available.
  m="$(printf '%s\n' ${majors} | head -1)"
  log "postgresql${want}-client not in apk; using ${m} (lowest available; have: ${majors})"
  printf '%s\n' "${m}"
}

install_client_and_dev() {
  local ver client_pkg dev_pkg

  # Ensure index is present for search + install.
  apk update >/dev/null
  ver="$(resolve_major "${POSTGRESQL_VERSION}")"
  client_pkg="postgresql${ver}-client"
  dev_pkg="postgresql${ver}-dev"

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
