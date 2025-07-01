local M = {}

local config = require("inline-reviews.config")

-- Store comments indexed by file path and line number
local comments_by_file = {}
local all_comments = {}

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
  
  for _, thread in ipairs(review_threads) do
    local file_path = normalize_path(thread.path)
    
    if not comments_by_file[file_path] then
      comments_by_file[file_path] = {}
    end
    
    -- Handle null/nil line numbers from GraphQL (vim.NIL)
    local line = thread.line
    if line == vim.NIL or line == nil then
      line = thread.original_line
    end
    if line == vim.NIL then
      line = nil
    end
    
    if line then
      if not comments_by_file[file_path][line] then
        comments_by_file[file_path][line] = {}
      end
      
      table.insert(comments_by_file[file_path][line], thread)
      table.insert(all_comments, {
        file = file_path,
        line = line,
        thread = thread
      })
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

return M