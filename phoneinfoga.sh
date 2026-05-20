#!/usr/bin/env bash
#
# PhoneInfoga installer
#
# Downloads the latest PhoneInfoga release binary from
# https://github.com/sundowndev/phoneinfoga and installs it on
# Linux, macOS, or Termux (Android).
#
# Usage:
#   bash phoneinfoga.sh                # install latest
#   PHONEINFOGA_VERSION=v2.11.0 bash phoneinfoga.sh   # pin a version
#   PHONEINFOGA_PREFIX=$HOME/.local bash phoneinfoga.sh
#
# Color modes (PHONEINFOGA_COLOR):
#   auto    detect terminal capability (default)
#   rainbow truecolor rainbow gradient banner + cycling log accents
#   neon    256-color neon palette
#   mono    no color
#   off     alias for mono
#

set -euo pipefail

REPO="sundowndev/phoneinfoga"
VERSION="${PHONEINFOGA_VERSION:-latest}"
COLOR_MODE="${PHONEINFOGA_COLOR:-auto}"
NO_BANNER="${PHONEINFOGA_NO_BANNER:-0}"
TMPDIR_INSTALL=""
SPINNER_PID=""

cleanup() {
  [ -n "${SPINNER_PID}" ] && kill "${SPINNER_PID}" 2>/dev/null || true
  [ -n "${TMPDIR_INSTALL}" ] && rm -rf "${TMPDIR_INSTALL}"
  # restore cursor in case a spinner left it hidden
  printf '\033[?25h' 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Color engine
# ---------------------------------------------------------------------------

detect_color_support() {
  # Honour explicit off-switches and NO_COLOR (https://no-color.org/).
  if [ -n "${NO_COLOR:-}" ]; then echo "mono"; return; fi
  case "${COLOR_MODE}" in
    rainbow|neon|mono|off) echo "${COLOR_MODE/off/mono}"; return ;;
  esac
  # auto:
  if [ ! -t 1 ]; then echo "mono"; return; fi
  case "${COLORTERM:-}" in
    truecolor|24bit) echo "rainbow"; return ;;
  esac
  if command -v tput >/dev/null 2>&1; then
    local colors
    colors="$(tput colors 2>/dev/null || echo 0)"
    if [ "${colors:-0}" -ge 256 ]; then echo "neon"; return; fi
    if [ "${colors:-0}" -ge 8 ];   then echo "neon"; return; fi
  fi
  echo "mono"
}

ACTIVE_COLOR="$(detect_color_support)"

# Truecolor escape: rgb foreground.
rgb() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
# 256-color escape: indexed foreground.
fg256() { printf '\033[38;5;%dm' "$1"; }

c_reset='\033[0m'
c_dim='\033[2m'

# Cycling palettes ------------------------------------------------------------
# RAINBOW_PAL: truecolor hex tuples for smooth gradients.
# NEON_PAL:    256-color indices that pop on dark + light terminals.
RAINBOW_PAL=(
  '255 0 102'   '255 87  34'  '255 193 7'   '139 195 74'
  '0   200 150' '0   188 212' '63  81  181' '156 39  176'
)
NEON_PAL=(198 208 220 154 49 45 33 99 201)

palette_size() {
  case "${ACTIVE_COLOR}" in
    rainbow) echo "${#RAINBOW_PAL[@]}" ;;
    neon)    echo "${#NEON_PAL[@]}" ;;
    *)       echo 1 ;;
  esac
}

# palette_color N -> outputs the ANSI sequence for slot N of the active palette
palette_color() {
  local idx="$1"
  case "${ACTIVE_COLOR}" in
    rainbow)
      local n="${#RAINBOW_PAL[@]}"
      idx=$(( idx % n ))
      # shellcheck disable=SC2206
      local rgb_arr=( ${RAINBOW_PAL[$idx]} )
      rgb "${rgb_arr[0]}" "${rgb_arr[1]}" "${rgb_arr[2]}"
      ;;
    neon)
      local n="${#NEON_PAL[@]}"
      idx=$(( idx % n ))
      fg256 "${NEON_PAL[$idx]}"
      ;;
    *) : ;;  # mono: emit nothing
  esac
}

