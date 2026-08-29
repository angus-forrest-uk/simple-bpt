#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="${BPT_DIST:-$ROOT/dist}"
PREFIX="${BPT_PREFIX:-/opt/simple-bpt}"
UNIT=/etc/systemd/system/simple-bpt.service
CONFDIR=/etc/simple-bpt
USER_NAME=simple-bpt

die() { printf 'simple-bpt: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*" >&2; }

[ "$(id -u)" = 0 ] || die "run as root"
command -v systemctl >/dev/null 2>&1 || die "no systemctl"

uninstall() {
  log "stopping and disabling the service"
  systemctl disable --now simple-bpt.service 2>/dev/null || true
  rm -f "$UNIT"
  systemctl daemon-reload
  rm -rf "$PREFIX"
  log "left in place: /var/lib/simple-bpt, $CONFDIR, user $USER_NAME"
}

install_all() {
  local missing="" lib

  [ -d "$DIST/bptserver" ] || die "no build in $DIST, run ./build.sh first"
  [ "$(uname -m)" = "x86_64" ] || die "BPT is x86_64 only, this host is $(uname -m)"

  for lib in libsqlite3.so.0 libz.so.1 libbz2.so.1.0; do
    ldconfig -p 2>/dev/null | grep -q "$lib" || missing="$missing $lib"
  done
  [ -z "$missing" ] || die "missing shared libraries:$missing"

  if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    log "creating system user $USER_NAME"
    useradd --system --home-dir /var/lib/simple-bpt --shell /usr/sbin/nologin \
            --comment "Basic PAYE Tools" "$USER_NAME"
  fi

  log "installing to $PREFIX"
  rm -rf "$PREFIX"
  mkdir -p "$PREFIX"
  cp -a "$DIST/." "$PREFIX/"
  chmod +x "$PREFIX/simple-bpt" "$PREFIX/bptserver/rti.linux"

  mkdir -p "$CONFDIR"
  if [ ! -e "$CONFDIR/config" ]; then
    log "writing $CONFDIR/config"
    cat > "$CONFDIR/config" <<'EOF'
BPT_BIND=127.0.0.1
BPT_PORT=46729
EOF
    chmod 0644 "$CONFDIR/config"
  fi

  log "installing the unit"
  install -m 0644 "$ROOT/systemd/simple-bpt.service" "$UNIT"
  systemctl daemon-reload
  systemctl enable --now simple-bpt.service

  sleep 2
  systemctl is-active --quiet simple-bpt.service || {
    systemctl --no-pager status simple-bpt.service || true
    die "the service did not start"
  }
  log "running $(cat "$PREFIX/VERSION" 2>/dev/null || echo unknown) on 127.0.0.1:46729"
}

case "${1:-install}" in
  install|"")  install_all ;;
  --uninstall) uninstall ;;
  *)           die "usage: install.sh [install|--uninstall]" ;;
esac
