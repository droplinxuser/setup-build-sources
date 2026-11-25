#!/usr/bin/env bash
# Refresh the mirror: the newest release of every source archive the
# compiled builds of ubuntu-setup-script download (php-fpm, Angie, Valkey),
# fetched and checked by the same code the servers run
# (tools/build-common.sh), then added as a release asset.  One release per
# component (tag = component name); SHA256SUMS in each release lists every
# archive it holds.  An archive already mirrored is never replaced: if the
# upstream file under the same name changed, the run fails and says so.
set -Eeuo pipefail
export LC_ALL=C
REPO=${GITHUB_REPOSITORY:?run from GitHub Actions or set GITHUB_REPOSITORY=owner/name}
WORK=${RUNNER_TEMP:-/tmp}/setup-build-mirror
COMMON_URL=${COMMON_URL:-https://raw.githubusercontent.com/droplinxuser/ubuntu-setup-script/main/tools/build-common.sh}
rm -rf "$WORK"; mkdir -p "$WORK"
curl -fsSL --retry 3 "$COMMON_URL" -o "$WORK/build-common.sh"

# What build-common.sh expects from the tool that sources it.  CONF does not
# exist, so every component resolves to "latest"; the mirror never falls back
# to itself.
# shellcheck disable=SC2034
LOG_TAG=setup-build-mirror SRC_CACHE=$WORK/cache CONF=$WORK/none ROOT=$WORK/none
export SETUP_BUILD_MIRROR=off
# shellcheck source=/dev/null
. "$WORK/build-common.sh"

COMPONENTS=(openssl pcre2 zlib-ng libxml2 libsodium gmp libiconv curl libjpeg-turbo
            libpng libwebp libzip redis igbinary angie brotli ngx-brotli valkey)
# PHP: the newest release of every series setup.sh can install.
PHP_SERIES=(8.3 8.4 8.5 8.6)
FAIL=0

publish() { # component file
  local comp=$1 f=$2 base sum have
  base=${f##*/}
  sum=$(sha256sum "$f" | awk '{print $1}')
  if ! gh release view "$comp" -R "$REPO" >/dev/null 2>&1; then
    gh release create "$comp" -R "$REPO" --title "$comp" \
      --notes "Unmodified upstream source archives of $comp, mirrored for ubuntu-setup-script's compiled builds. SHA256SUMS lists every file." >/dev/null
  fi
  rm -f "$WORK/SHA256SUMS"
  gh release download "$comp" -R "$REPO" -p SHA256SUMS -D "$WORK" >/dev/null 2>&1 || : > "$WORK/SHA256SUMS"
  have=$(awk -v f="$base" '$2 == f { print $1; exit }' "$WORK/SHA256SUMS")
  if [[ -n $have ]]; then
    if [[ $have != "$sum" ]]; then
      echo "::error::$comp/$base changed upstream (mirrored $have, now $sum); the mirrored copy is kept"
      FAIL=1
    fi
    return 0
  fi
  gh release upload "$comp" -R "$REPO" "$f" >/dev/null
  printf '%s  %s\n' "$sum" "$base" >> "$WORK/SHA256SUMS"
  gh release upload "$comp" -R "$REPO" "$WORK/SHA256SUMS" --clobber >/dev/null
  echo "added $comp/$base"
}

mirror_one() { # component version
  local f
  if f=$(fetch_component "$1" "$2"); then
    publish "$1" "$f"
  else
    echo "::warning::$1 $2: no upstream source answered; nothing mirrored this run"
  fi
}

for c in "${COMPONENTS[@]}"; do
  if v=$(latest_of "$c"); [[ -n ${v:-} ]]; then mirror_one "$c" "$v"
  else echo "::warning::$c: cannot resolve the newest release"
  fi
done
for x in "${PHP_SERIES[@]}"; do
  if v=$(latest_of php "$x"); [[ $v == "$x".* ]]; then mirror_one php "$v"
  else echo "php $x: no release yet"
  fi
done
exit "$FAIL"
