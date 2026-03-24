#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Arch install helper for this repo.

What it does:
  1) Installs packages (pacman + optional AUR helper)
  2) Symlinks dotfiles into $HOME (via stow)

Usage:
  ./install-arch.sh
  ./install-arch.sh --dry-run
  ./install-arch.sh --no-packages
  ./install-arch.sh --no-stow

Environment:
  AUR_HELPER=paru|yay    (optional; autodetected if unset)
  STOW_TARGET=/path      (optional; defaults to $HOME)
EOF
}

dry_run=false
do_packages=true
do_stow=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) dry_run=true; shift ;;
    --no-packages) do_packages=false; shift ;;
    --no-stow) do_stow=false; shift ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
fi
if [[ "${ID_LIKE:-} ${ID:-}" != *"arch"* ]]; then
  echo "This installer is for Arch-based distros (ID=$ID, ID_LIKE=${ID_LIKE:-})." >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

stow_target="${STOW_TARGET:-$HOME}"

run() {
  if $dry_run; then
    printf '[dry-run] %q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

upsert_ini_kv() {
  # Minimal INI editor: ensure a section exists and set key=value within it.
  # Only supports single [Section] blocks; good enough for GTK settings.ini.
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"

  run mkdir -p "$(dirname -- "$file")"
  if [[ ! -e "$file" ]]; then
    if $dry_run; then return 0; fi
    printf '%s\n' "[$section]" "$key=$value" "" >"$file"
    return 0
  fi

  if $dry_run; then
    echo "[dry-run] set $file [$section] $key=$value"
    return 0
  fi

  awk -v section="[$section]" -v key="$key" -v value="$value" '
    BEGIN { in_section=0; section_found=0; key_set=0 }
    $0 == section {
      in_section=1; section_found=1; print; next
    }
    /^\[/ {
      if (in_section && !key_set) { print key "=" value; key_set=1 }
      in_section=0; print; next
    }
    {
      if (in_section && $0 ~ ("^" key "=")) { print key "=" value; key_set=1; next }
      print
    }
    END {
      if (!section_found) {
        # Add a blank line before the new section if the file does not already end with one.
        if (NR > 0) print ""
        print section
        print key "=" value
        print ""
      }
      if (in_section && !key_set) {
        print key "=" value
        print ""
      }
    }
  ' "$file" >"${file}.tmp.$$"
  mv -f "${file}.tmp.$$" "$file"
}

apply_dark_theme_best_effort() {
  echo "Setting system theme preference to dark (best-effort)..."

  # GTK: works across most desktops/WMs without needing a running D-Bus session.
  upsert_ini_kv "$stow_target/.config/gtk-3.0/settings.ini" "Settings" "gtk-application-prefer-dark-theme" "1"
  upsert_ini_kv "$stow_target/.config/gtk-4.0/settings.ini" "Settings" "gtk-application-prefer-dark-theme" "1"
  # Force a dark GTK3 theme for apps like Nautilus that may not honor prefer-dark in non-GNOME sessions.
  upsert_ini_kv "$stow_target/.config/gtk-3.0/settings.ini" "Settings" "gtk-theme-name" "Adwaita-dark"

  kde_colorscheme_exists() {
    local name="$1"
    [[ -r "$stow_target/.local/share/color-schemes/${name}.colors" ]] && return 0
    [[ -r "/usr/share/color-schemes/${name}.colors" ]] && return 0
    return 1
  }

  # KDE/Qt apps: set a dark-ish color scheme. Prefer requested scheme if present; fall back to BreezeDark.
  # Note: writing a non-existent scheme (e.g. "Black" on a system without it) often makes KDE apps fall back
  # to the default Breeze (light), which is confusing.
  local requested_kde_scheme="${KDE_COLOR_SCHEME:-BreezeDark}"
  local kde_scheme=""
  if kde_colorscheme_exists "$requested_kde_scheme"; then
    kde_scheme="$requested_kde_scheme"
  elif kde_colorscheme_exists BreezeDark; then
    kde_scheme="BreezeDark"
  else
    kde_scheme=""
  fi
  if have_cmd plasma-apply-colorscheme; then
    [[ -n "$kde_scheme" ]] && XDG_CONFIG_HOME="$stow_target/.config" run plasma-apply-colorscheme "$kde_scheme" >/dev/null 2>&1 || true
  fi
  if have_cmd kwriteconfig6; then
    [[ -n "$kde_scheme" ]] && XDG_CONFIG_HOME="$stow_target/.config" run kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$kde_scheme" >/dev/null 2>&1 || true
  elif have_cmd kwriteconfig5; then
    [[ -n "$kde_scheme" ]] && XDG_CONFIG_HOME="$stow_target/.config" run kwriteconfig5 --file kdeglobals --group General --key ColorScheme "$kde_scheme" >/dev/null 2>&1 || true
  else
    [[ -n "$kde_scheme" ]] && upsert_ini_kv "$stow_target/.config/kdeglobals" "General" "ColorScheme" "$kde_scheme"
  fi

  # GNOME/GTK apps via gsettings, if available (requires a user session bus).
  if have_cmd gsettings; then
    run gsettings set org.gnome.desktop.interface color-scheme prefer-dark >/dev/null 2>&1 || true
    run gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark >/dev/null 2>&1 || true
  fi
}

backup_if_conflict() {
  local target="$1"
  # If the target exists and is not a symlink, stow will refuse. Back it up.
  if [[ -e "$target" && ! -L "$target" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    run mv -f "$target" "${target}.bak.${ts}"
  fi
}

pick_aur_helper() {
  if [[ -n "${AUR_HELPER:-}" ]]; then
    echo "$AUR_HELPER"
    return 0
  fi
  if have_cmd paru; then
    echo paru
    return 0
  fi
  if have_cmd yay; then
    echo yay
    return 0
  fi
  echo ""
}

pacman_install() {
  local -a pkgs=("$@")
  if [[ ${#pkgs[@]} -eq 0 ]]; then return 0; fi
  if ! have_cmd pacman; then
    echo "pacman not found." >&2
    exit 2
  fi

  local -a missing=()
  local p
  for p in "${pkgs[@]}"; do
    if pacman -Qi "$p" >/dev/null 2>&1; then
      continue
    fi
    missing+=("$p")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "pacman: all requested packages already installed."
    return 0
  fi

  if $dry_run; then
    run sudo pacman -S --needed --noconfirm "${missing[@]}"
  else
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
}

aur_install() {
  local helper="$1"
  shift
  local -a pkgs=("$@")
  if [[ -z "$helper" || ${#pkgs[@]} -eq 0 ]]; then return 0; fi

  if ! have_cmd pacman; then
    echo "pacman not found." >&2
    exit 2
  fi

  local -a missing=()
  local p
  for p in "${pkgs[@]}"; do
    if pacman -Qi "$p" >/dev/null 2>&1; then
      continue
    fi
    missing+=("$p")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "AUR: all requested packages already installed."
    return 0
  fi

  case "$helper" in
    paru) run paru -S --needed --noconfirm "${missing[@]}" ;;
    yay)  run yay  -S --needed --noconfirm "${missing[@]}" ;;
    *)
      echo "Unsupported AUR helper: $helper" >&2
      exit 2
      ;;
  esac
}

aur_install_optional() {
  local helper="$1"
  shift
  local -a pkgs=("$@")
  if [[ -z "$helper" || ${#pkgs[@]} -eq 0 ]]; then return 0; fi

  if ! aur_install "$helper" "${pkgs[@]}"; then
    echo "Warning: optional AUR install failed: ${pkgs[*]}" >&2
    return 0
  fi
}

if $do_packages; then
  echo "Installing dependencies..."

  # Repo packages (best-effort; names may vary by setup)
  pacman_install \
    stow \
    hyprland \
    kitty \
    dolphin \
    grim \
    slurp \
    wl-clipboard \
    hyprpicker \
    swaync \
    libnotify \
    bibata-cursor-theme \
    wlsunset \
    wf-recorder \
    rofi-wayland \
    cliphist \
    hyprlock \
    hypridle \
    ttf-nerd-fonts-symbols \
    swww \
    jq \
    imagemagick \
    libappindicator-gtk3

  # GNOME/GTK apps (e.g. Nautilus) in non-GNOME sessions: portals help propagate dark preference.
  pacman_install \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-wlr

  # AUR packages (optional; if you already have them, nothing happens)
  aur_helper="$(pick_aur_helper)"
  if [[ -z "$aur_helper" ]]; then
    echo "No AUR helper found (paru/yay). Skipping AUR packages." >&2
    echo "If you need them: install paru or yay, then re-run." >&2
  else
    aur_install "$aur_helper" \
      quickshell-git \
      matugen

    # Optional (font family used by the bar if available)
    aur_install_optional "$aur_helper" \
      ttf-google-sans
  fi
fi

if $do_stow; then
  echo "Symlinking dotfiles into: $stow_target"
  run mkdir -p "$stow_target"

  apply_dark_theme_best_effort

  # Default file manager (XDG): Nautilus
  if have_cmd xdg-mime; then
    run xdg-mime default org.gnome.Nautilus.desktop inode/directory >/dev/null 2>&1 || true
    run xdg-mime default org.gnome.Nautilus.desktop application/x-gnome-saved-search >/dev/null 2>&1 || true
  fi

  # Ensure helper scripts are executable after symlinking.
  run chmod +x "$repo_root/dotfiles/.local/bin/eink-wallpaper"
  run chmod +x "$repo_root/dotfiles/.local/bin/eink-launcher"
  run chmod +x "$repo_root/dotfiles/.local/bin/eink-hypridle-apply"
  run chmod +x "$repo_root/dotfiles/.local/bin/eink-notify"
  run chmod +x "$repo_root/dotfiles/.local/bin/eink-ws"
  run chmod +x "$repo_root/dotfiles/.local/bin/discord-tray"
  # Quickshell QML files are loaded directly; no chmod needed.

  if ! have_cmd stow; then
    echo "stow not found. Install it or re-run without --no-packages." >&2
    exit 2
  fi

  # Backup known conflict-prone files (stow refuses to overwrite real files).
  backup_if_conflict "$stow_target/.config/hypr/hyprlock.conf"

  run stow -t "$stow_target" dotfiles
  run chmod +x "$stow_target/.local/bin/eink-wallpaper" || true
  run chmod +x "$stow_target/.local/bin/eink-launcher" || true
  run chmod +x "$stow_target/.local/bin/eink-hypridle-apply" || true
fi

echo "Done."
