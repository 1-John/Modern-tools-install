#!/usr/bin/env bash
# macOS ships with ancient Bash 3.2 in /bin/bash (which lacks associative arrays `declare -A`).
# If running under Bash < 4 on macOS, re-exec with Homebrew bash.
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "$_b" ]; then
      exec "$_b" "$0" "$@"
    fi
  done
  echo "Error: Bash 4.0+ is required (current: $BASH_VERSION)." >&2
  echo "On macOS, please install modern bash via Homebrew: brew install bash" >&2
  exit 1
fi

# install-modern-cli.sh — modern CLI toolkit for Ubuntu, Fedora, and macOS (Homebrew)
# ─────────────────────────────────────────────────────────────────
# Modes:
#   ./install-modern-cli.sh            interactive checklist (installed tools shown unchecked)
#   ./install-modern-cli.sh -y         install all defaults, skips tools already installed
#   ./install-modern-cli.sh --force    force re-install even if tool already exists in PATH
#   ./install-modern-cli.sh -n         dry-run
#   ./install-modern-cli.sh --check    check and display install status of all tools
#   ./install-modern-cli.sh --update   re-install/upgrade all previously installed tools
#   ./install-modern-cli.sh --list     print all tools + usages
#   ./install-modern-cli.sh --table    print install method matrix per OS/distro
#   ./install-modern-cli.sh fd bat     install only named tools (skips existing unless --force)
#
# Supported distros: Ubuntu 22.04+, Fedora 40+, macOS (Homebrew)
# Dependencies: apt, dnf, or brew. Rustup/cargo installed by the `cargo` tool entry.
# Shell integration → ~/.config/modern-cli/integration.{bash,zsh}  (auto-sourced)
# Install DB       → ~/.config/modern-cli/installed.txt             (for --update)
set -uo pipefail

# ─── DISTRO DETECTION ────────────────────────────────────────────────────────
PKG_MGR=""          # apt | dnf | brew
DISTRO_FAMILY=""    # debian | fedora | macos

detect_distro() {
  if [ "$(uname -s)" = "Darwin" ]; then
    PKG_MGR="brew"
    DISTRO_FAMILY="macos"
    return 0
  fi

  if [ ! -f /etc/os-release ]; then
    echo "Cannot detect distro: /etc/os-release not found"; exit 1
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian|linuxmint|pop)
      PKG_MGR=apt; DISTRO_FAMILY=debian ;;
    fedora|rhel|centos|almalinux|rocky|ol)
      PKG_MGR=dnf; DISTRO_FAMILY=fedora ;;
    *)
      # unknown — try to guess from ID_LIKE
      case "${ID_LIKE:-}" in
        *debian*) PKG_MGR=apt; DISTRO_FAMILY=debian ;;
        *fedora*|*rhel*) PKG_MGR=dnf; DISTRO_FAMILY=fedora ;;
        *) printf 'Unsupported distro: %s\n' "${ID:-unknown}"; exit 1 ;;
      esac ;;
  esac
}
detect_distro

# ─── CONFIG ──────────────────────────────────────────────────────────────────
if [ "$DISTRO_FAMILY" = macos ]; then
  if [ "$(uname -m)" = "arm64" ] && [ -d "/opt/homebrew/bin" ]; then
    BIN_DIR="/opt/homebrew/bin"
  else
    BIN_DIR="/usr/local/bin"
  fi
else
  BIN_DIR="/usr/local/bin"
fi
CFG_DIR="$HOME/.config/modern-cli"
INST_DB="$CFG_DIR/installed.txt"
INTEGRATION_BASH="$CFG_DIR/integration.bash"
INTEGRATION_ZSH="$CFG_DIR/integration.zsh"
DL="https://github.com"
DRY=0
YES=0
FORCE=0

# Architecture — use uname -m (works on apt, dnf, and brew systems)
case "$(uname -m)" in
  x86_64)        ARCH=amd64; RARCH=x86_64;  GOARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64; RARCH=aarch64; GOARCH=arm64 ;;
  *)             printf 'Unsupported arch: %s\n' "$(uname -m)"; exit 1 ;;
esac
SUDO=""
[ "$DISTRO_FAMILY" != macos ] && [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# Distro-specific paths
case "$DISTRO_FAMILY" in
  debian) KEYRINGS=/etc/apt/keyrings; SOURCES=/etc/apt/sources.list.d ;;
  fedora) KEYRINGS=/etc/pki/rpm-gpg;  SOURCES=/etc/yum.repos.d ;;
  macos)  KEYRINGS=""; SOURCES="" ;;
esac

