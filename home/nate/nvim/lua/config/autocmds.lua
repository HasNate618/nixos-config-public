-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap")

-- Matugen live-reload: watch the theme file for changes triggered by skwd-wall
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    local theme_file = vim.fn.expand("~/.config/nvim/theme/matugen.lua")
    if vim.fn.filereadable(theme_file) ~= 1 then return end

    local uv = vim.uv or vim.loop
    local stat = uv.fs_stat(theme_file)
    if not stat then return end

    local last_mtime = stat.mtime.sec

    local timer = uv.new_timer()
    timer:start(0, 2000, vim.schedule_wrap(function()
      local ok, s = pcall(uv.fs_stat, theme_file)
      if ok and s and s.mtime.sec ~= last_mtime then
        last_mtime = s.mtime.sec
        vim.api.nvim_exec_autocmds("User", { pattern = "LazyReload" })
      end
    end))
  end,
})

-- Backup: also fire LazyReload on SIGUSR1 (pkill -USR1 nvim)
vim.api.nvim_create_autocmd("Signal", {
  pattern = "SIGUSR1",
  callback = function()
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyReload" })
  end,
})