# colorize_text TEXT [OFFSET] -- paints each char with the next palette slot.
colorize_text() {
  local text="$1" offset="${2:-0}" out="" i ch n
  if [ "${ACTIVE_COLOR}" = "mono" ]; then
    printf '%s' "$text"
    return
  fi
  n="$(palette_size)"
  for (( i=0; i<${#text}; i++ )); do
    ch="${text:i:1}"
    if [ "$ch" = " " ]; then
      out+="$ch"
      continue
    fi
    out+="$(palette_color $(( (i + offset) % n )))${ch}"
  done
  printf '%b%b' "$out" "$c_reset"
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

print_banner() {
  [ "${NO_BANNER}" = "1" ] && return
  [ ! -t 1 ] && return
  local lines=(
'  ____  _                      ___        __                  '
' |  _ \| |__   ___  _ __   ___|_ _|_ __  / _| ___   __ _  __ _'
' | |_) | `_ \ / _ \| `_ \ / _ \| || `_ \| |_ / _ \ / _` |/ _` |'
' |  __/| | | | (_) | | | |  __/| || | | |  _| (_) | (_| | (_| |'
' |_|   |_| |_|\___/|_| |_|\___|___|_| |_|_|  \___/ \__, |\__,_|'
'                                                   |___/       '
  )
  local i
  for i in "${!lines[@]}"; do
    colorize_text "${lines[$i]}" "$(( i * 2 ))"
    printf '\n'
  done
  local tag="  advanced installer · color: ${ACTIVE_COLOR} · target: ${REPO}"
  if [ "${ACTIVE_COLOR}" = "mono" ]; then
    printf '%s\n\n' "${tag}"
  else
    printf '%b%s%b\n\n' "${c_dim}" "${tag}" "${c_reset}"
  fi
}

# ---------------------------------------------------------------------------
# Logging — each call advances a global color cursor for a cycling effect.
# ---------------------------------------------------------------------------

LOG_TICK=0

render_tag() {
  # render_tag SYMBOL --> echoes the bracketed tag in the current cycle color
  local sym="$1" col
  if [ "${ACTIVE_COLOR}" = "mono" ]; then
    printf '[%s]' "$sym"
    return
  fi
  col="$(palette_color "${LOG_TICK}")"
  printf '%b[%s]%b' "${col}" "${sym}" "${c_reset}"
  LOG_TICK=$(( LOG_TICK + 1 ))
}

log()  { printf '%b %s\n' "$(render_tag '*')" "$*"; }
ok()   { printf '%b %s\n' "$(render_tag '+')" "$*"; }
warn() { printf '%b %s\n' "$(render_tag '!')" "$*" >&2; }
die() {
  if [ "${ACTIVE_COLOR}" = "mono" ]; then
    printf '[x] %s\n' "$*" >&2
  else
    printf '\033[1;91m[x]\033[0m %s\n' "$*" >&2
  fi
  exit 1
}

# ---------------------------------------------------------------------------
# Spinner — cycles through palette while a background task runs.
# ---------------------------------------------------------------------------

spinner_start() {
  [ ! -t 1 ] && return
  [ "${ACTIVE_COLOR}" = "mono" ] && return
  local msg="$1"
  printf '\033[?25l'  # hide cursor
  (
    local frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local i=0 n
    n="$(palette_size)"
    while :; do
      local f="${frames[$(( i % ${#frames[@]} ))]}"
      local col
      col="$(palette_color $(( i % n )))"
      printf '\r%b%s%b %s' "${col}" "${f}" "${c_reset}" "${msg}"
      i=$(( i + 1 ))
      sleep 0.08
    done
  ) &
  SPINNER_PID=$!
  disown "${SPINNER_PID}" 2>/dev/null || true
}

spinner_stop() {
  [ -z "${SPINNER_PID}" ] && return
  kill "${SPINNER_PID}" 2>/dev/null || true
  wait "${SPINNER_PID}" 2>/dev/null || true
  SPINNER_PID=""
  # clear the spinner line, restore cursor
  printf '\r\033[2K\033[?25h'
}

# Run a command silently with the spinner; on failure replay its output.
with_spinner() {
  local msg="$1"; shift
  local logfile
  logfile="$(mktemp)"
  spinner_start "${msg}"
  if "$@" >"${logfile}" 2>&1; then
    spinner_stop
    rm -f "${logfile}"
    ok "${msg}"
    return 0
  else
    local rc=$?
    spinner_stop
    warn "${msg} — failed"
    cat "${logfile}" >&2
    rm -f "${logfile}"
    return "${rc}"
  fi
}

# ---------------------------------------------------------------------------
# Detection + asset selection
# ---------------------------------------------------------------------------

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

detect_os() {
  if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}" ] && command -v termux-info >/dev/null 2>&1; then
    echo "termux"
    return
  fi
  case "$(uname -s)" in
    Linux)  echo "linux"  ;;
    Darwin) echo "darwin" ;;
    *)      die "unsupported OS: $(uname -s)" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)      echo "x86_64" ;;
    aarch64|arm64)     echo "arm64"  ;;
    armv7l|armv7|armv6l) echo "armv6" ;;
    i386|i686)         echo "i386"   ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

