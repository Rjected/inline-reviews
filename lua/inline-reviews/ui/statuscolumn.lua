local M = {}

local config = require("inline-reviews.config")
local comments = require("inline-reviews.comments")

-- Cache for sign data per buffer
local sign_cache = {}
local cache_timer = nil

-- Check if snacks.nvim is available
local function has_snacks()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks and snacks.statuscolumn
end

-- Get comment data for a specific line
local function get_line_comment_data(buf, lnum)
  local file_path = vim.api.nvim_buf_get_name(buf)
  if file_path == "" then
    return nil
  end
  
  local threads = comments.get_comments_for_line(file_path, lnum)
  if #threads == 0 then
    return nil
  end
  
  -- Analyze threads
  local total_count = 0
  local unresolved_count = 0
  local has_outdated = false
  local authors = {}
  
  for _, thread in ipairs(threads) do
    total_count = total_count + #thread.comments
    if not thread.is_resolved then
      unresolved_count = unresolved_count + 1
    end
    if thread.is_outdated then
      has_outdated = true
    end
    -- Collect unique authors
    for _, comment in ipairs(thread.comments) do
      authors[comment.author] = true
    end
  end
  
  return {
    total_threads = #threads,
    total_comments = total_count,
    unresolved_count = unresolved_count,
    all_resolved = unresolved_count == 0,
    has_outdated = has_outdated,
    authors = vim.tbl_keys(authors),
  }
end

-- Get the appropriate icon and highlight for comment data
local function get_comment_display(data, opts)
  if not data then
    return nil
  end
  
  local text, hl
  
  -- Determine icon based on state
  if data.has_outdated and opts.show_outdated then
    text = opts.icons.outdated or "○"
    hl = "InlineReviewOutdatedSign"
  elseif data.all_resolved then
    text = opts.icons.resolved or "✓"
    hl = "InlineReviewResolvedSign"
  else
    text = opts.icons.comment or "●"
    hl = "InlineReviewCommentSign"
  end
  
  -- Show count if enabled and multiple comments
  if opts.show_count and data.total_comments > 1 then
    local count = data.total_comments
    if count > opts.max_count then
      text = tostring(opts.max_count) .. "+"
    else
      text = tostring(count)
    end
  end
  
  return { text = text, texthl = hl }
end

-- Custom component for snacks statuscolumn
function M.component(win, buf, lnum)
  local opts = config.get().statuscolumn
  if not opts or not opts.enabled then
    return nil
  end
  
  -- Get cached data or compute it
  if not sign_cache[buf] then
    sign_cache[buf] = {}
  end
  
  if sign_cache[buf][lnum] == nil then
    sign_cache[buf][lnum] = get_line_comment_data(buf, lnum) or false
  end
  
  local data = sign_cache[buf][lnum]
  if not data then
    return nil
  end
  
  return get_comment_display(data, opts)
end

-- Clear cache for a buffer
function M.clear_cache(buf)
  if buf then
    sign_cache[buf] = nil
  else
    sign_cache = {}
  end
end

-- Setup statuscolumn integration
function M.setup()
  local opts = config.get().statuscolumn
  if not opts or not opts.enabled then
    return
  end
  
  if not has_snacks() then
    require("inline-reviews.ui.notifier").warn("snacks.nvim statuscolumn not available")
    return
  end
  
  -- Set up cache refresh timer
  if cache_timer then
    cache_timer:stop()
  end
  
  cache_timer = vim.loop.new_timer()
  cache_timer:start(1000, 1000, vim.schedule_wrap(function()
    -- Clear cache periodically to pick up changes
    sign_cache = {}
  end))
  
  -- Create a sign definition for inline reviews
  -- This allows it to work with the standard "sign" component
  vim.fn.sign_define("InlineReviewsStatusColumn", {
    text = "",
    texthl = "",
  })
  
  -- Hook into sign placement
  local original_refresh = require("inline-reviews.ui").refresh_buffer
  require("inline-reviews.ui").refresh_buffer = function(bufnr)
    -- Call original
    original_refresh(bufnr)
    
    -- Add our custom signs for statuscolumn
    local file_path = vim.api.nvim_buf_get_name(bufnr or 0)
    if file_path == "" then return end
    
    local comment_lines = comments.get_all_comment_lines_for_file(file_path)
    for _, line in ipairs(comment_lines) do
      local data = get_line_comment_data(bufnr or 0, line)
      if data then
        local display = get_comment_display(data, opts)
        if display then
          -- Place a sign with our custom text
          vim.fn.sign_place(
            line * 1000 + 999, -- Unique ID
            "InlineReviewsStatusColumn",
            "InlineReviewsStatusColumn",
            bufnr or 0,
            {
              lnum = line,
              priority = 90,
              text = display.text,
              texthl = display.texthl
            }
          )
        end
      end
    end
  end
  
  -- Notify user
  require("inline-reviews.ui.notifier").info("Inline reviews statuscolumn enabled - signs will appear when comments are loaded")
end

-- Click handler for statuscolumn
function M.click(args)
  local buf = args.buf
  local lnum = args.mousepos.line
  
  -- Get comments for this line and show hover
  local file_path = vim.api.nvim_buf_get_name(buf)
  if file_path == "" then
    return
  end
  
  local threads = comments.get_comments_for_line(file_path, lnum)
  if #threads > 0 then
    require("inline-reviews.ui.hover").show(threads)
  end
end

return M