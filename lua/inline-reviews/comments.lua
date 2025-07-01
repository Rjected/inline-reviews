local M = {}

local config = require("inline-reviews.config")

-- Store comments indexed by file path and line number
local comments_by_file = {}
local all_comments = {}
local current_pr_number = nil
local pr_base_ref = nil
local line_mappings = {} -- Store mapped lines for each comment

local function normalize_path(path)
  -- Remove leading slash if present
  path = path:gsub("^/", "")
  
  -- Get current working directory
  local cwd = vim.fn.getcwd()
  
  -- Check if the path matches the current buffer
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname:find(path .. "$") then
    return bufname
  end
  
  -- Try to match against cwd
  local full_path = cwd .. "/" .. path
  if vim.fn.filereadable(full_path) == 1 then
    return full_path
  end
  
  return path
end

function M.load_comments(review_threads)
  -- Clear existing comments
  comments_by_file = {}
  all_comments = {}
  line_mappings = {}
  
  local diff = require("inline-reviews.diff")
  local opts = config.get()
  local diff_tracking_enabled = opts.diff_tracking and opts.diff_tracking.enabled
  
  for _, thread in ipairs(review_threads) do
    local file_path = normalize_path(thread.path)
    
    if not comments_by_file[file_path] then
      comments_by_file[file_path] = {}
    end
    
    -- Handle null/nil line numbers from GraphQL (vim.NIL)
    local original_line = thread.line
    if original_line == vim.NIL or original_line == nil then
      original_line = thread.original_line
    end
    if original_line == vim.NIL then
      original_line = nil
    end
    
    if original_line then
      -- Store the original line in the thread for reference
      thread.pr_line = original_line
      
      -- The display line will be calculated asynchronously
      local display_line = original_line
      
      -- Store comment at original line for now
      if not comments_by_file[file_path][display_line] then
        comments_by_file[file_path][display_line] = {}
      end
      
      table.insert(comments_by_file[file_path][display_line], thread)
      local comment_entry = {
        file = file_path,
        line = display_line,
        original_line = original_line,
        thread = thread
      }
      table.insert(all_comments, comment_entry)
      
      -- If diff tracking is enabled, calculate mapped line asynchronously
      if diff_tracking_enabled and pr_base_ref then
        diff.map_line_to_current(file_path, original_line, pr_base_ref, function(mapped_line)
          if mapped_line and mapped_line ~= original_line then
            -- Update the mapping
            line_mappings[file_path] = line_mappings[file_path] or {}
            line_mappings[file_path][original_line] = mapped_line
            
            -- Schedule UI update
            vim.schedule(function()
              M.update_comment_positions()
            end)
          end
        end)
      end
    end
  end
  
  -- Sort all_comments by file and line for navigation
  table.sort(all_comments, function(a, b)
    if a.file == b.file then
      -- Both lines should be numbers at this point, but be defensive
      if type(a.line) == "number" and type(b.line) == "number" then
        return a.line < b.line
      end
      return false
    end
    return a.file < b.file
  end)
end

function M.get_comments_for_file(file_path)
  return comments_by_file[file_path] or {}
end

function M.get_comments_for_line(file_path, line)
  local file_comments = comments_by_file[file_path]
  if not file_comments then return {} end
  
  local line_comments = file_comments[line] or {}
  local opts = config.get()
  
  -- Filter based on configuration
  local filtered = {}
  for _, thread in ipairs(line_comments) do
    local include = true
    
    if thread.is_resolved and not opts.display.show_resolved then
      include = false
    end
    
    if thread.is_outdated and not opts.display.show_outdated then
      include = false
    end
    
    if include then
      table.insert(filtered, thread)
    end
  end
  
  return filtered
end

function M.get_all_comment_lines_for_file(file_path)
  local lines = {}
  local file_comments = comments_by_file[file_path]
  
  if file_comments then
    for line, threads in pairs(file_comments) do
      local has_visible = false
      local opts = config.get()
      
      for _, thread in ipairs(threads) do
        if (not thread.is_resolved or opts.display.show_resolved) and
           (not thread.is_outdated or opts.display.show_outdated) then
          has_visible = true
          break
        end
      end
      
      if has_visible then
        table.insert(lines, line)
      end
    end
  end
  
  table.sort(lines)
  return lines
end

