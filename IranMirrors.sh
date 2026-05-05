#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RED=$'\033[0;31m'
GRN=$'\033[0;32m'
YLW=$'\033[0;33m'
BLU=$'\033[0;34m'
RST=$'\033[0m'

log()  { printf "%s\n" "$*"; }
info() { printf "%s[INFO]%s %s\n" "$BLU" "$RST" "$*"; }
ok()   { printf "%s[OK]%s   %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YLW" "$RST" "$*"; }
err()  { printf "%s[ERR]%s  %s\n" "$RED" "$RST" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing dependency: $1"; exit 1; }
}

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }
ts_now() { date +"%Y%m%d-%H%M%S"; }
mkdirp() { mkdir -p "$1"; }

curl_http_code() {
  local url="$1"
  curl -fsS -o /dev/null --max-time 6 -w "%{http_code}" "$url" 2>/dev/null || echo "000"
}

curl_time_total_ms() {
  local url="$1"
  local t
  t="$(curl -fsS -o /dev/null --max-time 6 -w "%{time_total}" "$url" 2>/dev/null || echo "99.999")"
  awk -v t="$t" 'BEGIN{ printf "%.0f", (t*1000) }'
}

ping_ms() {
  local host="$1"
  if command -v ping >/dev/null 2>&1; then
    local out
    out="$(ping -c 1 -W 1 "$host" 2>/dev/null || true)"
    awk 'match($0,/time=([0-9.]+)[ ]*ms/,a){print a[1]}' <<<"$out" | head -n1 | awk '{printf "%.0f",$1}' || true
  fi
}

host_from_url() {
  local url="$1"
  url="${url#http://}"
  url="${url#https://}"
  url="${url%%/*}"
  printf "%s" "$url"
}

score_mirror() {
  local base="$1"
  local probe="$2"
  local expect="$3"

  local url
  if [[ -n "$probe" ]]; then
    url="${base%/}/${probe#/}"
  else
    url="${base%/}/"
  fi

  local code
  code="$(curl_http_code "$url")"

  local pass=0
  case "$expect" in
    ok)
      [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]] && pass=1
      ;;
    docker)
      [[ "$code" == "200" || "$code" == "401" ]] && pass=1
      ;;
    any)
      [[ "$code" != "000" ]] && pass=1
      ;;
  esac

  if [[ "$pass" -ne 1 ]]; then
    printf "999999 %s %s\n" "$code" "$url"
    return 0
  fi

  local host pms tms
  host="$(host_from_url "$base")"
  pms="$(ping_ms "$host" || true)"

  if [[ -n "${pms:-}" ]]; then
    printf "%s %s %s\n" "$pms" "$code" "$url"
  else
    tms="$(curl_time_total_ms "$url")"
    printf "%s %s %s\n" "$((tms+25))" "$code" "$url"
  fi
}

progress_bar() {
  local current="$1"
  local total="$2"
  local width=40
  local percent=$(( current * 100 / total ))
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  printf "\r[WORK] Testing mirrors: %3d%% [" "$percent"
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$empty" ''  | tr ' ' '.'
  printf "]"
}

choose_best_mirrors() {
  local -n _arr="$1"
  local BEST_N="${2:-4}"

  local total="${#_arr[@]}"
  local idx=0

  local scored=()
  local item name base probe expect

  for item in "${_arr[@]}"; do
    idx=$((idx+1))
    progress_bar "$idx" "$total"
    IFS='|' read -r name base probe expect <<<"$item"
    local s code url
    read -r s code url < <(score_mirror "$base" "$probe" "$expect")
    scored+=("${s}|${name}|${base}|${code}|${url}")
  done

  printf "\r[WORK] Testing mirrors: 100%% [########################################]\n"

  printf "%s\n" "${scored[@]}" \
    | sort -t'|' -k1,1n \
    | head -n "$BEST_N" \
    | awk -F'|' '{print $3}'
}

OS_ID=""
OS_LIKE=""
OS_NAME=""
OS_VERSION_ID=""

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
    OS_NAME="${NAME:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
  else
    err "/etc/os-release not found."
    exit 1
  fi
  info "Detected OS: ${OS_NAME:-unknown} (ID=${OS_ID:-?}, VERSION_ID=${OS_VERSION_ID:-?})"
}

is_debian_family() {
  [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"debian"* ]]
}

