# setup-build-sources

A mirror of the upstream source archives that
[ubuntu-setup-script](https://github.com/droplinxuser/ubuntu-setup-script)'s
compiled builds download.  Since 1.22 every PHP, nginx and Valkey on a
setup.sh host is built from source: php-fpm and the php CLI
(`tools/php-build.sh`), nginx (`tools/nginx-build.sh`) and Valkey
(`tools/valkey-build.sh`).

Every download in those builds already has two upstream sources (the
project's own site, then its GitHub release or a second official mirror).
This repository is the third, tried only when both fail: a release deleted
or re-tagged upstream, a site down for hours, a mirror that stalls.

## Layout

* One **release per component**, tagged with the component's name:
  * PHP: `php` (the newest release of every series from 8.1 up), `redis`,
    `igbinary`, `sqlite`, `icu` (built only for `intl`), and the libraries
    PHP links: `openssl`, `pcre2`, `zlib-ng`, `zlib`, `libxml2`,
    `libsodium`, `gmp`, `libiconv`, `curl`, `libjpeg-turbo`, `libpng`,
    `libwebp`, `libzip`.
  * nginx: `nginx` (the newest mainline release, plus the fallback version
    `tools/nginx-build.sh` names), `brotli`, `ngx-brotli`, and the shared
    `openssl`, `pcre2` and `zlib-ng`.
  * Valkey: `valkey`.
* Its assets are the **unmodified** upstream archives under the file names
  the build tools use, plus a `SHA256SUMS` listing every one of them.
* The `nginx` release also holds each tarball's nginx.org signature,
  `nginx-X.Y.Z.tar.gz.asc`, next to it.
* Download URL: `https://github.com/droplinxuser/setup-build-sources/releases/download/<component>/<file>`.

LLVM is not mirrored: its first source is apt.llvm.org and its second is
LLVM's own GitHub release.

The `angie` release is left as it was for 1.21 hosts.  Nothing new is added
to it.

## How it stays honest

* `mirror.sh` runs daily (`.github/workflows/mirror.yml`) with the same
  code the servers run (`tools/build-common.sh`, and `tools/php-build.sh`
  for SQLite and ICU), taken from ubuntu-setup-script's `main` branch
  (`USS_REF` picks another).  These archives are checked against their
  published checksum before they are added: the SHA-256 of PHP, OpenSSL,
  libxml2, curl, libsodium, libzip, PCRE2, libjpeg-turbo, ICU and zlib
  (GitHub's release digest), and SQLite's SHA3-256.  Valkey is added on
  its first-seen hash; the servers check it against valkey-io/valkey-hashes
  when they download it from the mirror.
* An nginx tarball is added only with a good PGP signature by one of the
  nginx.org keys pinned in `tools/build-common.sh`, and its `.asc` goes up
  first.
* A file is never replaced.  If an upstream file changes under the same
  name, the run fails and the mirrored copy stays.
* A server accepts a file from here only if it matches, in order: the
  upstream's published SHA-256, the hash it pinned on its own first download
  of that file, or this release's `SHA256SUMS`.
* nginx is stricter.  A server takes `nginx-X.Y.Z.tar.gz` and its `.asc`
  from here and checks the signature against the same pinned keys, exactly
  as for a download from nginx.org.  A tarball without a good signature is
  refused and the running nginx keeps serving.
* Valkey: a server checks the tarball against the SHA-256 in the Valkey
  project's valkey-hashes repository when that repository answers.

`SETUP_BUILD_MIRROR=off` turns the mirror off on a server;
`SETUP_BUILD_MIRROR=https://github.com/<you>/<fork>/releases/download` points
at a fork.

## Licences

The archives are the projects' own source releases, redistributed unmodified
under their own licences (PHP License, BSD-2-Clause for nginx, BSD-3-Clause
for Valkey, Apache-2.0, MIT, zlib, Unicode, public domain for SQLite,
LGPL/GPL, ...); each archive carries its licence file.  The scripts in this
repository are MIT-licensed (`LICENSE`).

GitHub disables scheduled workflows in a repository with no activity for 60
days (it e-mails the owner first); re-enable it under Actions, or run the
workflow by hand.
