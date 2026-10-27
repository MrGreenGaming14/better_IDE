-- Languages: Python, Rust, C/C++ (via LazyVim extras) plus x86-64/ARM assembly.
-- Assembly target is chosen per project: `asm-lsp gen-config` writes .asm-lsp.toml.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "asm", "nasm", "objdump", "c", "cpp", "rust", "ron", "python", "toml" } },
  },
  {
    "mason-org/mason.nvim",
    -- the rust extra only checks executable("rust-analyzer"); bundle it for offline use
    opts = { ensure_installed = { "rust-analyzer" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- mason's asm-lsp is pkg:cargo; the binary is vendored into vendor/bin instead
        asm_lsp = { mason = false, filetypes = { "asm", "nasm", "vmasm" } },
      },
    },
  },
}
