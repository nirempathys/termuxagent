#!/usr/bin/env bash

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:?HOME not set}"
XDG_STATE="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
GLIBC_PREFIX="$PREFIX/glibc"
GLIBC_LIB="$GLIBC_PREFIX/lib"
GLIBC_LDSO="$GLIBC_PREFIX/bin/ld.so"
GLIBC_SOURCE="$PREFIX/etc/apt/sources.list.d/glibc.list"
APT_OPTS=(-o Dpkg::Options::=--force-confold)
REGISTRY="https://registry.npmjs.org"

c_reset=$'\033[0m'
c_dim=$'\033[2m'
c_green=$'\033[32m'
c_red=$'\033[31m'
c_orange=$'\033[38;5;214m'

info() { printf '%s[.]%s %s\n' "$c_dim" "$c_reset" "$*"; }
ok() { printf '%s[ok]%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_orange" "$c_reset" "$*"; }
die() {
	printf '%s[x]%s %s\n' "$c_red" "$c_reset" "$*" >&2
	exit 1
}
line() { printf '%s%s%s\n' "$c_dim" "------------------------------------------------------------" "$c_reset"; }

is_termux() {
	[ -n "${TERMUX_VERSION:-}" ] && return 0
	[ -d /data/data/com.termux/files/usr ] && return 0
	return 1
}

require() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

detect_arch() {
	case "$(uname -m)" in
	aarch64 | arm64) ARCH=arm64 ;;
	x86_64 | amd64) ARCH=x64 ;;
	*) die "unsupported architecture: $(uname -m)" ;;
	esac
}

confirm() {
	local reply
	read -rp "$1 [y/N]: " reply || reply=""
	case "$reply" in
	y | Y | yes | YES) return 0 ;;
	*) return 1 ;;
	esac
}

npm_versions() {
	local pkg="$1" count="$2" pre="${3:-0}"
	curl -fsSL --max-time 40 "$REGISTRY/${pkg//\//%2f}" | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
times = data.get("time", {})
allow_pre = sys.argv[2] == "1"

def stable(v, meta):
    if meta.get("deprecated"):
        return False
    if re.fullmatch(r"\d+\.\d+\.\d+", v):
        return True
    return allow_pre and bool(re.fullmatch(r"\d+\.\d+\.\d+-[0-9A-Za-z.-]+", v))

keep = [v for v, m in data["versions"].items() if stable(v, m)]
keep.sort(key=lambda v: times.get(v, ""))
print("\n".join(reversed(keep[-int(sys.argv[1]):])))
' "$count" "$pre"
}

npm_latest() {
	curl -fsSL --max-time 40 "$REGISTRY/${1//\//%2f}/latest" |
		python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])'
}

pick_version() {
	local pkg="$1" label="$2" current="$3" pre="${4:-0}" choice index version
	local versions=()
	mapfile -t versions < <(npm_versions "$pkg" 5 "$pre")
	[ "${#versions[@]}" -gt 0 ] || die "cannot fetch $label version list"
	printf '%s\n' "$label available versions:" >&2
	for index in "${!versions[@]}"; do
		version="${versions[$index]}"
		if [ "$version" = "$current" ]; then
			printf '  %d) %s %s(installed)%s\n' "$((index + 1))" "$version" "$c_dim" "$c_reset" >&2
		else
			printf '  %d) %s\n' "$((index + 1))" "$version" >&2
		fi
	done
	printf '  l) latest\n  0) manual input\n' >&2
	while :; do
		read -rp "select [1-${#versions[@]}/l/0]: " choice || die "input aborted"
		case "$choice" in
		l | L)
			npm_latest "$pkg"
			return 0
			;;
		0)
			read -rp "version: " version || die "input aborted"
			version="${version#v}"
			if [ -n "$version" ]; then
				printf '%s\n' "$version"
				return 0
			fi
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

ensure_path() {
	local dir="$1" rc
	case ":$PATH:" in
	*":$dir:"*) ;;
	*) export PATH="$dir:$PATH" ;;
	esac
	for rc in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc"; do
		[ -f "$rc" ] || continue
		grep -Fqx "export PATH=\"$dir:\$PATH\"" "$rc" 2>/dev/null && continue
		printf '\nexport PATH="%s:$PATH"\n' "$dir" >>"$rc"
	done
}

glibc_ldso_path() {
	local candidate
	for candidate in "$GLIBC_LIB"/ld-linux-*.so.*; do
		[ -e "$candidate" ] && printf '%s\n' "$candidate" && return 0
	done
	return 1
}

npm_fix_shebang() {
	local target resolved
	target="$1"
	resolved="$(readlink -f "$target" 2>/dev/null || true)"
	if [ -z "$resolved" ] || [ ! -f "$resolved" ]; then
		return 0
	fi
	python3 - "$resolved" "$PREFIX/bin/node" <<'PY'
import sys

path, node = sys.argv[1], sys.argv[2]
raw = open(path, "rb").read()
first, sep, rest = raw.partition(b"\n")
if first.startswith(b"#!/usr/bin/env node"):
    with open(path, "wb") as handle:
        handle.write(("#!" + node).encode() + sep + rest)
PY
}

node_pkg_version() {
	local file="$1"
	[ -f "$file" ] || return 0
	python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$file" 2>/dev/null || true
}

patchelf_cmd() {
	local candidate
	for candidate in "$PREFIX/glibc/bin/patchelf" "$(command -v patchelf 2>/dev/null || true)"; do
		[ -n "$candidate" ] && [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
	done
	pkg install -y "${APT_OPTS[@]}" patchelf >/dev/null 2>&1 || true
	for candidate in "$PREFIX/glibc/bin/patchelf" "$(command -v patchelf 2>/dev/null || true)"; do
		[ -n "$candidate" ] && [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
	done
	return 1
}

detect_arch