# colours
B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' OFF=$'\033[0m'
say()  { printf '%s\n' "${B}==>${OFF} $*"; }
ok()   { printf '%s\n' "    ${G}✓${OFF} $*"; }
warn() { printf '%s\n' "    ${Y}!${OFF} $*"; }
err()  { printf '%s\n' "    ${R}✗${OFF} $*" >&2; }
run()  { [ "$DRY" = 1 ] && { printf '%s\n' "    ${D}[dry] $*${OFF}"; return 0; }; eval "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ─── TOOL REGISTRY ───────────────────────────────────────────────────────────
# Parallel arrays — declared in registration order = display order
TOOLS=()          # tool names (canonical order)
declare -A CAT    # tool → category
declare -A METHOD # tool → install method
declare -A A64    # tool → amd64 asset name (or apt pkg name)
declare -A ARM    # tool → arm64 asset name
declare -A REPO   # tool → github "owner/repo"
declare -A BIN    # tool → binary name inside archive
declare -A DESC   # tool → one-liner
declare -A USAGE  # tool → usage examples

reg() {  # reg NAME CATEGORY METHOD REPO ASSET_AMD64 ASSET_ARM64 BINARY "DESC" "USAGE"
  local name="$1"; TOOLS+=("$name")
  CAT["$name"]="$2"; METHOD["$name"]="$3"; REPO["$name"]="$4"
  A64["$name"]="$5"; ARM["$name"]="$6"; BIN["$name"]="$7"
  DESC["$name"]="$8"; USAGE["$name"]="$9"
}

# ── toolchain ────────────────────────────────────────────────────────────────
reg cargo toolchain custom - - - cargo \
  "Rust toolchain (rustup + cargo): install/update any crate" \
  "cargo install ripgrep     install a crate
cargo install-update -a   upgrade all installed crates (needs cargo-update)
rustup update             update toolchain
rustup show               installed targets"

# ── editors ──────────────────────────────────────────────────────────────────
reg nvim editors github-tgz neovim/neovim \
  "nvim-linux-x86_64.tar.gz" "nvim-linux-arm64.tar.gz" nvim \
  "Neovim: modal editor with LSP, Treesitter, plugin ecosystem" \
  "nvim file           open a file
:Lazy               plugin manager (lazy.nvim)
:Mason              LSP server manager
Ctrl-W hjkl         navigate splits
:checkhealth        diagnose setup"

reg micro editors apt micro \
  "" "" micro \
  "Modern terminal editor — Ctrl-S save, Ctrl-C/V, familiar keys (apt: 2.0.13)" \
  "micro file          open file
Ctrl-E              command mode
Ctrl-F              find
Ctrl-G              help
micro -plugin install NAME  install plugin"

reg helix editors apt-ppa helix-editor \
  "" "" hx \
  "Post-modern modal editor: selection-first, zero-config LSP+treesitter (PPA: maveonair)" \
  "hx file            open file (binary is 'hx')
space then f        file picker
Ctrl-W s/v          split horizontal/vertical
:sh CMD             run shell command
hx --health         check LSP/treesitter status"

# ── file managers ─────────────────────────────────────────────────────────────
reg yazi file-managers github-zip sxyazi/yazi \
  "yazi-x86_64-unknown-linux-musl.zip" "yazi-aarch64-unknown-linux-musl.zip" yazi \
  "Async TUI file manager: vim keys, image previews, y wrapper cds on quit" \
  "y                  launch (cds to last dir on quit)
h/j/k/l            navigate (vim-style)
space / v           select / visual select
y / x / p           yank / cut / paste
a / r / d           create / rename / trash
s/z/Z               rg/fzf/zoxide search"

reg broot file-managers cargo-bin broot \
  "broot_1.57.0.zip" "broot_1.57.0.zip" broot \
  "Interactive tree+cd: search, preview, launch — the best 'tree' replacement" \
  "br                 launch (br function cds on quit)
:gf PATTERN         find files
:e FILE             open in editor
:rm / :mv           file operations
broot --sizes       show sizes"

reg nnn file-managers apt nnn - - nnn \
  "Tiny blazing-fast file manager: plugins, batch rename, near-zero config" \
  "nnn                launch
n                   new file; shift-n new dir
y                   yank; p paste; x delete
e                   open in EDITOR
!                   spawn shell"

reg lf file-managers github-tgz gokcehan/lf \
  "lf-linux-amd64.tar.gz" "lf-linux-arm64.tar.gz" lf \
  "ranger-inspired file manager: single binary, shell-command driven" \
  "lf                 launch
:set hidden true    show hidden
map <key> CMD       custom keybinding in ~/.config/lf/lfrc
e                   open in editor; q quit"

# ── ls family ─────────────────────────────────────────────────────────────────
reg eza ls-family apt-repo eza - - eza \
  "ls replacement: colors, icons, git status, tree (aliases: ll la lt)" \
  "ll                 long list (alias → eza -lh --git)
la                 show hidden (alias → eza -lah)
lt                 tree view (alias → eza --tree --level=2)
eza -l --sort=size  sort by size
eza --git-ignore    respect .gitignore"

reg lsd ls-family apt lsd \
  "" "" lsd \
  "ls with icons/colors/tree — simpler/lighter than eza (Ubuntu 24.04+ apt)" \
  "lsd                basic list
lsd -l             long format
lsd --tree         tree view
lsd -la            all files, long
lsd --group-dirs first"

# ── search ────────────────────────────────────────────────────────────────────
reg fzf search apt fzf - - fzf \
  "Fuzzy finder: Ctrl-R history, Ctrl-T files, **Tab completion" \
  "Ctrl-R             fuzzy history search
Ctrl-T             insert file path
Alt-C              cd into subdirectory
vim **Tab          fuzzy complete path
kill -9 **Tab      pick a process to kill
git switch \$(git branch | fzf)"

reg ripgrep search apt ripgrep - - rg \
  "grep replacement: recursive, gitignore-aware, very fast" \
  "rg PATTERN         search cwd recursively
rg -i error        case-insensitive
rg -t py def       only Python files
rg -l pattern      list matching files only
rg -A3 -B3 pat     3 lines of context
rg --files | rg x  list+filter filenames"

reg fd search apt fd-find - - fdfind \
  "find replacement: intuitive syntax, gitignore-aware, parallel exec" \
  "fd report          find files matching 'report'
fd -e pdf          only .pdf extension
fd -H secret       include hidden files
fd -t d tmp        directories only
fd -x wc -l        run command on each result
fd . /etc -e conf  search specific path"

reg plocate search custom plocate - - plocate \
  "Fast modern locate: find files instantly by name across the whole filesystem" \
  "plocate report     find files named 'report' anywhere
plocate -r '\.py\$'  regex search
plocate -l 5 foo   limit to 5 results
sudo updatedb      refresh index (cron runs this daily)
plocate -i NAME    case-insensitive"

# ── view ──────────────────────────────────────────────────────────────────────
reg bat view apt bat - - batcat \
  "cat with syntax highlighting, line numbers, git change markers, paging" \
  "bat file.py        pretty-print a file
bat -A file        show invisible chars
bat -r 20:40 file  show only lines 20-40
bat -p file        plain (no decorations)
rg -l x | xargs bat  view all matches
man CMD            now colored (MANPAGER auto-set)"

# ── shell UX ──────────────────────────────────────────────────────────────────
reg zoxide shell-ux apt zoxide \
  "" "" zoxide \
  "Smart cd: frecency-based jump, learns your directories (Ubuntu 24.04+ apt)" \
  "z proj             jump to best match for 'proj'
z proj api         multi-word match
zi                 interactive fuzzy pick (uses fzf)
z -                previous directory
z ..               still works like cd .."

reg starship shell-ux github-tgz starship/starship \
  "starship-x86_64-unknown-linux-musl.tar.gz" "starship-aarch64-unknown-linux-musl.tar.gz" starship \
  "Fast minimal cross-shell prompt: git/lang/status, configurable" \
  "starship init bash  (auto-loaded in shell)
starship config    open ~/.config/starship.toml
starship explain   why prompt shows what it shows
starship preset nerd-font-symbols -o ~/.config/starship.toml"

reg atuin shell-ux github-tgz atuinsh/atuin \
  "atuin-x86_64-unknown-linux-musl.tar.gz" "atuin-aarch64-unknown-linux-musl.tar.gz" atuin \
  "Shell history in SQLite: fuzzy Ctrl-R, stats, optional encrypted sync" \
  "Ctrl-R             open history search UI
atuin search CMD   search from terminal
atuin stats        show command stats
atuin import auto  import existing history
Up arrow           prefix-filter recent commands"

reg zellij shell-ux github-tgz zellij-org/zellij \
  "zellij-x86_64-unknown-linux-musl.tar.gz" "zellij-aarch64-unknown-linux-musl.tar.gz" zellij \
  "Terminal multiplexer: panes, tabs, layouts, sessions — discoverable" \
  "zellij             start new session
zellij attach      reattach last session
Ctrl-p n           new pane
Ctrl-t n           new tab
zellij --layout compact  minimal chrome"

reg just shell-ux github-tgz casey/just \
  "just-x86_64-unknown-linux-musl.tar.gz" "just-aarch64-unknown-linux-musl.tar.gz" just \
  "make alternative: project task runner, clean syntax, no footguns" \
  "just               list available recipes
just build         run 'build' recipe
just -n            dry-run
just --dump        print computed justfile
echo 'build:\n  cargo build' > justfile"

reg navi shell-ux cargo-bin navi \
  "navi-x86_64-unknown-linux-musl.tar.gz" "navi-aarch64-unknown-linux-musl.tar.gz" navi \
  "Interactive cheatsheet launcher: Ctrl-G fills in command arguments" \
  "Ctrl-G             open cheatsheet picker (shell-hooked)
navi               standalone browser
navi repo add URL  add community cheatsheets
navi fn welcome    onboarding"

reg tealdeer shell-ux github-raw tealdeer-rs/tealdeer \
  "tealdeer-linux-x86_64-musl" "tealdeer-linux-aarch64-musl" tldr \
  "tldr pages: concise practical command examples, fast Rust client" \
  "tldr tar           examples for tar
tldr --update      refresh page cache
tldr -l            list all available pages
tldr ssh           quick ssh recipes"

# ── monitors ──────────────────────────────────────────────────────────────────
reg btop monitors apt btop - - btop \
  "Beautiful C++ system monitor: CPU/mem/net/disk graphs, full mouse support" \
  "btop               launch
m                  toggle mem display
n                  toggle network
f                  filter processes
k                  send signal; dd kill selected"

reg bottom monitors apt btm \
  "" "" btm \
  "Rust system monitor (btm): graphs, process tree, mouse, highly configurable (apt: btm)" \
  "btm                launch
/                  filter processes
t                  toggle process tree
dd                 kill process
e                  expand widget fullscreen"

# ── process ───────────────────────────────────────────────────────────────────
reg procs process cargo-bin procs \
  "procs-x86_64-linux.zip" "procs-aarch64-linux.zip" procs \
  "ps replacement: colored, human-readable, tree, search by name/port/user" \
  "procs              show all processes
procs nginx        filter by name
procs --tree       process tree
procs --sortd cpu  sort by CPU desc
procs --tcp        show listening ports"

# ── disk ──────────────────────────────────────────────────────────────────────
reg dust disk cargo-bin du-dust \
  "dust-x86_64-unknown-linux-musl.tar.gz" "dust-aarch64-unknown-linux-musl.tar.gz" dust \
  "du replacement: instant visual tree showing what eats your disk" \
  "dust               analyze current directory
dust -d 2          limit depth to 2 levels
dust -r            reverse (biggest at top)
dust /var/log      analyze specific path
dust -X .git       exclude pattern"

reg duf disk apt duf - - duf \
  "df replacement: clean colored table of disks/mounts, sortable" \
  "duf                all filesystems
duf /home          specific mount
duf --only local   hide network/fuse mounts
duf --sort size    sort by size
duf --json         machine-readable output"

reg ncdu disk apt ncdu - - ncdu \
  "Classic interactive ncurses disk usage analyzer — battle-tested" \
  "ncdu               analyze cwd
ncdu /             analyze root (with sudo)
d                  delete file/dir
e                  show extended info
ncdu -x            stay on one filesystem"

reg gdu disk apt-ppa gdu \
  "" "" gdu \
  "Fast disk analyzer: parallel scan, SSD-optimized, ncdu-style TUI (PPA: daniel-milde)" \
  "gdu                interactive TUI
gdu -l /           analyze root
gdu --no-color     plain output
gdu -p /home       show progress bar"

# ── git ───────────────────────────────────────────────────────────────────────
reg delta git apt git-delta \
  "" "" delta \
  "git pager: syntax-highlighted, side-by-side diffs (apt: git-delta, Ubuntu 24.04+)" \
  "git diff           now highlighted (auto-configured)
git show / log -p  also uses delta
delta a.txt b.txt  diff two files directly
n / N              next/prev file in pager
--side-by-side     flag (or set in .gitconfig)"

reg lazygit git apt-ppa lazygit \
  "" "" lazygit \
  "TUI git: stage hunks/lines, commit, branch, rebase, cherry-pick (PPA: lazygit-team)" \
  "lazygit            launch (in a git repo)
space              stage/unstage file
c                  commit; P push; p pull
e                  open in editor
1-5 / ?            switch panels / help"

reg gitui git github-tgz gitui-org/gitui \
  "gitui-linux-x86_64.tar.gz" "gitui-linux-aarch64.tar.gz" gitui \
  "Blazing-fast git TUI written in Rust — lighter than lazygit on huge repos" \
  "gitui              launch
tab                switch panels
space              stage/unstage
c                  commit; p push
Ctrl-P             branch select"

reg difftastic git cargo-bin difftastic \
  "" "" difft \
  "Structural diff: understands syntax, not lines — ignores pure reformatting" \
  "difft a.js b.js    syntax-aware diff
GIT_EXTERNAL_DIFF=difft git diff  use in git
difft --display inline  inline mode
# great for: seeing real changes through mass reformats"

# ── data / http ───────────────────────────────────────────────────────────────
reg jq data apt jq - - jq \
  "Command-line JSON processor: filter, transform, reshape JSON" \
  "jq . file.json     pretty-print
jq '.items[].name' extract a field
jq 'map(.x)|add'   aggregate
curl ... | jq -r .token  raw string
jq 'select(.age>30)' filter"

reg jless data cargo-bin jless \
  "jless-x86_64-unknown-linux-gnu.zip" "jless-aarch64-unknown-linux-gnu.zip" jless \
  "TUI JSON/YAML viewer: fold, search, navigate — like 'less' for JSON" \
  "jless big.json     open viewer
j/k  h/l           move / collapse-expand
/pattern           search
space              fold a node
curl ... | jless   pipe straight in"

reg yq data github-raw mikefarah/yq \
  "yq_linux_amd64" "yq_linux_arm64" yq \
  "jq for YAML/TOML/XML: query and edit structured config files" \
  "yq .services.web docker-compose.yml
yq -i '.version=2' f.yml  edit in place
yq -P file.json           JSON → YAML
yq -o=json f.yml          YAML → JSON"

reg xh data cargo-bin xh \
  "xh-x86_64-unknown-linux-musl.tar.gz" "xh-aarch64-unknown-linux-musl.tar.gz" xh \
  "HTTPie-style HTTP client (curl alt): friendly syntax, fast Rust binary" \
  "xh httpbin.org/get          GET request
xh POST api/users name=bob  JSON body
xh GET api q==search        query param
xh -d URL > file            download
xh --follow --timeout=30 URL"

reg curlie data github-tgz rs/curlie \
  "curlie_linux_amd64.tar.gz" "curlie_linux_arm64.tar.gz" curlie \
  "curl frontend with HTTPie-style output + all curl flags available" \
  "curlie api.x/y     GET with colored output
curlie POST api -d @file
curlie -v URL       verbose
curlie --curl URL   show equivalent curl command"

reg csvlens data cargo-bin csvlens \
  "" "" csvlens \
  "less for CSV: scroll, search, filter, stats on large CSV files (via cargo)" \
  "csvlens file.csv   open viewer
/ pattern          search
Tab                switch between rows/cols mode
g / G              first / last row
q                  quit"

# ── network ───────────────────────────────────────────────────────────────────
reg gping network apt-azlux gping \
  "" "" gping \
  "ping with a live latency graph; compare multiple hosts (azlux.fr repo)" \
  "gping google.com           graph latency
gping a.com b.com          compare hosts
gping --cmd 'curl -o/dev/null URL'  graph cmd time
gping -n 0.5 host          0.5s interval"

reg bandwhich network cargo-bin bandwhich \
  "bandwhich-x86_64-unknown-linux-musl.tar.gz" "bandwhich-aarch64-unknown-linux-musl.tar.gz" bandwhich \
  "Bandwidth utilization by process/connection/remote host (needs sudo)" \
  "sudo bandwhich     show bandwidth by process
q                  quit; p pause
# requires elevated privileges or: sudo setcap cap_sys_ptrace,cap_net_raw+ep \$(which bandwhich)"

# ── text / productivity ───────────────────────────────────────────────────────
reg sd text apt sd \
  "" "" sd \
  "sed for humans: intuitive find-and-replace with real regex (Ubuntu 24.04+ apt)" \
  "sd old new file           replace in file
sd '(\\w+)@' '\$1 at ' f   capture groups
cmd | sd '\\t' ','         pipe transform
fd -e txt -x sd a b        replace across files"

reg hyperfine text apt hyperfine \
  "" "" hyperfine \
  "Statistical CLI benchmarking: warmup, comparison, export, parameter scans (apt)" \
  "hyperfine 'sleep 0.3'       benchmark
hyperfine 'cmd a' 'cmd b'   compare
hyperfine -w 3 CMD           3 warmup runs
hyperfine -p 'make clean' CMD  setup cmd
hyperfine --export-markdown out.md"

reg tokei text cargo-bin tokei \
  "" "" tokei \
  "Count lines of code by language: fast, accurate, gitignore-aware (via cargo)" \
  "tokei              count in cwd
tokei src/         count specific dir
tokei -e vendor    exclude directory
tokei --output json  machine-readable
tokei -s lines     sort by lines"

# ─── DEFAULTS (shown pre-checked in interactive mode) ─────────────────────────
DEFAULTS=(
  cargo
  nvim micro
  fzf ripgrep fd bat plocate
  eza yazi zoxide
  starship atuin
  btop procs dust duf
  delta lazygit
  jq jless xh yq
  sd hyperfine tealdeer zellij
  gping
)

# BIN_CHECK: what to actually run `command -v` against per tool.
# Differs from BIN[] when Ubuntu apt renames the binary (batcat, fdfind).
# Also covers tools whose archive binary name differs from "how you invoke it".
declare -A BIN_CHECK
# Ubuntu/Debian: apt renames some binaries
BIN_CHECK[bat]="batcat:bat"       # Ubuntu apt: batcat; Fedora: bat
BIN_CHECK[fd]="fdfind:fd"         # Ubuntu apt: fdfind; Fedora: fd
BIN_CHECK[ripgrep]="rg"
BIN_CHECK[difftastic]="difft"
BIN_CHECK[tealdeer]="tldr"
BIN_CHECK[helix]="hx"
BIN_CHECK[bottom]="btm"
BIN_CHECK[plocate]="plocate"
BIN_CHECK[delta]="delta"

# On Fedora and macOS, bat/fd use their natural binary names — remove the Ubuntu fallback
[ "$DISTRO_FAMILY" = fedora ] || [ "$DISTRO_FAMILY" = macos ] && {
  BIN_CHECK[bat]="bat"
  BIN_CHECK[fd]="fd"
}

# PPA (Ubuntu/Debian), COPR (Fedora), and Homebrew (macOS) metadata
declare -A PPA_NAME APT_PKG COPR_REPO DNF_PKG BREW_PKG

PPA_NAME[lazygit]="lazygit-team/release"
PPA_NAME[helix]="maveonair/helix-editor"
PPA_NAME[gdu]="daniel-milde/gdu"
APT_PKG[helix]="helix-editor"
APT_PKG[delta]="git-delta"
APT_PKG[bottom]="btm"

# Homebrew package names (macOS)
BREW_PKG[nvim]="neovim"
BREW_PKG[delta]="git-delta"

# Fedora COPR repos (equivalent to Ubuntu PPAs)
COPR_REPO[lazygit]="atim/lazygit"
COPR_REPO[gdu]="danielmilde/gdu"
# helix and eza are in standard Fedora 40+ repos — no COPR needed

# Fedora DNF package names (when different from REPO/APT_PKG)
DNF_PKG[bottom]="bottom"          # Ubuntu apt pkg is "btm"
DNF_PKG[helix]="helix"            # Ubuntu PPA pkg is "helix-editor"; Fedora: native "helix"
DNF_PKG[delta]="git-delta"        # same as APT_PKG, but explicit
DNF_PKG[dust]="du-dust"           # Ubuntu: cargo-bin du-dust; Fedora: dnf du-dust
DNF_PKG[gping]="gping"            # same name, but on Fedora it's in native repos
DNF_PKG[yq]="yq"                  # mikefarah's yq is "yq" on Fedora too

# Returns the right package name for the current distro
_pkg_name() {
  local t="$1"
  case "$PKG_MGR" in
    apt)  printf '%s' "${APT_PKG[$t]:-${REPO[$t]:-$t}}" ;;
    dnf)  printf '%s' "${DNF_PKG[$t]:-${APT_PKG[$t]:-${REPO[$t]:-$t}}}" ;;
    brew) printf '%s' "${BREW_PKG[$t]:-$t}" ;;
  esac
}

