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

set -euo pipefail

REPO="sundowndev/phoneinfoga"
VERSION="${PHONEINFOGA_VERSION:-latest}"

c_red='\033[1;91m'
c_green='\033[1;92m'
c_yellow='\033[1;93m'
c_reset='\033[0m'

log()  { printf "${c_green}[*]${c_reset} %s\n" "$*"; }
warn() { printf "${c_yellow}[!]${c_reset} %s\n" "$*"; }
die()  { printf "${c_red}[x]${c_reset} %s\n" "$*" >&2; exit 1; }

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

main() {
  require curl
  require tar
  require uname

  local os arch install_dir tmp json url archive
  os="$(detect_os)"
  arch="$(detect_arch)"
  install_dir="$(choose_install_dir "$os")"

  # The release assets use "Linux" capitalized for Termux too.
  local asset_os="$os"
  [ "$asset_os" = "termux" ] && asset_os="linux"

  log "OS: $os  arch: $arch"
  log "install dir: $install_dir"
  log "fetching release metadata (${VERSION})..."
  json="$(fetch_release_json)" || die "could not reach GitHub API"

  if command -v jq >/dev/null 2>&1; then
    url="$(pick_asset_url_jq "$asset_os" "$arch" "$json")"
  elif command -v python3 >/dev/null 2>&1; then
    url="$(pick_asset_url "$asset_os" "$arch" "$json")"
  else
    die "need either 'jq' or 'python3' to parse the release manifest"
  fi
  [ -n "$url" ] || die "no release asset matches ${asset_os}/${arch}"

  log "downloading $(basename "$url")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  archive="${tmp}/phoneinfoga.tar.gz"
  curl -fsSL -o "$archive" "$url"

  log "extracting..."
  tar -xzf "$archive" -C "$tmp"

  local bin="${tmp}/phoneinfoga"
  [ -f "$bin" ] || bin="$(find "$tmp" -maxdepth 3 -type f -name phoneinfoga | head -n1)"
  [ -n "$bin" ] && [ -f "$bin" ] || die "phoneinfoga binary not found in archive"

  mkdir -p "$install_dir"
  install -m 0755 "$bin" "${install_dir}/phoneinfoga"

  log "installed: ${install_dir}/phoneinfoga"
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
