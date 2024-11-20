local function decode_json(filename)
  -- Open the file in read mode
  local file = io.open(filename, "r")
  if not file then
    return false -- File doesn't exist or cannot be opened
  end

  -- Read the contents of the file
  local content = file:read "*all"
  file:close()

  -- Parse the JSON content
  local json_parsed, json = pcall(vim.fn.json_decode, content)
  if not json_parsed or type(json) ~= "table" then
    return false -- Invalid JSON format
  end
  return json
end

local format_filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "svelte" }

local function check_json_key_exists(json, ...) return vim.tbl_get(json, ...) ~= nil end

local lsp_rooter, prettierrc_rooter, biomerc_rooter

local function has_biome(bufnr)
  return true
  -- if type(bufnr) ~= "number" then bufnr = vim.api.nvim_get_current_buf() end
  -- local rooter = require "astrocore.rooter"
  -- if not lsp_rooter then
  --   lsp_rooter = rooter.resolve("lsp", {
  --     ignore = {
  --       servers = function(client)
  --         return not vim.tbl_contains({ "eslint", "ts_ls", "typescript-tools", "volar", "vtsls" }, client.name)
  --       end,
  --     },
  --   })
  -- end
  -- if not biomerc_rooter then biomerc_rooter = rooter.resolve { "biome.json" } end
  -- local biome_dependency = false
  -- for _, root in ipairs(require("astrocore").list_insert_unique(lsp_rooter(bufnr), { vim.fn.getcwd() })) do
  --   local package_json = decode_json(root .. "/package.json")
  --   if
  --     package_json
  --     and (
  --       check_json_key_exists(package_json, "dependencies", "@biomejs/biome")
  --       or check_json_key_exists(package_json, "devDependencies", "@biomejs/biome")
  --     )
  --   then
  --     biome_dependency = true
  --     break
  --   end
  -- end
  -- return biome_dependency or next(biomerc_rooter(bufnr))
end

local function has_prettier(bufnr)
  if type(bufnr) ~= "number" then bufnr = vim.api.nvim_get_current_buf() end
  local rooter = require "astrocore.rooter"
  if not lsp_rooter then
    lsp_rooter = rooter.resolve("lsp", {
      ignore = {
        servers = function(client)
          return not vim.tbl_contains({ "eslint", "ts_ls", "typescript-tools", "volar", "vtsls" }, client.name)
        end,
      },
    })
  end
  if not prettierrc_rooter then
    prettierrc_rooter = rooter.resolve {
      ".prettierrc",
      ".prettierrc.json",
      ".prettierrc.yml",
      ".prettierrc.yaml",
      ".prettierrc.json5",
      ".prettierrc.js",
      ".prettierrc.cjs",
      "prettier.config.js",
      ".prettierrc.mjs",
      "prettier.config.mjs",
      "prettier.config.cjs",
      ".prettierrc.toml",
    }
  end
  local prettier_dependency = false
  for _, root in ipairs(require("astrocore").list_insert_unique(lsp_rooter(bufnr), { vim.fn.getcwd() })) do
    local package_json = decode_json(root .. "/package.json")
    if
      package_json
      and (
        check_json_key_exists(package_json, "dependencies", "prettier")
        or check_json_key_exists(package_json, "devDependencies", "prettier")
      )
    then
      prettier_dependency = true
      break
    end
  end
  return prettier_dependency or next(prettierrc_rooter(bufnr))
end

local null_ls_formatter_biome = function(params)
  if vim.tbl_contains(format_filetypes, params.filetype) then return has_biome(params.bufnr) end
  return true
end

local null_ls_formatter_prettier = function(params)
  if vim.tbl_contains(format_filetypes, params.filetype) then
    return not has_biome(params.bufnr) and has_prettier(params.bufnr)
  end
  return true
end

-- Use Biome instead of prettier / eslint
local conform_formatter = function(bufnr)
  if has_biome(bufnr) then
    return { "biome" }
  elseif has_prettier(bufnr) then
    return { "prettierd" }
  else
    return {}
  end
end

return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      if not opts.formatters_by_ft then opts.formatters_by_ft = {} end
      for _, filetype in ipairs(format_filetypes) do
        opts.formatters_by_ft[filetype] = conform_formatter
      end
    end,
  },
  {
    "jay-babu/mason-null-ls.nvim",
    optional = true,
    opts = function(_, opts)
      local null_ls = require "null-ls"
      null_ls.deregister "prettierd"
      opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "biome" })
      if not opts.handlers then opts.handlers = {} end
      opts.handlers.biome = function(source_name, methods)
        for _, method in ipairs(methods) do
          null_ls.register(null_ls.builtins[method][source_name].with { runtime_condition = null_ls_formatter_biome })
        end
      end
      local prettier_handler = opts.handlers.prettierd
      -- opts.handlers.prettierd = function(source_name, methods)
      -- return not has_biome
      -- end
      opts.handlers.prettierd = function(source_name, methods)
        for _, method in ipairs(methods) do
          -- null_ls.register(
          --   null_ls.builtins[method][source_name].with { runtime_condition = null_ls_formatter_prettier }
          -- )
        end
      end
    end,
  },
  {
    "AstroNvim/astrolsp",
    servers = {
      "biome",
    },
    --   config = {
    --     biome = {
    --       -- Use the package manager of your project: npx, yarn, pnpm, bun...
    --       cmd = { "pnpm", "biome", "lsp-proxy" },
    --     },
    --   },
  },
}