# resolve the actual on-disk binary name for a tool (first found wins)
resolve_bin() {
  local t="$1"
  local check="${BIN_CHECK[$t]:-${BIN[$t]:-$t}}"
  local b
  IFS=: read -ra candidates <<< "$check"
  for b in "${candidates[@]}"; do
    command -v "$b" >/dev/null 2>&1 && { echo "$b"; return 0; }
  done
  return 1
}

# ─── HELPERS ──────────────────────────────────────────────────────────────────

# Distro-aware package installer
pkg_install() {
  case "$PKG_MGR" in
    apt)  run "$SUDO apt-get install -y --no-install-recommends $*" ;;
    dnf)  run "$SUDO dnf install -y $*" ;;
    brew) run "brew install $*" ;;
  esac
}
apt_install() { pkg_install "$@"; }   # backward-compat shim

# ── Dynamic tag discovery (no API, no rate limits) ────────────────────────────
# Follows the /releases/latest redirect → extracts the tag from the final URL.
# Works for every public GitHub repo.
get_latest_tag() {
  curl -fsSL -o /dev/null -w '%{url_effective}' \
    "$DL/$1/releases/latest" 2>/dev/null \
    | sed 's|.*/tag/||; s|[[:space:]]*$||'
}

# ── Asset name templates ───────────────────────────────────────────────────────
# Many tools embed their version number in the release asset filename.
# When a new release ships, the old versionless "latest/download/NAME" → 404.
# Solution: discover the current tag at install time, expand the template.
#   {TAG} = full tag  (e.g.  v1.2.3  or  0.19.2 for delta)
#   {VER} = tag without leading 'v'  (e.g.  1.2.3)
# Tools without a template use the stable "latest/download/FIXED_NAME" path.
declare -A A64T ARMT

# helix: kept for reference if PPA ever removed
A64T[helix]="helix-{TAG}-x86_64-linux.tar.xz";     ARMT[helix]="helix-{TAG}-aarch64-linux.tar.xz"
# broot: kept for reference (now uses cargo-bin)
A64T[broot]="broot_{VER}.zip";                      ARMT[broot]="broot_{VER}.zip"
# curlie: Go binary, version-embedded — still uses dynamic download
A64T[curlie]="curlie_{VER}_linux_amd64.tar.gz";     ARMT[curlie]="curlie_{VER}_linux_arm64.tar.gz"

# ── Cargo crate names (tools with no prebuilt binary) ─────────────────────────
# gping:    tag format is 'gping-v1.x.y' (non-standard) + no prebuilt Linux binary
# csvlens:  v0.15.1 dropped prebuilt binaries
# tokei:    v14.0.0 dropped prebuilt binaries
# dog:      unmaintained since 2021 (ogham/dog), no release assets; still on crates.io
declare -A CARGO_CRATE
CARGO_CRATE[csvlens]="csvlens"
CARGO_CRATE[tokei]="tokei"

# ── URL builder: handles both stable and dynamic (versioned) asset names ───────
# Returns the full download URL; for dynamic tools it fetches the current tag.
get_dl_url() {
  local t="$1" ext="$2"   # ext = tgz|txz|bz2|zip|raw (informational)
  local tmpl
  if [ -n "${A64T[$t]:-}" ]; then
    local tag; tag="$(get_latest_tag "${REPO[$t]}")"
    [ -z "$tag" ] && { err "could not discover latest tag for ${REPO[$t]}"; return 1; }
    local ver="${tag#v}"
    [ "$ARCH" = amd64 ] && tmpl="${A64T[$t]}" || tmpl="${ARMT[$t]:-${A64T[$t]}}"
    local a="${tmpl//\{TAG\}/$tag}"; a="${a//\{VER\}/$ver}"
    echo "$DL/${REPO[$t]}/releases/download/$tag/$a"
  else
    local a; [ "$ARCH" = amd64 ] && a="${A64[$t]}" || a="${ARM[$t]}"
    echo "$DL/${REPO[$t]}/releases/latest/download/$a"
  fi
}

# select stable arch-specific asset name (only for non-template tools)
asset() { local t="$1"; [ "$ARCH" = amd64 ] && echo "${A64[$t]}" || echo "${ARM[$t]}"; }

# ── Generic download+extract installers ──────────────────────────────────────
# All now use get_dl_url() so they work for both stable and version-embedded names.

