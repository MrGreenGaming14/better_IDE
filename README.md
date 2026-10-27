# bide

A personal, offline-portable IDE based on Neovim and LazyVim, integrated with the [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`) AI agent.

Layout:
- **Center:** Code editing area
- **Left:** File explorer (`<M-e>`)
- **Right:** AI terminal panel running `omp` (`<M-o>` or `<leader>aa`)
- **Bottom:** Shell terminal (`<C-/>`)

---

## Requirements

### Target Machine Requirements
- **OS & Architecture:** Linux x86_64 with glibc ≥ 2.39.
- **Dependencies:** `git`. A C compiler is **not** required on the offline machine (all parsers, tools, and language servers are pre-compiled and vendored).
- **Terminal Font:** Set your terminal font to **JetBrainsMono Nerd Font** (bundled fonts are installed by `install.sh`).
- **AI Agent:** `omp` (oh-my-pi) is not bundled and must be installed separately on any machine where the AI panel is used.

### What Lives Outside the Repo
bide is designed so all configuration, vendored tools, parsers, and plugins remain self-contained inside the repository root (`BIDE_ROOT`). Only three paths outside the repository are touched:
1. `~/.config/bide` — symlink pointing to `$BIDE_ROOT/nvim`
2. `~/.local/bin/bide` — symlink pointing to `$BIDE_ROOT/bin/bide`
3. `~/.local/share/fonts/bide/` — directory containing copied JetBrainsMono Nerd Font TTF files

Ephemeral Neovim caches and state (`~/.local/state/bide` and `~/.cache/bide`: shada, undo history, logs) are managed dynamically by Neovim at runtime and are not bundled.

---

## Setup & Workflows

### Online Setup (Connected Machine)
To set up from source and vendor all dependencies:
```bash
./install.sh
scripts/vendor.sh
```
`scripts/vendor.sh` downloads pinned tools (Neovim v0.12.6, ripgrep, fd, lazygit, tree-sitter, asm-lsp, Node.js, fonts), syncs Lazy plugins, and installs Mason packages and Tree-sitter parsers into `vendor/`.

After setup or updates, commit the lockfiles to git:
```bash
git add nvim/lazy-lock.json nvim/lazyvim.json
git commit -m "update vendor lockfiles"
```

### Building & Publishing the Offline Bundle
To package the offline distribution tarball:
```bash
scripts/bundle.sh
```
`scripts/bundle.sh` verifies that the git tree is clean, packages git-tracked files together with `vendor/` into `dist/bide-offline-linux-x86_64.tar.gz`, and generates a corresponding `.sha256` checksum.

Upload `dist/bide-offline-linux-x86_64.tar.gz` as a GitHub Release asset using GitHub's web interface (`gh` CLI is not required).

### Offline Installation (Target Machine)
On a machine with no internet connection:
```bash
tar xzf bide-offline-linux-x86_64.tar.gz
cd bide
./install.sh --offline
```
`install.sh` automatically relocates vendored paths (rewriting virtual environment shebangs and configuration if extracted to a different directory), creates the config/launcher symlinks, installs the Nerd Font, and writes `.offline`.

Ensure `~/.local/bin` is in your `$PATH`, then launch bide:
```bash
bide [file ...]
```

### Updating Plugins
To update plugins on an online machine:
1. Inside bide, run `:Lazy update`
2. Run `scripts/vendor.sh` to update vendored packages and stamps
3. Commit the updated `nvim/lazy-lock.json`
4. Rebuild the offline bundle with `scripts/bundle.sh`

---

## Keymaps

| Keymap | Mode | Action |
|---|---|---|
| `<M-o>` | `n`, `t` | Toggle `omp` panel (right) |
| `<leader>aa` | `n` | Toggle `omp` panel (right) |
| `<M-e>` | `n`, `t` | Toggle explorer (left) |
| `<C-/>` | `n`, `t` | Bottom shell terminal (LazyVim default) |
| `<M-w>` | `t` | Leave terminal mode + window command prefix (then `h`/`j`/`k`/`l` to switch windows) |
| `<leader>af` | `n` | Add current file to `omp` composer (as `@file`) |
| `<leader>as` | `x` | Add visual selection to `omp` composer with line numbers and markdown code block |
| `<leader>aF` | `n` | Pick any files under `~` via picker (`<Tab>` multi-select) to add to `omp` |
| `<leader>aq` | `n` | Review `omp`'s last turn (quickfix list) |
| `A` | explorer | Add selected files/dirs in explorer to `omp` composer (explorer remains open) |

---

## omp Integration & Review Workflow

### Live Reload of Agent Edits
- When `omp` (or anything else) changes a file on disk, its open buffer reloads immediately without changing focus. This includes files that did not exist yet when you opened them (e.g. `bide new.c` before `omp` writes it) and files that are deleted and recreated.
- Undo history is preserved across reloads: pressing `u` in a clean buffer immediately reverts the external change.
- Unsaved buffers are **never** silently overwritten. If a file changes on disk while you have unsaved modifications, bide displays a warning notification (`:e!` loads disk version, `:w!` keeps yours).
- Edits made via shell or evaluation commands (e.g. `sed -i` or codegen scripts) reload live through the file watcher, but do not appear in the turn list.

### Reviewing and Rejecting Changes
- **Review:** When an agent turn finishes, bide records the modified files. Press `<leader>aq` to open a quickfix list titled `omp: last turn (N file[s])` and jump between modified locations.
- **Reject buffer edits:** Press `u` in any buffer open at change time.
- **Reject git hunks:** Use LazyVim's gitsigns keybindings:
  - `]h` / `[h`: Jump to next / previous change hunk
  - `<leader>ghp`: Preview change hunk diff
  - `<leader>ghr`: Reset (reject) current hunk
  - `<leader>ghR`: Reset (reject) entire buffer to git HEAD

### `nvim_context` Tool
`omp` is registered with an `nvim_context` tool via `omp/bide-bridge.ts`. Whenever the agent needs editor context (such as when asked about "this file", "here", "the selection", or "this error"), it queries Neovim via RPC to inspect:
- Current active file path, cursor position (line and 1-based column), and modified state
- Active visual selection (start line, end line, and selected text)
- List of open buffers
- Active LSP diagnostics across open buffers (severity, location, and message)

---

## Language Support Notes

- **Python:** Language server (`pyright`) and linter/formatter (`ruff`) are vendored.
- **Rust:** `rust-analyzer` is vendored. For standard library analysis, ensure a Rust toolchain with `rust-src` is present on the machine (`rustup component add rust-src`).
- **C / C++:** `clangd` and `codelldb` are vendored.
- **Assembly (x86-64, ARM, NASM):** `asm-lsp` is vendored in `vendor/bin`. Architecture is configured per-project: run `asm-lsp gen-config` in your project root to generate `.asm-lsp.toml` (e.g. `instruction_set = "x86-64"` or `"arm64"`).
