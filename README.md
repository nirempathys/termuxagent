# termuxagent

Installer for terminal coding agents on Termux. It installs the Termux glibc layer, then sets up any of the agents below and verifies each one end to end.

Supported agents:

| Key | Menu | Command | Install method |
| --- | --- | --- | --- |
| claude | 1) claude code | `claude` | npm JS wrapper + glibc native binary |
| opencode | 2) opencode | `opencode` | native linux arm64 tarball + service launcher |
| codex | 3) codex cli | `codex` | static musl binary from the npm platform tarball |
| copilot | 4) github copilot cli | `copilot` | glibc native binary + interpreter patch |
| gemini | 5) gemini cli | `gemini` | npm global with rewritten shebang |
| qwen | 6) qwen code | `qwen` | npm global with rewritten shebang |
| dsh | 7) deepseek harness | `dsh` | npm global, scripts skipped |
| antigravity | 8) antigravity cli | `agy` | official Android build from the release manifest |
| hermes | 9) hermes agent | `hermes` | official Termux APT repository |

Additional menu entries:

```
a) all               install every agent in order
s) shell shortcut    add claudesettings to ~/.bashrc and ~/.zshrc
v) verify install    check every installed agent and smoke test its TUI
0) exit
```

## Requirements

- Termux from F-Droid or GitHub releases. The Play Store build is outdated.
- `aarch64` or `x86_64` device. Hermes is arm64 only.
- About 4 GB free storage for all nine agents.
- Working network connection to npm, GitHub, Google, and the Termux mirrors.
- No root required.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/nirempathys/termuxagent/main/install.sh | bash
```

The script downloads its own library files when piped, so no clone is needed.

## Manual install

```bash
pkg install -y git
git clone https://github.com/nirempathys/termuxagent
cd termuxagent
bash install.sh
```

## Installer flow

1. Detects Termux and the CPU architecture.
2. Runs `pkg update`, `pkg upgrade`, then installs `python`, `nodejs`, `curl`, `tar`, `gnupg`.
3. Detects glibc. If `$PREFIX/glibc/bin/ld.so` or `grun` is missing, it adds the `termux-glibc` repository and installs `glibc` plus `glibc-runner`.
4. Shows the agent menu.
5. Lists the **last five published versions** of the selected agent, plus `latest` and manual input. Antigravity is latest only, because the binary self-updates and only one Android build is published.
6. Installs the selected version and verifies it by running `--version`.

Every step is idempotent. Re-running the installer reuses the existing glibc install and only replaces the agent you select.

## Version selection

```
gemini cli available versions:
  1) 0.70.0 (installed)
  2) 0.69.0
  3) 0.68.0
  4) 0.67.0
  5) 0.66.0
  l) latest
  0) manual input
select [1-5/l/0]:
```

npm-based agents list the five newest releases by publish time, filtered to stable versions. DeepSeek Harness also lists prereleases because it has no stable line. Claude versions come from the native package so the JS wrapper and native binary always match. Hermes versions come from the APT `Packages` index of the active channel.

## Verify

Menu option `v` checks every agent on this device:

1. version readable from disk,
2. command resolves from `PATH`,
3. the TUI boots inside a real pty for 10 seconds and keeps running.

```
[ok] claude code: 2.1.330
    claude -> /data/data/com.termux/files/usr/bin/claude
[ok] opencode: 2.3.0
    opencode -> /data/data/com.termux/files/home/bin/opencode
[ok] codex cli: 0.171.0
    codex -> /data/data/com.termux/files/usr/bin/codex
[ok] github copilot cli: 1.0.114
    copilot -> /data/data/com.termux/files/usr/bin/copilot
[ok] gemini cli: 0.70.0
...
[ok] claude tui booted and stayed alive
[ok] opencode tui booted and stayed alive
[!] deepseek harness: no tui probe, cli verified
[ok] all checks passed
```

DeepSeek Harness has no TUI probe because its TUI needs a native `koffi` build that is skipped on Termux. The CLI itself is verified.

## Usage

```bash
claude                 # Claude Code
opencode               # OpenCode v2
codex                  # Codex CLI
copilot                # GitHub Copilot CLI
gemini                 # Gemini CLI
qwen                   # Qwen Code
dsh --profile tui      # DeepSeek Harness
agy                    # Antigravity CLI
hermes --tui           # Hermes Agent
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

