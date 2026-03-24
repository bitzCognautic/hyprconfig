# eink dotfiles (Hyprland + Quickshell)

This repo contains a small set of dotfiles that recreates the centered “pill” top bar from `./inspo/` using **Quickshell**, with **dynamic colors generated from your wallpaper** (via `matugen`).

## What you get

- Quickshell top bar (time + workspaces + volume + Wi‑Fi SSID + battery pill)
- Dynamic colors driven by wallpaper (`matugen image ... -j hex`)
- Hyprland keybinds:
  - `SUPER + T` → `kitty`
  - `SUPER + Q` → close active window
  - `SUPER + E` → `nautilus`

## Install (stow-style layout)

These files are laid out to be used with `stow`:

### One-shot (Arch)

```bash
chmod +x ./install-arch.sh
./install-arch.sh
```

### Manual

```bash
cd /path/to/this/repo
stow -t "$HOME" dotfiles
```

Make the helper script executable:

```bash
chmod +x ~/.local/bin/eink-wallpaper
```

## Usage

Set a wallpaper (also regenerates theme):

```bash
eink-wallpaper /path/to/wallpaper.png
```

Restore last wallpaper on login (Hyprland `exec-once` calls this):

```bash
eink-wallpaper --restore
```
# hyprconfig
