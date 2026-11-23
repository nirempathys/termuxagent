#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ARCHIVE="https://github.com/nirempathys/termuxagent/archive/refs/heads/main.tar.gz"

if [ ! -f "$ROOT/lib/common.sh" ]; then
	printf '[x] bootstrapping termuxagent sources\n' >&2
	command -v curl >/dev/null 2>&1 || {
		printf '[x] curl is required, run: pkg install curl\n' >&2
		exit 1
	}
	staging="$(mktemp -d "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/termuxagent.XXXXXX")"
	curl -fsSL "$REPO_ARCHIVE" | tar -xz -C "$staging"
	if [ -r /dev/tty ]; then
		exec bash "$staging/termuxagent-main/install.sh" </dev/tty
	fi
	exec bash "$staging/termuxagent-main/install.sh"
fi

. "$ROOT/lib/common.sh"
. "$ROOT/lib/glibc.sh"
. "$ROOT/lib/claude.sh"
. "$ROOT/lib/opencode.sh"

banner() {
	printf '\n%s termuxagent %s\n' "$c_orange" "$c_reset"
	printf '%s claude code + opencode v2 on termux via glibc %s\n\n' "$c_dim" "$c_reset"
}

tui_check() {
	local command="$1" name="$2" log rc
	log="${TMPDIR:-$PREFIX/tmp}/termuxagent-$name-tui.log"
	if ! command -v script >/dev/null 2>&1; then
		warn "$name tui skipped, script not available"
		return 0
	fi
	timeout 10 script -qec "$command" /dev/null </dev/null >"$log" 2>&1
	rc=$?
	if [ "$rc" -eq 124 ]; then
		ok "$name tui booted and stayed alive"
		return 0
	fi
	if [ "$rc" -eq 0 ] && [ -s "$log" ]; then
		ok "$name tui started and exited cleanly"
		return 0
	fi
	warn "$name tui failed, rc=$rc"
	tail -n 5 "$log" 2>/dev/null
	return 1
}

verify_flow() {
	local current failures=0
	line
	info "checking claude code"
	if claude_installed && [ -x "$CLAUDE_LINK" ]; then
		current="$("$CLAUDE_LINK" --version 2>&1 | head -n1)"
		ok "claude version: $current"
		tui_check "$CLAUDE_LINK" claude || failures=$((failures + 1))
	else
		warn "claude code is not installed"
		failures=$((failures + 1))
	fi
	line
	info "checking opencode"
	if opencode_installed; then
		current="$(opencode_version)"
		ok "opencode version: $current"
		if command -v opencode >/dev/null 2>&1; then
			ok "opencode path: $(command -v opencode)"
		else
			warn "opencode is not on PATH, repair with menu 2"
			failures=$((failures + 1))
		fi
		tui_check "$OPENCODE_CMD" opencode || failures=$((failures + 1))
	else
		warn "opencode is not installed"
		failures=$((failures + 1))
	fi
	line
	if [ "$failures" -eq 0 ]; then
		ok "all checks passed"
	else
		warn "$failures check failed"
	fi
}

prepare_base() {
	info "running pkg update"
	pkg update -y "${APT_OPTS[@]}"
	info "running pkg upgrade"
	pkg upgrade -y "${APT_OPTS[@]}"
	info "installing python nodejs curl tar"
	pkg install -y "${APT_OPTS[@]}" python nodejs curl tar
	require python3
	require npm
	require curl
	require tar
	ok "base packages ready"
}

claude_flow() {
	local current version installed
	current="$(claude_version)"
	if [ -n "$current" ]; then
		ok "claude already installed: $current"
		confirm "install or switch claude version?" || return 0
	fi
	if ! version="$(pick_version "$CLAUDE_NATIVE_PKG" "claude code" "$current")"; then
		warn "claude install cancelled"
		return 0
	fi
	claude_install "$version"
	claude_shortcut
	installed="$("$CLAUDE_LINK" --version 2>/dev/null | head -n1 || true)"
	[ -n "$installed" ] || die "claude verification failed, run claude --version manually"
	ok "claude ready: $installed"
}

opencode_flow() {
	local current version installed
	current="$(opencode_version || true)"
	if [ -n "$current" ]; then
		ok "opencode already installed: $current"
		confirm "install or switch opencode version?" || return 0
	fi
	if ! version="$(pick_version "$OPENCODE_PKG" "opencode" "$current")"; then
		warn "opencode install cancelled"
		return 0
	fi
	opencode_install "$version"
	installed="$(opencode_version || true)"
	[ -n "$installed" ] || die "opencode verification failed, run opencode --version manually"
	ok "opencode ready: $installed"
}

menu() {
	local choice
	while :; do
		line
		printf '  1) claude code\n'
		printf '  2) opencode\n'
		printf '  3) both\n'
		printf '  4) shell shortcut\n'
		printf '  5) verify install\n'
		printf '  0) exit\n'
		line
		read -rp 'select: ' choice || exit 0
		case "$choice" in
		'') exit 0 ;;
		1) claude_flow ;;
		2) opencode_flow ;;
		3)
			claude_flow
			opencode_flow
			;;
		4) claude_shortcut ;;
		5) verify_flow ;;
		0 | q | Q) exit 0 ;;
		*) warn "invalid selection" ;;
		esac
	done
}

main() {
	banner
	is_termux || die "this installer targets termux only"
	ok "architecture: $ARCH"
	prepare_base
	if glibc_ready; then
		ok "glibc $(glibc_version) already ready"
	else
		glibc_install
	fi
	menu
}

main "$@"