# .tar.gz
inst_tgz() {
  local t="$1"
  local url; url="$(get_dl_url "$t" tgz)" || return 1
  local a="${url##*/}"
  local tmp; tmp="$(mktemp -d)"
  run "curl -fsSL '$url' -o '$tmp/a.tar.gz'"
  [ "$DRY" = 1 ] && { rm -rf "$tmp"; ok "(dry) ${BIN[$t]} from $a"; return 0; }
  tar -xzf "$tmp/a.tar.gz" -C "$tmp" 2>/dev/null || { err "extract failed: $a"; rm -rf "$tmp"; return 1; }
  local f; f="$(find "$tmp" -type f -name "${BIN[$t]}" \( -perm -u+x -o -name "${BIN[$t]}" \) | head -1)"
  [ -z "$f" ] && { err "binary '${BIN[$t]}' not in $a"; rm -rf "$tmp"; return 1; }
  $SUDO install -m755 "$f" "$BIN_DIR/${BIN[$t]}"; rm -rf "$tmp"
  ok "installed ${BIN[$t]}"
}

# .tar.xz (helix — also copies runtime dir)
inst_txz() {
  local t="$1"
  local url; url="$(get_dl_url "$t" txz)" || return 1
  local a="${url##*/}"
  local tmp; tmp="$(mktemp -d)"
  run "curl -fsSL '$url' -o '$tmp/a.tar.xz'"
  [ "$DRY" = 1 ] && { rm -rf "$tmp"; ok "(dry) ${BIN[$t]} from $a"; return 0; }
  tar -xJf "$tmp/a.tar.xz" -C "$tmp" 2>/dev/null || { err "extract failed: $a"; rm -rf "$tmp"; return 1; }
  local f; f="$(find "$tmp" -type f -name "${BIN[$t]}" | head -1)"
  [ -z "$f" ] && { err "binary '${BIN[$t]}' not in $a"; rm -rf "$tmp"; return 1; }
  $SUDO install -m755 "$f" "$BIN_DIR/${BIN[$t]}"
  local rt; rt="$(find "$tmp" -type d -name runtime | head -1)"
  if [ -n "$rt" ]; then
    $SUDO mkdir -p /usr/local/share/helix
    $SUDO cp -r "$rt" /usr/local/share/helix/runtime
    ok "installed hx + runtime"
  fi
  rm -rf "$tmp"; ok "installed ${BIN[$t]}"
}

# .zip
inst_zip() {
  local t="$1"
  local url; url="$(get_dl_url "$t" zip)" || return 1
  local a="${url##*/}"
  local tmp; tmp="$(mktemp -d)"
  run "curl -fsSL '$url' -o '$tmp/a.zip'"
  [ "$DRY" = 1 ] && { rm -rf "$tmp"; ok "(dry) ${BIN[$t]} from $a"; return 0; }
  unzip -qo "$tmp/a.zip" -d "$tmp" || { err "unzip failed: $a"; rm -rf "$tmp"; return 1; }
  local f; f="$(find "$tmp" -type f -name "${BIN[$t]}" | head -1)"
  [ -z "$f" ] && { err "binary '${BIN[$t]}' not in $a"; rm -rf "$tmp"; return 1; }
  $SUDO install -m755 "$f" "$BIN_DIR/${BIN[$t]}"; rm -rf "$tmp"; ok "installed ${BIN[$t]}"
}

# raw binary (no archive)
inst_raw() {
  local t="$1"
  local url; url="$(get_dl_url "$t" raw)" || return 1
  local tmp; tmp="$(mktemp -d)"
  run "curl -fsSL '$url' -o '$tmp/${BIN[$t]}'"
  [ "$DRY" = 1 ] && { rm -rf "$tmp"; ok "(dry) ${BIN[$t]}"; return 0; }
  $SUDO install -m755 "$tmp/${BIN[$t]}" "$BIN_DIR/${BIN[$t]}"; rm -rf "$tmp"; ok "installed ${BIN[$t]}"
}

# cargo install (for tools without prebuilt binaries)
inst_cargo_crate() {
  local t="$1" crate="${CARGO_CRATE[$1]:-$1}"
  have cargo || { err "$t needs cargo — add 'cargo' to your selection first"; return 1; }
  run "cargo install --locked '$crate'"
  [ "$DRY" = 1 ] && { ok "(dry) cargo install $crate"; return 0; }
  ok "installed $t via cargo install $crate"
}

# yazi: extract both yazi and ya from one zip in a single download
inst_yazi_zip() {
  local t="$1"
  local url; url="$(get_dl_url "$t" zip)" || return 1
  local a="${url##*/}"
  local tmp; tmp="$(mktemp -d)"
  run "curl -fsSL '$url' -o '$tmp/a.zip'"
  [ "$DRY" = 1 ] && { rm -rf "$tmp"; ok "(dry) yazi+ya from $a"; return 0; }
  unzip -qo "$tmp/a.zip" -d "$tmp" || { err "unzip failed: $a"; rm -rf "$tmp"; return 1; }
  for b in yazi ya; do
    local f; f="$(find "$tmp" -type f -name "$b" | head -1)"
    [ -n "$f" ] && $SUDO install -m755 "$f" "$BIN_DIR/$b" && ok "installed $b"
  done
  rm -rf "$tmp"
}

# plocate: postinstall calls `updatedb` synchronously (full filesystem scan = minutes).
# Fix: stub at /usr/local/bin/updatedb (higher PATH priority) intercepts the call
# and re-launches the real /usr/bin/updatedb in the background, then returns.
# apt finishes immediately; the scan runs asynchronously.
inst_plocate() {
  if [ "$PKG_MGR" = brew ]; then
    warn "plocate is Linux-specific (systemd/updatedb) and not available via Homebrew on macOS."
    warn "macOS has native mdfind / locate. Skipping plocate."
    return 0
  fi
  [ "$DRY" = 1 ] && { say "plocate — ${PKG_MGR} install plocate (updatedb async)"; return 0; }
  local stub="$BIN_DIR/updatedb"
  # Stub intercepts postinstall updatedb; relaunches async; apt/dnf returns immediately.
  printf '#!/bin/sh\nnohup /usr/bin/updatedb --quiet >/dev/null 2>&1 &\ndisown\nexit 0\n' \
    | $SUDO tee "$stub" >/dev/null
  $SUDO chmod +x "$stub"

  case "$PKG_MGR" in
    apt) $SUDO apt-get install -y --no-install-recommends plocate ;;
    dnf) $SUDO dnf install -y plocate ;;
  esac
  local rc=$?

  $SUDO rm -f "$stub"
  [ "$rc" -eq 0 ] && ok "plocate installed — updatedb running in background" || return "$rc"
}

# neovim: tarball with subdirectory structure, also copies share/nvim runtime
inst_nvim() {
  local narch; case "$ARCH" in amd64) narch="x86_64";; arm64) narch="arm64";; esac
  local a="nvim-linux-${narch}.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  run "curl -fsSL '$DL/neovim/neovim/releases/latest/download/$a' -o '$tmp/nvim.tar.gz'"
  [ "$DRY" = 1 ] && { rm -rf "$tmp"; ok "(dry) nvim from $a"; return 0; }
  tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
  local f; f="$(find "$tmp" -type f -name nvim -perm -u+x | head -1)"
  [ -z "$f" ] && { err "nvim binary not found in $a"; rm -rf "$tmp"; return 1; }
  $SUDO install -m755 "$f" "$BIN_DIR/nvim"
  local share; share="$(find "$tmp" -type d -name nvim -path '*/share/nvim' | head -1)"
  [ -n "$share" ] && $SUDO mkdir -p /usr/local/share && $SUDO cp -r "$share" /usr/local/share/
  rm -rf "$tmp"; ok "installed nvim"
}

# cargo / rustup toolchain
inst_cargo() {
  if have cargo; then
    ok "cargo already present ($(cargo --version 2>/dev/null))"; 
  else
    say "Installing rustup + cargo (profile=minimal, no PATH modification)"
    run "curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal"
    [ "$DRY" = 1 ] && return 0
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    have cargo && run "cargo install --locked cargo-update 2>/dev/null || true"
    ok "installed rustup + cargo + cargo-update"
  fi
  # Install cargo-binstall — downloads prebuilt Rust binaries instead of compiling.
  # Uses cargo-binstall's own prebuilt bootstrap, which is a stable URL.
  if have cargo-binstall; then
    ok "cargo-binstall already present"
  else
    [ "$DRY" = 1 ] && { ok "(dry) would install cargo-binstall"; return 0; }
    say "Installing cargo-binstall (fast binary installer for Rust tools)"
    local arch; case "$ARCH" in amd64) arch="x86_64";; arm64) arch="aarch64";; *) arch="$RARCH";; esac
    local url="https://github.com/cargo-bins/cargo-binstall/releases/latest/download"
    local asset="cargo-binstall-${arch}-unknown-linux-musl.tgz"
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL "$url/$asset" -o "$tmp/cb.tgz" && \
      tar -xzf "$tmp/cb.tgz" -C "$tmp" && \
      $SUDO install -m755 "$tmp/cargo-binstall" "$BIN_DIR/cargo-binstall"
    rm -rf "$tmp"
    have cargo-binstall && ok "installed cargo-binstall" || warn "cargo-binstall install failed — will fall back to cargo install"
  fi
}

# cargo-binstall: downloads prebuilt binaries for Rust crates (seconds, not minutes)
# Falls back to `cargo install` (compile) if no prebuilt binary exists.
# REPO field holds the crate name (may differ from tool name: dust → du-dust)
inst_cargo_bin() {
  local t="$1" crate="${REPO[$t]}"
  [ "$DRY" = 1 ] && { ok "(dry) cargo binstall $crate  (or cargo install if binstall unavailable)"; return 0; }
  if have cargo-binstall; then
    run "cargo binstall --no-confirm '$crate'"
    ok "installed $t via cargo binstall $crate"
  elif have cargo; then
    warn "cargo-binstall not found, falling back to cargo install $crate (will compile)"
    run "cargo install --locked '$crate'"
    ok "installed $t via cargo install $crate"
  else
    err "$t needs cargo — add 'cargo' to your selection first"; return 1
  fi
}

