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
    vim.notify("Usage: :InlineComments <PR_NUMBER>", vim.log.levels.ERROR)
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
    vim.notify("Inline Reviews debug mode enabled", vim.log.levels.INFO)
  elseif opts.args == "off" then
    vim.g.inline_reviews_debug = false
    vim.notify("Inline Reviews debug mode disabled", vim.log.levels.INFO)
  else
    local status = vim.g.inline_reviews_debug and "on" or "off"
    vim.notify("Inline Reviews debug mode is " .. status, vim.log.levels.INFO)
  end
end, {
  nargs = "?",
  complete = function()
    return { "on", "off" }
  end,
  desc = "Toggle debug mode for inline reviews",
})

vim.api.nvim_create_user_command("InlineCommentsTelescope", function()
  local ok, telescope = pcall(require, "telescope")
  if not ok then
    vim.notify("Telescope is required for this feature", vim.log.levels.ERROR)
    return
  end
  
  -- Load the extension if not already loaded
  pcall(telescope.load_extension, "inline_reviews")
  
  -- Launch the picker
  telescope.extensions.inline_reviews.comments()
end, {
  desc = "Browse PR comments with Telescope",
})