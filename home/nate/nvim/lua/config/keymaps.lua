-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Open current file with default system app
vim.keymap.set("n", "<leader>o", function()
  local path = vim.fn.expand("%:p")
  if path == "" then
    -- Write unsaved buffer to a temp file and open that
    local tmp = vim.fn.tempname() .. "." .. vim.bo.filetype
    vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), tmp)
    vim.ui.open(tmp)
    return
  end
  if vim.bo.modified then
    vim.cmd.write()
  end
  vim.ui.open(path)
end, { desc = "[O]pen file with default app" })