function M.get_next_comment_line()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buf)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  
  -- First, check current file for next comment
  local file_lines = M.get_all_comment_lines_for_file(current_file)
  for _, line in ipairs(file_lines) do
    if line > current_line then
      return line
    end
  end
  
  -- If no next comment in current file, check other files
  for _, comment_info in ipairs(all_comments) do
    if comment_info.file == current_file and comment_info.line > current_line then
      return comment_info.line
    elseif comment_info.file > current_file then
      -- Would need to open a different file
      vim.notify("Next comment is in: " .. vim.fn.fnamemodify(comment_info.file, ":~:."), vim.log.levels.INFO)
      return nil
    end
  end
  
  return nil
end

function M.get_prev_comment_line()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buf)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  
  -- Check current file for previous comment
  local file_lines = M.get_all_comment_lines_for_file(current_file)
  for i = #file_lines, 1, -1 do
    if file_lines[i] < current_line then
      return file_lines[i]
    end
  end
  
  -- If no previous comment in current file, check other files
  for i = #all_comments, 1, -1 do
    local comment_info = all_comments[i]
    if comment_info.file == current_file and comment_info.line < current_line then
      return comment_info.line
    elseif comment_info.file < current_file then
      -- Would need to open a different file
      vim.notify("Previous comment is in: " .. vim.fn.fnamemodify(comment_info.file, ":~:."), vim.log.levels.INFO)
      return nil
    end
  end
  
  return nil
end

function M.clear()
  comments_by_file = {}
  all_comments = {}
end

function M.get_comment_count_for_line(file_path, line)
  local threads = M.get_comments_for_line(file_path, line)
  local count = 0
  
  for _, thread in ipairs(threads) do
    count = count + #thread.comments
  end
  
  return count
end

-- Internal function for telescope extension
function M._get_all_comments()
  return all_comments
end

function M.set_current_pr(pr_number)
  current_pr_number = pr_number
end

function M.get_current_pr()
  return current_pr_number
end

function M.set_comments(review_threads)
  M.load_comments(review_threads)
end

function M.set_pr_base_ref(base_ref)
  pr_base_ref = base_ref
end

function M.get_pr_base_ref()
  return pr_base_ref
end

-- Update comment positions based on line mappings
function M.update_comment_positions()
  local new_comments_by_file = {}
  local ui = require("inline-reviews.ui")
  
  -- Rebuild comments_by_file with mapped lines
  for _, comment_data in ipairs(all_comments) do
    local file_path = comment_data.file
    local original_line = comment_data.original_line
    local thread = comment_data.thread
    
    if not new_comments_by_file[file_path] then
      new_comments_by_file[file_path] = {}
    end
    
    -- Determine display line
    local display_line = original_line
    if line_mappings[file_path] and line_mappings[file_path][original_line] then
      display_line = line_mappings[file_path][original_line]
      thread.is_displaced = true
    else
      thread.is_displaced = false
    end
    
    -- Update comment entry
    comment_data.line = display_line
    
    if not new_comments_by_file[file_path][display_line] then
      new_comments_by_file[file_path][display_line] = {}
    end
    
    table.insert(new_comments_by_file[file_path][display_line], thread)
  end
  
  -- Replace the old structure
  comments_by_file = new_comments_by_file
  
  -- Re-sort all_comments
  table.sort(all_comments, function(a, b)
    if a.file == b.file then
      if type(a.line) == "number" and type(b.line) == "number" then
        return a.line < b.line
      end
      return false
    end
    return a.file < b.file
  end)
  
  -- Refresh UI
  ui.refresh_all()
end

-- Force refresh line mappings for a file
function M.refresh_file_mappings(file_path)
  local diff = require("inline-reviews.diff")
  local opts = config.get()
  
  if not opts.diff_tracking or not opts.diff_tracking.enabled then
    return
  end
  
  if not pr_base_ref then
    return
  end
  
  -- Clear cache for this file
  diff.clear_cache(file_path)
  
  -- Recalculate mappings for all comments in this file
  local file_comments = comments_by_file[file_path]
  if file_comments then
    for original_line, threads in pairs(file_comments) do
      for _, thread in ipairs(threads) do
        if thread.pr_line then
          diff.map_line_to_current(file_path, thread.pr_line, pr_base_ref, function(mapped_line)
            if mapped_line and mapped_line ~= thread.pr_line then
              line_mappings[file_path] = line_mappings[file_path] or {}
              line_mappings[file_path][thread.pr_line] = mapped_line
              
              vim.schedule(function()
                M.update_comment_positions()
              end)
            end
          end)
        end
      end
    end
  end
end

return M