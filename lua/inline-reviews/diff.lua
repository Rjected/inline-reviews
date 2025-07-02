local M = {}

local config = require("inline-reviews.config")
local notifier = require("inline-reviews.ui.notifier")

-- Cache for line mappings
local mappings_cache = {}
local cache_timestamps = {}

-- Parse a diff hunk header to extract line numbers
-- Format: @@ -old_start,old_count +new_start,new_count @@
local function parse_hunk_header(header)
  local old_start, old_count, new_start, new_count = 
    header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  
  if not old_start then
    return nil
  end
  
  -- Default count to 1 if not specified
  old_count = old_count ~= "" and tonumber(old_count) or 1
  new_count = new_count ~= "" and tonumber(new_count) or 1
  
  return {
    old_start = tonumber(old_start),
    old_count = old_count,
    new_start = tonumber(new_start),
    new_count = new_count,
  }
end

-- Build line mappings from diff output
local function build_line_mappings(diff_lines)
  local old_to_new = {}
  local new_to_old = {}
  
  local current_old_line = nil
  local current_new_line = nil
  
  if vim.g.inline_reviews_debug then
    notifier.debug("Building line mappings from " .. #diff_lines .. " diff lines")
  end
  
  for _, line in ipairs(diff_lines) do
    if line:match("^@@") then
      -- Parse hunk header
      local hunk = parse_hunk_header(line)
      if hunk then
        current_old_line = hunk.old_start
        current_new_line = hunk.new_start
        
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Hunk: old %d,%d -> new %d,%d", 
            hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count))
        end
      end
    elseif current_old_line and current_new_line then
      local first_char = line:sub(1, 1)
      
      if first_char == "-" then
        -- Line deleted from old version
        -- No mapping to new
        current_old_line = current_old_line + 1
      elseif first_char == "+" then
        -- Line added in new version
        -- No mapping from old
        current_new_line = current_new_line + 1
      elseif first_char == " " then
        -- Context line (unchanged) - must have space prefix
        -- Map bidirectionally
        old_to_new[current_old_line] = current_new_line
        new_to_old[current_new_line] = current_old_line
        current_old_line = current_old_line + 1
        current_new_line = current_new_line + 1
      end
      -- Skip lines that don't start with -, +, or space (like "\ No newline at end of file")
    end
  end
  
  if vim.g.inline_reviews_debug then
    local mapped_count = vim.tbl_count(old_to_new)
    notifier.debug("Mapped " .. mapped_count .. " lines")
  end
  
  return old_to_new, new_to_old
end

-- Get diff between base and working tree for a file
local function get_diff(file_path, base_ref, callback)
  -- Check if we're in a jj repo first
  vim.fn.jobstart({ "jj", "root" }, {
    on_exit = function(_, jj_exit_code, _)
      local cmd
      
      if jj_exit_code == 0 then
        -- We're in a jj repo
        if base_ref then
          cmd = { "jj", "diff", "--from", base_ref, "--to", "@", "--", file_path }
        else
          cmd = { "jj", "diff", "--", file_path }
        end
      else
        -- Fall back to git
        if base_ref then
          -- Use merge-base to get the actual common ancestor
          cmd = { "git", "diff", "origin/" .. base_ref, "--", file_path }
        else
          cmd = { "git", "diff", "HEAD", "--", file_path }
        end
      end
      
      local diff_lines = {}
      
      vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data, _)
          if data then
            vim.list_extend(diff_lines, data)
          end
        end,
        on_exit = function(_, exit_code, _)
          if exit_code == 0 then
            callback(diff_lines)
          else
            callback(nil)
          end
        end,
      })
    end,
  })
end

-- Get line mapping for a file
function M.get_line_mapping(file_path, base_ref, callback)
  local cache_key = file_path .. ":" .. (base_ref or "HEAD")
  
  -- Check cache
  local cached = mappings_cache[cache_key]
  if cached then
    local age = os.time() - (cache_timestamps[cache_key] or 0)
    local ttl = config.get().diff_tracking and config.get().diff_tracking.cache_ttl or 300
    
    if age < ttl then
      callback(cached.old_to_new, cached.new_to_old)
      return
    end
  end
  
  -- Get fresh diff
  get_diff(file_path, base_ref, function(diff_lines)
    if not diff_lines then
      callback(nil, nil)
      return
    end
    
    local old_to_new, new_to_old = build_line_mappings(diff_lines)
    
    -- Cache the result
    mappings_cache[cache_key] = {
      old_to_new = old_to_new,
      new_to_old = new_to_old,
    }
    cache_timestamps[cache_key] = os.time()
    
    callback(old_to_new, new_to_old)
  end)
end

-- Map a line number from old to new
function M.map_line_to_current(file_path, old_line, base_ref, callback)
  M.get_line_mapping(file_path, base_ref, function(old_to_new, _)
    if not old_to_new then
      -- No mapping available, return original line
      if vim.g.inline_reviews_debug then
        notifier.debug(string.format("No mapping available for %s:%d", file_path, old_line))
      end
      callback(old_line)
      return
    end
    
    -- Try direct mapping first
    local new_line = old_to_new[old_line]
    if new_line then
      if vim.g.inline_reviews_debug then
        notifier.debug(string.format("Direct mapping: %s:%d -> %d", file_path, old_line, new_line))
      end
      callback(new_line)
      return
    end
    
    -- Line might have been deleted, try to find nearest mapped line
    -- Search upward first
    for i = old_line - 1, 1, -1 do
      if old_to_new[i] then
        -- Found a mapped line above, estimate position
        local offset = old_line - i
        local estimated = old_to_new[i] + offset
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Estimated mapping (up): %s:%d -> %d (base %d + offset %d)", 
            file_path, old_line, estimated, old_to_new[i], offset))
        end
        callback(estimated)
        return
      end
    end
    
    -- Search downward
    for i = old_line + 1, old_line + 100 do
      if old_to_new[i] then
        -- Found a mapped line below
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Nearest mapping (down): %s:%d -> %d", 
            file_path, old_line, old_to_new[i]))
        end
        callback(old_to_new[i])
        return
      end
    end
    
    -- No mapping found, return original
    if vim.g.inline_reviews_debug then
      notifier.debug(string.format("No mapping found: %s:%d -> %d (unchanged)", file_path, old_line, old_line))
    end
    callback(old_line)
  end)
end

-- Clear cache for a file
function M.clear_cache(file_path)
  for key in pairs(mappings_cache) do
    if key:match("^" .. vim.pesc(file_path) .. ":") then
      mappings_cache[key] = nil
      cache_timestamps[key] = nil
    end
  end
end

-- Clear all cache
function M.clear_all_cache()
  mappings_cache = {}
  cache_timestamps = {}
end

-- Get the base reference for the current PR
function M.get_pr_base_ref(pr_number, callback)
  -- For now, we'll need to get this from PR info
  -- This would typically be the base branch of the PR
  local github = require("inline-reviews.github")
  
  github.get_pr_info(pr_number, function(pr_info)
    if pr_info and pr_info.baseRefName then
      callback(pr_info.baseRefName)
    else
      callback(nil)
    end
  end)
end

return M