## Per-agent notes

### Codex

The npm `@openai/codex` package is a shim, and its platform packages are published as `@openai/codex@<version>-linux-arm64`. Installing one of those with `npm install -g` replaces the main package and breaks the shim. The installer therefore downloads the platform tarball directly and extracts the static musl binary:

```
https://registry.npmjs.org/@openai/codex/-/codex-<version>-linux-arm64.tgz
package/vendor/aarch64-unknown-linux-musl/bin/codex
```

The binary is unpacked to `~/.codex-native/<version>` and linked at `$PREFIX/bin/codex`. Because it is statically linked musl, it does not need glibc or `grun`.

### Copilot

The native binary ships with a `linux-arm64` build that expects a glibc interpreter. The installer installs both `@github/copilot` and `@github/copilot-linux-arm64`, then patches only the ELF interpreter:

```bash
patchelf --set-interpreter $PREFIX/glibc/lib/ld-linux-aarch64.so.1 \
  $PREFIX/lib/node_modules/@github/copilot-linux-arm64/copilot
```

Adding an rpath as well makes the binary crash with `SIGSEGV`, so the installer sets the interpreter only.

### Gemini CLI and Qwen Code

Both are plain npm global packages that work under Termux node. npm keeps the `#!/usr/bin/env node` shebang, which fails on Android because `/usr/bin/env` does not exist. The installer rewrites the shebang of the resolved entry file to `#!$PREFIX/bin/node`.

### DeepSeek Harness

`@deepseek-ai/dsh` has a native dependency (`koffi`) whose build step fails on Termux. The installer uses `--ignore-scripts`, which is enough for `dsh --version` and the CLI entry point but not for the TUI profile, which loads the native module at runtime. Use `dsh headless` or the web profile, or install from a glibc environment if you need the TUI.

Only prerelease versions are published, so the version list includes them.

### Antigravity CLI

Antigravity publishes Android builds through a manifest:

```
https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/android_arm64.json
```

The installer reads the manifest, downloads the `cli_android_arm64.tar.gz` build, installs it to `~/.local/bin/agy`, and links `$PREFIX/bin/agy`. The binary is a bionic build, so no glibc is involved, and it updates itself.

### Hermes Agent

Hermes refuses its `install.sh` on Termux and points to the APT repository. The installer adds the key and source, then installs the package:

```
deb [signed-by=$PREFIX/etc/apt/keyrings/hermes-agent.asc] \
  https://hermes-assets.nousresearch.com/releases/termux/canary hermes-canary main
```

The key fingerprint is pinned to `C572B5FDD1A29CCFA9A912B6840B0848E139156D` and the installer aborts on a mismatch. The stable channel currently returns `404`, so the canary channel is used. Upstream still marks the Termux package as work in progress; the canary build installs and runs.

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
$HOME/.codex-native/<version>/bin/codex         Codex binary
$PREFIX/bin/codex                               symlink -> Codex binary
$PREFIX/lib/node_modules/@github/               Copilot packages
$PREFIX/bin/copilot                             symlink -> patched native binary
$PREFIX/lib/node_modules/@google/gemini-cli     Gemini CLI
$PREFIX/lib/node_modules/@qwen-code/qwen-code   Qwen Code
$PREFIX/lib/node_modules/@deepseek-ai/dsh       DeepSeek Harness
$HOME/.local/bin/agy                            Antigravity binary
$PREFIX/lib/hermes-agent/app                    Hermes Agent application
$HOME/.claude/settings.json                     Claude Code settings
```

## Switching or upgrading versions

Run `bash install.sh` again and pick the agent. The version list always contains the five newest releases, so downgrades and upgrades use the same path.

OpenCode upgrades take effect on the next launch: the launcher notices the new binary, stops the old service, and starts a fresh one. The binary is swapped atomically, so a running service is not killed mid-write.

## Linux and other platforms

Every agent has an official installer for glibc Linux:

```bash
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://opencode.ai/v2/install | bash
npm install -g @openai/codex
npm install -g @github/copilot
npm install -g @google/gemini-cli
npm install -g @qwen-code/qwen-code
npm install -g @deepseek-ai/dsh
curl -fsSL https://antigravity.google/cli/install.sh | bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

