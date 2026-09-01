-- Plugins.theme — LazyVim colorscheme config
-- The hot-reload handler (omarchy-theme-hotreload.lua) reloads this module
-- on `User LazyReload` to pick up matugen-generated colors.

local matugen_theme_path = vim.fn.expand("~/.config/nvim/theme/matugen.lua")

-- Load matugen-generated aether opts if available
local matugen_opts = {}
local ok, result = pcall(dofile, matugen_theme_path)
if ok and type(result) == "table" and #result > 0 then
  local spec = result[1]
  if spec.opts then
    matugen_opts = spec.opts
  end
end

return {
  -- Aether colorscheme — colors injected from matugen
  {
    "bjarneo/aether.nvim",
    lazy = false,
    priority = 1000,
    opts = matugen_opts,
    config = function(_, opts)
      require("aether").setup(opts)
    end,
  },

  -- Set LazyVim to use aether as the colorscheme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
