local M = {}

local config = require("inline-reviews.config")
local notifier = require("inline-reviews.ui.notifier")

-- Helper to run GraphQL mutations
local function run_mutation(mutation_query, callback)
  local gh_cmd = config.get().github.gh_cmd
  
  local cmd = { gh_cmd, "api", "graphql", "-f", "query=" .. mutation_query }
  
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
      if vim.g.inline_reviews_debug then
        notifier.debug("Mutation command: " .. table.concat(cmd, " "))
      end
      
      local stderr_str = table.concat(stderr_data, "\n"):gsub("^%s*(.-)%s*$", "%1")
      if stderr_str ~= "" and exit_code ~= 0 then
        callback(nil, "GitHub CLI error: " .. stderr_str)
        return
      end
      
      local stdout_str = table.concat(stdout_data, "\n"):gsub("^%s*(.-)%s*$", "%1")
      
      if stdout_str == "" then
        callback(nil, "No output from mutation")
        return
      end
      
      local ok, result = pcall(vim.json.decode, stdout_str)
      if ok then
        -- Check for GraphQL errors
        if result.errors then
          local error_msg = "GraphQL errors: "
          for _, err in ipairs(result.errors) do
            error_msg = error_msg .. err.message .. " "
          end
          callback(nil, error_msg)
        else
          callback(result.data)
        end
      else
        callback(nil, "Failed to parse JSON response")
      end
    end,
  })
end

-- Add a reply to a review thread
function M.add_reply(thread_id, body, callback)
  local mutation = string.format([[
    mutation {
      addPullRequestReviewThreadReply(input: {
        pullRequestReviewThreadId: "%s"
        body: "%s"
      }) {
        comment {
          id
          body
          author {
            login
            avatarUrl
          }
          createdAt
        }
      }
    }
  ]], thread_id, body:gsub('"', '\\"'):gsub('\n', '\\n'))
  
  run_mutation(mutation, function(data, err)
    if err then
      callback(nil, err)
    elseif data and data.addPullRequestReviewThreadReply then
      callback(data.addPullRequestReviewThreadReply.comment)
    else
      callback(nil, "Unexpected response format")
    end
  end)
end

-- Add a reaction to a comment
function M.add_reaction(subject_id, content, callback)
  -- Valid reaction content: THUMBS_UP, THUMBS_DOWN, LAUGH, HOORAY, CONFUSED, HEART, ROCKET, EYES
  local mutation = string.format([[
    mutation {
      addReaction(input: {
        subjectId: "%s"
        content: %s
      }) {
        reaction {
          id
          content
        }
        subject {
          id
        }
      }
    }
  ]], subject_id, content)
  
  run_mutation(mutation, function(data, err)
    if err then
      callback(nil, err)
    elseif data and data.addReaction then
      callback(data.addReaction.reaction)
    else
      callback(nil, "Unexpected response format")
    end
  end)
end

-- Remove a reaction from a comment
function M.remove_reaction(subject_id, content, callback)
  local mutation = string.format([[
    mutation {
      removeReaction(input: {
        subjectId: "%s"
        content: %s
      }) {
        reaction {
          id
          content
        }
      }
    }
  ]], subject_id, content)
  
  run_mutation(mutation, function(data, err)
    if err then
      callback(nil, err)
    elseif data and data.removeReaction then
      callback(data.removeReaction.reaction)
    else
      callback(nil, "Unexpected response format")
    end
  end)
end

-- Resolve a review thread
function M.resolve_thread(thread_id, callback)
  local mutation = string.format([[
    mutation {
      resolveReviewThread(input: {
        threadId: "%s"
      }) {
        thread {
          id
          isResolved
        }
      }
    }
  ]], thread_id)
  
  run_mutation(mutation, function(data, err)
    if err then
      callback(nil, err)
    elseif data and data.resolveReviewThread then
      callback(data.resolveReviewThread.thread)
    else
      callback(nil, "Unexpected response format")
    end
  end)
end

-- Unresolve a review thread
function M.unresolve_thread(thread_id, callback)
  local mutation = string.format([[
    mutation {
      unresolveReviewThread(input: {
        threadId: "%s"
      }) {
        thread {
          id
          isResolved
        }
      }
    }
  ]], thread_id)
  
  run_mutation(mutation, function(data, err)
    if err then
      callback(nil, err)
    elseif data and data.unresolveReviewThread then
      callback(data.unresolveReviewThread.thread)
    else
      callback(nil, "Unexpected response format")
    end
  end)
end

-- Map emoji to GraphQL enum values
M.emoji_to_content = {
  ["👍"] = "THUMBS_UP",
  ["👎"] = "THUMBS_DOWN",
  ["😄"] = "LAUGH",
  ["🎉"] = "HOORAY",
  ["😕"] = "CONFUSED",
  ["❤️"] = "HEART",
  ["🚀"] = "ROCKET",
  ["👀"] = "EYES",
}

-- Reverse mapping
M.content_to_emoji = {}
for emoji, content in pairs(M.emoji_to_content) do
  M.content_to_emoji[content] = emoji
end

return M