choose_install_dir() {
  if [ -n "${PHONEINFOGA_PREFIX:-}" ]; then
    echo "${PHONEINFOGA_PREFIX}/bin"
  elif [ "$1" = "termux" ] && [ -n "${PREFIX:-}" ]; then
    echo "${PREFIX}/bin"
  elif [ -w /usr/local/bin ]; then
    echo "/usr/local/bin"
  else
    echo "${HOME}/.local/bin"
  fi
}

fetch_release_json() {
  local url
  if [ "${VERSION}" = "latest" ]; then
    url="https://api.github.com/repos/${REPO}/releases/latest"
  else
    url="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
  fi
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    "${url}"
}

pick_asset_url() {
  local os="$1" arch="$2" json="$3"
  printf '%s' "$json" | python3 -c '
import json, sys
os_name, arch = sys.argv[1], sys.argv[2].lower()
data = json.load(sys.stdin)
matches = []
for asset in data.get("assets", []):
    name = asset["name"].lower()
    if not (name.endswith(".tar.gz") or name.endswith(".tgz")):
        continue
    if os_name not in name or arch not in name:
        continue
    matches.append((asset["name"], asset["browser_download_url"]))
matches.sort(key=lambda c: len(c[0]))
if matches:
    print(matches[0][1])
' "$os" "$arch"
}

pick_asset_url_jq() {
  local os="$1" arch="$2" json="$3"
  printf '%s' "$json" | jq -r --arg os "$os" --arg arch "$arch" '
    .assets
    | map(select(.name | ascii_downcase | test("\\.(tar\\.gz|tgz)$")))
    | map(select(.name | ascii_downcase | contains($os)))
    | map(select(.name | ascii_downcase | contains($arch | ascii_downcase)))
    | sort_by(.name | length)
    | .[0].browser_download_url // empty
  '
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------

main() {
  print_banner

  require curl
  require tar
  require uname

  local os arch install_dir tmp json url archive
  os="$(detect_os)"
  arch="$(detect_arch)"
  install_dir="$(choose_install_dir "$os")"

  local asset_os="$os"
  [ "$asset_os" = "termux" ] && asset_os="linux"

  log "OS: $(colorize_text "$os" 1)  arch: $(colorize_text "$arch" 3)"
  log "install dir: $install_dir"
  log "version: ${VERSION}"

  log "fetching release metadata..."
  json="$(fetch_release_json)" || die "could not reach GitHub API"

  if command -v jq >/dev/null 2>&1; then
    url="$(pick_asset_url_jq "$asset_os" "$arch" "$json")"
  elif command -v python3 >/dev/null 2>&1; then
    url="$(pick_asset_url "$asset_os" "$arch" "$json")"
  else
    die "need either 'jq' or 'python3' to parse the release manifest"
  fi
  [ -n "$url" ] || die "no release asset matches ${asset_os}/${arch}"

  log "asset: $(basename "$url")"
  TMPDIR_INSTALL="$(mktemp -d)"
  tmp="${TMPDIR_INSTALL}"
  archive="${tmp}/phoneinfoga.tar.gz"

  with_spinner "downloading release" curl -fsSL -o "$archive" "$url"
  with_spinner "extracting archive"  tar -xzf "$archive" -C "$tmp"

  local bin="${tmp}/phoneinfoga"
  [ -f "$bin" ] || bin="$(find "$tmp" -maxdepth 3 -type f -name phoneinfoga | head -n1)"
  [ -n "$bin" ] && [ -f "$bin" ] || die "phoneinfoga binary not found in archive"

  mkdir -p "$install_dir"
  install -m 0755 "$bin" "${install_dir}/phoneinfoga"

  ok "installed: ${install_dir}/phoneinfoga"
  case ":${PATH}:" in
    *":${install_dir}:"*) ;;
    *) warn "${install_dir} is not in \$PATH — add it to your shell rc to use 'phoneinfoga' directly" ;;
  esac

  if command -v phoneinfoga >/dev/null 2>&1; then
    phoneinfoga version || true
  else
    "${install_dir}/phoneinfoga" version || true
  fi
}

main "$@"
