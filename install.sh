#!/usr/bin/env bash
#
# Installs the ANDREI NITA setup on Omarchy:
#
#   --theme        the andrei-nita theme (colors, icons, wallpaper) and applies it
#   --lock         the lock screen, replacing Omarchy's built-in lock
#   --screensaver  the animated purple/pink screensaver with the ANDREI NITA text
#   --boot         the Plymouth disk-unlock screen (asks for sudo, rebuilds the boot image)
#   --all          all four
#
# With no flags, installs the theme, the lock screen and the screensaver.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
bin_dir="$HOME/.local/bin"
theme_name="andrei-nita"
backup_dir="$config/backups/andrei-nita-$(date +%Y%m%d-%H%M%S)-$$"

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

say() { printf '\033[35m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Moves an existing install aside instead of deleting it. Backups live outside
# the plugins/themes folders so Omarchy never discovers them as duplicates.
backup() {
  local path=$1
  [[ -e $path || -L $path ]] || return 0
  mkdir -p "$backup_dir"
  mv "$path" "$backup_dir/"
  echo "    previous copy saved to $backup_dir/$(basename "$path")"
}

# Copies a shell plugin in and enables it. Both plugins carry clonedFrom, so
# enabling one disables the Omarchy built-in it replaces and takes over its
# IPC target (`omarchy system lock` keeps working, for example).
install_plugin() {
  local src=$1 id
  id=$(basename "$src")
  mkdir -p "$config/plugins"
  backup "$config/plugins/$id"
  cp -r "$src" "$config/plugins/$id"

  omarchy-shell shell rescanPlugins >/dev/null
  local attempt
  for (( attempt = 0; attempt < 40; attempt++ )); do
    omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && break
    sleep 0.1
  done
  (( attempt < 40 )) || fail "the shell did not discover $id"
  omarchy plugin enable "$id" >/dev/null
}

# Service plugins stay loaded across hot reloads (so an open lock is never torn
# down), so a shell restart is what actually swaps them in.
restart_shell=0

install_theme() {
  say "Installing theme '$theme_name'"
  mkdir -p "$config/themes"
  backup "$config/themes/$theme_name"
  cp -r "$repo/theme/$theme_name" "$config/themes/$theme_name"
  omarchy theme set "$theme_name"
}

install_lock() {
  say "Installing lock screen"
  install_plugin "$repo/lockscreen/andrei.lock"
  restart_shell=1
  echo "    preview it safely with: omarchy-shell lock preview"
}

# Adds a menu override so System > Screensaver starts this screensaver too.
# Leaves the file alone if it already overrides that entry.
add_menu_override() {
  local menu="$config/extensions/omarchy-menu.jsonc"
  local entry='"system.screensaver": {"action":"andrei-launch-screensaver force"},'
  mkdir -p "$(dirname "$menu")"
  if [[ ! -f $menu ]]; then
    printf '{\n  %s\n}\n' "$entry" >"$menu"
    return
  fi
  grep -q '"system.screensaver"' "$menu" && return
  cp "$menu" "$menu.bak.$(date +%s)"
  python3 - "$menu" "$entry" <<'EOF'
import re, sys

path, entry = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read().rstrip()
if not text.endswith("}"):
    sys.exit("unexpected menu file layout; add the entry by hand")
body = text[:-1].rstrip()
# Previous entry needs a separating comma unless the object is still empty.
last = [l for l in body.splitlines() if l.strip() and not l.strip().startswith("//")][-1].rstrip()
if not last.endswith((",", "{")):
    body += ","
open(path, "w", encoding="utf-8").write(f"{body}\n\n  // ANDREI NITA screensaver\n  {entry}\n}}\n")
EOF
}

install_screensaver() {
  say "Installing screensaver"
  mkdir -p "$bin_dir" "$config/branding"
  install -m 755 "$repo/screensaver/andrei-screensaver" "$repo/screensaver/andrei-launch-screensaver" "$bin_dir/"
  if [[ -f $config/branding/screensaver.txt ]]; then
    cp "$config/branding/screensaver.txt" "$config/branding/screensaver.txt.bak.$(date +%s)"
  fi
  cp "$repo/screensaver/screensaver.txt" "$config/branding/screensaver.txt"
  install_plugin "$repo/screensaver/andrei.idle"
  add_menu_override
  restart_shell=1
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "    note: $bin_dir is not on your PATH; the screensaver needs it there" ;;
  esac
  echo "    try it now with: andrei-launch-screensaver force"
}

install_boot() {
  say "Installing Plymouth boot screen (needs sudo, rebuilds the boot image)"
  omarchy plymouth set '#000000' '#9d4edd' "$repo/boot/andrei-logo.png"
  echo "    shows on next boot; revert with: omarchy plymouth reset"
}

command -v omarchy >/dev/null || fail "this needs Omarchy (omarchy command not found)"

theme=0 lock=0 screensaver=0 boot=0
(( $# )) || { theme=1; lock=1; screensaver=1; }
while (( $# )); do
  case $1 in
    --theme) theme=1 ;;
    --lock) lock=1 ;;
    --screensaver) screensaver=1 ;;
    --boot) boot=1 ;;
    --all) theme=1; lock=1; screensaver=1; boot=1 ;;
    -h | --help) usage ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done

if (( theme )); then install_theme; fi
if (( lock )); then install_lock; fi
if (( screensaver )); then install_screensaver; fi
if (( restart_shell )); then
  say "Restarting the Omarchy shell"
  omarchy restart shell >/dev/null 2>&1 || true
fi
if (( boot )); then install_boot; fi
say "Done"
