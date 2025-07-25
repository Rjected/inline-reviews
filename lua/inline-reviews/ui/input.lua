local M = {}

local config = require("inline-reviews.config")
local notifier = require("inline-reviews.ui.notifier")

local input_win = nil
local input_buf = nil
local on_submit_callback = nil
local on_cancel_callback = nil
local parent_win = nil

-- Helper to check if snacks is available and user wants to use it
local function use_snacks()
  local cfg = config.get()
  local backend = cfg.ui and cfg.ui.backend or "auto"
  
  if backend == "native" then
    return false
  elseif backend == "snacks" then
    local ok, snacks = pcall(require, "snacks")
    if not ok or not snacks or not snacks.input then
      error("snacks.nvim is not available but ui.backend is set to 'snacks'")
    end
    return true
  else -- auto
    local ok, snacks = pcall(require, "snacks")
    return ok and snacks and snacks.input
  end
end

-- Show input using snacks.nvim
local function show_with_snacks(opts)
  local snacks = require("snacks")
  
  local title = opts.title or "Reply"
  local prompt = title .. " (Enter to submit, Esc to cancel): "
  
  -- Use snacks.input
  snacks.input({
    prompt = prompt,
    default = opts.initial_text or "",
    width = opts.width or 60,
    on_confirm = function(value)
      if value and value ~= "" then
        if opts.on_submit then
          -- Simulate the callback pattern used by native implementation
          opts.on_submit(value, function(success, message)
            if success then
              notifier.info(message or "Submitted!")
            else
              notifier.error(message or "Failed to submit")
            end
          end)
        end
      else
        notifier.warn("Cannot submit empty comment")
      end
    end,
    on_cancel = function()
      if opts.on_cancel then
        opts.on_cancel()
      end
    end,
  })
end

-- Native implementation continues below
local function show_native(opts)
  -- Close any existing input
  M.close()
  
  -- Save parent window
  parent_win = opts.parent_win or vim.api.nvim_get_current_win()
  
  -- Create buffer
  input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(input_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(input_buf, "bufhidden", "wipe")
  
  -- Set initial content if provided
  if opts.initial_text then
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, vim.split(opts.initial_text, "\n"))
  end
  
  -- Calculate window size and position
  local width = opts.width or 60
  local height = opts.height or 3
  local row = opts.row
  local col = opts.col
  
  -- If no position provided, position below cursor in parent window
  if not row or not col then
    local cursor_pos = vim.api.nvim_win_get_cursor(parent_win)
    local win_pos = vim.api.nvim_win_get_position(parent_win)
    local win_height = vim.api.nvim_win_get_height(parent_win)
    
    -- Position below current line in parent window
    row = win_pos[1] + cursor_pos[1] + 1
    col = win_pos[2] + 10
    
    -- Adjust if would go off screen
    if row + height > vim.o.lines - 2 then
      row = math.max(0, win_pos[1] + cursor_pos[1] - height - 1)
    end
  end
  
  -- Create window with simplified title
  local title = opts.title or " Reply "
  title = title .. "(C-s to submit) "
  
  input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    title = title,
    title_pos = "center",
  })
  
  -- Set window options
  vim.api.nvim_win_set_option(input_win, "wrap", true)
  vim.api.nvim_win_set_option(input_win, "linebreak", true)
  vim.api.nvim_win_set_option(input_win, "cursorline", false)
  
  -- Store callbacks
  on_submit_callback = opts.on_submit
  on_cancel_callback = opts.on_cancel
  
  -- Set up keymaps
  local keymap_opts = { noremap = true, silent = true, buffer = input_buf }
  
  -- Submit with Ctrl-s (lowercase)
  vim.keymap.set("n", "<C-s>", function()
    M.submit()
  end, keymap_opts)
  
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    M.submit()
  end, keymap_opts)
  
  -- Also try with different notation
  vim.keymap.set({"n", "i"}, "<c-s>", function()
    if vim.fn.mode() == "i" then
      vim.cmd("stopinsert")
    end
    M.submit()
  end, keymap_opts)
  
  -- Also support Ctrl-Enter
  vim.keymap.set("n", "<C-CR>", function()
    M.submit()
  end, keymap_opts)
  
  vim.keymap.set("i", "<C-CR>", function()
    vim.cmd("stopinsert")
    M.submit()
  end, keymap_opts)
  
  -- Cancel with Escape
  vim.keymap.set("n", "<Esc>", function()
    M.cancel()
  end, keymap_opts)
  
  vim.keymap.set("i", "<Esc>", function()
    vim.cmd("stopinsert")
    M.cancel()
  end, keymap_opts)
  
  -- Start in insert mode
  vim.cmd("startinsert")
  
  -- Create buffer-local command for submitting
  vim.api.nvim_buf_create_user_command(input_buf, "Submit", function()
    M.submit()
  end, {})
  
  -- Also map :w to submit (common pattern)
  vim.keymap.set("n", ":w<CR>", function()
    M.submit()
  end, { buffer = input_buf, silent = true })
  
  -- Auto-close on window leave (but not when submitting)
  local is_submitting = false
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = input_buf,
    once = true,
    callback = function()
      vim.schedule(function()
        -- Don't close if we're in the middle of submitting
        if not is_submitting and M.is_open() then
          M.close()
        end
      end)
    end,
  })
  
  -- Track when we're submitting
  vim.b[input_buf]._is_submitting = function()
    is_submitting = true
  end
  
  -- Don't show help text as virtual lines since it interferes with editing