# eza: official gierens apt repo (Ubuntu) or native dnf (Fedora 40+)
inst_eza() {
  case "$PKG_MGR" in
    dnf) pkg_install eza ;;   # native in Fedora 40+
    apt)
      run "$SUDO mkdir -p '$KEYRINGS'"
      run "wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
           | $SUDO gpg --dearmor -o '$KEYRINGS/gierens.gpg'"
      echo "deb [signed-by=$KEYRINGS/gierens.gpg] http://deb.gierens.de stable main" \
        | $SUDO tee "$SOURCES/gierens.list" >/dev/null
      run "$SUDO chmod 644 '$KEYRINGS/gierens.gpg' '$SOURCES/gierens.list'"
      run "$SUDO apt-get update -y"
      pkg_install eza ;;
  esac
}

# azlux repo: packages.azlux.fr (Debian/Ubuntu only; Fedora has gping natively)
_AZLUX_READY=0
inst_setup_azlux() {
  [ "$_AZLUX_READY" = 1 ] && return 0
  [ "$DRY" = 1 ] && { ok "(dry) would set up azlux repo"; _AZLUX_READY=1; return 0; }
  say "Adding packages.azlux.fr repository"
  $SUDO wget -qO "$KEYRINGS/azlux-archive-keyring.gpg" "https://azlux.fr/repo.gpg" \
    || { err "failed to download azlux GPG key"; return 1; }
  printf 'deb [signed-by=%s/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ stable main\n' \
    "$KEYRINGS" | $SUDO tee "$SOURCES/azlux.list" >/dev/null
  run "$SUDO apt-get update -qq"
  _AZLUX_READY=1; ok "azlux repo ready"
}

inst_apt_azlux() {
  local t="$1" pkg="${APT_PKG[$t]:-${REPO[$t]:-$t}}"
  case "$PKG_MGR" in
    dnf) pkg_install "${DNF_PKG[$t]:-$t}" ;;  # Fedora has gping natively
    apt) inst_setup_azlux || return 1; pkg_install "$pkg" ;;
  esac
}

# COPR: Fedora equivalent of Ubuntu PPA
inst_dnf_copr() {
  local t="$1"
  local copr="${COPR_REPO[$t]:-}"
  local pkg="${DNF_PKG[$t]:-${APT_PKG[$t]:-$t}}"
  if [ "$DRY" = 1 ]; then
    [ -n "$copr" ] && ok "(dry) dnf copr enable $copr && dnf install $pkg" \
                   || ok "(dry) dnf install $pkg"
    return 0
  fi
  if [ -n "$copr" ]; then
    say "Enabling COPR: $copr"
    run "$SUDO dnf copr enable -y '$copr'"
  fi
  pkg_install "$pkg"
}

# PPA (Ubuntu) or COPR (Fedora)
inst_apt_ppa() {
  local t="$1"
  case "$PKG_MGR" in
    dnf) inst_dnf_copr "$t" ;;
    apt)
      local ppa="${PPA_NAME[$t]:-}"
      local pkg="${APT_PKG[$t]:-$t}"
      [ -z "$ppa" ] && { err "no PPA configured for $t"; return 1; }
      [ "$DRY" = 1 ] && { ok "(dry) add-apt-repository ppa:$ppa && apt install $pkg"; return 0; }
      say "Adding ppa:$ppa"
      run "$SUDO add-apt-repository -y 'ppa:$ppa'"
      run "$SUDO apt-get update -qq"
      pkg_install "$pkg" ;;
  esac
}
# universal install dispatcher
install_tool() {
  local t="$1"
  if [ "$PKG_MGR" = brew ] && [ "$t" != cargo ]; then
    if [ "$t" = plocate ]; then
      inst_plocate
      return $?
    fi
    pkg_install "$(_pkg_name "$t")"
    return $?
  fi

  case "${METHOD[$t]}" in
    apt)       pkg_install "$(_pkg_name "$t")" ;;
    apt-repo)  inst_eza ;;
    apt-azlux) inst_apt_azlux "$t" ;;
    apt-ppa)   inst_apt_ppa "$t" ;;
    github-tgz)  inst_tgz "$t" ;;
    github-txz)  inst_txz "$t" ;;
    github-zip)
      if [ "$t" = yazi ]; then inst_yazi_zip "$t"; else inst_zip "$t"; fi ;;
    github-raw)  inst_raw "$t" ;;
    cargo-crate) inst_cargo_crate "$t" ;;
    cargo-bin)
      # Some cargo-bin tools exist as native Fedora packages — prefer dnf (faster)
      if [ "$PKG_MGR" = dnf ] && [ -n "${DNF_PKG[$t]:-}" ]; then
        pkg_install "${DNF_PKG[$t]}"
      else
        inst_cargo_bin "$t"
      fi ;;
    custom)
      case "$t" in
        cargo)   inst_cargo ;;
        nvim)    inst_nvim  ;;
        plocate) inst_plocate ;;
        *)       err "no custom installer for $t" ;;
      esac ;;
    *) err "unknown method '${METHOD[$t]}' for $t" ;;
  esac
}

# ─── UPDATE ───────────────────────────────────────────────────────────────────
_pkg_upgrade() {
  local pkg="$1"
  case "$PKG_MGR" in
    apt)  run "$SUDO apt-get install -y --only-upgrade '$pkg'" ;;
    dnf)  run "$SUDO dnf upgrade -y '$pkg'" ;;
    brew) run "brew upgrade '$pkg'" ;;
  esac
}

update_tool() {
  local t="$1"
  if [ "$PKG_MGR" = brew ] && [ "$t" != cargo ]; then
    if [ "$t" = plocate ]; then return 0; fi
    _pkg_upgrade "$(_pkg_name "$t")"
    return $?
  fi

  case "${METHOD[$t]}" in
    apt)       _pkg_upgrade "$(_pkg_name "$t")" ;;
    apt-repo)  _pkg_upgrade eza ;;
    apt-azlux) inst_setup_azlux; _pkg_upgrade "${REPO[$t]:-$t}" ;;
    apt-ppa)   _pkg_upgrade "${APT_PKG[$t]:-$t}" ;;
    cargo-crate) have cargo && run "cargo install --locked '${CARGO_CRATE[$t]:-$t}'" || inst_cargo_crate "$t" ;;
    cargo-bin)
      if [ "$PKG_MGR" = dnf ] && [ -n "${DNF_PKG[$t]:-}" ]; then
        _pkg_upgrade "${DNF_PKG[$t]}"
      else
        have cargo-binstall \
          && run "cargo binstall --no-confirm '${REPO[$t]}'" \
          || { have cargo && run "cargo install --locked '${REPO[$t]}'"; }
      fi ;;
    custom)
      case "$t" in
        cargo)   have rustup && run "rustup update" || inst_cargo
                 have cargo  && run "cargo install --locked cargo-update 2>/dev/null; cargo install-update -a 2>/dev/null || true" ;;
        nvim)    inst_nvim ;;
        plocate) _pkg_upgrade plocate ;;
      esac ;;
    *)  install_tool "$t" ;;
  esac
}

# ─── TRACK INSTALLED ─────────────────────────────────────────────────────────
record_installed() {
  local t="$1"
  [ "$DRY" = 1 ] && return
  mkdir -p "$CFG_DIR"
  # ensure no duplicate
  grep -v "^${t}:" "$INST_DB" > "$INST_DB.tmp" 2>/dev/null || true
  echo "${t}:${METHOD[$t]}:$(date +%s)" >> "$INST_DB.tmp"
  mv "$INST_DB.tmp" "$INST_DB"
}

load_installed() {
  [ -f "$INST_DB" ] && cut -d: -f1 "$INST_DB" | tr '\n' ' '
}

# ─── PHASE 1: VERIFY INSTALLS ────────────────────────────────────────────────
# Called after the install loop; populates INST_OK[] and INST_FAIL[].
declare -A INST_BINNAME   # tool → actual binary found (batcat, fdfind, etc.)
INST_OK=()
INST_FAIL=()

verify_installs() {
  if [ "$DRY" = 1 ]; then
    ok "(dry) would verify installs — skipped in dry-run"
    return 0
  fi
  local t
  INST_OK=(); INST_FAIL=()
  say "Verifying installed binaries…"
  for t in "${SELECTED[@]}"; do
    [ -z "$t" ] && continue
    [ -z "${DESC[$t]:-}" ] && continue
    local found; found="$(resolve_bin "$t" 2>/dev/null)" || true
    if [ -n "$found" ]; then
      INST_BINNAME[$t]="$found"
      INST_OK+=("$t")
    else
      INST_FAIL+=("$t")
    fi
  done

  printf '\n%s Installation summary %s\n' "${B}───" "───────────────────────────────${OFF}"
  local t
  for t in "${SELECTED[@]}"; do
    [ -z "$t" ] && continue
    [ -z "${DESC[$t]:-}" ] && continue
    if printf '%s\n' "${INST_OK[@]:-}" | grep -qx "$t"; then
      printf '  %s✓%s %-14s %s\n' "$G" "$OFF" "$t" "${INST_BINNAME[$t]}"
    else
      printf '  %s✗%s %-14s %s\n' "$R" "$OFF" "$t" "NOT FOUND — check errors above"
    fi
  done
  printf '%s\n' "${B}──────────────────────────────────────────────────${OFF}"
  local nok="${#INST_OK[@]}" nfail="${#INST_FAIL[@]}"
  printf '  %s%d installed%s   ' "$G" "$nok" "$OFF"
  [ "$nfail" -gt 0 ] \
    && printf '%s%d FAILED%s\n\n' "$R" "$nfail" "$OFF" \
    || printf '%s0 failed%s\n\n' "$D" "$OFF"
}

