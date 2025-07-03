local notifier = require("inline-reviews.ui.notifier")

if vim.fn.has("nvim-0.9.0") ~= 1 then
  vim.api.nvim_err_writeln("inline-reviews requires Neovim >= 0.9.0")
  return
end

if vim.g.loaded_inline_reviews then
  return
end
vim.g.loaded_inline_reviews = true

-- Define user commands
vim.api.nvim_create_user_command("InlineComments", function(opts)
  local pr_number = tonumber(opts.args)
  if pr_number then
    require("inline-reviews").load_pr(pr_number)
  else
    notifier.error("Usage: :InlineComments <PR_NUMBER>")
  end
end, {
  nargs = 1,
  desc = "Load comments from a specific PR",
})

vim.api.nvim_create_user_command("InlineCommentsReload", function()
  require("inline-reviews").reload()
end, {
  desc = "Reload comments for current PR",
})

vim.api.nvim_create_user_command("InlineCommentsClear", function()
  require("inline-reviews").clear()
end, {
  desc = "Clear all inline comments",
})

vim.api.nvim_create_user_command("InlineCommentsDebug", function(opts)
  if opts.args == "on" then
    vim.g.inline_reviews_debug = true
    notifier.info("Inline Reviews debug mode enabled")
  elseif opts.args == "off" then
    vim.g.inline_reviews_debug = false
    notifier.info("Inline Reviews debug mode disabled")
  else
    local status = vim.g.inline_reviews_debug and "on" or "off"
    notifier.info("Inline Reviews debug mode is " .. status)
  end
end, {
  nargs = "?",
  complete = function()
    return { "on", "off" }
  end,
  desc = "Toggle debug mode for inline reviews",
})

vim.api.nvim_create_user_command("InlineCommentsTelescope", function()
  require("inline-reviews.ui.picker").show()
end, {
  desc = "Browse PR comments with picker (snacks.nvim or telescope)",
})

vim.api.nvim_create_user_command("InlineCommentsRefreshDiff", function()
  local comments = require("inline-reviews.comments")
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path ~= "" then
    notifier.info("Refreshing diff mappings for " .. vim.fn.fnamemodify(file_path, ":~:."))
    comments.refresh_file_mappings(file_path)
  end
end, { desc = "Refresh diff mappings for current file" })

vim.api.nvim_create_user_command("InlineCommentsRefresh", function()
  require("inline-reviews").reload()
end, { desc = "Manually refresh PR comments from GitHub" })