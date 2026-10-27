#!/usr/bin/env bash
# ONLINE: download pinned tools and install plugins, LSPs and parsers into vendor/.
set -euo pipefail

BIDE_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=versions.env
source "$BIDE_ROOT/scripts/versions.env"

cd "$BIDE_ROOT"
mkdir -p vendor/bin vendor/.stamps

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { # fetch <url> <out>
  echo "bide vendor: downloading $1"
  curl -fL --retry 3 -o "$2" "$1"
}

# step <name> <version> <fn>: run fn unless the stamp exists; stamp on success.
step() {
  local stamp="vendor/.stamps/$1-$2"
  if [[ -e "$stamp" ]]; then
    echo "bide vendor: $1 $2 already present"
    return
  fi
  local work="$tmp/$1"
  rm -rf "$work" && mkdir -p "$work"
  "$3" "$work"
  touch "$stamp"
}

get_nvim() {
  fetch "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" "$1/a.tgz"
  rm -rf vendor/nvim && mkdir -p vendor/nvim
  tar -xzf "$1/a.tgz" -C vendor/nvim --strip-components=1
}

# install_bin <archive-dir> <name>: find the named executable in an extracted archive.
install_bin() {
  local f
  f="$(find "$1" -type f -name "$2" | head -n1)"
  [[ -n "$f" ]] || { echo "bide vendor: $2 not found in archive" >&2; exit 1; }
  install -m 0755 "$f" "vendor/bin/$2"
}

get_rg() {
  fetch "https://github.com/BurntSushi/ripgrep/releases/download/$RG_VERSION/ripgrep-$RG_VERSION-x86_64-unknown-linux-musl.tar.gz" "$1/a.tgz"
  tar -xzf "$1/a.tgz" -C "$1"
  install_bin "$1" rg
}

get_fd() {
  fetch "https://github.com/sharkdp/fd/releases/download/$FD_VERSION/fd-$FD_VERSION-x86_64-unknown-linux-musl.tar.gz" "$1/a.tgz"
  tar -xzf "$1/a.tgz" -C "$1"
  install_bin "$1" fd
}

get_lazygit() {
  fetch "https://github.com/jesseduffield/lazygit/releases/download/v$LAZYGIT_VERSION/lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz" "$1/a.tgz"
  tar -xzf "$1/a.tgz" -C "$1"
  install_bin "$1" lazygit
}

get_treesitter() {
  fetch "https://github.com/tree-sitter/tree-sitter/releases/download/$TREESITTER_VERSION/tree-sitter-linux-x64.gz" "$1/ts.gz"
  gunzip -c "$1/ts.gz" > "$1/tree-sitter"
  install -m 0755 "$1/tree-sitter" vendor/bin/tree-sitter
}

get_asm_lsp() {
  fetch "https://github.com/bergercookie/asm-lsp/releases/download/$ASM_LSP_VERSION/asm-lsp-x86_64-unknown-linux-gnu.tar.gz" "$1/a.tgz"
  tar -xzf "$1/a.tgz" -C "$1"
  install_bin "$1" asm-lsp
}

get_node() {
  fetch "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.xz" "$1/a.txz"
  rm -rf vendor/node && mkdir -p vendor/node
  tar -xJf "$1/a.txz" -C vendor/node --strip-components=1
}

get_font() {
  fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERDFONT_VERSION/JetBrainsMono.tar.xz" "$1/a.txz"
  rm -rf vendor/fonts/JetBrainsMono && mkdir -p vendor/fonts/JetBrainsMono
  tar -xJf "$1/a.txz" -C vendor/fonts/JetBrainsMono
}

step nvim "$NVIM_VERSION" get_nvim
step rg "$RG_VERSION" get_rg
step fd "$FD_VERSION" get_fd
step lazygit "$LAZYGIT_VERSION" get_lazygit
step tree-sitter "$TREESITTER_VERSION" get_treesitter
step asm-lsp "$ASM_LSP_VERSION" get_asm_lsp
step node "$NODE_VERSION" get_node
step font "$NERDFONT_VERSION" get_font

printf '%s' "$BIDE_ROOT" > vendor/.build-root
"$BIDE_ROOT/install.sh"

if [[ -f nvim/lazy-lock.json ]]; then
  bin/bide --headless "+Lazy! restore" +qa
else
  bin/bide --headless "+Lazy! sync" +qa
fi

bin/bide --headless "+lua require('bide.vendor').sync()"
