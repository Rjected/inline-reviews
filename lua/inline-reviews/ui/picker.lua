local M = {}

local config = require("inline-reviews.config")
local comments = require("inline-reviews.comments")
local notifier = require("inline-reviews.ui.notifier")

-- This module provides a picker UI for browsing PR comments using either
-- snacks.nvim or telescope. The snacks.nvim implementation includes:
-- - Custom preview showing both code context and comment discussion
-- - Manual syntax highlighting for code (to avoid highlighting comments)
-- - Support for multiple programming languages
-- - Reactions and thread status display

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

-- Parse filter string into structured filter
local function parse_filter(filter_str)
  local filters = {
    author = nil,
    status = nil,
    filetype = nil,
    outdated = nil,
  }
  
  if not filter_str or filter_str == "" then
    return filters
  end
  
  -- Parse filter patterns like "author:username status:resolved"
  for key, value in filter_str:gmatch("(%w+):(%S+)") do
    if key == "author" or key == "status" or key == "filetype" or key == "outdated" then
      filters[key] = value
    end
  end
  
  return filters
end

-- Apply filters to comment entries
local function apply_filters(entries, filter_str)
  local filters = parse_filter(filter_str)
  
  -- Check if we have any active filters
  local has_filters = false
  for k, v in pairs(filters) do
    if v then
      has_filters = true
      break
    end
  end
  
  -- No filters, return all
  if not has_filters then
    return entries
  end
  
  local filtered = {}
  for _, entry in ipairs(entries) do
    local include = true
    
    -- Author filter
    if filters.author then
      local has_author = false
      for _, comment in ipairs(entry.thread.comments) do
        if comment.author:lower():find(filters.author:lower()) then
          has_author = true
          break
        end
      end
      if not has_author then
        include = false
      end
    end
    
    -- Status filter
    if filters.status and include then
      if filters.status == "resolved" and not entry.thread.is_resolved then
        include = false
      elseif filters.status == "unresolved" and entry.thread.is_resolved then
        include = false
      end
    end
    
    -- Filetype filter
    if filters.filetype and include then
      local ft = vim.filetype.match({ filename = entry.file }) or ""
      if ft ~= filters.filetype then
        include = false
      end
    end
    
    -- Outdated filter
    if filters.outdated and include then
      local is_outdated = entry.thread.is_outdated
      if filters.outdated == "true" and not is_outdated then
        include = false
      elseif filters.outdated == "false" and is_outdated then
        include = false
      end
    end
    
    if include then
      table.insert(filtered, entry)
    end
  end
  
  return filtered
end

