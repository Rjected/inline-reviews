local M = {}

local notifier = require("inline-reviews.ui.notifier")

function M.debounce(fn, ms)
  local timer = nil
  
  return function(...)
    local args = { ... }
    
    if timer then
      vim.fn.timer_stop(timer)
    end
    
    timer = vim.fn.timer_start(ms, function()
      timer = nil
      fn(unpack(args))
    end)
  end
end

function M.throttle(fn, ms)
  local last_call = 0
  local timer = nil
  
  return function(...)
    local args = { ... }
    local now = vim.loop.now()
    
    if now - last_call >= ms then
      last_call = now
      fn(unpack(args))
    elseif not timer then
      timer = vim.fn.timer_start(ms - (now - last_call), function()
        timer = nil
        last_call = vim.loop.now()
        fn(unpack(args))
      end)
    end
  end
end

function M.get_visual_selection()
  local s_start = vim.fn.getpos("'<")
  local s_end = vim.fn.getpos("'>")
  local n_lines = math.abs(s_end[2] - s_start[2]) + 1
  local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
  
  if n_lines == 1 then
    lines[1] = string.sub(lines[1], s_start[3], s_end[3])
  else
    lines[1] = string.sub(lines[1], s_start[3])
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3])
  end
  
  return table.concat(lines, "\n")
end

function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.schedule(function()
    notifier.notify(msg, level, { title = "Inline Reviews" })
  end)
end

return M