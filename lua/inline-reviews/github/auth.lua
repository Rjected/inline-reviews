local M = {}

local config = require("inline-reviews.config")

function M.check(callback)
  local gh_cmd = config.get().github.gh_cmd
  
  vim.fn.jobstart({ gh_cmd, "auth", "status" }, {
    on_exit = function(_, exit_code, _)
      if exit_code == 0 then
        callback(true)
      else
        vim.notify("GitHub CLI not authenticated. Run 'gh auth login' first.", vim.log.levels.ERROR)
        callback(false)
      end
    end,
  })
end

function M.get_token(callback)
  local gh_cmd = config.get().github.gh_cmd
  
  vim.fn.jobstart({ gh_cmd, "auth", "token" }, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      if data and data[1] ~= "" then
        callback(vim.trim(data[1]))
      else
        callback(nil)
      end
    end,
    on_stderr = function(_, _, _)
      callback(nil)
    end,
  })
end

return M