# ─── PHASE 1: CACHE SHELL INITS ──────────────────────────────────────────────
# Run the expensive `tool init shell` subprocesses ONCE at install time.
# The integration file then just `source`s the cached output — zero subprocess
# overhead at every shell startup.
cache_shell_inits() {
  [ "$DRY" = 1 ] && { ok "(dry) would cache shell inits"; return 0; }
  local init_dir="$CFG_DIR/init"
  mkdir -p "$init_dir"
  local t

  for t in "${INST_OK[@]}"; do
    case "$t" in
      fzf)
        # Modern fzf has --bash/--zsh; older apt version uses sourced files
        if fzf --bash >/dev/null 2>&1; then
          fzf --bash  > "$init_dir/fzf.bash"  2>/dev/null
          fzf --zsh   > "$init_dir/fzf.zsh"   2>/dev/null
        else
          # Fallback: concatenate the apt-installed keybinding files
          {
            for f in /usr/share/doc/fzf/examples/key-bindings.bash \
                     /usr/share/fzf/key-bindings.bash; do [ -f "$f" ] && cat "$f"; done
            for f in /usr/share/doc/fzf/examples/completion.bash \
                     /usr/share/fzf/completion.bash; do [ -f "$f" ] && cat "$f"; done
          } > "$init_dir/fzf.bash"
          {
            for f in /usr/share/doc/fzf/examples/key-bindings.zsh \
                     /usr/share/fzf/key-bindings.zsh; do [ -f "$f" ] && cat "$f"; done
            for f in /usr/share/doc/fzf/examples/completion.zsh \
                     /usr/share/fzf/completion.zsh; do [ -f "$f" ] && cat "$f"; done
          } > "$init_dir/fzf.zsh"
        fi
        ok "cached fzf init"
        ;;
      zoxide)
        zoxide init bash > "$init_dir/zoxide.bash" 2>/dev/null
        zoxide init zsh  > "$init_dir/zoxide.zsh"  2>/dev/null
        ok "cached zoxide init"
        ;;
      atuin)
        atuin init bash > "$init_dir/atuin.bash" 2>/dev/null
        atuin init zsh  > "$init_dir/atuin.zsh"  2>/dev/null
        ok "cached atuin init"
        ;;
      starship)
        starship init bash > "$init_dir/starship.bash" 2>/dev/null
        starship init zsh  > "$init_dir/starship.zsh"  2>/dev/null
        ok "cached starship init"
        ;;
      navi)
        navi widget bash > "$init_dir/navi.bash" 2>/dev/null
        navi widget zsh  > "$init_dir/navi.zsh"  2>/dev/null
        ok "cached navi init"
        ;;
    esac
  done
}

# ─── PHASE 2: WRITE STATIC INTEGRATION ───────────────────────────────────────
# Generates a shell file with NO runtime `command -v` checks.
# Everything here is conditional on what was confirmed installed.
# At shell startup: zero subprocess spawning, zero binary probing — just source.
write_static_integration() {
  local shell="$1" file="$2"
  local init_dir="$CFG_DIR/init"
  [ "$DRY" = 1 ] && { ok "(dry) would write static $file"; return 0; }
  mkdir -p "$(dirname "$file")" "$init_dir"

  # helper: is tool in the verified-installed list?
  inst() { printf '%s\n' "${INST_OK[@]:-}" | grep -qx "$1"; }

  {
    echo "# ─── modern-cli integration ($shell) ────────────────────────────────────────"
    echo "# STATIC FILE — generated by install-modern-cli.sh on $(date '+%Y-%m-%d %H:%M')"
    echo "# To regenerate:  $(realpath "$0" 2>/dev/null || echo install-modern-cli.sh) --update"
    echo "# Do not edit manually — changes will be overwritten on next update."
    echo

    # ── cargo PATH ───────────────────────────────────────────────────────────
    inst cargo && cat <<'EOF'
# cargo / rustup
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
EOF
    echo

    # ── ls aliases (eza preferred, lsd fallback, no checks needed) ───────────
    if inst eza; then
      cat <<'EOF'
# ls → eza
alias ls='eza --group-directories-first --icons=auto'
alias l='eza -1 --group-directories-first --icons=auto'
alias ll='eza -lh --git --group-directories-first --icons=auto'
alias la='eza -lah --git --group-directories-first --icons=auto'
alias lt='eza --tree --level=2 --icons=auto'
alias lt3='eza --tree --level=3 --icons=auto'
EOF
    elif inst lsd; then
      cat <<'EOF'
# ls → lsd
alias ls='lsd --group-dirs first'
alias l='lsd -1 --group-dirs first'
alias ll='lsd -l --group-dirs first'
alias la='lsd -la --group-dirs first'
alias lt='lsd --tree --depth=2'
EOF
    fi
    echo

    # ── bat (Ubuntu installs as 'batcat') ─────────────────────────────────────
    if inst bat; then
      local batbin="${INST_BINNAME[bat]:-bat}"
      printf '# bat\n'
      [ "$batbin" = "batcat" ] && printf 'alias bat=batcat\n'
      printf "export MANPAGER=\"sh -c 'col -bx | %s -l man -p'\"\n" "$batbin"
      printf 'export MANROFFOPT="-c"\n'
    fi
    echo

    # ── fd (Ubuntu installs as 'fdfind') ──────────────────────────────────────
    if inst fd; then
      local fdbin="${INST_BINNAME[fd]:-fd}"
      printf '# fd\n'
      [ "$fdbin" = "fdfind" ] && printf 'alias fd=fdfind\n'
    fi
    echo

    # ── convenience aliases ────────────────────────────────────────────────────
    printf '# convenience aliases\n'
    inst dust     && printf "alias du='dust'\n"
    inst duf      && printf "alias df='duf'\n"
    inst procs    && printf "alias ps='procs'\n"
    inst bottom   && printf "alias top='btm'\n"
    inst dog      && printf "alias dig='dog'\n"
    inst plocate  && printf "# plocate replaces locate — index updated daily by cron\n"
    echo

    # ── fzf (sourced from pre-cached init, + fd integration) ─────────────────
    if inst fzf && [ -f "$init_dir/fzf.$shell" ]; then
      printf '# fzf — Ctrl-R history, Ctrl-T files, Alt-C cd\n'
      printf 'source "%s/init/fzf.%s"\n' "$CFG_DIR" "$shell"
      # fd-backed listings (static paths, no command-v needed)
      local fdbin="${INST_BINNAME[fd]:-}"
      if [ -n "$fdbin" ]; then
        printf 'export FZF_DEFAULT_COMMAND="%s --type f --hidden --exclude .git"\n' "$fdbin"
        printf 'export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"\n'
        printf 'export FZF_ALT_C_COMMAND="%s --type d --hidden --exclude .git"\n' "$fdbin"
      fi
      printf 'export FZF_DEFAULT_OPTS="--height 40%% --layout=reverse --border"\n'
    fi
    echo

    # ── zoxide ────────────────────────────────────────────────────────────────
    if inst zoxide && [ -f "$init_dir/zoxide.$shell" ]; then
      printf '# zoxide — z / zi\n'
      printf 'source "%s/init/zoxide.%s"\n' "$CFG_DIR" "$shell"
    fi
    echo

    # ── navi ──────────────────────────────────────────────────────────────────
    if inst navi && [ -f "$init_dir/navi.$shell" ]; then
      printf '# navi — Ctrl-G cheatsheet\n'
      printf 'source "%s/init/navi.%s"\n' "$CFG_DIR" "$shell"
    fi
    echo

    # ── atuin (after fzf so it wins Ctrl-R) ───────────────────────────────────
    if inst atuin && [ -f "$init_dir/atuin.$shell" ]; then
      printf '# atuin — Ctrl-R (overrides fzf Ctrl-R)\n'
      printf 'source "%s/init/atuin.%s"\n' "$CFG_DIR" "$shell"
    fi
    echo

    # ── starship (must be last — sets PS1/PROMPT) ─────────────────────────────
    if inst starship && [ -f "$init_dir/starship.$shell" ]; then
      printf '# starship prompt\n'
      printf 'source "%s/init/starship.%s"\n' "$CFG_DIR" "$shell"
    fi
    echo

    # ── helix runtime ─────────────────────────────────────────────────────────
    inst helix && [ -d /usr/local/share/helix/runtime ] && \
      printf '# helix\nexport HELIX_RUNTIME=/usr/local/share/helix/runtime\n\n'

    # ── yazi y wrapper ────────────────────────────────────────────────────────
    inst yazi && cat <<'EOF'
# yazi — y cds to last visited dir on quit
y() {
  local tmp cwd; tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  command yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
EOF
    echo

    # ── broot br wrapper ──────────────────────────────────────────────────────
    inst broot && cat <<'EOF'
# broot — br cds to selected dir on quit
br() { local f; f="$(mktemp)"; broot --outcmd "$f" "$@" && source "$f"; rm -f "$f"; }
EOF
    echo

    # ── delta: one-time git config ────────────────────────────────────────────
    if inst delta; then
      cat <<'EOF'
# delta — configure git pager (idempotent)
if [ -z "${_MCLI_DELTA_CONFIGURED:-}" ]; then
  git config --global core.pager delta 2>/dev/null
  git config --global interactive.diffFilter 'delta --color-only' 2>/dev/null
  git config --global delta.navigate true 2>/dev/null
  git config --global delta.side-by-side true 2>/dev/null
  git config --global merge.conflictstyle diff3 2>/dev/null
  export _MCLI_DELTA_CONFIGURED=1
fi
EOF
    fi
    echo

    # ── cli-update alias ──────────────────────────────────────────────────────
    local self_path; self_path="$(realpath "$0" 2>/dev/null || echo "$HOME/.local/bin/install-modern-cli.sh")"
    printf '# update all tools: cli-update\n'
    printf "alias cli-update='%s --update'\n" "$self_path"
    echo

    # ── modern overview function ───────────────────────────────────────────────
    generate_modern_fn

    echo "# ─── end modern-cli integration ───"
  } > "$file"
  ok "wrote static integration → $file"
}

# ─── GENERATE `modern` FUNCTION ───────────────────────────────────────────────
# Embeds the full tool catalog into the shell function.
# `command -v` is only called here — at explicit invocation, never at startup.
generate_modern_fn() {
  local t

  # Build catalog as bash literal arrays embedded in the function
  local cat_list=""
  local seen_cats=()
  for t in "${TOOLS[@]}"; do
    local c="${CAT[$t]}"
    printf '%s\n' "${seen_cats[@]:-}" | grep -qx "$c" || { seen_cats+=("$c"); cat_list+="$c "; }
  done

  printf '# modern — colorful overview of all CLI tools\n'
  printf '# Usage: modern [CATEGORY]   e.g. modern git\n'
  printf 'modern() {\n'

  # Embed color codes
  printf '  local B=$'"'"'\\033[1m'"'"' G=$'"'"'\\033[32m'"'"' Y=$'"'"'\\033[33m'"'"'\n'
  printf '  local C=$'"'"'\\033[36m'"'"' D=$'"'"'\\033[2m'"'"' M=$'"'"'\\033[35m'"'"' OFF=$'"'"'\\033[0m'"'"'\n'
  printf '  local filter="${1:-}"\n'
  printf '  local inst=0 total=0\n'
  printf '  # count totals first\n'

  # Embed all tool+category+desc+bin into the function body
  printf '  declare -A _desc _cat _bin\n'
  for t in "${TOOLS[@]}"; do
    # Escape single quotes in desc
    local d="${DESC[$t]//\'/\'\\\'\'}"
    local chk="${BIN_CHECK[$t]:-${BIN[$t]:-$t}}"
    # take first candidate from colon-separated list
    local b="${chk%%:*}"
    printf "  _desc[%s]='%s'\n" "$t" "$d"
    printf "  _cat[%s]='%s'\n"  "$t" "${CAT[$t]}"
    printf "  _bin[%s]='%s'\n"  "$t" "$b"
  done

  # Embed ordered tool list and category list
  printf '  local _tools=(%s)\n' "${TOOLS[*]}"
  printf '  local _cats=(%s)\n'  "${seen_cats[*]}"

  cat <<'MFUNC'
  # count
  local t
  for t in "${_tools[@]}"; do
    (( total++ )) || true
    command -v "${_bin[$t]}" >/dev/null 2>&1 && (( inst++ )) || true
  done

  printf '\n%s  MODERN CLI TOOLKIT%s  ·  %d installed  /  %d total\n' \
    "$B" "$OFF" "$inst" "$total"
  printf '%s%s%s\n\n' "$D" "$(printf '─%.0s' {1..56})" "$OFF"

  local prev_cat="" cat_shown
  for t in "${_tools[@]}"; do
    local c="${_cat[$t]}"
    [ -n "$filter" ] && [[ "$c" != *"$filter"* ]] && continue
    if [ "$c" != "$prev_cat" ]; then
      [ -n "$prev_cat" ] && echo
      printf ' %s■ %s%s\n' "$C$B" "${c//-/ }" "$OFF"
      prev_cat="$c"
    fi
    if command -v "${_bin[$t]}" >/dev/null 2>&1; then
      printf '   %s✓%s %-14s%s%s%s\n' "$G" "$OFF" "$t" "$D" "${_desc[$t]}" "$OFF"
    else
      printf '   %s·%s %-14s%s%s%s\n' "$D" "$OFF" "$t" "$D" "${_desc[$t]}" "$OFF"
    fi
  done
  echo
  printf '%s  ✓ installed   · available to install   cli-update to upgrade%s\n\n' "$D" "$OFF"
}
MFUNC
}

