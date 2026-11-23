#!/usr/bin/env bash

CLAUDE_JS_PKG="@anthropic-ai/claude-code"
CLAUDE_NATIVE_PKG="@anthropic-ai/claude-code-linux-$ARCH"
CLAUDE_PKG_DIR="$PREFIX/lib/node_modules/@anthropic-ai/claude-code"
CLAUDE_NATIVE_DIR="$PREFIX/lib/node_modules/@anthropic-ai/claude-code-linux-$ARCH"
CLAUDE_NATIVE="$CLAUDE_NATIVE_DIR/claude"
CLAUDE_WRAPPER="$CLAUDE_PKG_DIR/bin/claude.exe"
CLAUDE_LINK="$PREFIX/bin/claude"
CLAUDE_SETTINGS="$HOME_DIR/.claude/settings.json"

claude_installed() {
	[ -x "$CLAUDE_NATIVE" ] && [ -f "$CLAUDE_WRAPPER" ] && return 0
	return 1
}

claude_version() {
	[ -f "$CLAUDE_NATIVE_DIR/package.json" ] || return 0
	python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' \
		"$CLAUDE_NATIVE_DIR/package.json" 2>/dev/null || true
}

claude_write_wrapper() {
	local template="$CLAUDE_PKG_DIR/bin/claude.exe.template"
	mkdir -p "$(dirname "$CLAUDE_WRAPPER")"
	cat >"$template" <<'WRAPPER'
#!@BASH@
set -euo pipefail
export DISABLE_AUTOUPDATER=1
export TMPDIR="${TMPDIR:-@TMPDIR@}"
native="@NATIVE@"
ldso="@LDSO@"
libdir="@LIBDIR@"
if [ ! -x "$native" ]; then
	echo "claude native binary not found: $native" >&2
	exit 127
fi
if [ ! -x "$ldso" ]; then
	echo "glibc loader not found: $ldso" >&2
	exit 127
fi
gateway="$HOME/.claude/gateway.json"
extra=()
if [ -f "$gateway" ]; then
	has_settings=0
	for arg in "$@"; do
		if [ "$arg" = "--settings" ]; then
			has_settings=1
		fi
	done
	if [ "$has_settings" -eq 0 ]; then
		extra=(--settings "$gateway")
	fi
fi
unset LD_PRELOAD
exec "$ldso" --library-path "$libdir" "$native" "${extra[@]}" "$@"
WRAPPER
	sed -e "s|@BASH@|$PREFIX/bin/bash|g" \
		-e "s|@TMPDIR@|$PREFIX/tmp|g" \
		-e "s|@NATIVE@|$CLAUDE_NATIVE|g" \
		-e "s|@LDSO@|$GLIBC_LDSO|g" \
		-e "s|@LIBDIR@|$GLIBC_LIB|g" \
		"$template" >"$CLAUDE_WRAPPER"
	rm -f "$template"
	chmod 755 "$CLAUDE_WRAPPER"
}

claude_patch_settings() {
	mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
	python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, os, sys

path = sys.argv[1]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError:
        os.replace(path, path + ".invalid.bak")
        data = {}
env = data.setdefault("env", {})
env["DISABLE_AUTOUPDATER"] = "1"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
}

claude_shortcut() {
	local rc block
	block='# termuxagent
claudesettings() { nano "$HOME/.claude/settings.json"; }'
	for rc in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc"; do
		[ -f "$rc" ] || continue
		grep -Fq '# termuxagent' "$rc" 2>/dev/null && continue
		printf '\n%s\n' "$block" >>"$rc"
	done
	ok "claudesettings shortcut available after shell reload"
}

claude_install() {
	local version="$1"
	glibc_ready || die "glibc is not ready, run the installer again"
	require npm
	info "installing $CLAUDE_JS_PKG@$version"
	npm install -g "$CLAUDE_JS_PKG@$version" --no-fund --no-audit --loglevel=error
	info "installing $CLAUDE_NATIVE_PKG@$version"
	npm install -g "$CLAUDE_NATIVE_PKG@$version" --force --no-fund --no-audit --loglevel=error
	[ -x "$CLAUDE_NATIVE" ] || die "claude native binary missing"
	[ -d "$CLAUDE_PKG_DIR/bin" ] || die "claude bin directory missing"
	claude_write_wrapper
	claude_patch_settings
	ln -sfn "../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe" "$CLAUDE_LINK"
	ok "claude $version installed"
}
