local M = {}

function M.review_comments_query(pr_number)
  -- GraphQL query to fetch all review comments for a PR
  return string.format([[
    query {
      viewer {
        login
      }
      repository(owner: "OWNER", name: "REPO") {
        pullRequest(number: %d) {
          reviewThreads(first: 100) {
            nodes {
              id
              path
              line
              originalLine
              diffSide
              isResolved
              isOutdated
              comments(first: 50) {
                nodes {
                  id
                  body
                  author {
                    login
                    avatarUrl
                  }
                  createdAt
                  lastEditedAt
                  diffHunk
                  position
                  originalPosition
                  reactionGroups {
                    content
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ]], pr_number)
end

function M.parse_review_comments(response)
  local comments = {}
  
  if not response or not response.data then
    return comments
  end
  
  local pr = response.data.repository and response.data.repository.pullRequest
  if not pr or not pr.reviewThreads then
    return comments
  end
  
  for _, thread in ipairs(pr.reviewThreads.nodes or {}) do
    local thread_comments = {}
    
    for _, comment in ipairs(thread.comments.nodes or {}) do
      table.insert(thread_comments, {
        id = comment.id,
        body = comment.body,
        author = comment.author.login,
        author_avatar = comment.author.avatarUrl,
        created_at = comment.createdAt,
        edited_at = comment.lastEditedAt,
        diff_hunk = comment.diffHunk,
        position = comment.position,
        original_position = comment.originalPosition,
        reactions = comment.reactionGroups,
      })
    end
    
    if #thread_comments > 0 then
      -- Convert vim.NIL to nil for easier handling
      local line = thread.line
      if line == vim.NIL then
        line = nil
      end
      local original_line = thread.originalLine
      if original_line == vim.NIL then
        original_line = nil
      end
      
      table.insert(comments, {
        id = thread.id,
        path = thread.path,
        line = line,
        original_line = original_line,
        side = thread.diffSide,
        is_resolved = thread.isResolved,
        is_outdated = thread.isOutdated,
        comments = thread_comments,
      })
    end
  end
  
  return comments
end

-- Helper to get repository info from current repo (git or jj)
function M.get_repo_info()
  -- First try to check if we're in a jj repo
  local jj_handle = io.popen("jj root 2>/dev/null")
  if jj_handle then
    local jj_root = jj_handle:read("*a")
    jj_handle:close()
    
    if jj_root and jj_root ~= "" then
      -- We're in a jj repo, get the git remote URL through jj
      local jj_remote_handle = io.popen("cd " .. vim.fn.shellescape(vim.trim(jj_root)) .. " && jj git remote list 2>/dev/null | grep origin | awk '{print $2}'")
      if jj_remote_handle then
        local url = jj_remote_handle:read("*a")
        jj_remote_handle:close()
        
        if url and url ~= "" then
          -- Parse the URL
          local owner, repo = url:match("github%.com[:/]([^/]+)/([^%.]+)")
          if owner and repo then
            repo = repo:gsub("%.git$", ""):gsub("\n$", "")
            return owner, repo
          end
        end
      end
    end
  end
  
  -- Fall back to git
  local handle = io.popen("git remote get-url origin 2>/dev/null")
  if not handle then return nil, nil end
  
  local url = handle:read("*a")
  handle:close()
  
  if not url or url == "" then return nil, nil end
  
  -- Parse GitHub URL formats
  -- https://github.com/owner/repo.git
  -- git@github.com:owner/repo.git
  local owner, repo = url:match("github%.com[:/]([^/]+)/([^%.]+)")
  if owner and repo then
    repo = repo:gsub("%.git$", ""):gsub("\n$", "")
    return owner, repo
  end
  
  return nil, nil
end

-- Update query with actual repo info
function M.review_comments_query(pr_number)
  local owner, repo = M.get_repo_info()
  if not owner or not repo then
    vim.notify("Could not determine repository info", vim.log.levels.ERROR)
    return nil
  end
  
  return string.format([[
    query {
      viewer {
        login
      }
      repository(owner: "%s", name: "%s") {
        pullRequest(number: %d) {
          reviewThreads(first: 100) {
            nodes {
              id
              path
              line
              originalLine
              diffSide
              isResolved
              isOutdated
              comments(first: 50) {
                nodes {
                  id
                  body
                  author {
                    login
                    avatarUrl
                  }
                  createdAt
                  lastEditedAt
                  diffHunk
                  position
                  originalPosition
                  reactionGroups {
                    content
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ]], owner, repo, pr_number)
end

return M