is_rhel_family() {
  [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID" == "rocky" || "$OS_ID" == "almalinux" || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* ]]
}

is_arch_family() {
  [[ "$OS_ID" == "arch" || "$OS_ID" == "manjaro" || "$OS_LIKE" == *"arch"* ]]
}

BACKUP_DIR="/var/backups/mirrorgpt"
BACKUP_META="${BACKUP_DIR}/LAST_BACKUP"

backup_debian() {
  mkdirp "$BACKUP_DIR"
  local stamp; stamp="$(ts_now)"
  local dest="${BACKUP_DIR}/debian-apt-${stamp}"
  mkdirp "$dest"

  if [[ -d /etc/apt ]]; then
    cp -a /etc/apt/sources.list "$dest/" 2>/dev/null || true
    cp -a /etc/apt/sources.list.d "$dest/" 2>/dev/null || true
    ok "Backed up APT config to: $dest"
  else
    warn "/etc/apt not found."
  fi

  printf "%s\n" "$dest" >"$BACKUP_META"
}

restore_debian() {
  if [[ ! -r "$BACKUP_META" ]]; then
    err "No backup metadata found at $BACKUP_META"
    exit 1
  fi
  local src; src="$(cat "$BACKUP_META")"
  if [[ ! -d "$src" ]]; then
    err "Backup directory not found: $src"
    exit 1
  fi

  if [[ -f "$src/sources.list" ]]; then
    cp -a "$src/sources.list" /etc/apt/sources.list
  fi
  if [[ -d "$src/sources.list.d" ]]; then
    rm -rf /etc/apt/sources.list.d
    cp -a "$src/sources.list.d" /etc/apt/
  fi

  ok "Restored APT config from: $src"
  info "Run: apt update"
}

backup_rhel() {
  mkdirp "$BACKUP_DIR"
  local stamp; stamp="$(ts_now)"
  local dest="${BACKUP_DIR}/rhel-repos-${stamp}"
  mkdirp "$dest"

  if [[ -d /etc/yum.repos.d ]]; then
    cp -a /etc/yum.repos.d "$dest/"
    ok "Backed up YUM/DNF repos to: $dest"
  else
    warn "/etc/yum.repos.d not found."
  fi

  printf "%s\n" "$dest" >"$BACKUP_META"
}

restore_rhel() {
  if [[ ! -r "$BACKUP_META" ]]; then
    err "No backup metadata found at $BACKUP_META"
    exit 1
  fi
  local src; src="$(cat "$BACKUP_META")"
  if [[ ! -d "$src" ]]; then
    err "Backup directory not found: $src"
    exit 1
  fi
  if [[ -d "$src/yum.repos.d" ]]; then
    rm -rf /etc/yum.repos.d
    cp -a "$src/yum.repos.d" /etc/
    ok "Restored YUM/DNF repos from: $src"
    info "Run: dnf makecache or yum makecache"
  else
    err "Backup does not contain yum.repos.d: $src"
    exit 1
  fi
}

backup_arch() {
  mkdirp "$BACKUP_DIR"
  local stamp; stamp="$(ts_now)"
  local dest="${BACKUP_DIR}/arch-pacman-${stamp}"
  mkdirp "$dest"

  if [[ -f /etc/pacman.d/mirrorlist ]]; then
    cp -a /etc/pacman.d/mirrorlist "$dest/"
    ok "Backed up pacman mirrorlist to: $dest"
  else
    warn "/etc/pacman.d/mirrorlist not found."
  fi

  printf "%s\n" "$dest" >"$BACKUP_META"
}

restore_arch() {
  if [[ ! -r "$BACKUP_META" ]]; then
    err "No backup metadata found at $BACKUP_META"
    exit 1
  fi
  local src; src="$(cat "$BACKUP_META")"
  if [[ ! -d "$src" ]]; then
    err "Backup directory not found: $src"
    exit 1
  fi
  if [[ -f "$src/mirrorlist" ]]; then
    cp -a "$src/mirrorlist" /etc/pacman.d/mirrorlist
    ok "Restored pacman mirrorlist from: $src"
    info "Run: pacman -Syy"
  else
    err "Backup does not contain mirrorlist: $src"
    exit 1
  fi
}

do_backup() {
  detect_os
  if is_debian_family; then
    backup_debian
  elif is_rhel_family; then
    backup_rhel
  elif is_arch_family; then
    backup_arch
  else
    err "Backup not implemented for this OS."
    exit 1
  fi
}

do_restore() {
  detect_os
  if is_debian_family; then
    restore_debian
  elif is_rhel_family; then
    restore_rhel
  elif is_arch_family; then
    restore_arch
  else
    err "Restore not implemented for this OS."
    exit 1
  fi
}

MIRRORS_UBUNTU=(
  "Ubuntu Official Archive|https://archive.ubuntu.com/ubuntu|dists/|ok"
  "Ubuntu Official Security|https://security.ubuntu.com/ubuntu|dists/|ok"
  "Ubuntu IR Official (ir.archive.ubuntu.com)|http://ir.archive.ubuntu.com/ubuntu|dists/|ok"
  "Shatel Mirror|https://mirror.shatel.ir/ubuntu|dists/|ok"
  "Arvan Linux Repo|https://arvancloud.ir/dev/linux-repository/ubuntu|dists/|ok"
  "IranServer Mirror|https://mirror.iranserver.com/ubuntu|dists/|ok"
  "MobinHost Mirror|https://mirror.mobinhost.com/ubuntu|dists/|ok"
  "0-1 Cloud Mirror|https://mirror.0-1.cloud/ubuntu|dists/|ok"
  "ManageIT Mirror|https://mirror.manageit.ir/ubuntu|dists/|ok"
  "AminiDC Mirror|https://mirror.aminidc.com/ubuntu|dists/|ok"
  "Kimiahost Ubuntu Mirror|https://ubuntu-mirror.kimiahost.com/ubuntu|dists/|ok"
  "DigitalVPS Mirror|https://mirror.digitalvps.ir/ubuntu|dists/|ok"
  "Sindad Ubuntu Mirror|https://ir.ubuntu.sindad.cloud/ubuntu|dists/|ok"
  "Afranet Mirror|https://afranet.com/ubuntu|dists/|ok"
  "Pishgaman Mirror|https://pishgaman.net/ubuntu|dists/|ok"
  "Parsdev Mirror|https://parsdev.com/ubuntu|dists/|ok"
  "LinuxMirrors.ir|https://linuxmirrors.ir/ubuntu|dists/|ok"
  "IUT Mirror|https://repo.iut.ac.ir/ubuntu|dists/|ok"
  "Pardisco Mirror|https://pardisco.co/ubuntu|dists/|ok"
  "Abrha Mirror|https://abrha.net/ubuntu|dists/|ok"
  "AtlanticsCloud Mirror|https://atlanticscloud.ir/ubuntu|dists/|ok"
)

MIRRORS_DEBIAN=(
  "Debian Official|https://deb.debian.org/debian|dists/|ok"
  "Debian Security|https://security.debian.org/debian-security|dists/|ok"
  "Shatel Mirror|https://mirror.shatel.ir/debian|dists/|ok"
  "Arvan Linux Repo|https://arvancloud.ir/dev/linux-repository/debian|dists/|ok"
  "IranServer Mirror|https://mirror.iranserver.com/debian|dists/|ok"
  "MobinHost Mirror|https://mirror.mobinhost.com/debian|dists/|ok"
  "0-1 Cloud Mirror|https://mirror.0-1.cloud/debian|dists/|ok"
  "AminiDC Mirror|https://mirror.aminidc.com/debian|dists/|ok"
  "IUT Mirror|https://repo.iut.ac.ir/debian|dists/|ok"
  "Pardisco Mirror|https://pardisco.co/debian|dists/|ok"
  "Abrha Mirror|https://abrha.net/debian|dists/|ok"
  "Parsdev Mirror|https://parsdev.com/debian|dists/|ok"
  "LinuxMirrors.ir|https://linuxmirrors.ir/debian|dists/|ok"
)

MIRRORS_ARCH=(
  "Arch Official|https://geo.mirror.pkgbuild.com|core/os/x86_64/|ok"
  "IUT Mirror|https://repo.iut.ac.ir/archlinux|core/os/x86_64/|ok"
  "MobinHost Mirror|https://mirror.mobinhost.com/archlinux|core/os/x86_64/|ok"
  "0-1 Cloud Mirror|https://mirror.0-1.cloud/archlinux|core/os/x86_64/|ok"
  "Arvan Linux Repo|https://arvancloud.ir/dev/linux-repository/archlinux|core/os/x86_64/|ok"
  "Pardisco Mirror|https://pardisco.co/archlinux|core/os/x86_64/|ok"
)

MIRRORS_RHEL_GENERIC=(
  "ITO Repo Portal|https://repo-portal.ito.gov.ir| |any"
  "Arvan Linux Repo|https://arvancloud.ir/dev/linux-repository| |any"
  "IranServer Mirror|https://mirror.iranserver.com| |any"
  "MobinHost Mirror|https://mirror.mobinhost.com| |any"
  "0-1 Cloud Mirror|https://mirror.0-1.cloud| |any"
  "AminiDC Mirror|https://mirror.aminidc.com| |any"
  "IUT Mirror|https://repo.iut.ac.ir| |any"
  "Abrha Mirror|https://abrha.net| |any"
  "LinuxMirrors.ir|https://linuxmirrors.ir| |any"
  "Pardisco Mirror|https://pardisco.co| |any"
)

write_apt_sources_for_ubuntu_debian() {
  local primary="$1"
  local secondary="$2"
  local codename
  codename="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
  if [[ -z "${codename:-}" ]]; then
    err "VERSION_CODENAME not found in /etc/os-release."
    exit 1
  fi

  local f="/etc/apt/sources.list"
  cp -a "$f" "${f}.mirrorgpt.bak.$(ts_now)" 2>/dev/null || true

  info "Writing APT sources with selected mirrors..."
  cat >"$f" <<EOF
# Generated by mirrorgpt.sh at $(date -Is)
# Primary:   ${primary}
# Secondary: ${secondary}

deb ${primary%/} ${codename} main restricted universe multiverse
deb ${primary%/} ${codename}-updates main restricted universe multiverse
deb ${primary%/} ${codename}-backports main restricted universe multiverse

deb ${secondary%/} ${codename} main restricted universe multiverse
deb ${secondary%/} ${codename}-updates main restricted universe multiverse
deb ${secondary%/} ${codename}-backports main restricted universe multiverse
EOF

  if [[ "$OS_ID" == "ubuntu" ]]; then
    cat >>"$f" <<EOF
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
  else
    cat >>"$f" <<EOF
deb https://security.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
  fi

  ok "Updated /etc/apt/sources.list"
  info "Run: apt update"
}

apply_arch_mirrorlist() {
  local primary="$1"
  local secondary="$2"
  local f="/etc/pacman.d/mirrorlist"
  cp -a "$f" "${f}.mirrorgpt.bak.$(ts_now)" 2>/dev/null || true

  info "Writing pacman mirrorlist with selected mirrors..."
  cat >"$f" <<EOF
# Generated by mirrorgpt.sh at $(date -Is)
Server = ${primary%/}/\$repo/os/\$arch
Server = ${secondary%/}/\$repo/os/\$arch
EOF

  ok "Updated /etc/pacman.d/mirrorlist"
  info "Run: pacman -Syy"
}

apply_rhel_repo_hint() {
  local primary="$1"
  local secondary="$2"
  warn "Automatic YUM/DNF repo rewriting is not enabled (distro-specific)."
  info "Selected mirrors:"
  log "  Primary:   $primary"
  log "  Secondary: $secondary"
}

switch_to_best_mirrors() {
  detect_os

  if ! is_root; then
    err "Run as root (sudo) to modify system repo configuration."
    exit 1
  fi

  info "Creating backup..."
  do_backup

  info "Scanning mirrors (this may take a little while)..."

  local best=()
  local primary="" secondary=""

  if is_debian_family; then
    if [[ "$OS_ID" == "ubuntu" ]]; then
      mapfile -t best < <(choose_best_mirrors MIRRORS_UBUNTU 4)
    else
      mapfile -t best < <(choose_best_mirrors MIRRORS_DEBIAN 4)
    fi
    primary="${best[0]:-}"
    secondary="${best[1]:-${best[0]:-}}"
    if [[ -z "$primary" ]]; then
      err "No working mirrors found."
      exit 1
    fi
    info "Best mirrors found:"
    printf "  1) %s\n" "$primary"
    printf "  2) %s\n" "$secondary"
    write_apt_sources_for_ubuntu_debian "$primary" "$secondary"
    return 0
  fi

  if is_arch_family; then
    mapfile -t best < <(choose_best_mirrors MIRRORS_ARCH 4)
    primary="${best[0]:-}"
    secondary="${best[1]:-${best[0]:-}}"
    if [[ -z "$primary" ]]; then
      err "No working mirrors found."
      exit 1
    fi
    info "Best mirrors found:"
    printf "  1) %s\n" "$primary"
    printf "  2) %s\n" "$secondary"
    apply_arch_mirrorlist "$primary" "$secondary"
    return 0
  fi

  if is_rhel_family; then
    mapfile -t best < <(choose_best_mirrors MIRRORS_RHEL_GENERIC 4)
    primary="${best[0]:-}"
    secondary="${best[1]:-${best[0]:-}}"
    if [[ -z "$primary" ]]; then
      err "No working mirrors found."
      exit 1
    fi
    info "Best mirrors found:"
    printf "  1) %s\n" "$primary"
    printf "  2) %s\n" "$secondary"
    apply_rhel_repo_hint "$primary" "$secondary"
    return 0
  fi

  err "Unsupported OS for mirror switching."
  exit 1
}

menu() {
  cat <<'EOF'
Select an action:
  1) Backup current configuration
  2) Restore from last backup
  3) Switch mirrors (official first, then Iranian mirrors; auto-ranked)

Enter a number (1-3):
EOF
}

main() {
  need_cmd curl

  menu
  read -r choice
  case "$choice" in
    1)
      if ! is_root; then err "Run as root (sudo) to backup system repo configuration."; exit 1; fi
      do_backup
      ;;
    2)
      if ! is_root; then err "Run as root (sudo) to restore system repo configuration."; exit 1; fi
      do_restore
      ;;
    3)
      switch_to_best_mirrors
      ;;
    *)
      err "Invalid choice."
      exit 1
      ;;
  esac
}

main "$@"
