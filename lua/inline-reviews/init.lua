local M = {}

local config = require("inline-reviews.config")
local github = require("inline-reviews.github")
local comments = require("inline-reviews.comments")
local ui = require("inline-reviews.ui")

local current_pr = nil
local loaded_buffers = {}

function M.setup(opts)
  if not config.setup(opts) then
    return
  end
  
  -- Initialize UI after config is set up
  ui.setup()
  
  -- Set up keymaps
  local keymaps = config.get().keymaps
  for action, key in pairs(keymaps) do
    if key and key ~= "" then
      if action == "telescope_comments" then
        -- Special handling for telescope
        vim.keymap.set("n", key, function()
          vim.cmd("InlineCommentsTelescope")
        end, { desc = "Inline Reviews: browse comments with telescope" })
      elseif M[action] then
        vim.keymap.set("n", key, function()
          M[action]()
        end, { desc = "Inline Reviews: " .. action:gsub("_", " ") })
      end
    end
  end
  
  -- Set up autocommands
  local augroup = vim.api.nvim_create_augroup("InlineReviews", { clear = true })
  
  -- Auto-load PR if configured
  if config.get().auto_load then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      callback = function(ev)
        if not loaded_buffers[ev.buf] then
          loaded_buffers[ev.buf] = true
          M.auto_load()
        end
      end,
    })
  end
  
  -- Refresh UI when entering a buffer (signs might have been cleared)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      -- Only refresh if we have comments loaded
      if M.has_comments_loaded() then
        ui.refresh_buffer(ev.buf)
      end
    end,
  })
  
  -- Update virtual text on cursor move
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    callback = function()
      ui.update_virtual_text()
    end,
  })
  
  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    callback = function(ev)
      ui.clear_buffer(ev.buf)
      loaded_buffers[ev.buf] = nil
    end,
  })
end

function M.load_pr(pr_number)
  vim.notify("Loading PR #" .. pr_number .. " comments...", vim.log.levels.INFO)
  
  github.get_pr_info(pr_number, function(pr_info)
    if not pr_info then
      vim.notify("Failed to load PR #" .. pr_number, vim.log.levels.ERROR)
      return
    end
    
    current_pr = pr_info
    
    github.get_review_comments(pr_number, function(review_comments)
      if not review_comments then
        vim.notify("Failed to load comments for PR #" .. pr_number, vim.log.levels.ERROR)
        return
      end
      
      comments.load_comments(review_comments)
      ui.refresh_all_buffers()
      
      local count = #review_comments
      vim.notify(string.format("Loaded %d comment%s from PR #%d", 
        count, count == 1 and "" or "s", pr_number), vim.log.levels.INFO)
    end)
  end)
end

function M.auto_load()
  github.get_current_pr(function(pr_number)
    if pr_number then
      M.load_pr(pr_number)
    end
  end)
end

function M.reload()
  if current_pr then
    M.load_pr(current_pr.number)
  else
    vim.notify("No PR loaded. Use :InlineComments <PR_NUMBER> first.", vim.log.levels.WARN)
  end
end

function M.clear()
  comments.clear()
  ui.clear_all_buffers()
  current_pr = nil
  vim.notify("Cleared all inline comments", vim.log.levels.INFO)
end

function M.view_comments()
  -- Check if hover is already open - if so, focus it
  local hover = require("inline-reviews.ui.hover")
  if hover.is_open() then
    hover.focus()
    return
  end
  
  -- Otherwise, show comments for current line
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  
  local thread_comments = comments.get_comments_for_line(file_path, line)
  if #thread_comments > 0 then
    ui.show_comment_hover(thread_comments)
  else
    vim.notify("No comments on this line", vim.log.levels.INFO)
  end
end

function M.next_comment()
  local next_line = comments.get_next_comment_line()
  if next_line then
    vim.api.nvim_win_set_cursor(0, { next_line, 0 })
  else
    vim.notify("No more comments", vim.log.levels.INFO)
  end
end

function M.prev_comment()
  local prev_line = comments.get_prev_comment_line()
  if prev_line then
    vim.api.nvim_win_set_cursor(0, { prev_line, 0 })
  else
    vim.notify("No previous comments", vim.log.levels.INFO)
  end
end

function M.toggle_resolved()
  local opts = config.get()
  opts.display.show_resolved = not opts.display.show_resolved
  ui.refresh_all_buffers()
  vim.notify("Resolved comments: " .. (opts.display.show_resolved and "shown" or "hidden"))
end

function M.has_comments_loaded()
  return current_pr ~= nil
end

return M