#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

UBUNTU_MIRRORS=(
  "Ubuntu Official|http://archive.ubuntu.com/ubuntu/|dists/|"
  "Ubuntu Security|http://security.ubuntu.com/ubuntu/|dists/|"
  "Canonical Partner|http://archive.canonical.com/ubuntu/|dists/|"
  "Iran Asis|http://ir.archive.ubuntu.com/ubuntu/|dists/|"
  "ASIS Tehran|http://ubuntu.asis.io/ubuntu/|dists/|"
  "Yazd University|http://mirror.yazd.ac.ir/ubuntu/|dists/|"
  "Shiraz University|http://mirror.shirazu.ac.ir/ubuntu/|dists/|"
  "Amirkabir University|http://mirror.aut.ac.ir/ubuntu/|dists/|"
  "Shahed University|http://mirror.shahed.ac.ir/ubuntu/|dists/|"
  "Rasht Parsian|http://ubuntu.parsianhost.com/ubuntu/|dists/|"
  "Bardia|http://mirror.bardia.tech/ubuntu/|dists/|"
  "Hamravesh|http://mirror.hamravesh.com/ubuntu/|dists/|"
)

DEBIAN_MIRRORS=(
  "Debian Official|http://deb.debian.org/debian/|dists/|"
  "Debian Security|http://security.debian.org/debian-security/|dists/|"
  "Iran Asis|http://ir.debian.asis.io/debian/|dists/|"
  "Yazd University|http://mirror.yazd.ac.ir/debian/|dists/|"
  "Shiraz University|http://mirror.shirazu.ac.ir/debian/|dists/|"
  "Amirkabir University|http://mirror.aut.ac.ir/debian/|dists/|"
  "Shahed University|http://mirror.shahed.ac.ir/debian/|dists/|"
  "Bardia|http://mirror.bardia.tech/debian/|dists/|"
)

ARCH_MIRRORS=(
  "Arch Official Tier1|http://mirror.rackspace.com/archlinux/|core/os/x86_64/|"
  "Arch Kernel.org|http://mirrors.kernel.org/archlinux/|core/os/x86_64/|"
  "Iran Asis|http://mirror.asis.io/archlinux/|core/os/x86_64/|"
  "Yazd University|http://mirror.yazd.ac.ir/archlinux/|core/os/x86_64/|"
  "Shiraz University|http://mirror.shirazu.ac.ir/archlinux/|core/os/x86_64/|"
  "Amirkabir University|http://mirror.aut.ac.ir/archlinux/|core/os/x86_64/|"
  "Shahed University|http://mirror.shahed.ac.ir/archlinux/|core/os/x86_64/|"
)

ALPINE_MIRRORS=(
  "Alpine Official|http://dl-cdn.alpinelinux.org/alpine/|latest-stable/main/|"
  "Iran Asis|http://mirror.asis.io/alpine/|latest-stable/main/|"
  "Yazd University|http://mirror.yazd.ac.ir/alpine/|latest-stable/main/|"
  "Shiraz University|http://mirror.shirazu.ac.ir/alpine/|latest-stable/main/|"
)

DOCKER_REGISTRIES=(
  "Docker Hub|https://registry-1.docker.io/v2/|library/alpine/manifests/latest|200"
  "Iran Asis|https://docker.asis.io/v2/|library/alpine/manifests/latest|200"
  "Arvan Cloud|https://docker.arvancloud.ir/v2/|library/alpine/manifests/latest|200"
  "Hamravesh|https://docker.hamravesh.com/v2/|library/alpine/manifests/latest|200"
)

detect_os() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo "$ID"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  elif [[ -f /etc/redhat-release ]]; then
    echo "rhel"
  elif [[ -f /etc/arch-release ]]; then
    echo "arch"
  else
    echo "unknown"
  fi
}

backup_apt_sources() {
  local backup_dir="/etc/apt/sources.list.d.backup-$(date +%Y%m%d%H%M%S)"
  info "Backing up /etc/apt/sources.list* to $backup_dir"
  mkdir -p "$backup_dir"
  [[ -f /etc/apt/sources.list ]] && cp /etc/apt/sources.list "$backup_dir/"
  [[ -d /etc/apt/sources.list.d ]] && cp -r /etc/apt/sources.list.d "$backup_dir/"
  ok "Backup created at $backup_dir"
}