-- Show picker using snacks.nvim
local function show_with_snacks()
  local snacks = require("snacks")
  local picker_config = config.get().picker or {}
  
  -- Get all comments
  local all_threads = comments._get_all_comments()
  if #all_threads == 0 then
    notifier.info("No comments to display")
    return
  end
  
  -- Apply default filter if configured
  local current_filter = picker_config.filters and picker_config.filters.default or ""
  local filtered_threads = apply_filters(all_threads, current_filter)
  
  -- Create items as objects with text property
  local items = {}
  
  for _, comment_entry in ipairs(filtered_threads) do
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
  
  -- Determine layout configuration
  local layout_config = {}
  if picker_config.layout == "split" then
    layout_config.layout = {
      preset = "bottom",
      height = picker_config.split_height or 15,
    }
  elseif picker_config.layout == "vsplit" then
    layout_config.layout = {
      preset = "right",
      width = picker_config.split_width or 40,
    }
  else
    -- Default float layout
    layout_config.layout = {
      preset = "float",
    }
  end
  
  -- Store picker instance for potential pinning
  local picker_instance = nil
  
  -- Add help text about filtering
  local help_text = picker_config.keymaps and picker_config.filters and picker_config.filters.enabled 
    and " (Press ? for help)" or ""
  
  -- Create picker with custom config
  local picker_opts = vim.tbl_deep_extend("force", layout_config, {
    title = " PR Comments " .. (current_filter ~= "" and " [" .. current_filter .. "]" or "") .. help_text,
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
      local code_start_line = 3  -- Track where code starts in the buffer
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
      
      local code_end_line = #lines
      
      -- Add separator
      table.insert(lines, "")
      table.insert(lines, "────────────────────────────────────────")
      table.insert(lines, "")
      
      local comment_start_line = #lines + 1
      
      -- Add thread status
      local status = thread.is_resolved and "✓ Resolved" or "○ Open"
      if thread.is_outdated then
        status = status .. " (Outdated)"
      end
      table.insert(lines, "Thread: " .. status)
      table.insert(lines, "")
      
      -- Add comments (limit based on available space)
      local win_height = vim.api.nvim_win_get_height(ctx.win)
      local current_lines = #lines
      local available_lines = win_height - current_lines - 5 -- Leave some buffer
      local max_comments = math.max(1, math.floor(available_lines / 10)) -- Estimate ~10 lines per comment
      
      for i, comment in ipairs(thread.comments) do
        if i > max_comments and #thread.comments > max_comments then
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
      
      -- Set buffer options
      vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.buf })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = ctx.buf })
      
      -- Don't set filetype - we'll apply custom highlighting instead
      -- This prevents the comments from being syntax highlighted
      -- 
      -- NOTE: We use manual syntax highlighting because Vim's syntax highlighting
      -- is buffer-wide and cannot be selectively applied to only parts of a buffer.
      -- This approach allows us to highlight only the code portion while keeping
      -- the comment discussion plain.
      
      -- Create namespace for our custom highlights
      local ns_id = vim.api.nvim_create_namespace("inline_reviews_picker_preview")
      
      -- Apply custom syntax highlighting to just the code lines
      local ft = vim.filetype.match({ filename = comment_entry.file }) or "text"
      
      if ft ~= "text" and code_start_line <= code_end_line then
        -- Apply syntax highlighting based on detected language
        for i = code_start_line, code_end_line do
          if i <= #lines then
            local line = lines[i]
            
            -- Skip the line number prefix when applying highlights
            local prefix_match = line:match("^%s*>?%s*%d+%s*│%s*")
            local prefix_len = prefix_match and #prefix_match or 0
            
            -- Language-specific keywords
            local lang_keywords = {
              rust = {"fn", "let", "mut", "impl", "pub", "struct", "enum", "trait", "use", "mod", "self", "Self", "return", "if", "else", "match", "for", "while", "loop", "async", "await", "const", "static", "type", "where", "crate", "super", "unsafe", "extern", "as", "in", "move", "ref"},
              lua = {"function", "local", "if", "then", "else", "elseif", "end", "for", "while", "do", "repeat", "until", "return", "break", "and", "or", "not", "nil", "true", "false", "in", "pairs", "ipairs", "require", "module", "pcall", "xpcall"},
              python = {"def", "class", "if", "elif", "else", "for", "while", "return", "break", "continue", "pass", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "assert", "del", "global", "nonlocal", "in", "is", "and", "or", "not", "True", "False", "None"},
              javascript = {"function", "const", "let", "var", "if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "try", "catch", "finally", "throw", "new", "class", "extends", "import", "export", "from", "async", "await", "yield", "this", "super"},
              typescript = {"function", "const", "let", "var", "if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "try", "catch", "finally", "throw", "new", "class", "extends", "implements", "interface", "type", "enum", "namespace", "import", "export", "from", "async", "await", "yield", "this", "super", "public", "private", "protected", "readonly"},
              go = {"func", "package", "import", "const", "var", "type", "struct", "interface", "if", "else", "for", "range", "switch", "case", "default", "return", "break", "continue", "goto", "defer", "go", "select", "chan", "map"},
              c = {"if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue", "goto", "struct", "union", "enum", "typedef", "const", "static", "extern", "void", "int", "char", "float", "double", "long", "short", "unsigned", "signed"},
              cpp = {"if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue", "goto", "struct", "union", "enum", "typedef", "const", "static", "extern", "void", "int", "char", "float", "double", "long", "short", "unsigned", "signed", "class", "public", "private", "protected", "namespace", "template", "typename", "using", "virtual", "override", "new", "delete", "this", "nullptr"},
              java = {"class", "interface", "enum", "extends", "implements", "public", "private", "protected", "static", "final", "abstract", "if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue", "try", "catch", "finally", "throw", "throws", "new", "this", "super", "import", "package", "void", "int", "char", "boolean", "float", "double", "long", "short"},
            }
            
            local keywords = lang_keywords[ft] or {}
            for _, keyword in ipairs(keywords) do
              local start_pos = prefix_len + 1
              while true do
                local s, e = line:find("%f[%w]" .. keyword .. "%f[%W]", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Keyword", i - 1, s - 1, e)
                start_pos = e + 1
              end
            end
            
            -- Language-specific features
            if ft == "rust" then
              -- Types (PascalCase)
              local start_pos = prefix_len + 1
              while true do
                local s, e = line:find("%f[%w][A-Z][A-Za-z0-9_]*%f[%W]", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Type", i - 1, s - 1, e)
                start_pos = e + 1
              end
              
              -- Lifetimes
              start_pos = prefix_len + 1
              while true do
                local s, e = line:find("'[a-zA-Z_][a-zA-Z0-9_]*", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Special", i - 1, s - 1, e)
                start_pos = e + 1
              end
              
              -- Macros (ending with !)
              start_pos = prefix_len + 1
              while true do
                local s, e = line:find("%f[%w][%w_]+!", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Macro", i - 1, s - 1, e)
                start_pos = e + 1
              end
            elseif ft == "lua" then
              -- Lua self and require calls
              local start_pos = prefix_len + 1
              while true do
                local s, e = line:find("%f[%w]self%f[%W]", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Special", i - 1, s - 1, e)
                start_pos = e + 1
              end
            elseif ft == "python" then
              -- Python decorators
              local start_pos = prefix_len + 1
              while true do
                local s, e = line:find("@%w+", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Special", i - 1, s - 1, e)
                start_pos = e + 1
              end
              -- Python self
              start_pos = prefix_len + 1
              while true do
                local s, e = line:find("%f[%w]self%f[%W]", start_pos)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Special", i - 1, s - 1, e)
                start_pos = e + 1
              end
            elseif ft == "go" then
              -- Go built-in functions
              local builtins = {"append", "cap", "close", "complex", "copy", "delete", "imag", "len", "make", "new", "panic", "print", "println", "real", "recover"}
              for _, builtin in ipairs(builtins) do
                local start_pos = prefix_len + 1
                while true do
                  local s, e = line:find("%f[%w]" .. builtin .. "%f[%W]", start_pos)
                  if not s then break end
                  vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Special", i - 1, s - 1, e)
                  start_pos = e + 1
                end
              end
            end
            
            -- Language-agnostic patterns
            -- Functions (identifier followed by parenthesis)
            local start_pos = prefix_len + 1
            while true do
              local s = line:find("%f[%w][%w_]+%s*%(", start_pos)
              if not s then break end
              local func_end = line:find("%s*%(", s)
              if func_end then
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Function", i - 1, s - 1, func_end - 1)
                start_pos = func_end + 1
              else
                break
              end
            end
            
            -- Strings (double quotes)
            start_pos = prefix_len + 1
            while true do
              local s, e = line:find('"[^"]*"', start_pos)
              if not s then break end
              vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "String", i - 1, s - 1, e)
              start_pos = e + 1
            end
            
            -- Strings (single quotes for char literals)
            start_pos = prefix_len + 1
            while true do
              local s, e = line:find("'[^']*'", start_pos)
              if not s then break end
              -- Skip Rust lifetimes
              if not (ft == "rust" and line:sub(s-1, s-1):match("[%w_]")) then
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "String", i - 1, s - 1, e)
              end
              start_pos = e + 1
            end
            
            -- Comments
            local comment_start = line:find("//")
            if comment_start then
              vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Comment", i - 1, comment_start - 1, -1)
            end
            
            -- Numbers
            start_pos = prefix_len + 1
            while true do
              local s, e = line:find("%f[%w]%d+%.?%d*%f[%W]", start_pos)
              if not s then break end
              vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Number", i - 1, s - 1, e)
              start_pos = e + 1
            end
            
            -- Special operators
            local operators = {"->", "=>", "::", "&&", "||", "!=", "==", "<=", ">=", "<<", ">>", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="}
            for _, op in ipairs(operators) do
              start_pos = prefix_len + 1
              while true do
                local s, e = line:find(vim.pesc(op), start_pos, true)
                if not s then break end
                vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Operator", i - 1, s - 1, e)
                start_pos = e + 1
              end
            end
          end
        end
      end
      
      -- Highlight file path
      vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Comment", 0, 0, -1)
      
      -- Highlight current line marker in code
      for i = code_start_line, code_end_line do
        if i <= #lines and lines[i]:match("^%s*>") then
          vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "CursorLineNr", i - 1, 0, 7)
        end
      end
      
      -- Highlight separator
      if comment_start_line - 2 <= #lines then
        vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, "Comment", comment_start_line - 3, 0, -1)
      end
      
      -- Highlight thread status
      if comment_start_line <= #lines then
        vim.api.nvim_buf_add_highlight(ctx.buf, ns_id, 
          thread.is_resolved and "DiagnosticOk" or "DiagnosticWarn", 
          comment_start_line - 1, 0, -1)
      end
      
      -- Highlight comment authors
      local line_idx = comment_start_line + 1
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
      
      return true
    end,
    actions = {
      default = function(picker, item)
        if not item or not item.comment_entry then return end
        
        local comment_entry = item.comment_entry
        
        -- Only close if auto_close is enabled
        if picker_config.auto_close then
          picker:close()
        end
        
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
  
  -- Add custom keymaps
  if picker_config.keymaps then
    -- Filter by status
    if picker_config.keymaps.filter_status then
      picker_opts.keys = picker_opts.keys or {}
      picker_opts.keys[picker_config.keymaps.filter_status] = {
        function()
          vim.ui.input({
            prompt = "Filter by status (resolved/unresolved): ",
            default = current_filter:match("status:(%S+)") or "",
          }, function(input)
            if input then
              -- Update filter
              current_filter = current_filter:gsub("status:%S+", "")
              if input ~= "" then
                current_filter = current_filter .. " status:" .. input
              end
              current_filter = vim.trim(current_filter)
              
              -- Refresh picker
              picker_instance:close()
              vim.schedule(function()
                show_with_snacks()
              end)
            end
          end)
        end,
        desc = "Filter by status",
      }
    end
    
    -- Filter by author
    if picker_config.keymaps.filter_author then
      picker_opts.keys = picker_opts.keys or {}
      picker_opts.keys[picker_config.keymaps.filter_author] = {
        function()
          vim.ui.input({
            prompt = "Filter by author: ",
            default = current_filter:match("author:(%S+)") or "",
          }, function(input)
            if input then
              -- Update filter
              current_filter = current_filter:gsub("author:%S+", "")
              if input ~= "" then
                current_filter = current_filter .. " author:" .. input
              end
              current_filter = vim.trim(current_filter)
              
              -- Refresh picker
              picker_instance:close()
              vim.schedule(function()
                show_with_snacks()
              end)
            end
          end)
        end,
        desc = "Filter by author",
      }
    end
    
    -- Pin window
    if picker_config.keymaps.pin_window then
      picker_opts.keys = picker_opts.keys or {}
      picker_opts.keys[picker_config.keymaps.pin_window] = {
        function()
          picker_config.auto_close = not picker_config.auto_close
          notifier.info("Picker auto-close: " .. (picker_config.auto_close and "enabled" or "disabled"))
        end,
        desc = "Toggle pin window",
      }
    end
  end
  
  -- Add help key
  picker_opts.keys = picker_opts.keys or {}
  picker_opts.keys["?"] = {
    function()
      local help_lines = {
        "PR Comments Picker Help",
        "",
        "Navigation:",
        "  <CR>    Jump to comment",
        "  <Esc>   Close picker",
        "",
        "Filtering:",
      }
      
      if picker_config.keymaps.filter_status then
        table.insert(help_lines, "  " .. picker_config.keymaps.filter_status .. "    Filter by status (resolved/unresolved)")
      end
      if picker_config.keymaps.filter_author then
        table.insert(help_lines, "  " .. picker_config.keymaps.filter_author .. "    Filter by author")
      end
      
      table.insert(help_lines, "")
      table.insert(help_lines, "Other:")
      
      if picker_config.keymaps.pin_window then
        table.insert(help_lines, "  " .. picker_config.keymaps.pin_window .. "    Toggle auto-close")
      end
      
      table.insert(help_lines, "")
      table.insert(help_lines, "Current filter: " .. (current_filter ~= "" and current_filter or "none"))
      table.insert(help_lines, "")
      table.insert(help_lines, "Filter syntax: author:name status:resolved filetype:rust")
      
      vim.notify(table.concat(help_lines, "\n"), vim.log.levels.INFO, {
        title = "Inline Reviews Picker"
      })
    end,
    desc = "Show help",
  }
  
  picker_instance = snacks.picker(picker_opts)
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