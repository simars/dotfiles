-- Read the docs: https://www.lunarvim.org/docs/configuration
-- Example configs: https://github.com/LunarVim/starter.lvim
-- Video Tutorials: https://www.youtube.com/watch?v=sFA9kX-Ud_c&list=PLhoH5vyxr6QqGu0i7tt_XoVK9v-KvZ3m6
-- Forum: https://www.reddit.com/r/lunarvim/
-- Discord: https://discord.com/invite/Xb9B4Ny

-- Line endings: the script Vim and Neovim share warns when a CRLF or mixed file is opened and adds :Lf, which saves
-- the file with LF. lualine shows its label (CRLF or mixed, nothing for LF) first in section x. LunarVim fills the
-- sections from its style only when lualine is set up, after this file runs, so the component is added afterwards.
local line_endings = vim.fn.expand("~/.vim/plugin/line-endings.vim")
if vim.fn.filereadable(line_endings) == 1 then
  vim.cmd.source(line_endings)
  lvim.builtin.lualine.on_config_done = function(lualine)
    local config = lualine.get_config()
    table.insert(config.sections.lualine_x, 1, {
      function()
        return vim.b.line_endings or ""
      end,
      cond = function()
        return (vim.b.line_endings or "") ~= ""
      end,
      color = "WarningMsg",
    })
    lualine.setup(config)
  end
end
