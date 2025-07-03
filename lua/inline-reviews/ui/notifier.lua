local M = {}

-- Notification wrapper that supports both vim.notify and snacks.nvim
-- Falls back gracefully if snacks.nvim is not available

local function has_snacks()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks and snacks.notify
end

-- Map vim.log.levels to snacks notification types
local level_map = {
  [vim.log.levels.ERROR] = "error",
  [vim.log.levels.WARN] = "warn",
  [vim.log.levels.INFO] = "info",
  [vim.log.levels.DEBUG] = "debug",
  [vim.log.levels.TRACE] = "trace",
}

-- Main notify function that wraps vim.notify
function M.notify(msg, level, opts)
  -- Debug type checking
  if type(opts) == "number" then
    -- This is likely the old vim.notify signature where third param is a number
    -- Convert it to the new signature
    opts = {}
  end
  
  opts = opts or {}
  level = level or vim.log.levels.INFO
  
  if has_snacks() then
    local snacks = require("snacks")
    local snacks_opts = {
      title = opts.title,
      level = level_map[level] or "info",
    }
    
    -- Pass through any snacks-specific options
    if opts.id then snacks_opts.id = opts.id end
    if opts.timeout then snacks_opts.timeout = opts.timeout end
    if opts.icon then snacks_opts.icon = opts.icon end
    
    snacks.notify(msg, snacks_opts)
  else
    -- Fallback to vim.notify
    vim.notify(msg, level, opts)
  end
end

-- Progress notification that can be updated
function M.progress(id, msg, percentage)
  local opts = {
    id = "inline_reviews_progress_" .. id,
    title = "Inline Reviews",
  }
  
  if percentage then
    msg = string.format("%s (%.0f%%)", msg, percentage * 100)
  end
  
  M.notify(msg, vim.log.levels.INFO, opts)
end

-- Convenience functions
function M.info(msg, opts)
  -- Handle case where opts might be passed as a number (old vim.notify pattern)
  if type(opts) == "number" then
    opts = nil
  end
  M.notify(msg, vim.log.levels.INFO, opts)
end

function M.warn(msg, opts)
  if type(opts) == "number" then
    opts = nil
  end
  M.notify(msg, vim.log.levels.WARN, opts)
end

function M.error(msg, opts)
  if type(opts) == "number" then
    opts = nil
  end
  M.notify(msg, vim.log.levels.ERROR, opts)
end

function M.debug(msg, opts)
  if vim.g.inline_reviews_debug then
    if type(opts) == "number" then
      opts = nil
    end
    M.notify(msg, vim.log.levels.DEBUG, opts)
  end
end

return M