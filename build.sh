#!/usr/bin/env bash
set -euo pipefail

BASE="${BPT_BASE:-https://www.gov.uk/government/uploads/uploaded/hmrc}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="${BPT_CACHE:-$ROOT/.cache}"
BUILD="${BPT_BUILD:-$ROOT/build}"
DIST="${BPT_DIST:-$ROOT/dist}"
LOCK="$ROOT/lock.json"
SWEEP_TO="${BPT_SWEEP_TO:-40}"

die() { printf 'simple-bpt: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*" >&2; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

json_get() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

manifest_version() {
  local major="$1" body
  body="$(curl -fsL --max-time 30 "$BASE/realtimepayetools-update-v$major.xml" 2>/dev/null)" || return 0
  printf '%s' "$body" | tr -d '\n' \
    | sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p'
}

newest_version() {
  local major v found=""
  for ((major = 14; major <= SWEEP_TO; major++)); do
    v="$(manifest_version "$major")"
    [ -n "$v" ] && found="$v"
  done
  [ -n "$found" ] || die "no manifest answered"
  printf '%s' "$found"
}

fetch() {
  local version="$1" want="$2"
  local zip="payetools-rti-$version-linux.zip"
  local out="$CACHE/$zip"

  mkdir -p "$CACHE"
  if [ ! -s "$out" ]; then
    log "downloading $zip"
    curl -fL --max-time 1800 --progress-bar -o "$out.part" "$BASE/$zip" \
      || die "download failed: $BASE/$zip"
    mv "$out.part" "$out"
  else
    log "using cached $zip"
  fi

  local got
  got="$(sha256 "$out")"
  if [ "$want" != "PENDING" ] && [ "$got" != "$want" ]; then
    die "sha256 mismatch for $zip: expected $want, got $got"
  fi
  printf '%s' "$out"
}

extract() {
  local zip="$1" appimage offset

  rm -rf "$BUILD"
  mkdir -p "$BUILD"
  log "unpacking release zip"
  unzip -q -o "$zip" -d "$BUILD"

  appimage="$(find "$BUILD" -maxdepth 1 -name '*.AppImage' -print -quit)"
  [ -n "$appimage" ] || die "no AppImage in $zip"

  offset="$("$ROOT/appimage-offset.py" "$appimage")" \
    || die "no squashfs offset in $appimage"
  log "squashfs starts at byte $offset"

  if command -v unsquashfs >/dev/null 2>&1; then
    unsquashfs -q -f -o "$offset" -d "$BUILD/squashfs-root" "$appimage" >/dev/null
  elif [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
    log "unsquashfs not found, falling back to --appimage-extract"
    chmod +x "$appimage"
    ( cd "$BUILD" && "$appimage" --appimage-extract >/dev/null )
  else
    die "need unsquashfs (squashfs-tools)"
  fi

  [ -d "$BUILD/squashfs-root/usr/bptserver" ] || die "no usr/bptserver in the AppImage"
}

verify() {
  local dir="$1" rti="$1/rti.linux" listing n

  [ -f "$rti" ] || die "no rti.linux in $dir"

  listing="$(unzip -l "$rti" 2>/dev/null)" || die "rti.linux has no appended zip"

  n="$(printf '%s\n' "$listing" | tail -1 | awk '{print $2}')"
  log "rti.linux carries $n frozen modules"

  [[ "$listing" == *"__main__.pyc"* ]] || die "rti.linux has no __main__.pyc"
  [[ "$listing" == *"mysite/settings.pyc"* ]] || log "warning: no mysite/settings.pyc"

  [ -f "$dir/libpython2.7.so.1.0" ] || [ -f "$dir/libpython2.7.so" ] \
    || log "warning: no libpython2.7.so beside rti.linux"

  [ -f "$dir/sqlite3.db" ] || log "warning: no seed database beside rti.linux"
}

assemble() {
  local version="$1" src="$BUILD/squashfs-root/usr/bptserver"

  verify "$src"

  rm -rf "$DIST"
  mkdir -p "$DIST/bptserver"
  log "assembling dist/"
  cp -a "$src/." "$DIST/bptserver/"
  chmod -R u+rwX "$DIST/bptserver"
  chmod +x "$DIST/bptserver/rti.linux"

  install -m 0755 "$ROOT/bin/simple-bpt" "$DIST/simple-bpt"
  printf '%s\n' "$version" > "$DIST/VERSION"

  log "built $version into $DIST ($(du -sh "$DIST" | cut -f1))"
}

cmd_check() {
  local pinned newest
  pinned="$(json_get "$LOCK" version)"
  newest="$(newest_version)"
  log "pinned:     $pinned"
  log "advertised: $newest"
  if [ "$pinned" = "$newest" ]; then
    echo "up to date"
  else
    echo "newer release available: $newest"
    return 1
  fi
}

cmd_update() {
  local newest out
  newest="$(newest_version)"
  log "newest advertised release: $newest"
  out="$(fetch "$newest" PENDING)"

  python3 - "$LOCK" "$newest" "$(sha256 "$out")" \
           "$(wc -c < "$out" | tr -d ' ')" "payetools-rti-$newest-linux.zip" <<'PY'
import json, sys
lock, version, digest, size, zipname = sys.argv[1:6]
d = json.load(open(lock))
parts = version.split(".")
d.update({
    "major": int(parts[0]),
    "version": version,
    "versionId": parts[2],
    "linux_zip": zipname,
    "size": int(size),
    "sha256": digest,
})
json.dump(d, open(lock, "w"), indent=2)
open(lock, "a").write("\n")
print(f"lock.json now pins {version} ({digest[:12]}...)")
PY
}

cmd_build() {
  local version sha zip
  version="$(json_get "$LOCK" version)"
  sha="$(json_get "$LOCK" sha256)"
  log "building Basic PAYE Tools $version"
  zip="$(fetch "$version" "$sha")"
  extract "$zip"
  assemble "$version"
}

command -v curl    >/dev/null 2>&1 || die "need curl"
command -v unzip   >/dev/null 2>&1 || die "need unzip"
command -v python3 >/dev/null 2>&1 || die "need python3"

case "${1:-build}" in
  build|"")  cmd_build ;;
  --check)   cmd_check ;;
  --update)  cmd_update ;;
  *)         die "usage: build.sh [build|--check|--update]" ;;
esac
