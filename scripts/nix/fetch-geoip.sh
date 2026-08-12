#!/usr/bin/env bash
# Download the GeoLite2 City database used by the geofence feature.
#
# This is deliberately a runtime fetch rather than a Nix fixed-output
# derivation: the upstream mirror re-publishes the file regularly, so a pinned
# hash would break the build every time MaxMind refresh their data.
#
# The database is MaxMind licensed. We do not redistribute it; each developer
# fetches their own copy, exactly as the Dockerfiles do at image build time.
set -euo pipefail

# Resolve the repository root so this works both when run directly from a
# checkout and when installed into the Nix store by writeShellApplication.
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export PROJECT_ROOT
# shellcheck source=./common.sh
. "${PROJECT_ROOT}/scripts/nix/common.sh"

URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
TARGET="${GEOIP_DIR}/GeoLite2-City.mmdb"

mkdir -p "${GEOIP_DIR}"

echo "Fetching GeoLite2-City.mmdb"
# Download to a temporary file so an interrupted transfer cannot leave a
# truncated database in place.
tmp="$(mktemp "${GEOIP_DIR}/.GeoLite2-City.mmdb.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT

curl --fail --location --silent --show-error --output "${tmp}" "${URL}"

# A valid mmdb is several megabytes; anything tiny means we fetched an error
# page or a redirect stub.
size="$(wc -c <"${tmp}")"
if [ "${size}" -lt 1000000 ]; then
    die "downloaded file is only ${size} bytes, that is not a valid mmdb database"
fi

mv "${tmp}" "${TARGET}"
trap - EXIT

echo "GeoIP database installed at ${TARGET} ($((size / 1024 / 1024)) MB)"