This repo is only needed on Termux, where the musl userland cannot load glibc binaries directly and several npm packages need shebang or ELF fixes.

## Troubleshooting

**`bad interpreter: /usr/bin/env: no such file or directory`**
An npm package kept its `#!/usr/bin/env node` shebang. Run the installer again for that agent, or fix it manually:

```bash
pkg install -y python
python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read(); f,s,r=d.partition(b'\n'); open(p,'wb').write(b'#!/data/data/com.termux/files/usr/bin/node'+s+r) if f.startswith(b'#!/usr/bin/env node') else None" "$(readlink -f $PREFIX/bin/gemini)"
```

**Copilot exits with `SIGSEGV` or `139`**
The binary has an rpath that points at a missing glibc path. Re-run the installer for Copilot, which sets the interpreter only:

```bash
$PREFIX/glibc/bin/patchelf --set-interpreter \
  $PREFIX/glibc/lib/ld-linux-aarch64.so.1 \
  $PREFIX/lib/node_modules/@github/copilot-linux-arm64/copilot
```

**Copilot reports `unrecognized option '--binary-version'`**
The binary was started through `ld.so` directly and the flag was parsed by the loader. Run `copilot` from `PATH` after the interpreter patch instead.

**`codex: command not found` after an npm install**
`npm install -g @openai/codex-linux-arm64` replaces the main `@openai/codex` package. Remove both and let the installer extract the platform tarball:

```bash
rm -rf $PREFIX/lib/node_modules/@openai/codex
bash install.sh
```

**`dsh` crashes with a koffi or native module error**
The TUI profile needs a native build that is skipped on Termux. Use `dsh --version` to confirm the CLI, and prefer `dsh headless`.

**`hermes` repository returns `404`**
The stable channel is not published. The installer falls back to canary automatically. If it still fails, remove the source and retry:

```bash
rm -f $PREFIX/etc/apt/sources.list.d/hermes-agent.list
bash install.sh
```

**`serve: error while loading shared libraries: serve`**
The OpenCode launcher was bypassed. Run `opencode` from `~/bin` or `$PREFIX/bin`, not `~/.opencode/bin/opencode` directly.

**`opencode: command not found`**
The launcher lives at `~/bin/opencode` and a symlink at `$PREFIX/bin/opencode`. To fix manually:

```bash
ln -sfn "$HOME/bin/opencode" "$PREFIX/bin/opencode"
hash -r
```

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

**npm install fails on a native package**
Native packages are published per platform. Verify the architecture with `uname -m`; `aarch64` maps to `arm64` and `x86_64` maps to `x64`.

## Repository layout

```
install.sh          entry point, bootstrap, base packages, menu, verify
lib/common.sh       helpers, version lookup, version picker, shebang and patchelf helpers
lib/glibc.sh        glibc detection and installation
lib/claude.sh       Claude Code install, wrapper, settings patch
lib/opencode.sh     OpenCode v2 install, service launcher
lib/agents.sh       registry and per-agent install for codex, copilot, gemini, qwen, dsh, antigravity, hermes
README.md           this file
```

## Uninstall

```bash
pkg uninstall hermes-agent
rm -rf ~/.opencode ~/bin/opencode ~/.codex-native ~/.local/bin/agy
npm uninstall -g @anthropic-ai/claude-code @anthropic-ai/claude-code-linux-arm64
npm uninstall -g @github/copilot @github/copilot-linux-arm64
npm uninstall -g @google/gemini-cli @qwen-code/qwen-code @deepseek-ai/dsh
rm -f $PREFIX/bin/claude $PREFIX/bin/opencode $PREFIX/bin/codex $PREFIX/bin/copilot \
  $PREFIX/bin/gemini $PREFIX/bin/qwen $PREFIX/bin/dsh $PREFIX/bin/agy
rm -f $PREFIX/etc/apt/sources.list.d/hermes-agent.list
pkg uninstall glibc-runner
```

Removing glibc is optional and only needed if no other glibc binary is in use.
