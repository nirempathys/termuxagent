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
. "$ROOT/lib/agents.sh"

banner() {
	printf '\n%s termuxagent %s\n' "$c_orange" "$c_reset"
	printf '%s agent installer for termux: glibc natives, npm cli, apt builds %s\n\n' "$c_dim" "$c_reset"
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

prepare_base() {
	info "running pkg update"
	pkg update -y "${APT_OPTS[@]}"
	info "running pkg upgrade"
	pkg upgrade -y "${APT_OPTS[@]}"
	info "installing python nodejs curl tar gnupg"
	pkg install -y "${APT_OPTS[@]}" python nodejs curl tar gnupg
	require python3
	require npm
	require curl
	require tar
	command -v gpg >/dev/null 2>&1 || warn "gpg missing, hermes key check will install it"
	ok "base packages ready"
}

agent_flow() {
	local key="$1" label current version
	label="$(agent_label "$key")"
	current="$("${key}_version" 2>/dev/null || true)"
	if [ -n "$current" ]; then
		ok "$label already installed: $current"
		confirm "install or switch $label version?" || return 0
	fi
	if ! version="$(agent_pick "$key" "$label" "$current")"; then
		warn "$label install cancelled"
		return 0
	fi
	if [ -z "$version" ]; then
		warn "$label install cancelled"
		return 0
	fi
	"${key}_install" "$version"
	current="$("${key}_version" 2>/dev/null || true)"
	[ -n "$current" ] || die "$label verification failed, run $(agent_command "$key") --version manually"
	ok "$label ready: $current"
}

all_flows() {
	local key
	for key in $AGENT_KEYS; do
		(agent_flow "$key") || warn "$(agent_label "$key") skipped"
	done
}

verify_flow() {
	local key label command current failures=0 tui_cmd
	local installed=()
	for key in $AGENT_KEYS; do
		label="$(agent_label "$key")"
		command="$(agent_command "$key")"
		current="$("${key}_version" 2>/dev/null || true)"
		if [ -z "$current" ]; then
			warn "$label: not installed"
			continue
		fi
		ok "$label: $current"
		if command -v "$command" >/dev/null 2>&1; then
			printf '    %s -> %s\n' "$command" "$(command -v "$command")"
			installed+=("$key")
		else
			warn "$command not found on PATH"
			failures=$((failures + 1))
		fi
	done
	line
	if [ "${#installed[@]}" -eq 0 ]; then
		warn "no agent installed yet"
		return 0
	fi
	if confirm "run tui smoke test for ${#installed[@]} installed agent(s)?"; then
		for key in "${installed[@]}"; do
			tui_cmd="$(agent_tui_cmd "$key")" || {
				warn "$(agent_label "$key"): no tui probe, cli verified"
				continue
			}
			tui_check "$tui_cmd" "$key" || failures=$((failures + 1))
		done
	fi
	line
	if [ "$failures" -eq 0 ]; then
		ok "all checks passed"
	else
		warn "$failures check failed"
	fi
}

menu() {
	local choice index line_no
	local keys=()
	mapfile -t keys < <(printf '%s\n' $AGENT_KEYS)
	while :; do
		line
		for index in "${!keys[@]}"; do
			printf '  %d) %s\n' "$((index + 1))" "$(agent_label "${keys[$index]}")"
			if [ $(((index + 1) % 3)) -eq 0 ] && [ $((index + 1)) -lt "${#keys[@]}" ]; then
				printf '\n'
			fi
		done
		printf '\n'
		printf '  a) all\n'
		printf '  s) shell shortcut\n'
		printf '  v) verify install\n'
		printf '  0) exit\n'
		line
		read -rp 'select: ' choice || exit 0
		case "$choice" in
		'') exit 0 ;;
		a | A) all_flows ;;
		s | S) claude_shortcut ;;
		v | V) verify_flow ;;
		0 | q | Q) exit 0 ;;
		*[!0-9]*) warn "invalid selection" ;;
		*)
			if [ "$choice" -ge 1 ] && [ "$choice" -le "${#keys[@]}" ]; then
				agent_flow "${keys[$((choice - 1))]}"
			else
				warn "invalid selection"
			fi
			;;
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
