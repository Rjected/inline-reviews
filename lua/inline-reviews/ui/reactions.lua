local M = {}

local mutations = require("inline-reviews.github.mutations")

local reaction_win = nil
local reaction_buf = nil
local on_select_callback = nil
local parent_win = nil

-- Available reactions in order
local reactions = {
  { emoji = "👍", content = "THUMBS_UP", key = "1" },
  { emoji = "👎", content = "THUMBS_DOWN", key = "2" },
  { emoji = "😄", content = "LAUGH", key = "3" },
  { emoji = "🎉", content = "HOORAY", key = "4" },
  { emoji = "😕", content = "CONFUSED", key = "5" },
  { emoji = "❤️", content = "HEART", key = "6" },
  { emoji = "🚀", content = "ROCKET", key = "7" },
  { emoji = "👀", content = "EYES", key = "8" },
}

-- Create reaction picker window
function M.show(opts)
  opts = opts or {}
  
  -- Close any existing picker
  M.close()
  
  -- Save parent window
  parent_win = opts.parent_win or vim.api.nvim_get_current_win()
  
  -- Create buffer content
  local lines = {}
  local highlights = {}
  
  -- Header
  table.insert(lines, "─── Select Reaction ───")
  table.insert(highlights, { line = 0, col = 0, end_col = -1, hl_group = "Comment" })
  table.insert(lines, "")
  
  -- Reaction row
  local reaction_line = ""
  for _, r in ipairs(reactions) do
    reaction_line = reaction_line .. string.format(" %s:%s ", r.key, r.emoji)
  end
  table.insert(lines, reaction_line)
  
  -- Current reactions if provided
  if opts.current_reactions then
    table.insert(lines, "")
    table.insert(lines, "─── Current ───")
    table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "Comment" })
    
    local current_line = ""
    for _, reaction in ipairs(opts.current_reactions) do
      if reaction.users.totalCount > 0 then
        local emoji = mutations.content_to_emoji[reaction.content] or "?"
        current_line = current_line .. string.format(" %s:%d ", emoji, reaction.users.totalCount)
      end
    end
    
    if current_line ~= "" then
      table.insert(lines, current_line)
    else
      table.insert(lines, " (no reactions yet)")
      table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "Comment" })
    end
  end
  
  -- Create buffer
  reaction_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(reaction_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(reaction_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(reaction_buf, "buftype", "nofile")
  
  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(reaction_buf, -1, hl.hl_group, hl.line, hl.col, hl.end_col)
  end
  
  -- Calculate window size and position
  local width = 50
  local height = #lines
  local row = opts.row
  local col = opts.col
  
  -- If no position provided, position near cursor
  if not row or not col then
    local cursor_pos = vim.api.nvim_win_get_cursor(parent_win)
    local win_pos = vim.api.nvim_win_get_position(parent_win)
    
    row = win_pos[1] + cursor_pos[1] - 1
    col = win_pos[2] + 20
    
    -- Adjust if would go off screen
    if col + width > vim.o.columns then
      col = math.max(0, vim.o.columns - width - 2)
    end
    if row + height > vim.o.lines - 2 then
      row = math.max(0, vim.o.lines - height - 3)
    end
  end
  
  -- Create window
  reaction_win = vim.api.nvim_open_win(reaction_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
  })
  
  -- Store callback
  on_select_callback = opts.on_select
  
  -- Set up keymaps
  local keymap_opts = { noremap = true, silent = true, buffer = reaction_buf }
  
  -- Number keys for quick selection
  for _, r in ipairs(reactions) do
    vim.keymap.set("n", r.key, function()
      M.select_reaction(r.emoji, r.content)
    end, keymap_opts)
  end
  
  -- Click on emoji (simplified - just close on any click)
  vim.keymap.set("n", "<LeftMouse>", function()
    -- Get mouse position and try to determine which emoji was clicked
    local mouse_pos = vim.fn.getmousepos()
    if mouse_pos.line == 3 then  -- Reaction line
      -- Simple heuristic: divide column by spacing
      local col = mouse_pos.column
      local emoji_index = math.floor((col - 1) / 6) + 1
      if emoji_index > 0 and emoji_index <= #reactions then
        local r = reactions[emoji_index]
        M.select_reaction(r.emoji, r.content)
      end
    end
  end, keymap_opts)
  
  -- Escape to close
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, keymap_opts)
  
  vim.keymap.set("n", "q", function()
    M.close()
  end, keymap_opts)
  
  -- Auto-close on window leave
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = reaction_buf,
    once = true,
    callback = function()
      vim.schedule(function()
        M.close()
      end)
    end,
  })
end

function M.select_reaction(emoji, content)
  M.close()
  
  if on_select_callback then
    on_select_callback(emoji, content)
  end
end

function M.close()
  if reaction_win and vim.api.nvim_win_is_valid(reaction_win) then
    vim.api.nvim_win_close(reaction_win, true)
  end
  
  if reaction_buf and vim.api.nvim_buf_is_valid(reaction_buf) then
    vim.api.nvim_buf_delete(reaction_buf, { force = true })
  end
  
  reaction_win = nil
  reaction_buf = nil
  on_select_callback = nil
  
  -- Return focus to parent window if valid
  if parent_win and vim.api.nvim_win_is_valid(parent_win) then
    vim.api.nvim_set_current_win(parent_win)
  end
end

function M.is_open()
  return reaction_win ~= nil and vim.api.nvim_win_is_valid(reaction_win)
end

return M