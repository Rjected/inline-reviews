-- Example configuration for inline-reviews.nvim

-- Basic setup with defaults
require("inline-reviews").setup()

-- Or with custom configuration
require("inline-reviews").setup({
  -- Automatically load PR comments when opening files
  auto_load = true,
  
  -- Custom keymaps
  keymaps = {
    view_comments = "<leader>cc",    -- Changed from default <leader>rc
    next_comment = "]r",             -- Changed from default ]c
    prev_comment = "[r",             -- Changed from default [c
    toggle_resolved = "<leader>cr",  -- Changed from default <leader>rt
  },
  
  -- Display customization
  display = {
    show_hints = true,               -- Show EOL virtual text
    hint_prefix = " 💬 ",           -- Fun emoji prefix
    sign_text = "💬",               -- Comment bubble for unresolved
    resolved_sign_text = "✅",      -- Checkmark for resolved
    show_resolved = false,           -- Hide resolved by default
    show_outdated = false,           -- Hide outdated by default
    max_height = 30,                 -- Larger hover windows
    max_width = 100,                 -- Wider hover windows
    border = "double",               -- Different border style
  },
  
  -- GitHub settings
  github = {
    cache_ttl = 600,                 -- Cache for 10 minutes
  }
})

-- Example of loading a specific PR on startup
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Check if we're in a specific project
    if vim.fn.getcwd():match("my%-project") then
      -- Load PR 123 automatically
      require("inline-reviews").load_pr(123)
    end
  end,
})

-- Example of custom highlighting
vim.api.nvim_set_hl(0, "InlineReviewCommentLine", { bg = "#2a2a3a" })
vim.api.nvim_set_hl(0, "InlineReviewResolvedLine", { bg = "#1a2a1a" })
vim.api.nvim_set_hl(0, "InlineReviewHint", { fg = "#888888", italic = true })