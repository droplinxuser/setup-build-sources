# setup-build-sources

A mirror of the upstream source archives that
[ubuntu-setup-script](https://github.com/droplinxuser/ubuntu-setup-script)'s
compiled builds download: php-fpm (`--source=php`), Angie (`--source=angie`)
and Valkey (`--source=valkey`).

Every download in those builds already has two upstream sources (the
project's own site, then its GitHub release or a second official mirror).
This repository is the third, tried only when both fail: a release deleted
or re-tagged upstream, a site down for hours, a mirror that stalls.

## Layout

* One **release per component**, tagged with the component's name (`php`,
  `openssl`, `pcre2`, `zlib-ng`, `libxml2`, `libsodium`, `gmp`, `libiconv`,
  `curl`, `libjpeg-turbo`, `libpng`, `libwebp`, `libzip`, `redis`,
  `igbinary`, `angie`, `brotli`, `ngx-brotli`, `valkey`).
* Its assets are the **unmodified** upstream archives under the file names
  the build tools use, plus a `SHA256SUMS` listing every one of them.
* Download URL: `https://github.com/droplinxuser/setup-build-sources/releases/download/<component>/<file>`.

LLVM is not mirrored: its first source is apt.llvm.org and its second is
LLVM's own GitHub release.

## How it stays honest

* `mirror.sh` runs daily (`.github/workflows/mirror.yml`) and with the same
  code the servers run (`tools/build-common.sh`): every archive with a
  published SHA-256 (PHP, OpenSSL, libxml2, curl, libsodium, libzip, PCRE2,
  libjpeg-turbo) is checked against it before it is added.
* An archive is never replaced.  If an upstream file changes under the same
  name, the run fails and the mirrored copy stays.
* A server accepts a file from here only if it matches, in order: the
  upstream's published SHA-256, the hash it pinned on its own first download
  of that file, or this release's `SHA256SUMS`.

`SETUP_BUILD_MIRROR=off` turns the mirror off on a server;
`SETUP_BUILD_MIRROR=https://github.com/<you>/<fork>/releases/download` points
at a fork.

## Licences

The archives are the projects' own source releases, redistributed unmodified
under their own licences (PHP License, Apache-2.0, BSD, MIT, zlib, LGPL/GPL,
BSD-2-Clause, ...); each archive carries its licence file.  The scripts in
this repository are MIT-licensed (`LICENSE`).

GitHub disables scheduled workflows in a repository with no activity for 60
days (it e-mails the owner first); re-enable it under Actions, or run the
workflow by hand.