end

-- Create a floating input window
function M.show(opts)
  opts = opts or {}
  
  if use_snacks() then
    show_with_snacks(opts)
    return
  end
  
  show_native(opts)
end

function M.submit()
  if not input_buf or not vim.api.nvim_buf_is_valid(input_buf) then
    if vim.g.inline_reviews_debug then
      notifier.debug("Submit: invalid buffer")
    end
    return
  end
  
  -- Mark that we're submitting
  if vim.b[input_buf]._is_submitting then
    vim.b[input_buf]._is_submitting()
  end
  
  -- Get the text
  local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
  local text = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")
  
  if vim.g.inline_reviews_debug then
    notifier.debug("Submit: text = " .. vim.inspect(text))
  end
  
  -- Save callback before updating UI
  local callback = on_submit_callback
  
  if text == "" then
    notifier.warn("Cannot submit empty comment")
    return
  end
  
  -- Update window to show submitting state
  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_win_set_config(input_win, {
      title = " Submitting... ",
      title_pos = "center",
    })
    
    -- Make buffer read-only
    vim.api.nvim_buf_set_option(input_buf, "modifiable", false)
    
    -- Call submit callback
    if callback then
      callback(text, function(success, message)
        -- Handle result
        if success then
          -- Show success state briefly
          if input_win and vim.api.nvim_win_is_valid(input_win) then
            vim.api.nvim_win_set_config(input_win, {
              title = " Submitted! ",
              title_pos = "center",
            })
            -- Close after a short delay
            vim.defer_fn(function()
              M.close()
            end, 500)
          else
            M.close()
          end
        else
          -- Show error and allow retry
          if input_win and vim.api.nvim_win_is_valid(input_win) then
            vim.api.nvim_win_set_config(input_win, {
              title = " Failed! " .. (message or "") .. " ",
              title_pos = "center",
            })
            -- Make buffer editable again
            vim.api.nvim_buf_set_option(input_buf, "modifiable", true)
            -- Focus window
            vim.api.nvim_set_current_win(input_win)
          end
        end
      end)
    else
      -- No callback, just close
      M.close()
    end
  end
end

function M.cancel()
  if on_cancel_callback then
    on_cancel_callback()
  end
  M.close()
end

function M.close()
  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_win_close(input_win, true)
  end
  
  if input_buf and vim.api.nvim_buf_is_valid(input_buf) then
    vim.api.nvim_buf_delete(input_buf, { force = true })
  end
  
  input_win = nil
  input_buf = nil
  on_submit_callback = nil
  on_cancel_callback = nil
  
  -- Return focus to parent window if valid
  if parent_win and vim.api.nvim_win_is_valid(parent_win) then
    vim.api.nvim_set_current_win(parent_win)
  end
end

function M.is_open()
  return input_win ~= nil and vim.api.nvim_win_is_valid(input_win)
end

return M