# Modern CLI Toolkit — 44 Tools

> Installed by `install-modern-cli.sh` on Ubuntu 22.04+, Fedora 40+, and macOS (via Homebrew).
> Tools are grouped by function. Install sources for Ubuntu (`apt`), Fedora (`dnf`), and macOS (`brew`) are listed for each.

---

## Table of Contents

- [Modes & Usage](#modes--usage)
- [Toolchain](#toolchain)
- [Editors](#editors)
- [File Managers](#file-managers)
- [ls Replacements](#ls-replacements)
- [Search & Find](#search--find)
- [Pager & View](#pager--view)
- [Shell UX](#shell-ux)
- [System Monitors](#system-monitors)
- [Process](#process)
- [Disk Usage](#disk-usage)
- [Git](#git)
- [Data / HTTP](#data--http)
- [Network](#network)
- [Text / Productivity](#text--productivity)
- [Install Method Legend](#install-method-legend)
- [Counts & Matrix](#counts--matrix)

---

## Modes & Usage

```bash
./install-modern-cli.sh            # interactive checklist (already installed tools shown unchecked)
./install-modern-cli.sh -y         # non-interactive install of defaults (skips installed tools)
./install-modern-cli.sh --force    # force re-install / overwrite even if tool exists in PATH
./install-modern-cli.sh -n         # dry-run (preview what would run without executing)
./install-modern-cli.sh --check    # audit system: list status & binary paths for all tools
./install-modern-cli.sh --table    # print install method matrix across Ubuntu, Fedora, and macOS
./install-modern-cli.sh --list     # print all tools + concise usage cheatsheet
./install-modern-cli.sh --update   # update all tools previously installed via this script
./install-modern-cli.sh fd bat     # install only named tools (skips if already installed)
```

> **Smart Skipping by Default:**
> The script automatically detects whether a tool's binary already exists in your `$PATH`.
> - In interactive mode, already-installed tools are labeled `[installed]` and start **unchecked**.
> - In non-interactive mode, installed tools are reported with `✓ <tool> already installed (<path>) — skipping`.
> - To force re-installation or overwrite existing binaries, pass `-f` or `--force`.

---

## Toolchain

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**cargo**](https://github.com/rust-lang/cargo) | Rust toolchain (rustup + cargo-binstall): install/update any crate | rustup installer | rustup installer | rustup installer | `cargo` `rustup` |

---

## Editors

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**nvim**](https://github.com/neovim/neovim) | Modal editor with LSP, Treesitter, massive plugin ecosystem | GitHub release | GitHub release | `brew install neovim` | `nvim` |
| [**micro**](https://github.com/zyedidia/micro) | Modern terminal editor — Ctrl-S save, Ctrl-C/V, familiar keybindings | `apt install micro` | `dnf install micro` | `brew install micro` | `micro` |
| [**helix**](https://github.com/helix-editor/helix) | Post-modern modal editor: selection-first, zero-config LSP + treesitter | PPA `maveonair/helix-editor` | `dnf install helix` (native) | `brew install helix` | `hx` |

---

## File Managers

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**yazi**](https://github.com/sxyazi/yazi) | Async TUI file manager: vim keys, image previews, `y` wrapper cds on quit | GitHub zip | GitHub zip | `brew install yazi` | `yazi` `ya` |
| [**broot**](https://github.com/Canop/broot) | Interactive tree+cd: search, preview, launch — best `tree` replacement | `cargo binstall broot` | `cargo binstall broot` | `brew install broot` | `broot` |
| [**nnn**](https://github.com/jarun/nnn) | Tiny blazing-fast file manager: plugins, batch rename, near-zero config | `apt install nnn` | `dnf install nnn` | `brew install nnn` | `nnn` |
| [**lf**](https://github.com/gokcehan/lf) | ranger-inspired file manager: single binary, shell-command driven | GitHub tarball | GitHub tarball | `brew install lf` | `lf` |

---

## ls Replacements

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**eza**](https://github.com/eza-community/eza) | `ls` replacement: icons, git status, tree, grouped dirs — aliases `ll la lt` | apt repo (gierens.de) | `dnf install eza` (native) | `brew install eza` | `eza` |
| [**lsd**](https://github.com/lsd-rs/lsd) | `ls` with icons/colors/tree — simpler and lighter than eza | `apt install lsd` | `dnf install lsd` | `brew install lsd` | `lsd` |

---

## Search & Find

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**fzf**](https://github.com/junegunn/fzf) | Fuzzy finder: Ctrl-T files, Alt-C cd, Tab completion everywhere | `apt install fzf` | `dnf install fzf` | `brew install fzf` | `fzf` |
| [**ripgrep**](https://github.com/BurntSushi/ripgrep) | `grep` replacement: recursive, gitignore-aware, very fast | `apt install ripgrep` | `dnf install ripgrep` | `brew install ripgrep` | `rg` |
| [**fd**](https://github.com/sharkdp/fd) | `find` replacement: intuitive syntax, gitignore-aware, parallel exec | `apt install fd-find` → `fdfind` | `dnf install fd-find` → `fd` | `brew install fd` | `fd` / `fdfind`¹ |
| [**plocate**](https://plocate.sesse.net/) | Fast modern `locate`: find files instantly by name across whole filesystem | `apt install plocate` (async updatedb) | `dnf install plocate` (async updatedb) | *(Linux only — macOS uses `mdfind`)* | `plocate` |

> ¹ Ubuntu apt renames `fd` to `fdfind`; the integration file adds `alias fd=fdfind` automatically. On Fedora and macOS, binary is native `fd`.

---

## Pager & View

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**bat**](https://github.com/sharkdp/bat) | `cat` with syntax highlighting, line numbers, git change markers, paging | `apt install bat` → `batcat` | `dnf install bat` → `bat` | `brew install bat` | `bat` / `batcat`¹ |

> ¹ Ubuntu apt renames `bat` to `batcat`; the integration file adds `alias bat=batcat` automatically. On Fedora and macOS, binary is native `bat`.

---

## Shell UX

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**zoxide**](https://github.com/ajeetdsouza/zoxide) | Smart `cd`: frecency-based jump, learns your directories — `z dir` | `apt install zoxide` | `dnf install zoxide` | `brew install zoxide` | `zoxide` |
| [**starship**](https://github.com/starship/starship) | Fast minimal cross-shell prompt: git/lang/status, highly configurable | GitHub tarball | GitHub tarball | `brew install starship` | `starship` |
| [**atuin**](https://github.com/atuinsh/atuin) | Shell history in SQLite: fuzzy Ctrl-R, statistics, optional encrypted sync | GitHub tarball | GitHub tarball | `brew install atuin` | `atuin` |
| [**zellij**](https://github.com/zellij-org/zellij) | Terminal multiplexer: panes, tabs, layouts, sessions — discoverable UX | GitHub tarball | GitHub tarball | `brew install zellij` | `zellij` |
| [**just**](https://github.com/casey/just) | `make` alternative: project task runner, clean syntax, no footguns | GitHub tarball | GitHub tarball | `brew install just` | `just` |
| [**navi**](https://github.com/denisidoro/navi) | Interactive cheatsheet launcher: Ctrl-G fills in command arguments | `cargo binstall navi` | `cargo binstall navi` | `brew install navi` | `navi` |
| [**tealdeer**](https://github.com/tealdeer-rs/tealdeer) | `tldr` pages: concise practical examples, fast Rust client | GitHub binary | GitHub binary | `brew install tealdeer` | `tldr` |

**Ctrl-R split when both atuin + fzf are installed:**
- **atuin** owns Ctrl-R (cached with `--disable-up-arrow` so up-arrow stays normal)
- **fzf** keeps Ctrl-T (files) and Alt-C (cd)

---

## System Monitors

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**btop**](https://github.com/aristocratos/btop) | Beautiful C++ system monitor: CPU/mem/net/disk graphs, full mouse support | `apt install btop` | `dnf install btop` | `brew install btop` | `btop` |
| [**bottom**](https://github.com/ClementTsang/bottom) | Rust system monitor: graphs, process tree, mouse, highly configurable | `apt install btm` | `dnf install bottom` | `brew install bottom` | `btm` |

---

## Process

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**procs**](https://github.com/dalance/procs) | `ps` replacement: colored, human-readable, tree, search by name/port/user | `cargo binstall procs` | `cargo binstall procs` | `brew install procs` | `procs` |

---

## Disk Usage

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**dust**](https://github.com/bootandy/dust) | `du` replacement: instant visual tree showing what eats your disk | `cargo binstall du-dust` | `dnf install du-dust` (native) | `brew install dust` | `dust` |
| [**duf**](https://github.com/muesli/duf) | `df` replacement: clean colored table of disks/mounts, sortable | `apt install duf` | `dnf install duf` | `brew install duf` | `duf` |
| [**ncdu**](https://dev.yorhel.nl/ncdu) | Classic interactive ncurses disk usage analyzer — battle-tested | `apt install ncdu` | `dnf install ncdu` | `brew install ncdu` | `ncdu` |
| [**gdu**](https://github.com/dundee/gdu) | Fast disk analyzer: parallel scan, SSD-optimized, ncdu-style TUI | PPA `daniel-milde/gdu` | COPR `danielmilde/gdu` | `brew install gdu` | `gdu` |

---

## Git

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**delta**](https://github.com/dandavison/delta) | git pager: syntax-highlighted, side-by-side diffs, section navigation | `apt install git-delta` | `dnf install git-delta` | `brew install git-delta` | `delta` |
| [**lazygit**](https://github.com/jesseduffield/lazygit) | TUI git: stage hunks/lines, commit, branch, rebase, cherry-pick | PPA `lazygit-team/release` | COPR `atim/lazygit` | `brew install lazygit` | `lazygit` |
| [**gitui**](https://github.com/gitui-org/gitui) | Blazing-fast git TUI written in Rust — lighter than lazygit on huge repos | GitHub tarball | GitHub tarball | `brew install gitui` | `gitui` |
| [**difftastic**](https://github.com/Wilfred/difftastic) | Structural diff: understands syntax, not lines — ignores pure reformatting | `cargo binstall difftastic` | `cargo binstall difftastic` | `brew install difftastic` | `difft` |

---

## Data / HTTP

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**jq**](https://github.com/jqlang/jq) | Command-line JSON processor: filter, transform, reshape JSON | `apt install jq` | `dnf install jq` | `brew install jq` | `jq` |
| [**jless**](https://github.com/PaulJuliusMartinez/jless) | TUI JSON/YAML viewer: fold, search, navigate — like `less` for JSON | `cargo binstall jless` | `cargo binstall jless` | `brew install jless` | `jless` |
| [**yq**](https://github.com/mikefarah/yq) | jq for YAML/TOML/XML: query and edit structured config files | GitHub binary | GitHub binary | `brew install yq` | `yq` |
| [**xh**](https://github.com/ducaale/xh) | HTTPie-style HTTP client (curl alt): friendly syntax, fast Rust binary | `cargo binstall xh` | `cargo binstall xh` | `brew install xh` | `xh` |
| [**curlie**](https://github.com/rs/curlie) | curl frontend with HTTPie-style output + all curl flags available | GitHub tarball (dynamic) | GitHub tarball (dynamic) | `brew install curlie` | `curlie` |
| [**csvlens**](https://github.com/YS-L/csvlens) | `less` for CSV: scroll, search, filter, column stats on large files | `cargo binstall csvlens` | `cargo binstall csvlens` | `brew install csvlens` | `csvlens` |

---

## Network

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**gping**](https://github.com/orf/gping) | `ping` with a live latency graph; compare multiple hosts simultaneously | apt (azlux.fr repo) | `dnf install gping` (native) | `brew install gping` | `gping` |
| [**bandwhich**](https://github.com/imsnif/bandwhich) | Bandwidth utilization by process/connection/remote host (needs sudo) | `cargo binstall bandwhich` | `cargo binstall bandwhich` | `brew install bandwhich` | `bandwhich` |

---

## Text / Productivity

| Tool | Description | Ubuntu (apt) | Fedora (dnf) | macOS (brew) | Binary |
|------|-------------|--------------|--------------|--------------|--------|
| [**sd**](https://github.com/chmln/sd) | `sed` for humans: intuitive find-and-replace with real regex | `cargo binstall sd` | `cargo binstall sd` | `brew install sd` | `sd` |
| [**hyperfine**](https://github.com/sharkdp/hyperfine) | Statistical CLI benchmarking: warmup, comparison, export, parameter scans | `apt install hyperfine` | `dnf install hyperfine` | `brew install hyperfine` | `hyperfine` |
| [**tokei**](https://github.com/XAMPPRocky/tokei) | Count lines of code by language: fast, accurate, gitignore-aware | `cargo binstall tokei` | `cargo binstall tokei` | `brew install tokei` | `tokei` |

---

## Install Method Legend

| Method | What it means |
|--------|---------------|
| `apt install PKG` | Ubuntu 24.04+ standard repos |
| `dnf install PKG` | Fedora 40+ standard repos (native) |
| `brew install PKG` | macOS Homebrew standard formulae |
| `apt` repo | Tool's own signed Debian repo (e.g. gierens.de for eza, azlux.fr for gping) |
| PPA `owner/name` | Ubuntu Launchpad PPA (`add-apt-repository ppa:owner/name`) |
| COPR `owner/name` | Fedora COPR repo (`dnf copr enable owner/name`) |
| GitHub tarball / zip | Stable `releases/latest/download/...` archive extracted to `/usr/local/bin` |
| GitHub tarball (dynamic) | Version-embedded filename; script discovers tag at install time |
| `cargo binstall CRATE` | Downloads prebuilt binary via cargo-binstall (seconds, no compilation) |
| rustup installer | `curl sh.rustup.rs` — installs rustup, cargo, cargo-binstall |

---

## Counts & Matrix

- **44 tools** across **14 categories**
- Supported platforms: **Ubuntu (apt)**, **Fedora (dnf)**, and **macOS (brew)**
- **43 of 44 tools** available on macOS via Homebrew (`plocate` is Linux-specific; macOS uses native `mdfind` / Spotlight)
