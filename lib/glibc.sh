#!/usr/bin/env bash

glibc_ready() {
	[ -x "$GLIBC_LDSO" ] || return 1
	[ -d "$GLIBC_LIB" ] || return 1
	command -v grun >/dev/null 2>&1 || return 1
	return 0
}

glibc_version() {
	dpkg-query -W -f='${Version}' glibc 2>/dev/null || printf 'unknown'
}

glibc_install() {
	local source_line="deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable"
	info "adding termux-glibc repository"
	mkdir -p "$(dirname "$GLIBC_SOURCE")"
	[ -f "$GLIBC_SOURCE" ] || printf '%s\n' "$source_line" >"$GLIBC_SOURCE"
	info "updating package index"
	pkg update -y "${APT_OPTS[@]}"
	info "installing glibc and glibc-runner"
	pkg install -y "${APT_OPTS[@]}" glibc glibc-runner
	glibc_ready || die "glibc install failed, check connection and retry"
	ln -sfn glibc-runner "$PREFIX/bin/grun"
	ok "glibc $(glibc_version) installed"
}
