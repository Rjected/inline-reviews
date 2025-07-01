local M = {}

local defaults = {
  auto_load = false,
  keymaps = {
    view_comments = "<leader>rc",
    next_comment = "]c",
    prev_comment = "[c",
    toggle_resolved = "<leader>rt",
    telescope_comments = "<leader>rC",  -- Capital C for telescope
  },
  display = {
    show_hints = true,
    hint_prefix = " ",
    hint_highlight = "Comment",
    sign_text = "●",
    sign_highlight = "DiagnosticSignInfo",
    resolved_sign_text = "✓",
    resolved_sign_highlight = "DiagnosticSignHint",
    comment_highlight = "CursorLine",
    show_resolved = true,
    show_outdated = true,
    max_height = 20,
    max_width = 80,
    border = "rounded",
  },
  interactions = {
    enabled = true,                -- Enable comment interactions
    reply_key = "r",              -- Key to reply to comment in hover
    react_key = "e",              -- Key to add reaction in hover
    resolve_key = "s",            -- Key to toggle resolve status in hover
    show_action_hints = true,     -- Show action hints in hover window
  },
  github = {
    gh_cmd = "gh",
    cache_ttl = 300,
    timeout = 30000,
  },
  icons = {
    comment = "",
    resolved = "✓",
    pending = "●",
    outdated = "○",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  
  -- Validate gh command exists
  local gh_exists = vim.fn.executable(M.options.github.gh_cmd) == 1
  if not gh_exists then
    vim.notify("GitHub CLI (gh) not found. Please install it first.", vim.log.levels.ERROR)
    return false
  end
  
  return true
end

function M.get()
  return M.options
end

return M