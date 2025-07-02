local M = {}

local config = require("inline-reviews.config")
local comments = require("inline-reviews.comments")
local notifier = require("inline-reviews.ui.notifier")

-- Helper to check if snacks is available and user wants to use it
local function use_snacks()
  local cfg = config.get()
  local backend = cfg.ui and cfg.ui.backend or "auto"
  
  if backend == "native" then
    return false
  elseif backend == "snacks" then
    local ok, snacks = pcall(require, "snacks")
    if not ok or not snacks or not snacks.picker then
      error("snacks.nvim is not available but ui.backend is set to 'snacks'")
    end
    return true
  else -- auto
    local ok, snacks = pcall(require, "snacks")
    return ok and snacks and snacks.picker
  end
end

-- Helper to check if telescope is available
local function has_telescope()
  local ok = pcall(require, "telescope")
  return ok
end

-- Show picker using snacks.nvim
local function show_with_snacks()
  local snacks = require("snacks")
  
  -- Get all comments
  local all_threads = comments._get_all_comments()
  if #all_threads == 0 then
    notifier.info("No comments to display")
    return
  end
  
  -- Create items as objects with text property
  local items = {}
  
  for _, comment_entry in ipairs(all_threads) do
    local thread = comment_entry.thread
    local comment = thread.comments[1]
    local prefix = thread.is_resolved and "[✓] " or ""
    local outdated = thread.is_outdated and " [OUTDATED]" or ""
    local file = vim.fn.fnamemodify(comment_entry.file, ":~:.")
    
    -- Create display string
    local display = string.format("%s%s: %s", 
      prefix, 
      comment.author, 
      comment.body:gsub("\n", " "):sub(1, 60))
    
    -- Add file info
    display = display .. " " .. file .. ":" .. comment_entry.line .. outdated
    
    -- Create item object
    table.insert(items, {
      text = display,
      comment_entry = comment_entry,
    })
  end
  
  -- Use snacks.picker with proper item structure
  local picker_items = {}
  
  for _, item in ipairs(items) do
    -- Each item needs a text field for filtering/matching
    table.insert(picker_items, {
      text = item.text,  -- This is what will be searched/matched
      display = item.text,  -- This is what we'll display
      comment_entry = item.comment_entry,  -- Our custom data
      file = item.comment_entry.file,  -- For file preview
      pos = { item.comment_entry.line, 0 },  -- For jumping to location
    })
  end
  
  -- Create picker with custom config
  snacks.picker({
    title = " PR Comments ",
    items = picker_items,
    format = function(item)
      -- Format function should return highlight data, not just a string
      -- Return an array of highlight specs
      return {
        { item.display or item.text or "" }
      }
    end,
    preview = function(ctx)
      local item = ctx.item
      if not item or not item.comment_entry then 
        return false
      end
      
      local comment_entry = item.comment_entry
      local thread = comment_entry.thread
      local lines = {}
      
      -- Show file content
      if vim.fn.filereadable(comment_entry.file) == 1 then
        local file_lines = vim.fn.readfile(comment_entry.file)
        local target_line = comment_entry.line
        local start_line = math.max(1, target_line - 15)
        local end_line = math.min(#file_lines, target_line + 15)
        
        for i = start_line, end_line do
          local prefix = i == target_line and "> " or "  "
          table.insert(lines, string.format("%s%4d │ %s", prefix, i, file_lines[i] or ""))
        end
        
        table.insert(lines, "")
        table.insert(lines, "─────────────────────────")
        table.insert(lines, "")
      end
      
      -- Add comment info
      table.insert(lines, "Status: " .. (thread.is_resolved and "✓ Resolved" or "○ Open"))
      table.insert(lines, "")
      
      -- Add comments
      for i, comment in ipairs(thread.comments) do
        if i > 1 then
          table.insert(lines, "───")
        end
        
        table.insert(lines, "● " .. comment.author .. " • " .. comment.created_at:sub(1, 10))
        table.insert(lines, "")
        
        -- Comment body
        local body_lines = {}
        for line in comment.body:gmatch("[^\n]+") do
          table.insert(body_lines, line)
        end
        
        for j, line in ipairs(body_lines) do
          if j <= 10 then
            table.insert(lines, "  " .. line)
          elseif j == 11 then
            table.insert(lines, "  ...")
            break
          end
        end
        
        -- Reactions
        if comment.reactions and #comment.reactions > 0 then
          local reaction_parts = {}
          for _, reaction in ipairs(comment.reactions) do
            if reaction.users and reaction.users.totalCount > 0 then
              local emoji = require("inline-reviews.github.mutations").content_to_emoji[reaction.content] or "?"
              table.insert(reaction_parts, emoji .. "×" .. reaction.users.totalCount)
            end
          end
          if #reaction_parts > 0 then
            table.insert(lines, "  " .. table.concat(reaction_parts, " "))
          end
        end
      end
      
      -- Set preview buffer content
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
      
      -- Set filetype for syntax highlighting
      local ft = vim.filetype.match({ filename = comment_entry.file }) or "text"
      vim.api.nvim_set_option_value("filetype", ft, { buf = ctx.buf })
      
      return true
    end,
    actions = {
      default = function(picker, item)
        if not item or not item.comment_entry then return end
        
        local comment_entry = item.comment_entry
        
        -- Close picker
        picker:close()
        
        -- Open file
        vim.cmd("edit " .. vim.fn.fnameescape(comment_entry.file))
        -- Go to line
        vim.api.nvim_win_set_cursor(0, { comment_entry.line, 0 })
        -- Show comment hover
        vim.schedule(function()
          require("inline-reviews").view_comments()
        end)
      end,
    },
  })
end

-- Show picker using telescope
local function show_with_telescope()
  local ok, telescope = pcall(require, "telescope")
  if not ok then
    notifier.error("Neither snacks.nvim picker nor telescope is available")
    return
  end
  
  -- Load the extension if not already loaded
  pcall(telescope.load_extension, "inline_reviews")
  
  -- Launch the picker
  telescope.extensions.inline_reviews.comments()
end

-- Main entry point
function M.show()
  if use_snacks() then
    show_with_snacks()
  elseif has_telescope() then
    show_with_telescope()
  else
    notifier.error("No picker available. Install snacks.nvim or telescope.nvim")
  end
end

return M