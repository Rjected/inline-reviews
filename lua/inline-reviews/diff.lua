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
-- Returns:
--   old_to_new: direct line mappings for context lines
--   new_to_old: reverse mappings
--   hunks: list of {old_start, old_end, offset} for lines outside context
local function build_line_mappings(diff_lines)
  local old_to_new = {}
  local new_to_old = {}
  local hunks = {}  -- Track each hunk's range and offset

  local current_old_line = nil
  local current_new_line = nil
  local current_hunk = nil

  if vim.g.inline_reviews_debug then
    notifier.debug("Building line mappings from " .. #diff_lines .. " diff lines")
  end

  for _, line in ipairs(diff_lines) do
    if line:match("^@@") then
      -- Save previous hunk info
      if current_hunk then
        table.insert(hunks, current_hunk)
      end

      -- Parse hunk header
      local hunk = parse_hunk_header(line)
      if hunk then
        current_old_line = hunk.old_start
        current_new_line = hunk.new_start

        -- Track this hunk: lines old_start to old_start+old_count-1 map with offset
        current_hunk = {
          old_start = hunk.old_start,
          old_end = hunk.old_start + hunk.old_count - 1,
          new_start = hunk.new_start,
          new_end = hunk.new_start + hunk.new_count - 1,
          -- Offset is the cumulative shift: positive = lines added, negative = lines removed
          offset = hunk.new_start - hunk.old_start,
        }

        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Hunk: old %d-%d -> new %d-%d (offset %+d)",
            current_hunk.old_start, current_hunk.old_end,
            current_hunk.new_start, current_hunk.new_end,
            current_hunk.offset))
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

  -- Save last hunk
  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  -- Sort hunks by old_start for easier lookup
  table.sort(hunks, function(a, b) return a.old_start < b.old_start end)

  if vim.g.inline_reviews_debug then
    local mapped_count = vim.tbl_count(old_to_new)
    notifier.debug("Mapped " .. mapped_count .. " context lines, " .. #hunks .. " hunks")
  end

  return old_to_new, new_to_old, hunks
end

-- Get diff between HEAD and working tree for a file
-- Note: base_ref is ignored now - we always diff HEAD to working tree
-- because PR comments are relative to the PR's HEAD, not the base branch
local function get_diff(file_path, base_ref, callback)
  -- Check if we're in a jj repo first
  vim.fn.jobstart({ "jj", "root" }, {
    on_exit = function(_, jj_exit_code, _)
      local cmd

      if jj_exit_code == 0 then
        -- We're in a jj repo - diff working copy against its parent
        cmd = { "jj", "diff", "--", file_path }
      else
        -- Fall back to git - diff HEAD against working tree
        -- This shows only uncommitted changes, which is what we want
        -- PR comments are relative to the PR's HEAD commit
        cmd = { "git", "diff", "HEAD", "--", file_path }
      end

      if vim.g.inline_reviews_debug then
        notifier.debug("Diff command: " .. table.concat(cmd, " "))
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
          if vim.g.inline_reviews_debug then
            notifier.debug(string.format("Diff exit code: %d, lines: %d", exit_code, #diff_lines))
            if #diff_lines > 0 and #diff_lines <= 50 then
              for i, line in ipairs(diff_lines) do
                notifier.debug(string.format("  [%d] %s", i, line:sub(1, 80)))
              end
            elseif #diff_lines > 50 then
              notifier.debug("  (diff too long, showing first 10 lines)")
              for i = 1, 10 do
                notifier.debug(string.format("  [%d] %s", i, diff_lines[i]:sub(1, 80)))
              end
            end
          end
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
  -- Cache key is just the file path now since we always diff HEAD -> working tree
  local cache_key = file_path .. ":HEAD"

  -- Check cache
  local cached = mappings_cache[cache_key]
  if cached then
    local age = os.time() - (cache_timestamps[cache_key] or 0)
    local ttl = config.get().diff_tracking and config.get().diff_tracking.cache_ttl or 300

    if age < ttl then
      callback(cached.old_to_new, cached.new_to_old, cached.hunks)
      return
    end
  end

  -- Get fresh diff
  get_diff(file_path, base_ref, function(diff_lines)
    if not diff_lines then
      callback(nil, nil, nil)
      return
    end

    local old_to_new, new_to_old, hunks = build_line_mappings(diff_lines)

    -- Cache the result
    mappings_cache[cache_key] = {
      old_to_new = old_to_new,
      new_to_old = new_to_old,
      hunks = hunks,
    }
    cache_timestamps[cache_key] = os.time()

    callback(old_to_new, new_to_old, hunks)
  end)
end

-- Calculate the cumulative offset for a line based on all hunks before it
local function calculate_offset_for_line(hunks, old_line)
  local cumulative_offset = 0

  for _, hunk in ipairs(hunks) do
    if hunk.old_end < old_line then
      -- This entire hunk is before our line, add its net change
      local hunk_delta = (hunk.new_end - hunk.new_start + 1) - (hunk.old_end - hunk.old_start + 1)
      cumulative_offset = cumulative_offset + hunk_delta
    elseif hunk.old_start <= old_line and old_line <= hunk.old_end then
      -- Line is inside a hunk - it may have been modified/deleted
      -- Return nil to indicate we can't calculate a simple offset
      return nil
    else
      -- Hunk is after our line, stop
      break
    end
  end

  return cumulative_offset
end

-- Map a line number from old to new
function M.map_line_to_current(file_path, old_line, base_ref, callback)
  M.get_line_mapping(file_path, base_ref, function(old_to_new, _, hunks)
    if not old_to_new then
      -- No mapping available (diff failed), return original line
      if vim.g.inline_reviews_debug then
        notifier.debug(string.format("No mapping available for %s:%d", file_path, old_line))
      end
      callback(old_line)
      return
    end

    -- If mapping is empty and no hunks, the file has no changes - return original line
    if vim.tbl_isempty(old_to_new) and (not hunks or #hunks == 0) then
      if vim.g.inline_reviews_debug then
        notifier.debug(string.format("Empty mapping (no diff) for %s:%d", file_path, old_line))
      end
      callback(old_line)
      return
    end

    -- Try direct mapping first (for lines in diff context)
    local new_line = old_to_new[old_line]
    if new_line then
      if vim.g.inline_reviews_debug then
        notifier.debug(string.format("Direct mapping: %s:%d -> %d", file_path, old_line, new_line))
      end
      callback(new_line)
      return
    end

    -- Line is not in direct context - calculate cumulative offset from hunks
    if hunks and #hunks > 0 then
      local offset = calculate_offset_for_line(hunks, old_line)
      if offset ~= nil then
        -- Line is outside all hunks, apply cumulative offset
        local mapped = old_line + offset
        mapped = math.max(1, mapped)
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Offset mapping: %s:%d -> %d (cumulative offset %+d)",
            file_path, old_line, mapped, offset))
        end
        callback(mapped)
        return
      else
        -- Line is inside a hunk but not in context - try to find nearest context line
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Line %d is inside a modified hunk, searching for nearest context", old_line))
        end
      end
    end

    -- Fallback: search for nearby mapped lines (for lines inside modified hunks)
    local max_search_distance = 20

    -- Search upward first (closer context is more reliable)
    for i = old_line - 1, math.max(1, old_line - max_search_distance), -1 do
      if old_to_new[i] then
        -- Found a mapped line above, estimate position
        local line_offset = old_line - i
        local estimated = old_to_new[i] + line_offset
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Estimated mapping (up): %s:%d -> %d (base %d + offset %d)",
            file_path, old_line, estimated, old_to_new[i], line_offset))
        end
        callback(estimated)
        return
      end
    end

    -- Search downward
    for i = old_line + 1, old_line + max_search_distance do
      if old_to_new[i] then
        -- Found a mapped line below, estimate position
        local line_offset = i - old_line
        local estimated = old_to_new[i] - line_offset
        -- Don't go below line 1
        estimated = math.max(1, estimated)
        if vim.g.inline_reviews_debug then
          notifier.debug(string.format("Estimated mapping (down): %s:%d -> %d (base %d - offset %d)",
            file_path, old_line, estimated, old_to_new[i], line_offset))
        end
        callback(estimated)
        return
      end
    end

    -- No mapping found at all - return original line
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

-- Debug: dump current cache state
function M.debug_dump_cache()
  local lines = { "=== Diff Cache State ===" }
  table.insert(lines, string.format("Cache entries: %d", vim.tbl_count(mappings_cache)))

  for cache_key, cached in pairs(mappings_cache) do
    table.insert(lines, "")
    table.insert(lines, string.format("Key: %s", cache_key))
    local age = os.time() - (cache_timestamps[cache_key] or 0)
    table.insert(lines, string.format("  Age: %ds", age))
    table.insert(lines, string.format("  Context mappings: %d", vim.tbl_count(cached.old_to_new or {})))
    table.insert(lines, string.format("  Hunks: %d", #(cached.hunks or {})))

    -- Show hunks
    if cached.hunks and #cached.hunks > 0 then
      for i, hunk in ipairs(cached.hunks) do
        local delta = (hunk.new_end - hunk.new_start + 1) - (hunk.old_end - hunk.old_start + 1)
        table.insert(lines, string.format("    Hunk %d: old %d-%d -> new %d-%d (delta %+d)",
          i, hunk.old_start, hunk.old_end, hunk.new_start, hunk.new_end, delta))
      end
    end

    -- Show a sample of context mappings
    local count = 0
    for old, new in pairs(cached.old_to_new or {}) do
      if count < 6 then
        table.insert(lines, string.format("    context: %d -> %d", old, new))
        count = count + 1
      else
        table.insert(lines, string.format("    ... and %d more context lines", vim.tbl_count(cached.old_to_new) - 6))
        break
      end
    end
  end

  return lines
end

-- Debug: test mapping for a specific file and line
function M.debug_test_mapping(file_path, old_line, base_ref)
  local lines = { "=== Testing Line Mapping ===" }
  table.insert(lines, string.format("File: %s", file_path))
  table.insert(lines, string.format("Original line: %d", old_line))
  table.insert(lines, string.format("Base ref: %s", base_ref or "HEAD"))

  -- Force fresh diff (clear cache first)
  M.clear_cache(file_path)

  M.map_line_to_current(file_path, old_line, base_ref, function(mapped_line)
    table.insert(lines, string.format("Mapped to: %d", mapped_line))
    table.insert(lines, "")

    -- Also show cache state for this file
    local cache_key = file_path .. ":" .. (base_ref or "HEAD")
    local cached = mappings_cache[cache_key]
    if cached then
      table.insert(lines, "Mappings in cache:")
      local sorted_keys = {}
      for k in pairs(cached.old_to_new or {}) do
        table.insert(sorted_keys, k)
      end
      table.sort(sorted_keys)
      for _, k in ipairs(sorted_keys) do
        local marker = k == old_line and " <-- target" or ""
        table.insert(lines, string.format("  %d -> %d%s", k, cached.old_to_new[k], marker))
      end
    end

    -- Print to messages
    for _, line in ipairs(lines) do
      print(line)
    end
  end)

  return lines
end

return M