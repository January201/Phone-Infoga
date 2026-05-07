# PhoneInfoga installer

A small installer script that downloads the latest [PhoneInfoga](https://github.com/sundowndev/phoneinfoga)
release binary and drops it on your `$PATH`.

PhoneInfoga is an OSINT framework for scanning international phone numbers — it
checks number validity, gathers carrier / country / line-type information, and
helps pivot to public footprints (search engines, reputation reports, etc.).

> This repo only ships the installer. The tool itself lives upstream at
> [`sundowndev/phoneinfoga`](https://github.com/sundowndev/phoneinfoga).
> The previous Python version (v1) is no longer maintained — this installer
> fetches the current Go-based v2 release.

## Supported platforms

- Linux (x86_64, arm64, armv6, i386)
- macOS (x86_64, arm64)
- Termux on Android (arm64, armv6)

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/january201/phone-infoga/master/phoneinfoga.sh)
```

Or clone and run locally:

```bash
git clone https://github.com/january201/phone-infoga.git
cd phone-infoga
bash phoneinfoga.sh
```

### Options

| Variable               | Purpose                                                  |
|------------------------|----------------------------------------------------------|
| `PHONEINFOGA_VERSION`  | Pin a specific release tag (e.g. `v2.11.0`). Default: `latest`. |
| `PHONEINFOGA_PREFIX`   | Install under `<prefix>/bin` instead of the default.    |
| `GITHUB_TOKEN`         | Optional, used to avoid rate-limiting on the GitHub API. |

Examples:

```bash
PHONEINFOGA_VERSION=v2.11.0 bash phoneinfoga.sh
PHONEINFOGA_PREFIX="$HOME/.local" bash phoneinfoga.sh
```

## Default install location

| Environment              | Path                  |
|--------------------------|-----------------------|
| Termux                   | `$PREFIX/bin`         |
| Linux/macOS (root)       | `/usr/local/bin`      |
| Linux/macOS (non-root)   | `$HOME/.local/bin`    |

Make sure the chosen directory is on your `$PATH`.

## Requirements

- `curl`
- `tar`
- Either `jq` *or* `python3` (used to parse the GitHub release manifest)

The script does **not** install Python, pip, or any v1-era dependencies — the
upstream binary is self-contained.

## Usage

After installation:

```bash
phoneinfoga version
phoneinfoga scan -n "+33 1 23 45 67 89"
phoneinfoga serve   # web UI on :5000
```

See the [upstream documentation](https://sundowndev.github.io/phoneinfoga/)
for the full command reference.

## License

The installer in this repository is provided as-is. PhoneInfoga itself is
licensed by its upstream authors — see the upstream repository for details.

## Disclaimer

This tool is intended for authorized OSINT, security research, and educational
use. The maintainers are not responsible for misuse.
