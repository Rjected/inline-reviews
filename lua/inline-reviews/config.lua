local M = {}

local notifier = require("inline-reviews.ui.notifier")

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
  diff_tracking = {
    enabled = true,                -- Enable line number tracking through diffs
    update_on_save = true,         -- Auto-update mappings when files are saved
    show_original_line = true,     -- Show original line number in hover
    cache_ttl = 300,              -- Cache TTL for diff mappings in seconds
  },
  auto_refresh = {
    enabled = false,               -- Auto-refresh comments periodically
    interval = 300,                -- Refresh interval in seconds (5 minutes)
  },
  ui = {
    backend = "auto",             -- UI backend: "auto", "snacks", "native"
                                   -- auto: use snacks.nvim if available
                                   -- snacks: always use snacks.nvim (error if not available)
                                   -- native: always use built-in UI
  },
  statuscolumn = {
    enabled = false,              -- Enable statuscolumn integration (opt-in)
    component_position = "left",  -- Position: "left" or "right"
    show_count = true,            -- Show comment count
    show_outdated = true,         -- Show outdated indicator
    max_count = 9,                -- Show "9+" for more comments
    icons = {
      comment = "●",              -- Unresolved comment icon
      resolved = "✓",             -- Resolved comment icon
      outdated = "○",             -- Outdated comment icon
    },
  },
  picker = {
    layout = "float",             -- Layout: "float", "split", "vsplit"
    split_width = 40,             -- Width for vsplit layout
    split_height = 15,            -- Height for split layout
    auto_close = true,            -- Auto close picker when jumping
    filters = {
      enabled = true,             -- Enable advanced filtering
      default = "",               -- Default filter (e.g., "status:unresolved")
    },
    keymaps = {
      toggle_resolved = "<C-s>",  -- Toggle resolved status
      filter_author = "<C-a>",    -- Filter by author
      filter_status = "<C-f>",    -- Filter by status
      multi_select = "<Tab>",     -- Multi-select items
      pin_window = "<C-p>",       -- Pin picker window
    },
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  
  -- Validate gh command exists
  local gh_exists = vim.fn.executable(M.options.github.gh_cmd) == 1
  if not gh_exists then
    notifier.error("GitHub CLI (gh) not found. Please install it first.")
    return false
  end
  
  return true
end

function M.get()
  return M.options
end

return M