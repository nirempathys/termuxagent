#!/usr/bin/env bash

AGENT_KEYS="claude opencode codex copilot gemini qwen dsh antigravity hermes"

agent_label() {
	case "$1" in
	claude) printf 'claude code' ;;
	opencode) printf 'opencode' ;;
	codex) printf 'codex cli' ;;
	copilot) printf 'github copilot cli' ;;
	gemini) printf 'gemini cli' ;;
	qwen) printf 'qwen code' ;;
	dsh) printf 'deepseek harness' ;;
	antigravity) printf 'antigravity cli' ;;
	hermes) printf 'hermes agent' ;;
	*) printf '%s' "$1" ;;
	esac
}

agent_command() {
	case "$1" in
	antigravity) printf 'agy' ;;
	*) printf '%s' "$1" ;;
	esac
}

agent_tui_cmd() {
	case "$1" in
	dsh) return 1 ;;
	hermes) printf 'hermes --tui' ;;
	*) agent_command "$1" ;;
	esac
}

agent_pick() {
	local key="$1" label="$2" current="$3"
	case "$key" in
	claude) pick_version "$CLAUDE_NATIVE_PKG" "$label" "$current" ;;
	opencode) pick_version "$OPENCODE_PKG" "$label" "$current" ;;
	codex) pick_version "@openai/codex" "$label" "$current" ;;
	copilot) pick_version "@github/copilot" "$label" "$current" ;;
	gemini) pick_version "@google/gemini-cli" "$label" "$current" ;;
	qwen) pick_version "@qwen-code/qwen-code" "$label" "$current" ;;
	dsh) pick_version "@deepseek-ai/dsh" "$label" "$current" 1 ;;
	antigravity) printf 'latest\n' ;;
	hermes) hermes_pick "$current" ;;
	esac
}

npm_global_install() {
	local pkg="$1" version="$2"
	shift 2
	npm install -g "$pkg@$version" --no-fund --no-audit --loglevel=error "$@"
}

CODEX_HOME="$HOME_DIR/.codex-native"
COPILOT_NATIVE="$PREFIX/lib/node_modules/@github/copilot-linux-$ARCH/copilot"

codex_triple() {
	case "$ARCH" in
	arm64) printf 'aarch64-unknown-linux-musl' ;;
	*) printf 'x86_64-unknown-linux-musl' ;;
	esac
}

codex_version() {
	cat "$CODEX_HOME/version" 2>/dev/null || true
}

codex_install() {
	local version="$1" triple url tmp stale
	triple="$(codex_triple)"
	url="$REGISTRY/@openai/codex/-/codex-$version-linux-$ARCH.tgz"
	tmp="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/codex.XXXXXX")"
	info "downloading @openai/codex@$version"
	curl -fL --retry 3 --connect-timeout 20 "$url" -o "$tmp/codex.tgz"
	tar -xzf "$tmp/codex.tgz" -C "$tmp" "package/vendor/$triple"
	[ -x "$tmp/package/vendor/$triple/bin/codex" ] || die "codex binary missing in package"
	mkdir -p "$CODEX_HOME"
	rm -rf "$CODEX_HOME/$version"
	mv "$tmp/package/vendor/$triple" "$CODEX_HOME/$version"
	chmod 755 "$CODEX_HOME/$version/bin/"* 2>/dev/null || true
	printf '%s\n' "$version" >"$CODEX_HOME/version"
	ln -sfn "$CODEX_HOME/$version/bin/codex" "$PREFIX/bin/codex"
	for stale in "$CODEX_HOME"/*/; do
		[ -d "$stale" ] || continue
		[ "$(basename "$stale")" = "$version" ] || rm -rf "$stale"
	done
	rm -rf "$tmp"
	ok "codex $version installed"
}

copilot_version() {
	node_pkg_version "$PREFIX/lib/node_modules/@github/copilot-linux-$ARCH/package.json"
}

copilot_install() {
	local version="$1" ldso patchelf
	ldso="$(glibc_ldso_path)" || die "glibc interpreter not found"
	patchelf="$(patchelf_cmd)" || die "patchelf not available"
	npm_global_install "@github/copilot" "$version" --force
	npm_global_install "@github/copilot-linux-$ARCH" "$version" --force
	[ -x "$COPILOT_NATIVE" ] || die "copilot native binary missing"
	"$patchelf" --set-interpreter "$ldso" "$COPILOT_NATIVE"
	ln -sfn "$COPILOT_NATIVE" "$PREFIX/bin/copilot"
	ok "copilot $version installed"
}

gemini_version() {
	node_pkg_version "$PREFIX/lib/node_modules/@google/gemini-cli/package.json"
}

gemini_install() {
	npm_global_install "@google/gemini-cli" "$1"
	node_cli_wrap gemini "$PREFIX/bin/gemini"
	ok "gemini $1 installed"
}

qwen_version() {
	node_pkg_version "$PREFIX/lib/node_modules/@qwen-code/qwen-code/package.json"
}

qwen_install() {
	npm_global_install "@qwen-code/qwen-code" "$1"
	node_cli_wrap qwen "$PREFIX/bin/qwen"
	ok "qwen $1 installed"
}

dsh_version() {
	node_pkg_version "$PREFIX/lib/node_modules/@deepseek-ai/dsh/package.json"
}

dsh_install() {
	npm_global_install "@deepseek-ai/dsh" "$1" --ignore-scripts
	node_cli_wrap dsh "$PREFIX/bin/dsh"
	ok "deepseek harness $1 installed"
	warn "dsh runtime needs android native prebuilds that upstream does not publish, only --version is usable"
}

AGY_MANIFEST="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/android_$ARCH.json"

agy_field() {
	curl -fsSL --max-time 40 "$AGY_MANIFEST" | python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

agy_version() {
	command -v agy >/dev/null 2>&1 || return 0
	agy --version 2>/dev/null | tail -n1 | sed 's/^v//' || true
}

agy_install() {
	local url version tmp
	url="$(agy_field url)"
	version="$(agy_field version)"
	[ -n "$url" ] || die "cannot read antigravity release manifest"
	tmp="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/agy.XXXXXX")"
	info "downloading antigravity cli $version"
	curl -fL --retry 3 --connect-timeout 20 "$url" -o "$tmp/agy.pkg"
	case "$url" in
	*.tar.gz*)
		tar -xzf "$tmp/agy.pkg" -C "$tmp"
		[ -f "$tmp/antigravity" ] || die "unexpected antigravity archive layout"
		;;
	*) mv "$tmp/agy.pkg" "$tmp/antigravity" ;;
	esac
	mkdir -p "$HOME_DIR/.local/bin"
	install -m755 "$tmp/antigravity" "$HOME_DIR/.local/bin/agy"
	ln -sfn "$HOME_DIR/.local/bin/agy" "$PREFIX/bin/agy"
	rm -rf "$tmp"
	ok "antigravity $version installed"
}

antigravity_version() { agy_version; }

antigravity_install() { agy_install "$1"; }

HERMES_KEY="$PREFIX/etc/apt/keyrings/hermes-agent.asc"
HERMES_SOURCE="$PREFIX/etc/apt/sources.list.d/hermes-agent.list"
HERMES_BASE="https://hermes-assets.nousresearch.com/releases/termux"

hermes_channel() {
	local channel
	for channel in stable canary; do
		if curl -fsSL --max-time 20 -o /dev/null "$HERMES_BASE/$channel/dists/hermes-$channel/main/binary-aarch64/Packages" 2>/dev/null; then
			printf '%s\n' "$channel"
			return 0
		fi
	done
	return 1
}

hermes_versions() {
	local channel="$1" count="${2:-5}"
	curl -fsSL --max-time 40 "$HERMES_BASE/$channel/dists/hermes-$channel/main/binary-aarch64/Packages" |
		sed -n 's/^Version: *//p' | sort -V | tail -n "$count" | tac
}

