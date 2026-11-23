return {
	{
		name = "theme-hotreload",
		dir = vim.fn.stdpath("config"),
		lazy = false,
		priority = 1000,
		config = function()
			local transparency_file = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"

			vim.api.nvim_create_autocmd("User", {
				pattern = "LazyReload",
				callback = function()
					-- Unload the theme module to force fresh matugen opts read
					package.loaded["plugins.theme"] = nil

					vim.schedule(function()
						local ok, theme_spec = pcall(require, "plugins.theme")
						if not ok then
							return
						end

						-- Extract fresh matugen opts from the re-loaded spec
						local new_opts = {}
						for _, spec in ipairs(theme_spec) do
							if spec[1] and spec[1] ~= "LazyVim/LazyVim" and spec.opts then
								new_opts = spec.opts
								break
							end
						end

						-- Persist the new opts into aether's config so
						-- the subsequent colorscheme command picks them up
						local aether_ok, aether = pcall(require, "aether")
						if aether_ok and aether.setup then
							aether.setup(new_opts)
						end

						-- Find the theme plugin name for module unloading
						local theme_plugin_name = nil
						for _, spec in ipairs(theme_spec) do
							if spec[1] and spec[1] ~= "LazyVim/LazyVim" then
								theme_plugin_name = spec.name or spec[1]
								break
							end
						end

						-- Clear all highlight groups before applying new theme
						vim.cmd("highlight clear")
						if vim.fn.exists("syntax_on") then
							vim.cmd("syntax reset")
						end

						-- Reset background to default so colorscheme can set it properly
						vim.o.background = "dark"

						-- Unload theme plugin modules to force full reload
						if theme_plugin_name then
							local plugin = require("lazy.core.config").plugins[theme_plugin_name]
							if plugin then
								local plugin_dir = plugin.dir .. "/lua"
								require("lazy.core.util").walkmods(plugin_dir, function(modname)
									package.loaded[modname] = nil
									package.preload[modname] = nil
								end)
							end
						end

						-- Find and apply the new colorscheme
						for _, spec in ipairs(theme_spec) do
							if spec[1] == "LazyVim/LazyVim" and spec.opts and spec.opts.colorscheme then
								local colorscheme = spec.opts.colorscheme

								require("lazy.core.loader").colorscheme(colorscheme)

								vim.defer_fn(function()
									pcall(vim.cmd.colorscheme, colorscheme)
									vim.cmd("redraw!")
									if vim.fn.filereadable(transparency_file) == 1 then
										vim.defer_fn(function()
											vim.cmd.source(transparency_file)
											vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
											vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
											vim.cmd("redraw!")
										end, 5)
									end
								end, 5)

								break
							end
						end
					end)
				end,
			})
		end,
	},
}
