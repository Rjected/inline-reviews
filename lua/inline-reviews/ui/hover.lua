local M = {}

local config = require("inline-reviews.config")
local notifier = require("inline-reviews.ui.notifier")

local hover_win = nil
local hover_buf = nil
local diff_collapsed = {}  -- Track collapsed state per thread

-- Helper function to wrap text
local function wrap_text(text, width)
  local wrapped_lines = {}
  for line in text:gmatch("[^\n]+") do
    if #line <= width then
      table.insert(wrapped_lines, line)
    else
      -- Wrap long lines
      local current_line = ""
      for word in line:gmatch("%S+") do
        if #current_line + #word + 1 <= width then
          current_line = current_line == "" and word or current_line .. " " .. word
        else
          if current_line ~= "" then
            table.insert(wrapped_lines, current_line)
          end
          current_line = word
        end
      end
      if current_line ~= "" then
        table.insert(wrapped_lines, current_line)
      end
    end
  end
  return wrapped_lines
end

local function create_comment_lines(thread, max_width)
  local lines = {}
  local highlights = {}
  local metadata = {}  -- Store metadata about special lines
  
  -- Thread header with resolve action
  local status = thread.is_resolved and " [RESOLVED]" or ""
  local outdated = thread.is_outdated and " [OUTDATED]" or ""
  local displaced = ""
  local resolve_action = ""
  
  local opts = config.get()
  
  -- Show if comment is displaced from original line
  if thread.is_displaced and thread.pr_line and opts.diff_tracking and opts.diff_tracking.show_original_line then
    displaced = string.format(" [originally line %d]", thread.pr_line)
  end
  
  if opts.interactions.enabled and opts.interactions.show_action_hints then
    resolve_action = thread.is_resolved 
      and string.format(" [%s: unresolve]", opts.interactions.resolve_key)
      or string.format(" [%s: resolve]", opts.interactions.resolve_key)
  end
  
  -- Show resolve action for all threads (including outdated)
  if opts.interactions.enabled then
    table.insert(lines, string.format("──────── Thread%s%s%s%s ────────", status, outdated, displaced, resolve_action))
    metadata[#lines] = { 
      type = "thread_header", 
      thread_id = thread.id, 
      is_resolved = thread.is_resolved,
      action_start = string.len("──────── Thread" .. status .. outdated .. displaced .. " "),
      action_end = -9  -- Length of " ────────" from end
    }
  else
    table.insert(lines, string.format("──────── Thread%s%s%s ────────", status, outdated, displaced))
  end
  table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "Comment" })
  
  -- Each comment in the thread
  for i, comment in ipairs(thread.comments) do
    if i > 1 then
      table.insert(lines, "")
    end
    
    -- Author and time with action buttons
    local time = comment.created_at:match("(%d%d%d%d%-[^T]+)")
    local actions = ""
    local opts = config.get()
    if opts.interactions.enabled and opts.interactions.show_action_hints then
      actions = string.format(" [%s: reply] [%s: react]", 
        opts.interactions.reply_key, 
        opts.interactions.react_key)
    end
    local author_line = string.format("● %s • %s%s", comment.author, time or "", actions)
    table.insert(lines, author_line)
    
    -- Store metadata for this comment line
    metadata[#lines] = {
      type = "comment_header",
      comment_id = comment.id,
      thread_id = thread.id,
      actions_start = string.len(string.format("● %s • %s", comment.author, time or ""))
    }
    
    table.insert(highlights, { 
      line = #lines - 1, 
      col = 0, 
      end_col = string.len(comment.author) + 2,
      hl_group = "InlineReviewAuthor" 
    })
    
    -- Highlight action text
    table.insert(highlights, {
      line = #lines - 1,
      col = metadata[#lines].actions_start,
      end_col = -1,
      hl_group = "Comment"
    })
    
    -- Comment body
    table.insert(lines, "")
    
    -- Wrap and indent comment body (clean any remaining CR characters)
    local clean_body = comment.body:gsub("\r", "")
    local wrapped_body = wrap_text(clean_body, max_width - 2)  -- -2 for indent
    for _, body_line in ipairs(wrapped_body) do
      table.insert(lines, "  " .. body_line)
    end
    
    -- Reactions if any
    if comment.reactions and #comment.reactions > 0 then
      table.insert(lines, "")
      local reaction_parts = {}
      for _, reaction in ipairs(comment.reactions) do
        if reaction.users.totalCount > 0 then
          table.insert(reaction_parts, string.format("%s %d", 
            reaction.content, reaction.users.totalCount))
        end
      end
      if #reaction_parts > 0 then
        table.insert(lines, "  " .. table.concat(reaction_parts, "  "))
        table.insert(highlights, {
          line = #lines - 1,
          col = 0,
          end_col = -1,
          hl_group = "Comment"
        })
      end
    end
  end
  
  -- Diff context if available
  if thread.comments[1].diff_hunk then
    table.insert(lines, "")
    
    -- Check if diff is collapsed for this thread
    local thread_key = thread.id or tostring(thread)
    local is_collapsed = diff_collapsed[thread_key] ~= false  -- Default to collapsed
    
    if is_collapsed then
      table.insert(lines, "──────── Diff Context [+] ────────")
      metadata[#lines] = { type = "diff_toggle", thread_id = thread_key, collapsed = true }
    else
      table.insert(lines, "──────── Diff Context [-] ────────")
      metadata[#lines] = { type = "diff_toggle", thread_id = thread_key, collapsed = false }
      
      table.insert(lines, "")
      
      for hunk_line in thread.comments[1].diff_hunk:gmatch("[^\n]+") do
        -- Clean CR characters from diff lines
        local clean_line = hunk_line:gsub("\r", "")
        table.insert(lines, clean_line)
        
        -- Highlight diff lines based on the first character
        local hl_group = nil
        local first_char = clean_line:sub(1, 1)
        
        if first_char == "+" then
          hl_group = "DiffAdd"
        elseif first_char == "-" then
          hl_group = "DiffDelete"
        elseif hunk_line:match("^@@") then
          hl_group = "DiffChange"
        else
          -- For context lines (including those with bullet points)
          -- Don't highlight them specially
          hl_group = nil
        end
        
        if hl_group then
          table.insert(highlights, {
            line = #lines - 1,
            col = 0,
            end_col = -1,
            hl_group = hl_group
          })
        end
      end
    end
    
    table.insert(highlights, { line = #lines - 1 - (is_collapsed and 0 or 1), col = 0, end_col = -1, hl_group = "Comment" })
  end
  
  return lines, highlights, metadata
end

function M.show(threads)
  -- Close existing hover if any
  M.close()
  
  local opts = config.get()
  
  -- Create buffer content
  local all_lines = {}
  local all_highlights = {}
  local all_metadata = {}  -- Store line metadata
  
  -- Calculate max width for text wrapping
  local max_width = math.min(opts.display.max_width, vim.o.columns - 10)
  
  for i, thread in ipairs(threads) do
    if i > 1 then
      table.insert(all_lines, "")
      table.insert(all_lines, "")
    end
    
    local lines, highlights, metadata = create_comment_lines(thread, max_width)
    
    -- Adjust highlight line numbers and store metadata
    local line_offset = #all_lines
    for _, hl in ipairs(highlights) do
      hl.line = hl.line + line_offset
    end
    
    -- Adjust metadata line numbers
    for line_num, meta in pairs(metadata) do
      all_metadata[line_num + line_offset] = meta
    end
    
    vim.list_extend(all_lines, lines)
    vim.list_extend(all_highlights, highlights)
  end
  
  -- Create buffer
  hover_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(hover_buf, 0, -1, false, all_lines)
  vim.api.nvim_buf_set_option(hover_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(hover_buf, "buftype", "nofile")
  -- Don't set filetype to markdown as it might interfere with diff display
  -- vim.api.nvim_buf_set_option(hover_buf, "filetype", "markdown")
  
  -- Apply highlights
  for _, hl in ipairs(all_highlights) do
    vim.api.nvim_buf_add_highlight(hover_buf, -1, hl.hl_group, 
      hl.line, hl.col, hl.end_col)
  end
  
  -- Calculate window size
  local width = max_width
  
  -- Calculate height based on content and whether diffs are expanded
  local base_height = #all_lines
  local max_height = opts.display.max_height
  
  -- If diffs are expanded, allow more height and width
  local any_diff_expanded = false
  local max_diff_line_length = 0
  
  -- Check if any diffs are expanded and find the longest diff line
  for thread_id, collapsed in pairs(diff_collapsed) do
    if not collapsed then
      any_diff_expanded = true
      -- Find the thread and measure diff lines
      for _, thread in ipairs(threads) do
        if (thread.id or tostring(thread)) == thread_id and thread.comments[1].diff_hunk then
          for hunk_line in thread.comments[1].diff_hunk:gmatch("[^\n]+") do
            max_diff_line_length = math.max(max_diff_line_length, #hunk_line)
          end
        end
      end
    end
  end
  
  if any_diff_expanded then
    max_height = math.min(max_height * 1.5, vim.o.lines - 10)  -- Allow 50% more height for expanded diffs
    -- Make window wider for diff content, but within reason
    width = math.min(math.max(max_width, max_diff_line_length + 4), vim.o.columns - 10, 120)
  end
  
  local height = math.min(base_height, max_height, vim.o.lines - 10)
  
  -- Position window below the current line
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local win_row = cursor_pos[1] - win_info.topline + win_info.winrow
  
  -- Calculate position to show below the line
  local row = win_row + 1  -- One line below cursor
  local col = win_info.wincol + 5  -- Slightly indented
  
  -- Adjust if would go off screen
  if col + width > vim.o.columns then
    col = math.max(1, vim.o.columns - width - 1)
  end
  
  if row + height > vim.o.lines - 2 then
    -- If not enough space below, show above
    row = math.max(1, win_row - height - 1)
  end
  
  -- Create window (not focused initially)
  hover_win = vim.api.nvim_open_win(hover_buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.display.border,
    focusable = true,
  })
  
  -- Set window options
  vim.api.nvim_win_set_option(hover_win, "wrap", true)  -- Enable wrap for comments
  vim.api.nvim_win_set_option(hover_win, "linebreak", true)
  vim.api.nvim_win_set_option(hover_win, "cursorline", true)  -- Highlight current line
  vim.api.nvim_win_set_option(hover_win, "number", false)
  vim.api.nvim_win_set_option(hover_win, "relativenumber", false)
  
  -- Store metadata in buffer variable for keymaps
  vim.b[hover_buf].line_metadata = all_metadata
  vim.b[hover_buf].threads = threads
  
  -- Track if window is focused
  vim.b[hover_buf].is_hover_focused = false
  
  -- Close on cursor move only if not focused
  local augroup = vim.api.nvim_create_augroup("InlineReviewsHover", { clear = true })
  
  local close_if_not_focused = function()
    -- Safety checks
    if not hover_win or not vim.api.nvim_win_is_valid(hover_win) then
      return
    end
    
    if not hover_buf or not vim.api.nvim_buf_is_valid(hover_buf) then
      M.close()
      return
    end
    
    -- Check if we're in the hover window
    if vim.api.nvim_get_current_win() == hover_win then
      vim.b[hover_buf].is_hover_focused = true
      return
    end
    
    -- Only close if not focused
    local is_focused = vim.b[hover_buf].is_hover_focused
    if not is_focused then
      M.close()
    end
  end
  
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = close_if_not_focused,
  })
  
  -- Close when leaving the hover buffer
  vim.api.nvim_create_autocmd("WinLeave", {
    group = augroup,
    buffer = hover_buf,
    callback = function()
      vim.schedule(function()
        M.close()
      end)
    end,
  })
  
  -- Allow closing with Esc when focused
  vim.api.nvim_buf_set_keymap(hover_buf, "n", "<Esc>", "", {
    callback = function()
      M.close()
    end,
    noremap = true,
    silent = true,
  })
  
  vim.api.nvim_buf_set_keymap(hover_buf, "n", "q", "", {
    callback = function()
      M.close()
    end,
    noremap = true,
    silent = true,
  })
  
  local opts = config.get()
  
  -- Reply to comment
  if opts.interactions.enabled and opts.interactions.reply_key then
    vim.api.nvim_buf_set_keymap(hover_buf, "n", opts.interactions.reply_key, "", {
    callback = function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local metadata = vim.b[hover_buf].line_metadata
      
      -- Find the nearest comment header
      local comment_meta = nil
      for i = line, 1, -1 do
        if metadata[i] and metadata[i].type == "comment_header" then
          comment_meta = metadata[i]
          break
        end
      end
      
      if comment_meta then
        -- Show reply input
        local input = require("inline-reviews.ui.input")
        local mutations = require("inline-reviews.github.mutations")
        
        input.show({
          title = " Reply ",
          parent_win = hover_win,
          on_submit = function(text, result_callback)
            mutations.add_reply(comment_meta.thread_id, text, function(result, err)
              if err then
                if result_callback then
                  result_callback(false, err)
                end
                notifier.error("Failed to add reply: " .. err)
              else
                if result_callback then
                  result_callback(true)
                end
                -- Reload all comments from GitHub to get the new reply
                vim.schedule(function()
                  local inline_reviews = require("inline-reviews")
                  inline_reviews.reload(true) -- Silent reload
                  -- Then refresh the hover display after a short delay
                  vim.defer_fn(function()
                    M.refresh()
                  end, 1000)
                end)
              end
            end)
          end,
        })
      end
    end,
    noremap = true,
    silent = true,
    desc = "Reply to comment"
    })
  end
  
  -- Add reaction to comment
  if opts.interactions.enabled and opts.interactions.react_key then
    vim.api.nvim_buf_set_keymap(hover_buf, "n", opts.interactions.react_key, "", {
    callback = function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local metadata = vim.b[hover_buf].line_metadata
      
      -- Find the nearest comment header
      local comment_meta = nil
      local comment_data = nil
      for i = line, 1, -1 do
        if metadata[i] and metadata[i].type == "comment_header" then
          comment_meta = metadata[i]
          -- Find the actual comment data
          local threads = vim.b[hover_buf].threads
          if threads then
            for _, thread in ipairs(threads) do
              for _, comment in ipairs(thread.comments) do
                if comment.id == comment_meta.comment_id then
                  comment_data = comment
                  break
                end
              end
            end
          end
          break
        end
      end
      
      if comment_meta and comment_data then
        -- Show reaction picker
        local reactions_ui = require("inline-reviews.ui.reactions")
        local mutations = require("inline-reviews.github.mutations")
        
        reactions_ui.show({
          current_reactions = comment_data.reactions,
          parent_win = hover_win,
          on_select = function(emoji, content)
            notifier.info("Adding reaction...")
            mutations.add_reaction(comment_meta.comment_id, content, function(result, err)
              if err then
                notifier.error("Failed to add reaction: " .. err)
              else
                notifier.info("Reaction added!")
                -- Refresh the display
                vim.schedule(function()
                  M.refresh()
                end)
              end
            end)
          end,
        })
      end
    end,
    noremap = true,
    silent = true,
    desc = "Add reaction"
    })
  end
  
  -- Toggle resolve status
  if opts.interactions.enabled and opts.interactions.resolve_key then
    vim.api.nvim_buf_set_keymap(hover_buf, "n", opts.interactions.resolve_key, "", {
    callback = function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local metadata = vim.b[hover_buf].line_metadata
      local meta = metadata and metadata[line]
      
      if meta and meta.type == "thread_header" then
        local mutations = require("inline-reviews.github.mutations")
        
        if meta.is_resolved then
          notifier.info("Unresolving thread...")
          mutations.unresolve_thread(meta.thread_id, function(result, err)
            if err then
              notifier.error("Failed to unresolve thread: " .. err)
            else
              notifier.info("Thread unresolved!")
              -- Refresh the display
              vim.schedule(function()
                M.refresh()
              end)
            end
          end)
        else
          notifier.info("Resolving thread...")
          mutations.resolve_thread(meta.thread_id, function(result, err)
            if err then
              notifier.error("Failed to resolve thread: " .. err)
            else
              notifier.info("Thread resolved!")
              -- Refresh the display
              vim.schedule(function()
                M.refresh()
              end)
            end
          end)
        end
      end
    end,
    noremap = true,
    silent = true,
    desc = "Toggle resolve status"
    })
  end
  
  -- Add keymap for toggling diff sections
  vim.api.nvim_buf_set_keymap(hover_buf, "n", "<CR>", "", {
    callback = function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local metadata = vim.b[hover_buf].line_metadata
      local meta = metadata and metadata[line]
      
      if meta and meta.type == "diff_toggle" then
        -- Toggle the collapsed state
        diff_collapsed[meta.thread_id] = not meta.collapsed
        
        -- Get current threads and refresh content
        local threads = vim.b[hover_buf].threads
        if threads then
          -- Save current window and buffer
          local current_win = hover_win
          local current_buf = hover_buf
          
          -- Temporarily prevent closing
          hover_win = nil
          hover_buf = nil
          
          -- Recreate content
          local opts = config.get()
          local all_lines = {}
          local all_highlights = {}
          local all_metadata = {}
          local max_width = math.min(opts.display.max_width, vim.o.columns - 10)
          
          for i, thread in ipairs(threads) do
            if i > 1 then
              table.insert(all_lines, "")
              table.insert(all_lines, "")
            end
            
            local lines, highlights, metadata_new = create_comment_lines(thread, max_width)
            
            local line_offset = #all_lines
            for _, hl in ipairs(highlights) do
              hl.line = hl.line + line_offset
            end
            
            for line_num, meta_item in pairs(metadata_new) do
              all_metadata[line_num + line_offset] = meta_item
            end
            
            vim.list_extend(all_lines, lines)
            vim.list_extend(all_highlights, highlights)
          end
          
          -- Restore references
          hover_win = current_win
          hover_buf = current_buf
          
          -- Update buffer content
          vim.api.nvim_buf_set_option(current_buf, "modifiable", true)
          vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, all_lines)
          vim.api.nvim_buf_set_option(current_buf, "modifiable", false)
          
          -- Clear and reapply highlights
          vim.api.nvim_buf_clear_namespace(current_buf, -1, 0, -1)
          for _, hl in ipairs(all_highlights) do
            vim.api.nvim_buf_add_highlight(current_buf, -1, hl.hl_group, 
              hl.line, hl.col, hl.end_col)
          end
          
          -- Update metadata
          vim.b[current_buf].line_metadata = all_metadata
          
          -- Resize window if needed
          local base_height = #all_lines
          local max_height = opts.display.max_height
          local new_width = max_width
          
          local any_diff_expanded = false
          local max_diff_line_length = 0
          
          -- Check if any diffs are expanded and find longest line
          for thread_id, collapsed in pairs(diff_collapsed) do
            if not collapsed then
              any_diff_expanded = true
              -- Find the thread and measure diff lines
              for _, thread in ipairs(threads) do
                if (thread.id or tostring(thread)) == thread_id and thread.comments[1].diff_hunk then
                  for hunk_line in thread.comments[1].diff_hunk:gmatch("[^\n]+") do
                    max_diff_line_length = math.max(max_diff_line_length, #hunk_line)
                  end
                end
              end
            end
          end
          
          if any_diff_expanded then
            max_height = math.min(max_height * 1.5, vim.o.lines - 10)
            new_width = math.min(math.max(max_width, max_diff_line_length + 4), vim.o.columns - 10, 120)
          end
          
          local new_height = math.min(base_height, max_height, vim.o.lines - 10)
          
          -- Update window size
          vim.api.nvim_win_set_height(current_win, new_height)
          vim.api.nvim_win_set_width(current_win, new_width)
          
          -- Restore cursor position
          pcall(vim.api.nvim_win_set_cursor, current_win, {line, 0})
        end
      end
    end,
    noremap = true,
    silent = true,
    desc = "Toggle diff section"
  })
end

function M.close()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_win_close(hover_win, true)
  end
  
  if hover_buf and vim.api.nvim_buf_is_valid(hover_buf) then
    vim.api.nvim_buf_delete(hover_buf, { force = true })
  end
  
  hover_win = nil
  hover_buf = nil
  
  -- Clear diff collapsed state for next time
  diff_collapsed = {}
  
  -- No need to clear autocommands since they are set with once = true
  -- They automatically remove themselves after firing
end

function M.is_open()
  return hover_win ~= nil and vim.api.nvim_win_is_valid(hover_win)
end

function M.focus()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_set_current_win(hover_win)
    if hover_buf and vim.api.nvim_buf_is_valid(hover_buf) then
      vim.b[hover_buf].is_hover_focused = true
    end
    return true
  end
  return false
end

function M.get_hover_win()
  return hover_win
end

-- Refresh the current hover display after mutations
function M.refresh()
  if not hover_win or not vim.api.nvim_win_is_valid(hover_win) then
    return
  end
  
  local threads = vim.b[hover_buf].threads
  if not threads then
    return
  end
  
  -- Save cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(hover_win)
  
  -- Get the current PR number from comments module
  local comments = require("inline-reviews.comments")
  local current_pr = comments.get_current_pr()
  
  if not current_pr then
    return
  end
  
  -- Reload comments from GitHub
  local github = require("inline-reviews.github")
  github.get_review_comments(current_pr, function(review_comments)
    if not review_comments then
      return
    end
    
    -- Update the comment data
    comments.set_comments(review_comments)
    
    -- Find updated threads for current position
    local current_file = vim.api.nvim_buf_get_name(0)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    
    local updated_threads = {}
    for _, comment_thread in ipairs(review_comments) do
      local file_path = vim.fn.getcwd() .. "/" .. comment_thread.path
      if file_path == current_file and comment_thread.line == current_line then
        table.insert(updated_threads, {
          id = comment_thread.id,
          is_resolved = comment_thread.is_resolved,
          is_outdated = comment_thread.is_outdated,
          comments = comment_thread.comments,
        })
      end
    end
    
    if #updated_threads > 0 then
      -- Refresh display with updated data
      local current_win = hover_win
      local current_buf = hover_buf
      
      -- Temporarily prevent closing
      hover_win = nil
      hover_buf = nil
      
      -- Recreate content
      local opts = config.get()
      local all_lines = {}
      local all_highlights = {}
      local all_metadata = {}
      local max_width = math.min(opts.display.max_width, vim.o.columns - 10)
      
      for i, thread in ipairs(updated_threads) do
        if i > 1 then
          table.insert(all_lines, "")
          table.insert(all_lines, "")
        end
        
        local lines, highlights, metadata_new = create_comment_lines(thread, max_width)
        
        local line_offset = #all_lines
        for _, hl in ipairs(highlights) do
          hl.line = hl.line + line_offset
        end
        
        for line_num, meta_item in pairs(metadata_new) do
          all_metadata[line_num + line_offset] = meta_item
        end
        
        vim.list_extend(all_lines, lines)
        vim.list_extend(all_highlights, highlights)
      end
      
      -- Restore references
      hover_win = current_win
      hover_buf = current_buf
      
      -- Update buffer content
      vim.api.nvim_buf_set_option(current_buf, "modifiable", true)
      vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, all_lines)
      vim.api.nvim_buf_set_option(current_buf, "modifiable", false)
      
      -- Clear and reapply highlights
      vim.api.nvim_buf_clear_namespace(current_buf, -1, 0, -1)
      for _, hl in ipairs(all_highlights) do
        vim.api.nvim_buf_add_highlight(current_buf, -1, hl.hl_group, 
          hl.line, hl.col, hl.end_col)
      end
      
      -- Update metadata and threads
      vim.b[current_buf].line_metadata = all_metadata
      vim.b[current_buf].threads = updated_threads
      
      -- Restore cursor position
      pcall(vim.api.nvim_win_set_cursor, current_win, cursor_pos)
      
      -- Also refresh the main UI
      local ui = require("inline-reviews.ui")
      ui.refresh()
    end
  end)
end

return M