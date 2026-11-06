-- Shared by every machine, Omarchy included (chezmoi: dot_config/nvim/lua/plugins/shared.lua).
-- On Omarchy this is the only Neovim file chezmoi writes; Omarchy's own files are left alone.
return {
  -- Line endings: the script Vim also loads warns when a CRLF or mixed file is opened and adds :Lf, which
  -- saves the file with LF. Neovim does not read ~/.vim, so it is sourced here, at startup (lualine's init runs before
  -- the first buffer is read). lualine shows its label (CRLF or mixed, nothing for LF) first in section x.
  {
    "nvim-lualine/lualine.nvim",
    init = function()
      local line_endings = vim.fn.expand("~/.vim/plugin/line-endings.vim")
      if vim.fn.filereadable(line_endings) == 1 then
        vim.cmd.source(line_endings)
      end
    end,
    opts = function(_, opts)
      opts.sections = opts.sections or {}
      opts.sections.lualine_x = opts.sections.lualine_x or {}
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return vim.b.line_endings or ""
        end,
        cond = function()
          return (vim.b.line_endings or "") ~= ""
        end,
      })
    end,
  },

  -- Go parsers. LazyVim's default list already has python but not go, and LazyVim does not install parsers on
  -- demand. opts_extend merges this list with the default one. The first launch compiles them (needs tree-sitter-cli).
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "go", "gomod", "gowork", "gosum" } },
  },
}
