-- Simple approach: Just update the sign definitions to work better with statuscolumn
local M = {}

local config = require("inline-reviews.config")

function M.setup()
  local opts = config.get().statuscolumn
  if not opts or not opts.enabled then
    return
  end
  
  -- Update the existing sign definitions with the configured icons
  vim.fn.sign_define("InlineReviewComment", {
    text = opts.icons.comment or "●",
    texthl = "InlineReviewCommentSign",
  })
  
  vim.fn.sign_define("InlineReviewResolved", {
    text = opts.icons.resolved or "✓",
    texthl = "InlineReviewResolvedSign",
  })
  
  -- Add a new sign for outdated comments
  vim.fn.sign_define("InlineReviewOutdated", {
    text = opts.icons.outdated or "○",
    texthl = "InlineReviewOutdatedSign",
  })
  
  -- Modify the refresh logic to use the right sign based on state
  local ui = require("inline-reviews.ui")
  local comments = require("inline-reviews.comments")
  local original_refresh = ui.refresh_buffer
  
  ui.refresh_buffer = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    -- Clear existing marks
    ui.clear_buffer(bufnr)
    
    -- Get file path
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    if file_path == "" then return end
    
    -- Get all comment lines for this file
    local comment_lines = comments.get_all_comment_lines_for_file(file_path)
    
    for _, line in ipairs(comment_lines) do
      local threads = comments.get_comments_for_line(file_path, line)
      
      -- Analyze threads
      local all_resolved = true
      local has_outdated = false
      local total_comments = 0
      
      for _, thread in ipairs(threads) do
        total_comments = total_comments + #thread.comments
        if not thread.is_resolved then
          all_resolved = false
        end
        if thread.is_outdated then
          has_outdated = true
        end
      end
      
      -- Determine sign type
      local sign_name
      if has_outdated and opts.show_outdated then
        sign_name = "InlineReviewOutdated"
      elseif all_resolved then
        sign_name = "InlineReviewResolved"
      else
        sign_name = "InlineReviewComment"
      end
      
      -- Show count if enabled and multiple comments
      local sign_text = nil
      if opts.show_count and total_comments > 1 then
        if total_comments > opts.max_count then
          sign_text = tostring(opts.max_count) .. "+"
        else
          sign_text = tostring(total_comments)
        end
      end
      
      -- Place sign
      vim.fn.sign_place(
        line,
        "InlineReviewsSigns",
        sign_name,
        bufnr,
        { 
          lnum = line, 
          priority = 100,
          text = sign_text  -- Override text if count is shown
        }
      )
      
      -- Add highlight to line
      local hl_group = all_resolved and "InlineReviewResolvedLine" or "InlineReviewCommentLine"
      vim.api.nvim_buf_add_highlight(bufnr, vim.api.nvim_create_namespace("inline_reviews"), hl_group, line - 1, 0, -1)
    end
  end
  
  require("inline-reviews.ui.notifier").info("Statuscolumn icons updated - reload comments to see changes")
end

return M