backup_yum_repos() {
  local backup_dir="/etc/yum.repos.d.backup-$(date +%Y%m%d%H%M%S)"
  info "Backing up /etc/yum.repos.d to $backup_dir"
  mkdir -p "$backup_dir"
  cp -r /etc/yum.repos.d/* "$backup_dir/" 2>/dev/null || true
  ok "Backup created at $backup_dir"
}

backup_pacman_mirrorlist() {
  local backup_file="/etc/pacman.d/mirrorlist.backup-$(date +%Y%m%d%H%M%S)"
  info "Backing up /etc/pacman.d/mirrorlist to $backup_file"
  cp /etc/pacman.d/mirrorlist "$backup_file"
  ok "Backup created at $backup_file"
}

restore_apt_sources() {
  local latest_backup
  latest_backup=$(ls -dt /etc/apt/sources.list.d.backup-* 2>/dev/null | head -n1)
  if [[ -z "$latest_backup" ]]; then
    err "No backup found to restore."
    exit 1
  fi
  info "Restoring from $latest_backup"
  [[ -f "$latest_backup/sources.list" ]] && cp "$latest_backup/sources.list" /etc/apt/sources.list
  [[ -d "$latest_backup/sources.list.d" ]] && cp -r "$latest_backup/sources.list.d" /etc/apt/
  ok "Restored APT sources from backup."
}

restore_yum_repos() {
  local latest_backup
  latest_backup=$(ls -dt /etc/yum.repos.d.backup-* 2>/dev/null | head -n1)
  if [[ -z "$latest_backup" ]]; then
    err "No backup found to restore."
    exit 1
  fi
  info "Restoring from $latest_backup"
  rm -rf /etc/yum.repos.d/*
  cp -r "$latest_backup"/* /etc/yum.repos.d/
  ok "Restored YUM repos from backup."
}

restore_pacman_mirrorlist() {
  local latest_backup
  latest_backup=$(ls -t /etc/pacman.d/mirrorlist.backup-* 2>/dev/null | head -n1)
  if [[ -z "$latest_backup" ]]; then
    err "No backup found to restore."
    exit 1
  fi
  info "Restoring from $latest_backup"
  cp "$latest_backup" /etc/pacman.d/mirrorlist
  ok "Restored Pacman mirrorlist from backup."
}

curl_http_code() {
  local url="$1"
  curl -fsS -o /dev/null --max-time 15 -w "%{http_code}" "$url" 2>/dev/null || echo "000"
}

curl_time_total_ms() {
  local url="$1"
  local t
  t="$(curl -fsS -o /dev/null --max-time 15 -w "%{time_total}" "$url" 2>/dev/null || echo "99.999")"
  awk -v t="$t" 'BEGIN{ printf "%.0f", (t*1000) }'
}

ping_time_ms() {
  local host="$1"
  local t
  t="$(ping -c 1 -W 2 "$host" 2>/dev/null | grep -oP 'time=\K[0-9.]+' | head -n1 || echo "9999")"
  awk -v t="$t" 'BEGIN{ printf "%.0f", t }'
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

  info "Testing: $url"

  local code
  code="$(curl_http_code "$url")"

  info "Got HTTP code: $code"

  if [[ -n "$expect" && "$code" != "$expect" ]]; then
    warn "Expected $expect but got $code for $url"
    echo "999999 $code $url"
    return
  fi

  if [[ "$code" != "200" && "$code" != "301" && "$code" != "302" ]]; then
    warn "Non-success code $code for $url"
    echo "999999 $code $url"
    return
  fi

  local curl_ms ping_ms host
  curl_ms="$(curl_time_total_ms "$url")"

  host="$(echo "$base" | sed -E 's|^https?://([^/]+).*|\1|')"
  ping_ms="$(ping_time_ms "$host")"

  local score
  score=$(( curl_ms + ping_ms ))

  echo "$score $code $url"
}

rank_mirrors() {
  local -n mirror_arr="$1"
  local -a results=()

  for item in "${mirror_arr[@]}"; do
    IFS='|' read -r name base probe expect <<<"$item"
    local score code url
    IFS=' ' read -r score code url < <(score_mirror "$base" "$probe" "$expect")
    results+=("$score|$code|$name|$base|$url")
  done

  printf '%s\n' "${results[@]}" | sort -t'|' -k1 -n
}

top_n_mirrors() {
  local -n mirror_arr="$1"
  local n="$2"
  rank_mirrors mirror_arr | head -n "$n"
}

reachable_mirrors() {
  local -n mirror_arr="$1"
  local reachables=()

  for item in "${mirror_arr[@]}"; do
    IFS='|' read -r _ base probe expect <<<"$item"
    local score code url
    IFS=' ' read -r score code url < <(score_mirror "$base" "$probe" "$expect")
    if (( score < 999999 )); then
      reachables+=("$base")
    fi
  done

  if [[ ${#reachables[@]} -eq 0 ]]; then
    warn "No reachable mirrors found!"
    return 1
  fi

  printf '%s\n' "${reachables[@]}"
}

write_apt_sources_for_ubuntu_debian_top() {
  local codename
  codename="$(lsb_release -sc 2>/dev/null || grep -Po '(?<=VERSION_CODENAME=)\w+' /etc/os-release)"
  [[ -z "$codename" ]] && err "Could not detect Ubuntu/Debian codename." && exit 1

  local -n mirror_arr="$1"
  local n="$2"
  local dest="/etc/apt/sources.list"

  local -a top_results
  mapfile -t top_results < <(top_n_mirrors mirror_arr "$n")

  echo "# Generated by mirrorgpt.sh (top $n mode) $(date)" > "$dest"

  for line in "${top_results[@]}"; do
    IFS='|' read -r score code name base url <<<"$line"

    if [[ "$name" =~ Security ]]; then
      echo "deb ${base} ${codename}-security main restricted universe multiverse" >> "$dest"
    else
      echo "deb ${base} ${codename} main restricted universe multiverse" >> "$dest"
    fi
    echo "# $name [score=$score, code=$code]" >> "$dest"
  done

  ok "Updated /etc/apt/sources.list with top $n mirrors."
}

write_apt_sources_for_ubuntu_debian_reachable() {
  local codename
  codename="$(lsb_release -sc 2>/dev/null || grep -Po '(?<=VERSION_CODENAME=)\w+' /etc/os-release)"
  [[ -z "$codename" ]] && err "Could not detect Ubuntu/Debian codename." && exit 1

  local -n mirror_arr="$1"
  local -n reach_list="$2"
  local dest="/etc/apt/sources.list"

  local reach_str=" "
  for r in "${reach_list[@]}"; do
    reach_str+="$r "
  done

  echo "# Generated by mirrorgpt.sh (reachable only mode) $(date)" > "$dest"

  for item in "${mirror_arr[@]}"; do
    IFS='|' read -r name base _ _ <<<"$item"

    if [[ "$reach_str" == *" $base "* ]]; then
      if [[ "$name" =~ Security ]]; then
        echo "deb ${base} ${codename}-security main restricted universe multiverse" >> "$dest"
      else
        echo "deb ${base} ${codename} main restricted universe multiverse" >> "$dest"
      fi
      echo "# $name [reachable]" >> "$dest"
    else
      if [[ "$name" =~ Security ]]; then
        echo "# deb ${base} ${codename}-security main restricted universe multiverse" >> "$dest"
      else
        echo "# deb ${base} ${codename} main restricted universe multiverse" >> "$dest"
      fi
      echo "# $name [FAILED]" >> "$dest"
    fi
  done

  ok "Updated /etc/apt/sources.list with only reachable mirrors active."
}

write_pacman_mirrorlist_top() {
  local -n mirror_arr="$1"
  local n="$2"
  local dest="/etc/pacman.d/mirrorlist"

  local -a top_results
  mapfile -t top_results < <(top_n_mirrors mirror_arr "$n")

  echo "# Generated by mirrorgpt.sh (top $n mode) $(date)" > "$dest"

  for line in "${top_results[@]}"; do
    IFS='|' read -r score code name base url <<<"$line"
    echo "Server = ${base}\$repo/os/\$arch" >> "$dest"
    echo "# $name [score=$score, code=$code]" >> "$dest"
  done

  ok "Updated /etc/pacman.d/mirrorlist with top $n mirrors."
}

write_pacman_mirrorlist_reachable() {
  local -n mirror_arr="$1"
  local -n reach_list="$2"
  local dest="/etc/pacman.d/mirrorlist"

  local reach_str=" "
  for r in "${reach_list[@]}"; do
    reach_str+="$r "
  done

  echo "# Generated by mirrorgpt.sh (reachable only mode) $(date)" > "$dest"

  for item in "${mirror_arr[@]}"; do
    IFS='|' read -r name base _ _ <<<"$item"

    if [[ "$reach_str" == *" $base "* ]]; then
      echo "Server = ${base}\$repo/os/\$arch" >> "$dest"
      echo "# $name [reachable]" >> "$dest"
    else
      echo "# Server = ${base}\$repo/os/\$arch" >> "$dest"
      echo "# $name [FAILED]" >> "$dest"
    fi
  done

  ok "Updated /etc/pacman.d/mirrorlist with only reachable mirrors active."
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --backup              Backup current repository configuration
  --restore             Restore from latest backup
  --rank                Rank all mirrors by speed
  --top N               Update sources with top N fastest mirrors (default: 3)
  --reachable           Update sources with all reachable mirrors
  --help                Show this help message

Examples:
  $0 --backup
  $0 --rank
  $0 --top 5
  $0 --reachable
  $0 --restore
EOF
}

main() {
  local mode=""
  local top_count=3

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backup)
        mode="backup"
        shift
        ;;
      --restore)
        mode="restore"
        shift
        ;;
      --rank)
        mode="rank"
        shift
        ;;
      --top)
        mode="top"
        top_count="${2:-3}"
        shift 2
        ;;
      --reachable)
        mode="reachable"
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$mode" ]]; then
    usage
    exit 1
  fi

  local os_type
  os_type="$(detect_os)"
  info "Detected OS: $os_type"

  case "$mode" in
    backup)
      case "$os_type" in
        ubuntu|debian)
          backup_apt_sources
          ;;
        rhel|centos|fedora)
          backup_yum_repos
          ;;
        arch|manjaro)
          backup_pacman_mirrorlist
          ;;
        *)
          err "Unsupported OS for backup: $os_type"
          exit 1
          ;;
      esac
      ;;

    restore)
      case "$os_type" in
        ubuntu|debian)
          restore_apt_sources
          ;;
        rhel|centos|fedora)
          restore_yum_repos
          ;;
        arch|manjaro)
          restore_pacman_mirrorlist
          ;;
        *)
          err "Unsupported OS for restore: $os_type"
          exit 1
          ;;
      esac
      ;;

    rank)
      case "$os_type" in
        ubuntu)
          info "Ranking Ubuntu mirrors..."
          rank_mirrors UBUNTU_MIRRORS
          ;;
        debian)
          info "Ranking Debian mirrors..."
          rank_mirrors DEBIAN_MIRRORS
          ;;
        arch|manjaro)
          info "Ranking Arch mirrors..."
          rank_mirrors ARCH_MIRRORS
          ;;
        *)
          err "Unsupported OS for ranking: $os_type"
          exit 1
          ;;
      esac
      ;;

    top)
      backup_apt_sources 2>/dev/null || backup_pacman_mirrorlist 2>/dev/null || true

      case "$os_type" in
        ubuntu)
          info "Selecting top $top_count Ubuntu mirrors..."
          write_apt_sources_for_ubuntu_debian_top UBUNTU_MIRRORS "$top_count"
          ;;
        debian)
          info "Selecting top $top_count Debian mirrors..."
          write_apt_sources_for_ubuntu_debian_top DEBIAN_MIRRORS "$top_count"
          ;;
        arch|manjaro)
          info "Selecting top $top_count Arch mirrors..."
          write_pacman_mirrorlist_top ARCH_MIRRORS "$top_count"
          ;;
        *)
          err "Unsupported OS for top mode: $os_type"
          exit 1
          ;;
      esac
      ;;

    reachable)
      backup_apt_sources 2>/dev/null || backup_pacman_mirrorlist 2>/dev/null || true

      case "$os_type" in
        ubuntu)
          info "Finding reachable Ubuntu mirrors..."
          local -a reach_bases
          mapfile -t reach_bases < <(reachable_mirrors UBUNTU_MIRRORS)
          if [[ ${#reach_bases[@]} -eq 0 ]]; then
            err "No reachable mirrors found. Aborting."
            exit 1
          fi
          write_apt_sources_for_ubuntu_debian_reachable UBUNTU_MIRRORS reach_bases
          ;;
        debian)
          info "Finding reachable Debian mirrors..."
          local -a reach_bases
          mapfile -t reach_bases < <(reachable_mirrors DEBIAN_MIRRORS)
          if [[ ${#reach_bases[@]} -eq 0 ]]; then
            err "No reachable mirrors found. Aborting."
            exit 1
          fi
          write_apt_sources_for_ubuntu_debian_reachable DEBIAN_MIRRORS reach_bases
          ;;
        arch|manjaro)
          info "Finding reachable Arch mirrors..."
          local -a reach_bases
          mapfile -t reach_bases < <(reachable_mirrors ARCH_MIRRORS)
          if [[ ${#reach_bases[@]} -eq 0 ]]; then
            err "No reachable mirrors found. Aborting."
            exit 1
          fi
          write_pacman_mirrorlist_reachable ARCH_MIRRORS reach_bases
          ;;
        *)
          err "Unsupported OS for reachable mode: $os_type"
          exit 1
          ;;
      esac
      ;;
  esac
}

main "$@"
