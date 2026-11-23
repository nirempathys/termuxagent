# termuxagent

Installer for **Claude Code** and **OpenCode v2** on Termux, running the official glibc binaries through the Termux glibc layer.

Termux ships musl, while both agents ship glibc-only native binaries for `linux-arm64` (and `linux-x64`). This repo installs the glibc runtime, the dynamic loader bridge, the native packages, and the launcher wrappers that make both agents work on Android.

## What it installs

| Component | Source | Target |
| --- | --- | --- |
| glibc + glibc-runner | termux-glibc apt repo | `$PREFIX/glibc`, `$PREFIX/bin/grun` |
| Claude Code (JS wrapper) | `@anthropic-ai/claude-code` | `$PREFIX/lib/node_modules/@anthropic-ai/claude-code` |
| Claude Code (native) | `@anthropic-ai/claude-code-linux-arm64` | `$PREFIX/lib/node_modules/@anthropic-ai/claude-code-linux-arm64` |
| OpenCode v2 (native) | `@opencode/cli-linux-arm64` | `~/.opencode/bin/opencode` |
| OpenCode v2 (launcher) | this repo | `~/bin/opencode` |

The installer also writes `claudesettings`, a shell shortcut that opens `~/.claude/settings.json` in `nano`.

## Requirements

- Termux from F-Droid or GitHub releases (Play Store build is outdated).
- `aarch64` or `x86_64` device.
- About 1.5 GB free storage (both native binaries are large).
- Working network connection to npm registry and the Termux mirrors.
- No root required.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/nirempathys/termuxagent/main/install.sh | bash
```

The script bootstraps its own library files when piped, so no clone is needed.

## Manual install

```bash
pkg install -y git
git clone https://github.com/nirempathys/termuxagent
cd termuxagent
bash install.sh
```

## Installer flow

1. Detects Termux and the CPU architecture.
2. Runs `pkg update`, `pkg upgrade`, then installs `python`, `nodejs`, `curl`, `tar`.
3. Detects glibc. If `$PREFIX/glibc/bin/ld.so` or `grun` is missing, it adds the `termux-glibc` repository and installs `glibc` plus `glibc-runner`.
4. Shows the menu: Claude Code, OpenCode, both, or the shell shortcut.
5. Lists the **last five published versions** of the selected agent, plus `latest` and manual input.
6. Installs the selected version and verifies it by running `--version`.

Every step is idempotent. Re-running the installer reuses the existing glibc install and only replaces the agent you select.

## Version selection

```
claude code available versions:
  1) 2.1.330 (installed)
  2) 2.1.329
  3) 2.1.328
  4) 2.1.327
  5) 2.1.326
  l) latest
  0) manual input
select [1-5/l/0]:
```

Versions come from the npm registry, filtered to stable releases only. Claude versions are read from the native package so the JS wrapper and native binary always match.

## Usage

```bash
claude                 # Claude Code
opencode               # OpenCode v2
opencode --version     # opencode v2.4.1
claude --version       # 2.1.330 (Claude Code)
claudesettings         # nano ~/.claude/settings.json
grun ./some-linux-bin  # run any glibc binary
```

`claudesettings` is written to `~/.bashrc` and `~/.zshrc`. Reload the shell or open a new session to pick it up.

## How the glibc bridge works

`grun` (glibc-runner) prepends `$PREFIX/glibc/bin` to `PATH`, sets `LD_PRELOAD` to `libtermux-exec.so` so path translation still works, then executes `ld.so <binary>`. glibc binaries therefore run with Android's kernel but a glibc userland.

Claude Code is launched directly with the loader:

```
$PREFIX/glibc/bin/ld.so --library-path $PREFIX/glibc/lib \
  $PREFIX/lib/node_modules/@anthropic-ai/claude-code-linux-arm64/claude
```

The npm `claude` shim is replaced with a wrapper that does exactly this, disables the auto-updater, and forwards an optional `~/.claude/gateway.json` as `--settings`.

OpenCode v2 needs more than the loader. It spawns a background server by re-executing itself through `process.execPath`. Under `grun`, `/proc/self/exe` points at `ld.so`, so that child becomes `ld.so serve ...` and dies with:

```
serve: error while loading shared libraries: serve: cannot open shared object file
```

The `~/bin/opencode` launcher prevents that re-exec. Before the CLI starts, it launches a single `serve --service` process in the background, waits for `~/.local/state/opencode/service.json`, then hands over to the CLI, which reuses that server. The launcher restarts the service when the binary is newer than the service registration.

## Files installed outside the repo

```
$PREFIX/glibc/                                  glibc runtime and loader
$PREFIX/opt/glibc-runner/glibc-runner.sh        glibc-runner implementation
$PREFIX/lib/node_modules/@anthropic-ai/          Claude Code packages
$PREFIX/bin/claude                              wrapper -> claude.exe
$HOME/.opencode/bin/opencode                    OpenCode v2 binary
$HOME/.opencode/service.log                     OpenCode service log
$HOME/bin/opencode                              OpenCode launcher
$HOME/.local/state/opencode/service.json        OpenCode service registration
$HOME/.claude/settings.json                     Claude Code settings
```

## Switching or upgrading versions

Run `bash install.sh` again and pick the agent. The version list always contains the five newest stable releases, so downgrades and upgrades use the same path.

OpenCode upgrades take effect on the next launch: the launcher notices the new binary, stops the old service, and starts a fresh one.

## Linux and other platforms

Both agents ship official installers that do not need this repo. On glibc Linux distributions use:

```bash
# OpenCode v2
curl -fsSL https://opencode.ai/v2/install | bash

# Claude Code
curl -fsSL https://claude.ai/install.sh | bash
```

Node-based installs also work:

```bash
npm install -g @anthropic-ai/claude-code
npm install -g @opencode/cli
```

On macOS and Windows use the official installers from `opencode.ai` and `claude.ai`. This repo is only needed on Termux, where the musl userland cannot load the glibc binaries directly.

## Troubleshooting

**`serve: error while loading shared libraries: serve`**
The launcher was bypassed. Run `opencode` (from `~/bin`), not `~/.opencode/bin/opencode` directly, and make sure `~/bin` is before other entries in `PATH`.

**`Managed service port is already in use`**
Another OpenCode service still holds the port. Run `opencode service stop` or `pkill -f "serve --service"`, then start again.

**`glibc loader not found`**
Run `bash install.sh` again and let the glibc step finish, or install manually:

```bash
echo "deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable" \
  > $PREFIX/etc/apt/sources.list.d/glibc.list
pkg update
pkg install glibc glibc-runner
```

**`LD_PRELOAD` related crash**
Both wrappers unset `LD_PRELOAD` before executing the glibc binary. If you export `LD_PRELOAD` yourself, unset it for these commands.

**npm install fails on the native package**
Native packages are published per platform. Verify the architecture with `uname -m`; `aarch64` maps to `arm64` and `x86_64` maps to `x64`.

## Repository layout

```
install.sh          entry point, menu, base packages, glibc step
lib/common.sh       helpers, version lookup, version picker, PATH setup
lib/glibc.sh        glibc detection and installation
lib/claude.sh       Claude Code install, wrapper, settings patch
lib/opencode.sh     OpenCode v2 install, service launcher
README.md           this file
```

## Uninstall

```bash
rm -rf ~/.opencode ~/bin/opencode
npm uninstall -g @anthropic-ai/claude-code @anthropic-ai/claude-code-linux-arm64
rm -f $PREFIX/bin/claude
pkg uninstall glibc-runner
```

Removing glibc is optional and only needed if no other glibc binary is in use.
