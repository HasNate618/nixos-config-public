-- Matugen-generated aether.nvim colorscheme config
-- Auto-generated from wallpaper — DO NOT EDIT
return {
  {
    "bjarneo/aether.nvim",
    opts = {
      transparent = true,
      colors = {
        bg = "#141414",
        fg = "{{colors.on_surface.default.hex}}",
        blue = "{{colors.primary.default.hex}}",
        green = "{{colors.secondary.default.hex}}",
        red = "{{colors.error.default.hex}}",
        yellow = "{{colors.on_surface_variant.default.hex}}",
        magenta = "{{colors.secondary.default.hex}}",
        cyan = "{{colors.secondary_container.default.hex}}",
        orange = "{{colors.secondary_container.default.hex}}",
        comment = "{{colors.outline.default.hex}}",
        line_nr = "{{colors.outline.default.hex}}",
        cursor_line = "#262626",
        cursor_fg = "{{colors.on_primary.default.hex}}",
        selection = "{{colors.primary_container.default.hex}}",
        visual_selection = "{{colors.secondary_container.default.hex}}",
        non_text = "{{colors.outline_variant.default.hex}}",
        Sidebar = "#1c1c1c",
        Floating = "#242424",
        scrollbar = "{{colors.outline_variant.default.hex}}",
      },
      on_colors = function(colors)
        -- Derive additional colors from MD3 palette
        colors.bg_statusline = colors.bg
        colors.bg_sidebar = colors.Sidebar
        colors.bg_float = colors.Floating
        colors.git_added = colors.green
        colors.git_changed = colors.orange
        colors.git_removed = colors.red
      end,
    },
  },
}