hook_rc() {
  local rc="$1" file="$2"
  [ "$DRY" = 1 ] && { ok "(dry) would hook $rc"; return 0; }
  [ -f "$rc" ] || touch "$rc"
  grep -qF "# modern-cli" "$rc" 2>/dev/null && return 0
  printf '\n[ -f "%s" ] && source "%s"  # modern-cli\n' "$file" "$file" >> "$rc"
  ok "hooked $rc"
}

# ─── INTERACTIVE SELECTION — single screen, all categories ───────────────────
run_interactive() {
  have whiptail || {
    local install_hint="apt install whiptail"
    [ "$PKG_MGR" = dnf ] && install_hint="dnf install newt"
    [ "$PKG_MGR" = brew ] && install_hint="brew install newt"
    warn "whiptail missing — $install_hint"
    return
  }

  # Auto-size to terminal (fall back to safe defaults if tput unavailable)
  local tw th
  tw=$(tput cols  2>/dev/null || echo 100)
  th=$(tput lines 2>/dev/null || echo 40)
  local dlg_w=$(( tw - 4 < 130 ? tw - 4 : 130 ))  # cap at 130
  local dlg_h=$(( th - 2 ))                          # nearly full height
  local list_h=$(( dlg_h - 9 ))                      # leave room for chrome
  [ "$list_h" -lt 10 ] && list_h=10

  # ── Build item list: [Category] separator rows + tool rows ──────────────────
  # Separator tags use pattern [catname] — filtered out in post-processing.
  # Description of separators is a bold category header that fills the width.
  local args=() t prev_cat=""
  local sep_dashes; sep_dashes="$(printf '─%.0s' $(seq 1 $(( dlg_w - 20 )) ))"

  for t in "${TOOLS[@]}"; do
    local c="${CAT[$t]}"
    if [ "$c" != "$prev_cat" ]; then
      local label="${c//-/ }"; label="${label^}"
      # Separator: tag=[category], description is the visual header line
      args+=("[${c}]" "  ─── ${label} ${sep_dashes}" "OFF")
      prev_cat="$c"
    fi
    local on="OFF"
    local already=0
    if resolve_bin "$t" >/dev/null 2>&1; then
      already=1
    fi
    # If already installed, don't pre-check it unless --force is set
    if [ "$already" = 1 ] && [ "$FORCE" != 1 ]; then
      on="OFF"
    else
      printf '%s\n' "${DEFAULTS[@]}" | grep -qx "$t" && on="ON"
    fi
    # Indent tool rows slightly so they visually sit under their category
    local desc_text="${DESC[$t]:-}"
    [ "$already" = 1 ] && desc_text="[installed] $desc_text"
    args+=("$t" "  $desc_text" "$on")
  done

  # ── Show single checklist ────────────────────────────────────────────────────
  local chosen
  chosen="$(whiptail \
    --title " Modern CLI Toolkit — 45 tools across 14 categories " \
    --checklist \
    "space=toggle  ↑↓=scroll  tab=Ok/Cancel  enter=confirm
─── lines are category headers (selecting them has no effect) ───" \
    "$dlg_h" "$dlg_w" "$list_h" \
    "${args[@]}" 3>&1 1>&2 2>&3)" || { warn "Cancelled — nothing installed."; exit 0; }

  # ── Filter out separator tags, build SELECTED ────────────────────────────────
  SELECTED=()
  local x
  for x in $chosen; do
    x="${x//\"/}"
    [[ "$x" == \[*\] ]] && continue   # skip [category] separators
    printf '%s\n' "${SELECTED[@]:-}" | grep -qx "$x" || SELECTED+=("$x")
  done

  [ "${#SELECTED[@]}" = 0 ] && { warn "Nothing selected — exiting."; exit 0; }
}

# ─── LIST & STATUS ────────────────────────────────────────────────────────────
check_installed() {
  printf '\n%s  Modern CLI Toolkit — System Status  %s\n' "$B" "$OFF"
  printf '%s%s%s\n\n' "$D" "$(printf '─%.0s' {1..70})" "$OFF"
  local inst_count=0 total_count=0 prev_cat="" t

  for t in "${TOOLS[@]}"; do
    local c="${CAT[$t]}"
    (( total_count++ )) || true
    if [ "$c" != "$prev_cat" ]; then
      local label="${c//-/ }"; label="${label^}"
      printf '\n %s■ %s%s\n' "$B" "$label" "$OFF"
      prev_cat="$c"
    fi
    local found; found="$(resolve_bin "$t" 2>/dev/null)" || true
    if [ -n "$found" ]; then
      (( inst_count++ )) || true
      local bin_path; bin_path="$(command -v "$found" 2>/dev/null || echo "$found")"
      printf '   %s✓%s %-14s %s%-20s%s %s(%s)%s\n' \
        "$G" "$OFF" "$t" "$B" "$found" "$OFF" "$D" "$bin_path" "$OFF"
    else
      printf '   %s·%s %-14s %s%-20s%s %s%s%s\n' \
        "$D" "$OFF" "$t" "$D" "not installed" "$OFF" "$D" "${DESC[$t]:-}" "$OFF"
    fi
  done

  printf '\n%s%s%s\n' "$D" "$(printf '─%.0s' {1..70})" "$OFF"
  printf '  Summary: %s%d installed%s / %d total tools available\n\n' \
    "$G" "$inst_count" "$OFF" "$total_count"
}