hermes_version() {
	command -v hermes >/dev/null 2>&1 || return 0
	hermes --version 2>/dev/null | head -n1 | sed -n 's/.*[ v]\([0-9][0-9A-Za-z.~+-]*\).*/\1/p' || true
}

hermes_norm() {
	printf '%s' "$1" | tr '~+' '++' | sed 's/-[0-9][0-9]*$//'
}

hermes_pick() {
	local current="$1" channel choice index
	local versions=()
	[ "$ARCH" = arm64 ] || die "hermes agent is published for arm64 devices only"
	channel="$(hermes_channel)" || die "hermes apt channel unreachable"
	mapfile -t versions < <(hermes_versions "$channel" 5)
	[ "${#versions[@]}" -gt 0 ] || die "no hermes-agent versions in $channel"
	printf 'hermes agent versions (%s):\n' "$channel" >&2
	for index in "${!versions[@]}"; do
		if [ "$(hermes_norm "${versions[$index]}")" = "$(hermes_norm "$current")" ]; then
			printf '  %d) %s (installed)\n' "$((index + 1))" "${versions[$index]}" >&2
		else
			printf '  %d) %s\n' "$((index + 1))" "${versions[$index]}" >&2
		fi
	done
	printf '  l) latest\n' >&2
	while :; do
		read -rp "select [1-${#versions[@]}/l]: " choice || die "input aborted"
		case "$choice" in
		l | L)
			printf '%s\n' "${versions[0]}"
			return 0
			;;
		'') die "no version selected" ;;
		*[!0-9]*) ;;
		*)
			if [ "$choice" -ge 1 ] && [ "$choice" -le "${#versions[@]}" ]; then
				printf '%s\n' "${versions[$((choice - 1))]}"
				return 0
			fi
			;;
		esac
		printf 'invalid selection\n' >&2
	done
}

hermes_install() {
	local version="$1" channel
	[ "$ARCH" = arm64 ] || die "hermes agent is published for arm64 devices only"
	channel="$(hermes_channel)" || die "hermes apt channel unreachable"
	if ! command -v gpg >/dev/null 2>&1; then
		info "installing gnupg for repository key check"
		pkg install -y "${APT_OPTS[@]}" gnupg >/dev/null 2>&1 || true
	fi
	require gpg
	mkdir -p "$(dirname "$HERMES_KEY")"
	add_repo_key "$HERMES_KEY" "$HERMES_BASE/$channel/key.asc"
	printf 'deb [signed-by=%s] %s/%s hermes-%s main\n' "$HERMES_KEY" "$HERMES_BASE" "$channel" "$channel" >"$HERMES_SOURCE"
	pkg update -y "${APT_OPTS[@]}" >/dev/null 2>&1 || true
	info "installing hermes-agent $version ($channel)"
	if ! pkg install -y "${APT_OPTS[@]}" "hermes-agent=$version" 2>/dev/null; then
		pkg install -y "${APT_OPTS[@]}" hermes-agent
	fi
	ok "hermes $version installed"
}

add_repo_key() {
	local key="$1" url="$2" tmp fingerprint
	tmp="$(mktemp "${TMPDIR:-$PREFIX/tmp}/key.XXXXXX")"
	curl -fsSL --max-time 40 "$url" -o "$tmp"
	fingerprint="$(gpg --with-colons --import-options show-only --import "$tmp" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
	[ "$fingerprint" = "C572B5FDD1A29CCFA9A912B6840B0848E139156D" ] || die "hermes repo key fingerprint mismatch"
	install -m644 "$tmp" "$key"
	rm -f "$tmp"
}
