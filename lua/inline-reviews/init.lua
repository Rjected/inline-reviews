local M = {}

local config = require("inline-reviews.config")
local github = require("inline-reviews.github")
local comments = require("inline-reviews.comments")
local ui = require("inline-reviews.ui")
local notifier = require("inline-reviews.ui.notifier")

local current_pr = nil
local loaded_buffers = {}

function M.setup(opts)
  if not config.setup(opts) then
    return
  end
  
  -- Initialize UI after config is set up
  ui.setup()
  
  -- Setup statuscolumn if enabled
  if config.get().statuscolumn and config.get().statuscolumn.enabled then
    require("inline-reviews.ui.statuscolumn_simple").setup()
  end
  
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
  
  -- Also update virtual text when text changes
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = augroup,
    callback = function()
      -- Clear all virtual text and refresh for current cursor position
      local bufnr = vim.api.nvim_get_current_buf()
      require("inline-reviews.ui.virtual_text").clear_buffer(bufnr)
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
  
  -- Auto-refresh line mappings on file save
  local diff_opts = config.get().diff_tracking
  if diff_opts and diff_opts.enabled and diff_opts.update_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      callback = function(ev)
        if M.has_comments_loaded() then
          local file_path = vim.api.nvim_buf_get_name(ev.buf)
          if file_path ~= "" then
            -- Schedule the refresh to run after the file is saved
            vim.defer_fn(function()
              comments.refresh_file_mappings(file_path)
            end, 100)
          end
        end
      end,
    })
  end
  
  -- Auto-refresh comments periodically
  local auto_refresh_opts = config.get().auto_refresh
  if auto_refresh_opts and auto_refresh_opts.enabled then
    local timer = vim.loop.new_timer()
    M._auto_refresh_timer = timer
    
    timer:start(
      auto_refresh_opts.interval * 1000, -- Initial delay
      auto_refresh_opts.interval * 1000, -- Repeat interval
      vim.schedule_wrap(function()
        if M.has_comments_loaded() then
          -- Silently reload in background
          M.reload(true)
        end
      end)
    )
  end
end

function M.load_pr(pr_number)
  notifier.info("Loading PR #" .. pr_number .. " comments...")
  
  -- Store the current PR number
  comments.set_current_pr(pr_number)
  
  github.get_pr_info(pr_number, function(pr_info)
    if not pr_info then
      notifier.error("Failed to load PR #" .. pr_number)
      return
    end
    
    current_pr = pr_info
    
    -- Set the base ref for diff tracking
    if pr_info.baseRefName then
      comments.set_pr_base_ref(pr_info.baseRefName)
    end
    
    github.get_review_comments(pr_number, function(review_comments)
      if not review_comments then
        notifier.error("Failed to load comments for PR #" .. pr_number)
        return
      end
      
      comments.load_comments(review_comments)
      ui.refresh_all_buffers()
      
      local count = #review_comments
      notifier.info(string.format("Loaded %d comment%s from PR #%d", 
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

function M.reload(silent)
  if current_pr then
    if not silent then
      notifier.info("Reloading PR #" .. current_pr.number .. " comments...")
    end
    
    local pr_number = current_pr.number
    github.get_review_comments(pr_number, function(review_comments)
      if not review_comments then
        if not silent then
          notifier.error("Failed to reload comments")
        end
        return
      end
      
      comments.load_comments(review_comments)
      ui.refresh_all_buffers()
      
      if not silent then
        local count = #review_comments
        notifier.info(string.format("Reloaded %d comment%s from PR #%d", 
          count, count == 1 and "" or "s", pr_number), vim.log.levels.INFO)
      end
    end)
  else
    if not silent then
      notifier.warn("No PR loaded. Use :InlineComments <PR_NUMBER> first.")
    end
  end
end

function M.clear()
  comments.clear()
  ui.clear_all_buffers()
  current_pr = nil
  
  -- Stop auto-refresh timer if running
  if M._auto_refresh_timer then
    M._auto_refresh_timer:stop()
    M._auto_refresh_timer:close()
    M._auto_refresh_timer = nil
  end
  
  notifier.info("Cleared all inline comments")
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
    notifier.info("No comments on this line")
  end
end

function M.next_comment()
  local next_line = comments.get_next_comment_line()
  if next_line then
    vim.api.nvim_win_set_cursor(0, { next_line, 0 })
  else
    notifier.info("No more comments")
  end
end

function M.prev_comment()
  local prev_line = comments.get_prev_comment_line()
  if prev_line then
    vim.api.nvim_win_set_cursor(0, { prev_line, 0 })
  else
    notifier.info("No previous comments")
  end
end

function M.toggle_resolved()
  local opts = config.get()
  opts.display.show_resolved = not opts.display.show_resolved
  ui.refresh_all_buffers()
  notifier.info("Resolved comments: " .. (opts.display.show_resolved and "shown" or "hidden"))
end

function M.has_comments_loaded()
  return current_pr ~= nil
end

return M