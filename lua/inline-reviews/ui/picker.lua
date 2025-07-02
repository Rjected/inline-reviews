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
    local comment_entry = item.comment_entry
    local thread = comment_entry.thread
    
    -- Build preview text
    local preview_lines = {}
    
    -- Add file path
    table.insert(preview_lines, vim.fn.fnamemodify(comment_entry.file, ":~:.") .. ":" .. comment_entry.line)
    table.insert(preview_lines, "")
    
    -- Add thread status
    local status = thread.is_resolved and "✓ Resolved" or "○ Open"
    if thread.is_outdated then
      status = status .. " (Outdated)"
    end
    table.insert(preview_lines, "Thread: " .. status)
    table.insert(preview_lines, "")
    
    -- Add first comment
    local first_comment = thread.comments[1]
    if first_comment then
      table.insert(preview_lines, "● " .. first_comment.author .. " • " .. first_comment.created_at:sub(1, 10))
      table.insert(preview_lines, "")
      
      -- Add comment body (first few lines)
      local body_lines = {}
      for line in first_comment.body:gmatch("[^\n]+") do
        table.insert(body_lines, line)
      end
      
      for j = 1, math.min(#body_lines, 5) do
        table.insert(preview_lines, "  " .. body_lines[j])
      end
      
      if #body_lines > 5 then
        table.insert(preview_lines, "  ...")
      end
    end
    
    -- Each item needs a text field for filtering/matching
    table.insert(picker_items, {
      text = item.text,  -- This is what will be searched/matched
      display = item.text,  -- This is what we'll display
      comment_entry = item.comment_entry,  -- Our custom data
      file = item.comment_entry.file,  -- For file preview
      pos = { item.comment_entry.line, 0 },  -- For jumping to location
      -- Add preview data as expected by snacks
      preview = {
        text = table.concat(preview_lines, "\n"),
        ft = vim.filetype.match({ filename = comment_entry.file }) or "text",
      }
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
    -- Custom preview that shows both file content and comments
    preview = function(ctx)
      local item = ctx.item
      if not item or not item.comment_entry then 
        return false
      end
      
      local comment_entry = item.comment_entry
      local thread = comment_entry.thread
      
      -- Clear and set up the preview buffer
      vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.buf })
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, {})
      
      -- Build preview content
      local lines = {}
      
      -- Show file path
      table.insert(lines, vim.fn.fnamemodify(comment_entry.file, ":~:.") .. ":" .. comment_entry.line)
      table.insert(lines, "")
      
      -- Show limited code context (only 7 lines before and after)
      if vim.fn.filereadable(comment_entry.file) == 1 then
        local file_lines = vim.fn.readfile(comment_entry.file)
        local target_line = comment_entry.line
        local start_line = math.max(1, target_line - 7)
        local end_line = math.min(#file_lines, target_line + 7)
        
        for i = start_line, end_line do
          local line_num = string.format("%4d", i)
          local prefix = i == target_line and " >" or "  "
          local line_text = file_lines[i] or ""
          table.insert(lines, prefix .. line_num .. " │ " .. line_text)
        end
      end
      
      -- Add separator
      table.insert(lines, "")
      table.insert(lines, "────────────────────────────────────────")
      table.insert(lines, "")
      
      -- Add thread status
      local status = thread.is_resolved and "✓ Resolved" or "○ Open"
      if thread.is_outdated then
        status = status .. " (Outdated)"
      end
      table.insert(lines, "Thread: " .. status)
      table.insert(lines, "")
      
      -- Add comments (limit to first few)
      local max_comments = 2
      for i, comment in ipairs(thread.comments) do
        if i > max_comments then
          table.insert(lines, "")
          table.insert(lines, "... " .. (#thread.comments - max_comments) .. " more comments ...")
          break
        end
        
        if i > 1 then
          table.insert(lines, "")
          table.insert(lines, "───")
          table.insert(lines, "")
        end
        
        -- Author and date
        table.insert(lines, "● " .. comment.author .. " • " .. comment.created_at:sub(1, 10))
        
        -- Comment body (limit lines)
        local body_lines = {}
        for line in comment.body:gmatch("[^\n]+") do
          table.insert(body_lines, line)
        end
        
        for j = 1, math.min(#body_lines, 6) do
          table.insert(lines, "  " .. body_lines[j])
        end
        
        if #body_lines > 6 then
          table.insert(lines, "  ...")
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
      
      -- Set the buffer content
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
      
      -- Add highlights
      local ns_id = vim.api.nvim_create_namespace("inline_reviews_picker_preview")
      
      -- Highlight file path
      vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Comment", 0, 0, -1)
      
      -- Highlight code lines
      local code_start = 2
      local code_end = 2
      for i = code_start, #lines do
        if lines[i]:match("^%s*$") then
          code_end = i - 1
          break
        end
        -- Highlight current line marker
        if lines[i]:match("^%s*>") then
          vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "CursorLineNr", i - 1, 0, 7)
        end
      end
      
      -- Find where comments start (after empty line and separator)
      local comment_start = code_end + 4
      
      -- Highlight separator
      if comment_start - 2 <= #lines then
        vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Comment", comment_start - 3, 0, -1)
      end
      
      -- Highlight thread status
      if comment_start <= #lines then
        vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, 
          thread.is_resolved and "DiagnosticOk" or "DiagnosticWarn", 
          comment_start - 1, 0, -1)
      end
      
      -- Highlight comment authors
      local line_idx = comment_start + 2
      for i = 1, max_comments do
        if i > #thread.comments then break end
        
        if i > 1 then
          -- Skip separator lines
          line_idx = line_idx + 3
        end
        
        -- Highlight author line
        if line_idx <= #lines then
          vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Title", line_idx - 1, 0, -1)
        end
        
        -- Skip past comment body
        local comment = thread.comments[i]
        local body_line_count = 0
        for _ in comment.body:gmatch("[^\n]+") do
          body_line_count = body_line_count + 1
        end
        line_idx = line_idx + 1 + math.min(body_line_count, 6)
        if body_line_count > 6 then
          line_idx = line_idx + 1
        end
        if comment.reactions and #comment.reactions > 0 then
          line_idx = line_idx + 1
        end
      end
      
      -- Set buffer options
      vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.buf })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = ctx.buf })
      
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