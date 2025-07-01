local M = {}

function M.setup()
  -- Define default highlight groups
  local highlights = {
    -- Comment line highlights
    InlineReviewCommentLine = { link = "CursorLine" },
    InlineReviewResolvedLine = { link = "Comment" },
    
    -- Author highlight in hover
    InlineReviewAuthor = { link = "Function" },
    
    -- Virtual text hint
    InlineReviewHint = { link = "Comment" },
    
    -- Sign column
    InlineReviewSign = { link = "DiagnosticSignInfo" },
    InlineReviewResolvedSign = { link = "DiagnosticSignHint" },
  }
  
  for group, opts in pairs(highlights) do
    if opts.link then
      vim.api.nvim_set_hl(0, group, { link = opts.link, default = true })
    else
      vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", { default = true }, opts))
    end
  end
end

return M