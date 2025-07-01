local M = {}

local config = require("inline-reviews.config")
local comments = require("inline-reviews.comments")
local virtual_text = require("inline-reviews.ui.virtual_text")
local hover = require("inline-reviews.ui.hover")
local highlights = require("inline-reviews.ui.highlights")

local NAMESPACE = vim.api.nvim_create_namespace("inline_reviews")
local SIGN_GROUP = "InlineReviewsSigns"

-- Track which buffers have UI elements
local active_buffers = {}

function M.setup()
  -- Set up highlight groups
  highlights.setup()
  
  -- Define signs
  local opts = config.get()
  vim.fn.sign_define("InlineReviewComment", {
    text = opts.display.sign_text,
    texthl = opts.display.sign_highlight,
  })
  
  vim.fn.sign_define("InlineReviewResolved", {
    text = opts.display.resolved_sign_text,
    texthl = opts.display.resolved_sign_highlight,
  })
end

function M.refresh_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Clear existing marks
  M.clear_buffer(bufnr)
  
  -- Get file path
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then return end
  
  -- Get all comment lines for this file
  local comment_lines = comments.get_all_comment_lines_for_file(file_path)
  
  for _, line in ipairs(comment_lines) do
    local threads = comments.get_comments_for_line(file_path, line)
    
    -- Determine sign type
    local all_resolved = true
    for _, thread in ipairs(threads) do
      if not thread.is_resolved then
        all_resolved = false
        break
      end
    end
    
    local sign_name = all_resolved and "InlineReviewResolved" or "InlineReviewComment"
    
    -- Place sign
    vim.fn.sign_place(
      line,
      SIGN_GROUP,
      sign_name,
      bufnr,
      { lnum = line, priority = 100 }
    )
    
    -- Add highlight to line
    local hl_group = all_resolved and "InlineReviewResolvedLine" or "InlineReviewCommentLine"
    vim.api.nvim_buf_add_highlight(bufnr, NAMESPACE, hl_group, line - 1, 0, -1)
  end
  
  active_buffers[bufnr] = true
end

function M.refresh_all_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.refresh_buffer(bufnr)
    end
  end
end

function M.clear_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Clear signs
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
  
  -- Clear highlights and virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  virtual_text.clear_buffer(bufnr)
  
  active_buffers[bufnr] = nil
end

function M.clear_all_buffers()
  for bufnr, _ in pairs(active_buffers) do
    M.clear_buffer(bufnr)
  end
  hover.close()
end

function M.update_virtual_text()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  
  -- Check if we should show virtual text
  local opts = config.get()
  if not opts.display.show_hints then
    virtual_text.clear_buffer(bufnr)
    return
  end
  
  -- Get comments for current line
  local threads = comments.get_comments_for_line(file_path, line)
  
  if #threads > 0 then
    virtual_text.show_hint(bufnr, line, threads)
  else
    virtual_text.clear_buffer(bufnr)
  end
end

function M.show_comment_hover(threads)
  hover.show(threads)
end

-- Don't initialize here - wait for main init to call setup
-- M.setup()

return M