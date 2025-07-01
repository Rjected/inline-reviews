local M = {}

local config = require("inline-reviews.config")
local auth = require("inline-reviews.github.auth")
local graphql = require("inline-reviews.github.graphql")

local cache = {}
local cache_timestamps = {}

local function is_cache_valid(key)
  local timestamp = cache_timestamps[key]
  if not timestamp then return false end
  
  local ttl = config.get().github.cache_ttl
  return (os.time() - timestamp) < ttl
end

local function set_cache(key, value)
  cache[key] = value
  cache_timestamps[key] = os.time()
end

local function run_gh_command(args, callback)
  local gh_cmd = config.get().github.gh_cmd
  local timeout = config.get().github.timeout
  
  local cmd = { gh_cmd }
  vim.list_extend(cmd, args)
  
  -- Store all output for debugging
  local stdout_data = {}
  local stderr_data = {}
  
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      if data then
        vim.list_extend(stdout_data, data)
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        vim.list_extend(stderr_data, data)
      end
    end,
    on_exit = function(_, exit_code, _)
      -- Log the command for debugging
      if vim.g.inline_reviews_debug then
        vim.notify("Command: " .. table.concat(cmd, " "), vim.log.levels.DEBUG)
      end
      
      -- Handle stderr
      local stderr_str = table.concat(stderr_data, "\n"):gsub("^%s*(.-)%s*$", "%1")
      if stderr_str ~= "" and exit_code ~= 0 then
        callback(nil, "GitHub CLI error: " .. stderr_str)
        return
      end
      
      -- Handle stdout
      local stdout_str = table.concat(stdout_data, "\n"):gsub("^%s*(.-)%s*$", "%1")
      
      if stdout_str == "" then
        if exit_code ~= 0 then
          callback(nil, "Command failed with exit code: " .. exit_code)
        else
          callback(nil, "No output from command")
        end
        return
      end
      
      -- Log raw output for debugging
      if vim.g.inline_reviews_debug then
        vim.notify("Raw output: " .. vim.inspect(stdout_str), vim.log.levels.DEBUG)
      end
      
      -- Try to parse JSON
      local ok, result = pcall(vim.json.decode, stdout_str)
      if ok then
        callback(result)
      else
        -- Log the parse error with context
        local preview = stdout_str:sub(1, 200)
        if #stdout_str > 200 then
          preview = preview .. "..."
        end
        callback(nil, "Failed to parse JSON response. Output preview: " .. preview)
      end
    end,
  })
end

local function detect_vcs_and_get_branch(callback)
  -- First check if we're in a jj repo
  vim.fn.jobstart({ "jj", "root" }, {
    on_exit = function(_, jj_exit_code, _)
      if jj_exit_code == 0 then
        -- We're in a jj repo, get the current bookmark
        vim.fn.jobstart({ "jj", "log", "--no-graph", "-r", "@", "-T", "bookmarks" }, {
          stdout_buffered = true,
          on_stdout = function(_, data, _)
            if data and data[1] ~= "" then
              local bookmarks = vim.trim(data[1])
              -- jj can have multiple bookmarks, take the first one
              local branch = bookmarks:match("([^%s]+)")
              if branch then
                callback(branch, "jj")
              else
                callback(nil)
              end
            else
              callback(nil)
            end
          end,
        })
      else
        -- Not jj, try git
        vim.fn.jobstart({ "git", "branch", "--show-current" }, {
          stdout_buffered = true,
          on_stdout = function(_, data, _)
            if data and data[1] ~= "" then
              callback(vim.trim(data[1]), "git")
            else
              callback(nil)
            end
          end,
          on_exit = function(_, exit_code, _)
            if exit_code ~= 0 then
              callback(nil)
            end
          end,
        })
      end
    end,
  })
end

function M.get_current_pr(callback)
  detect_vcs_and_get_branch(function(branch, vcs_type)
    if not branch then
      callback(nil)
      return
    end
    
    -- For jj, we might need to strip prefixes like "push-" that jj git adds
    if vcs_type == "jj" and branch:match("^push%-") then
      branch = branch:gsub("^push%-", "")
    end
    
    -- Try to find PR for this branch
    run_gh_command({
      "pr", "list",
      "--head", branch,
      "--json", "number",
      "--limit", "1"
    }, function(result, err)
      if err or not result or #result == 0 then
        callback(nil)
      else
        callback(result[1].number)
      end
    end)
  end)
end

function M.get_pr_info(pr_number, callback)
  local cache_key = "pr_info_" .. pr_number
  
  if is_cache_valid(cache_key) then
    callback(cache[cache_key])
    return
  end
  
  run_gh_command({
    "pr", "view", tostring(pr_number),
    "--json", "number,title,state,url,headRefName,baseRefName"
  }, function(result, err)
    if err then
      vim.notify("Failed to get PR info: " .. err, vim.log.levels.ERROR)
      callback(nil)
    else
      set_cache(cache_key, result)
      callback(result)
    end
  end)
end

function M.get_review_comments(pr_number, callback)
  -- For review comments, we'll use GraphQL for better control
  local query = graphql.review_comments_query(pr_number)
  
  if not query then
    callback(nil)
    return
  end
  
  run_gh_command({
    "api", "graphql",
    "-f", "query=" .. query
  }, function(result, err)
    if err then
      vim.notify("Failed to get review comments: " .. err, vim.log.levels.ERROR)
      callback(nil)
      return
    end
    
    -- Parse and transform the GraphQL response
    local comments = graphql.parse_review_comments(result)
    callback(comments)
  end)
end

function M.check_auth(callback)
  auth.check(callback)
end

function M.clear_cache()
  cache = {}
  cache_timestamps = {}
end

return M