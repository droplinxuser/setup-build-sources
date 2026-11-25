#!/usr/bin/env bash
# Refresh the mirror: the newest release of every source archive the
# compiled builds of ubuntu-setup-script 1.22 download (php-fpm and the php
# CLI, nginx, Valkey), fetched and checked by the same code the servers run
# (tools/build-common.sh, plus tools/php-build.sh for SQLite and ICU), then
# added as a release asset.  One release per component (tag = component
# name); SHA256SUMS in each release lists every file it holds.  A file
# already mirrored is never replaced: if the upstream file under the same
# name changed, the run fails and says so.
#
# nginx: each tarball is mirrored with its nginx.org .asc signature next to
# it.  A server verifies the PGP signature of every nginx tarball, mirrored
# ones too, and refuses a tarball without one.  This run adds a tarball only
# after its signature checked out against the pinned nginx.org keys.
set -Eeuo pipefail
export LC_ALL=C
REPO=${GITHUB_REPOSITORY:?run from GitHub Actions or set GITHUB_REPOSITORY=owner/name}
WORK=${RUNNER_TEMP:-/tmp}/setup-build-mirror
# The branch of ubuntu-setup-script whose build tools say what to mirror.
USS_REF=${USS_REF:-main}
TOOLS_URL=${TOOLS_URL:-https://raw.githubusercontent.com/droplinxuser/ubuntu-setup-script/$USS_REF/tools}
rm -rf "$WORK"; mkdir -p "$WORK/cache/src" "$WORK/none"
for t in build-common.sh php-build.sh nginx-build.sh; do
  curl -fsSL --retry 3 "$TOOLS_URL/$t" -o "$WORK/$t"
done
grep -q 'PHP_BUILD_SOURCE_ONLY' "$WORK/php-build.sh" \
  || { echo "::error::$TOOLS_URL/php-build.sh is older than 1.22 (no PHP_BUILD_SOURCE_ONLY); set USS_REF"; exit 1; }

# What php-build.sh and build-common.sh expect from the environment.  The
# config file does not exist, so every component resolves to "latest"; the
# mirror never falls back to itself.  PHP_BUILD_SOURCE_ONLY=1 loads the
# functions without running a command.
export SETUP_BUILD_MIRROR=off PHP_BUILD_SOURCE_ONLY=1
export PHP_BUILD_COMMON=$WORK/build-common.sh PHP_BUILD_CACHE=$WORK/cache
export PHP_BUILD_ROOT=$WORK/none PHP_BUILD_CONF=$WORK/none/php-build.conf
# shellcheck source=/dev/null
. "$WORK/php-build.sh"
# shellcheck disable=SC2034 # read by build-common.sh
LOG_TAG=setup-build-mirror

# Every component the three build tools fetch, except LLVM (apt.llvm.org,
# then LLVM's own GitHub release).  zlib-ng is the default; zlib is the
# PHP_BUILD_ZLIB=zlib alternative.  ICU is built only for intl.
COMPONENTS=(openssl pcre2 zlib-ng zlib libxml2 libsodium gmp libiconv curl
            libjpeg-turbo libpng libwebp libzip sqlite icu redis igbinary
            nginx brotli ngx-brotli valkey)
FAIL=0
ADDED=0 KEPT=0 MISSED=0

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
    KEPT=$(( KEPT + 1 ))
    return 0
  fi
  gh release upload "$comp" -R "$REPO" "$f" >/dev/null
  printf '%s  %s\n' "$sum" "$base" >> "$WORK/SHA256SUMS"
  gh release upload "$comp" -R "$REPO" "$WORK/SHA256SUMS" --clobber >/dev/null
  echo "added $comp/$base"
  ADDED=$(( ADDED + 1 ))
}

mirror_one() { # component version
  local f
  if f=$(fetch_component "$1" "$2"); then
    # fetch_nginx_signed returns the tarball only when FILE.asc verified.
    # The signature goes up first, so the tarball is never there without it.
    if [[ $1 == nginx ]]; then
      [[ -s $f.asc ]] || { echo "::error::nginx $2: no verified .asc beside the tarball"; FAIL=1; return 0; }
      publish nginx "$f.asc"
    fi
    publish "$1" "$f"
  else
    echo "::warning::$1 $2: no upstream source answered (or nothing verified); nothing mirrored this run"
    MISSED=$(( MISSED + 1 ))
  fi
}

for c in "${COMPONENTS[@]}"; do
  if v=$(latest_of "$c"); [[ -n ${v:-} ]]; then mirror_one "$c" "$v"
  else echo "::warning::$c: cannot resolve the newest release"
  fi
done

# nginx-build.sh's fallback version: a fresh host whose branding patch fails
# on the newest mainline builds this one instead.
fb=$(sed -nE 's/^NGINX_FALLBACK_DEFAULT=([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' "$WORK/nginx-build.sh" | sed -n 1p)
if [[ -n $fb && $fb != "$(latest_of nginx || true)" ]]; then mirror_one nginx "$fb"; fi

# PHP: the newest release of every series from 8.1 (the oldest the build
# recipe supports) up to the newest series php.net has released.
newest=$(php_newest_release || true)
nx=${newest%.*} nmaj=${newest%%.*}
[[ $nmaj =~ ^[0-9]+$ ]] || { echo "::warning::cannot resolve the newest PHP release; trying 8.x"; nx="" nmaj=8; }
for (( maj = 8; maj <= nmaj; maj++ )); do
  for (( min = (maj == 8 ? 1 : 0); ; min++ )); do
    x=$maj.$min
    if [[ -n $nx ]] && ! ver_ge "$nx" "$x"; then break; fi
    if v=$(latest_of php "$x"); [[ ${v:-} == "$x".* ]]; then mirror_one php "$v"
    else echo "php $x: no release"; break
    fi
  done
done

# PHP 8.1 builds with the newest OpenSSL 3.x (it does not compile against
# OpenSSL 4); php-build.sh's latest_of picks that line for series 8.1.
o3=$(latest_of openssl 8.1 || true)
if [[ -n $o3 && $o3 != "$(latest_of openssl || true)" ]]; then mirror_one openssl "$o3"; fi

echo "added $ADDED, already mirrored $KEPT, unreachable $MISSED"
# A run that mirrored nothing at all is broken, not quiet.
(( ADDED + KEPT > 0 )) || { echo "::error::nothing could be mirrored"; FAIL=1; }
exit "$FAIL"
