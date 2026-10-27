#!/usr/bin/env bash
# bide installer: relocates vendored paths, links config + launcher, installs fonts.
# Usage: ./install.sh [--offline]
set -euo pipefail

BIDE_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
offline=0
for arg in "$@"; do
  case "$arg" in
    --offline) offline=1 ;;
    *) echo "usage: $0 [--offline]" >&2; exit 2 ;;
  esac
done

cd "$BIDE_ROOT"

# 1. Relocation: rewrite absolute paths baked in at vendor time (mason venvs, shebangs).
if [[ -f vendor/.build-root ]]; then
  OLD="$(cat vendor/.build-root)"
  if [[ -n "$OLD" && "$OLD" != "$BIDE_ROOT" ]]; then
    echo "bide: relocating vendor/ from $OLD to $BIDE_ROOT"
    dirs=()
    for d in vendor/mason vendor/node; do [[ -d "$d" ]] && dirs+=("$d"); done
    if ((${#dirs[@]})); then
      grep -rlIZ --fixed-strings "$OLD" "${dirs[@]}" | xargs -0 -r sed -i "s|$OLD|$BIDE_ROOT|g"
    fi
    while IFS= read -r -d '' link; do
      target="$(readlink "$link")"
      if [[ "$target" == "$OLD/"* ]]; then
        ln -sfn "$BIDE_ROOT/${target#"$OLD/"}" "$link"
      fi
    done < <(find vendor -type l -print0)
    printf '%s' "$BIDE_ROOT" > vendor/.build-root
  fi
fi

# 2. Symlinks.
link() { # link <dest> <target>
  local dest="$1" target="$2"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ ! -L "$dest" || "$(readlink -f "$dest")" != "$(readlink -f "$target")" ]]; then
      echo "bide: ${dest/#$HOME/\~} exists and is not this checkout; move it away first" >&2
      exit 1
    fi
  fi
  ln -sfn "$target" "$dest"
}
mkdir -p "$HOME/.config" "$HOME/.local/bin"
link "$HOME/.config/bide" "$BIDE_ROOT/nvim"
link "$HOME/.local/bin/bide" "$BIDE_ROOT/bin/bide"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "bide: add ~/.local/bin to your PATH to run 'bide'" ;;
esac

# 3. Fonts.
if [[ -d vendor/fonts/JetBrainsMono ]]; then
  mkdir -p "$HOME/.local/share/fonts/bide"
  cp -f vendor/fonts/JetBrainsMono/*.ttf "$HOME/.local/share/fonts/bide/"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f >/dev/null 2>&1 || true; fi
  echo 'Set your terminal font to "JetBrainsMono Nerd Font"'
fi

# 4. Offline marker.
if ((offline)); then
  touch "$BIDE_ROOT/.offline"
fi

echo "bide: installed from $BIDE_ROOT"
