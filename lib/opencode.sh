#!/usr/bin/env bash

OPENCODE_PKG="@opencode/cli-linux-$ARCH"
OPENCODE_NAME="cli-linux-$ARCH"
OPENCODE_DIR="$HOME_DIR/.opencode/bin"
OPENCODE_BIN="$OPENCODE_DIR/opencode"
OPENCODE_LOG="$HOME_DIR/.opencode/service.log"
OPENCODE_SERVICE="$XDG_STATE/opencode/service.json"
OPENCODE_CMD="$HOME_DIR/bin/opencode"

opencode_installed() {
	[ -x "$OPENCODE_BIN" ] && [ -x "$OPENCODE_CMD" ] && return 0
	return 1
}

opencode_version() {
	[ -x "$OPENCODE_CMD" ] || return 0
	"$OPENCODE_CMD" --version 2>/dev/null | awk '{print $NF}' | sed 's/^v//' || true
}

opencode_write_launcher() {
	local template="$OPENCODE_CMD.template"
	mkdir -p "$(dirname "$OPENCODE_CMD")"
	cat >"$template" <<'LAUNCHER'
#!@BASH@
set -uo pipefail
export TMPDIR="${TMPDIR:-@TMPDIR@}"
bin="@BIN@"
registry="@SERVICE@"
log="@LOG@"

healthy() {
	[ -f "$registry" ] || return 1
	[ "$bin" -nt "$registry" ] && return 1
	local pid
	pid=$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$registry" | head -n1)
	[ -n "$pid" ] || return 1
	kill -0 "$pid" 2>/dev/null || return 1
	tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q 'serve --service'
}

start() {
	local pid=""
	if [ -f "$registry" ]; then
		pid=$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$registry" | head -n1)
	fi
	if [ -n "$pid" ]; then
		kill "$pid" 2>/dev/null
	fi
	rm -f "$registry"
	mkdir -p "$(dirname "$log")"
	setsid nohup grun "$bin" serve --service >>"$log" 2>&1 </dev/null &
	local attempt
	for attempt in $(seq 1 150); do
		[ -f "$registry" ] && return 0
		sleep 0.2
	done
	return 0
}

case "${1:-}" in
serve | service | upgrade | update | uninstall | completions | --version | -v | --help | -h) ;;
*) healthy || start ;;
esac

exec grun "$bin" "$@"
LAUNCHER
	sed -e "s|@BASH@|$PREFIX/bin/bash|g" \
		-e "s|@TMPDIR@|$PREFIX/tmp|g" \
		-e "s|@BIN@|$OPENCODE_BIN|g" \
		-e "s|@SERVICE@|$OPENCODE_SERVICE|g" \
		-e "s|@LOG@|$OPENCODE_LOG|g" \
		"$template" >"$OPENCODE_CMD"
	rm -f "$template"
	chmod 755 "$OPENCODE_CMD"
}

opencode_install() {
	local version="$1" url tmp
	glibc_ready || die "glibc is not ready, run the installer again"
	require curl
	require tar
	url="$REGISTRY/$OPENCODE_PKG/-/$OPENCODE_NAME-$version.tgz"
	tmp="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/opencode.XXXXXX")"
	info "downloading $OPENCODE_PKG@$version"
	curl -fL --retry 3 --connect-timeout 20 "$url" -o "$tmp/pkg.tgz"
	tar -xzf "$tmp/pkg.tgz" -C "$tmp"
	[ -f "$tmp/package/bin/opencode" ] || die "unexpected opencode package layout"
	mkdir -p "$OPENCODE_DIR"
	install -m755 "$tmp/package/bin/opencode" "$OPENCODE_DIR/opencode.new"
	mv -f "$OPENCODE_DIR/opencode.new" "$OPENCODE_BIN"
	rm -rf "$tmp"
	opencode_write_launcher
	ensure_path "$HOME_DIR/bin"
	if [ -e "$PREFIX/bin/opencode" ] && [ ! -L "$PREFIX/bin/opencode" ]; then
		mv "$PREFIX/bin/opencode" "$PREFIX/bin/opencode.bak.$(date +%s)"
	fi
	ln -sfn "$OPENCODE_CMD" "$PREFIX/bin/opencode"
	ok "opencode $version installed"
}