print_table() {
  # Distro-aware routing table for every tool
  # Usage: ./install-modern-cli.sh --table
  local _ubuntu _fedora _macos t last_cat="" pkg copr dnfpkg

  _ubuntu() {
    local t="$1" m="${METHOD[$t]:-?}"
    local pkg="${APT_PKG[$t]:-${REPO[$t]:-$t}}"
    case "$m" in
      apt)         printf 'apt  %s' "$pkg" ;;
      apt-repo)    printf 'apt  gierens.de → eza' ;;
      apt-azlux)   printf 'apt  azlux.fr → %s' "${REPO[$t]:-$t}" ;;
      apt-ppa)     printf 'ppa  %s → %s' "${PPA_NAME[$t]:-?}" "${APT_PKG[$t]:-$t}" ;;
      github-*)    printf 'gh   %s' "${BIN[$t]:-$t}" ;;
      cargo-bin)   printf 'binstall  %s' "${REPO[$t]:-$t}" ;;
      cargo-crate) printf 'cargo  %s' "${CARGO_CRATE[$t]:-$t}" ;;
      custom)
        case "$t" in
          cargo)   printf 'rustup + cargo-binstall' ;;
          nvim)    printf 'gh   nvim (latest)' ;;
          plocate) printf 'apt  plocate  (async updatedb)' ;;
        esac ;;
      *) printf '?' ;;
    esac
  }

  _fedora() {
    local t="$1" m="${METHOD[$t]:-?}"
    local copr="${COPR_REPO[$t]:-}"
    local dnfpkg="${DNF_PKG[$t]:-${APT_PKG[$t]:-${REPO[$t]:-$t}}}"
    case "$m" in
      apt)         printf 'dnf  %s' "$dnfpkg" ;;
      apt-repo)    printf 'dnf  eza  (native Fedora 40+)' ;;
      apt-azlux)   printf 'dnf  %s  (native)' "${DNF_PKG[$t]:-$t}" ;;
      apt-ppa)
        if [ -n "$copr" ]; then printf 'copr %s → %s' "$copr" "$dnfpkg"
        else printf 'dnf  %s  (native)' "$dnfpkg"; fi ;;
      github-*)    printf 'gh   %s' "${BIN[$t]:-$t}" ;;
      cargo-bin)
        if [ -n "${DNF_PKG[$t]:-}" ]; then printf 'dnf  %s  (native)' "${DNF_PKG[$t]}"
        else printf 'binstall  %s' "${REPO[$t]:-$t}"; fi ;;
      cargo-crate) printf 'cargo  %s' "${CARGO_CRATE[$t]:-$t}" ;;
      custom)
        case "$t" in
          cargo)   printf 'rustup + cargo-binstall' ;;
          nvim)    printf 'gh   nvim (latest)' ;;
          plocate) printf 'dnf  plocate  (async updatedb)' ;;
        esac ;;
      *) printf '?' ;;
    esac
  }

  _macos() {
    local t="$1"
    if [ "$t" = cargo ]; then
      printf 'rustup + cargo-binstall'
    elif [ "$t" = plocate ]; then
      printf '-'
    else
      printf 'brew %s' "$(_pkg_name "$t")"
    fi
  }

  printf '\n%s Install method per tool — Ubuntu vs Fedora vs macOS %s\n' "$B" "$OFF"
  printf '%-13s %-12s  %-30s  %-30s  %s\n' "TOOL" "CATEGORY" "UBUNTU (apt)" "FEDORA (dnf)" "MACOS (brew)"
  printf '%0.s-' {1..115}; echo
  for t in "${TOOLS[@]}"; do
    local cat="${CAT[$t]}"
    [ "$cat" != "$last_cat" ] && { [ -n "$last_cat" ] && echo; last_cat="$cat"; }
    printf '%-13s %-12s  %-30s  %-30s  %s\n' \
      "$t" "$cat" "$(_ubuntu "$t")" "$(_fedora "$t")" "$(_macos "$t")"
  done
  echo
  printf '%s  apt/ppa = Ubuntu only   copr = Fedora COPR   gh = GitHub release   brew = Homebrew%s\n\n' "$D" "$OFF"
}

print_list() {
  printf '%s\n\n' "${B}Modern CLI toolkit — 44 tools${OFF}"
  local prev_cat="" t
  for t in "${TOOLS[@]}"; do
    local c="${CAT[$t]}"
    if [ "$c" != "$prev_cat" ]; then
      printf '\n%s── %s %s\n' "$B" "${c//-/ }" "$OFF"
      prev_cat="$c"
    fi
    printf '  %s%-12s%s %s\n' "$B" "$t" "$OFF" "${DESC[$t]:-}"
    if [ -n "${USAGE[$t]:-}" ]; then
      printf '%s' "${USAGE[$t]}" | sed 's/^/      /'
      printf '\n'
    fi
  done
}

# ─── BOOTSTRAP ────────────────────────────────────────────────────────────────
bootstrap() {
  say "Bootstrapping prerequisites (${PKG_MGR})"
  case "$PKG_MGR" in
    apt)
      run "$SUDO apt-get update -y"
      pkg_install ca-certificates curl wget gpg tar unzip xz-utils bzip2 whiptail software-properties-common ;;
    dnf)
      run "$SUDO dnf check-update -y || true"  # exit 100 = updates available (not an error)
      pkg_install curl wget tar unzip xz bzip2 newt dnf-plugins-core ;;
    brew)
      have brew || { err "Homebrew is not installed. Please install Homebrew from https://brew.sh first."; exit 1; }
      have whiptail || run "brew install newt || true" ;;
  esac
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
MODE=install   # install | update | list | check | table
SELECTED=()
EXPLICIT_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run)        DRY=1 ;;
    -y|--yes)            YES=1 ;;
    -f|--force)          FORCE=1 ;;
    --check|--status)    MODE=check ;;
    --update)            MODE=update ;;
    --list)              MODE=list ;;
    --table)             MODE=table ;;
    -h|--help)
      sed -n '15,26p' "$0"   # print the header comment
      exit 0 ;;
    rg)    EXPLICIT_ARGS+=(ripgrep) ;;
    *)     EXPLICIT_ARGS+=("$1") ;;
  esac
  shift
done

case "$MODE" in
  list)  print_list; exit 0 ;;
  table) print_table; exit 0 ;;
  check) check_installed; exit 0 ;;

  update)
    say "Update mode — upgrading all previously installed tools"
    readarray -t SELECTED < <(load_installed | tr ' ' '\n' | grep -v '^$')
    if [ "${#SELECTED[@]}" = 0 ]; then
      warn "No install DB found at $INST_DB"
      warn "Run without --update first to install tools."
      exit 1
    fi
    # cargo/rustup first
    printf '%s\n' "${SELECTED[@]}" | grep -qx cargo && {
      have rustup && run "rustup update"
      have cargo  && run "cargo install-update -a 2>/dev/null || true"
    }
    bootstrap
    for t in "${SELECTED[@]}"; do
      [ -z "${DESC[$t]:-}" ] && { warn "unknown tool '$t' in DB, skipping"; continue; }
      say "Updating $t — ${DESC[$t]}"
      update_tool "$t" && record_installed "$t" || err "update failed: $t (continuing)"
    done
    # re-verify and regenerate static integration
    verify_installs
    say "Regenerating shell integration (phase 1: caching shell inits)"
    cache_shell_inits
    say "Writing static integration (phase 2)"
    write_static_integration bash "$INTEGRATION_BASH"
    write_static_integration zsh  "$INTEGRATION_ZSH"
    printf '\n%s%sUpdate complete.%s  Restart shell or: source ~/.bashrc\n\n' "$B" "$G" "$OFF"
    exit 0 ;;

  install)
    if [ "${#EXPLICIT_ARGS[@]}" -gt 0 ]; then
      SELECTED=("${EXPLICIT_ARGS[@]}")
      bootstrap
    elif [ "$YES" = 1 ]; then
      SELECTED=("${DEFAULTS[@]}")
      bootstrap
    else
      bootstrap
      run_interactive
    fi

    # ensure cargo is first
    local_cargo_idx=-1
    for i in "${!SELECTED[@]}"; do
      [ "${SELECTED[$i]}" = cargo ] && { local_cargo_idx=$i; break; }
    done
    if [ "$local_cargo_idx" -ge 0 ]; then
      if [ "$FORCE" != 1 ] && resolve_bin cargo >/dev/null 2>&1; then
        cb="$(resolve_bin cargo)"
        ok "cargo already installed ($cb) — skipping"
        record_installed cargo
      else
        say "cargo — ${DESC[cargo]}"
        inst_cargo && record_installed cargo || err "cargo install failed (continuing)"
      fi
      unset 'SELECTED[$local_cargo_idx]'
      SELECTED=("${SELECTED[@]}")
    fi
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env" 2>/dev/null || true

    say "Will install: ${G}${SELECTED[*]}${OFF}"
    for t in "${SELECTED[@]}"; do
      [ -z "$t" ] && continue
      [ -z "${DESC[$t]:-}" ] && { warn "unknown tool '$t', skipping"; continue; }
      if [ "$FORCE" != 1 ] && resolve_bin "$t" >/dev/null 2>&1; then
        found_bin="$(resolve_bin "$t")"
        ok "$t already installed ($found_bin) — skipping"
        record_installed "$t"
        continue
      fi
      say "$t — ${DESC[$t]}"
      install_tool "$t" && record_installed "$t" || err "failed: $t (continuing)"
    done

    # put cargo back in SELECTED for verification (it was installed above)
    [ "$local_cargo_idx" -ge 0 ] && SELECTED=(cargo "${SELECTED[@]}")

    # ── PHASE 1: verify + cache ────────────────────────────────────────────────
    verify_installs
    say "Phase 1: caching shell inits (fzf, zoxide, atuin, starship, navi)"
    cache_shell_inits

    # ── PHASE 2: write static integration ─────────────────────────────────────
    say "Phase 2: writing static shell integration"
    write_static_integration bash "$INTEGRATION_BASH"
    write_static_integration zsh  "$INTEGRATION_ZSH"
    hook_rc "$HOME/.bashrc" "$INTEGRATION_BASH"
    [ -f "$HOME/.zshrc" ] && hook_rc "$HOME/.zshrc" "$INTEGRATION_ZSH"

    # copy self to stable location for cli-update
    self_copy="$HOME/.local/bin/install-modern-cli.sh"
    if [ "$DRY" != 1 ] && [ "$(realpath "$0" 2>/dev/null)" != "$(realpath "$self_copy" 2>/dev/null)" ]; then
      mkdir -p "$HOME/.local/bin"
      cp "$0" "$self_copy" && chmod +x "$self_copy"
      ok "copied script to $self_copy (cli-update will use this path)"
    fi

    # seed tealdeer cache
    have tldr && [ "$DRY" != 1 ] && tldr --update >/dev/null 2>&1 || true

    # import existing shell history into atuin's SQLite DB (Ctrl-R shows nothing without this)
    if have atuin && [ "$DRY" != 1 ]; then
      say "Importing existing shell history into atuin"
      atuin import auto 2>/dev/null && ok "history imported" || warn "atuin import auto failed (run it manually)"
    fi

    cat <<EOF

${B}${G}Done.${OFF}
  Restart shell or:  ${B}source ~/.bashrc${OFF}
  Integration:       $CFG_DIR/  (static — no startup overhead)
  Cached shell inits:$CFG_DIR/init/
  Install DB:        $INST_DB

  ${B}Update anytime:${OFF}  cli-update    (re-installs latest of all tools, regenerates integration)
  ${B}Overview:${OFF}        modern        (colorful tool list after restart)

Quick wins after restart:
  ${B}Ctrl-R${OFF} history    ${B}y${OFF} file manager   ${B}ll${OFF} pretty ls   ${B}z dir${OFF} smart cd
  ${B}lazygit${OFF} git TUI   ${B}btop${OFF} monitor      ${B}tldr CMD${OFF} quick help  ${B}modern${OFF} overview
EOF
    ;;
esac
