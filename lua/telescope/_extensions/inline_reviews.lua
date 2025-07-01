local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")

local comments = require("inline-reviews.comments")

local function get_all_comments()
  local results = {}
  
  -- Get all comment lines across all files
  for _, comment_data in ipairs(comments._get_all_comments()) do
    local file = comment_data.file
    local line = comment_data.line
    local thread = comment_data.thread
    
    -- Get relative path for display
    local relative_path = vim.fn.fnamemodify(file, ":~:.")
    
    -- Build display info
    local first_comment = thread.comments[1]
    local comment_preview = first_comment.body:gsub("\n", " "):sub(1, 50)
    if #first_comment.body > 50 then
      comment_preview = comment_preview .. "..."
    end
    
    local status_icon = thread.is_resolved and "✓" or "●"
    local outdated = thread.is_outdated and " [outdated]" or ""
    
    table.insert(results, {
      file = file,
      line = line,
      relative_path = relative_path,
      thread = thread,
      author = first_comment.author,
      preview = comment_preview,
      status_icon = status_icon,
      outdated = outdated,
      comment_count = #thread.comments,
    })
  end
  
  -- Sort by file and line
  table.sort(results, function(a, b)
    if a.file == b.file then
      return a.line < b.line
    end
    return a.file < b.file
  end)
  
  return results
end

-- Custom previewer that shows both code and comments
local function comment_previewer(opts)
  return previewers.new_buffer_previewer({
    title = "PR Comment Preview",
    get_buffer_by_name = function(_, entry)
      return entry.filename .. ":comment:" .. entry.lnum
    end,
    define_preview = function(self, entry, status)
      local preview_lines = {}
      local highlights = {}
      
      -- Load the file content
      local filename = entry.filename
      if not filename then
        return
      end
      
      -- Read file
      local file_lines = vim.fn.readfile(filename)
      if not file_lines then
        return
      end
      
      -- Get the comment line and context
      local comment_line = entry.lnum or 1
      local context_before = 5
      local context_after = 5
      local start_line = math.max(1, comment_line - context_before)
      local end_line = math.min(#file_lines, comment_line + context_after)
      
      -- Add code section header
      table.insert(preview_lines, "━━━━━━━━━━ Code Context ━━━━━━━━━━")
      table.insert(highlights, { line = #preview_lines - 1, col = 0, end_col = -1, hl_group = "TelescopePreviewTitle" })
      table.insert(preview_lines, "")
      
      -- Add code lines with line numbers
      for i = start_line, end_line do
        local line_prefix = string.format("%4d │ ", i)
        local code_line = line_prefix .. (file_lines[i] or "")
        table.insert(preview_lines, code_line)
        
        -- Highlight the commented line
        if i == comment_line then
          table.insert(highlights, {
            line = #preview_lines - 1,
            col = 0,
            end_col = -1,
            hl_group = "TelescopePreviewLine"
          })
        else
          -- Highlight line numbers
          table.insert(highlights, {
            line = #preview_lines - 1,
            col = 0,
            end_col = 6,
            hl_group = "LineNr"
          })
        end
      end
      
      -- Add separator
      table.insert(preview_lines, "")
      table.insert(preview_lines, "━━━━━━━━━━ PR Comments ━━━━━━━━━━")
      table.insert(highlights, { line = #preview_lines - 1, col = 0, end_col = -1, hl_group = "TelescopePreviewTitle" })
      table.insert(preview_lines, "")
      
      -- Add comment thread
      local thread = entry.value.thread
      local status_text = thread.is_resolved and " [RESOLVED]" or ""
      local outdated_text = thread.is_outdated and " [OUTDATED]" or ""
      
      -- Thread status
      if status_text ~= "" or outdated_text ~= "" then
        table.insert(preview_lines, "Status:" .. status_text .. outdated_text)
        table.insert(highlights, { 
          line = #preview_lines - 1, 
          col = 0, 
          end_col = -1, 
          hl_group = thread.is_resolved and "Comment" or "WarningMsg" 
        })
        table.insert(preview_lines, "")
      end
      
      -- Each comment in the thread
      for i, comment in ipairs(thread.comments) do
        if i > 1 then
          table.insert(preview_lines, "────────────────────────")
          table.insert(highlights, { line = #preview_lines - 1, col = 0, end_col = -1, hl_group = "Comment" })
        end
        
        -- Author and time
        local time = comment.created_at:match("(%d%d%d%d%-[^T]+)")
        local author_line = string.format("● %s • %s", comment.author, time or "")
        table.insert(preview_lines, author_line)
        table.insert(highlights, { 
          line = #preview_lines - 1, 
          col = 0, 
          end_col = string.len(comment.author) + 2,
          hl_group = "Function" 
        })
        table.insert(preview_lines, "")
        
        -- Comment body (wrapped)
        local max_width = vim.api.nvim_win_get_width(self.state.winid) - 4
        for body_line in comment.body:gmatch("[^\n]+") do
          -- Simple word wrap
          if #body_line <= max_width then
            table.insert(preview_lines, "  " .. body_line)
          else
            local current = ""
            for word in body_line:gmatch("%S+") do
              if #current + #word + 1 <= max_width - 2 then
                current = current == "" and word or current .. " " .. word
              else
                if current ~= "" then
                  table.insert(preview_lines, "  " .. current)
                end
                current = word
              end
            end
            if current ~= "" then
              table.insert(preview_lines, "  " .. current)
            end
          end
        end
        
        -- Reactions if any
        if comment.reactions and #comment.reactions > 0 then
          table.insert(preview_lines, "")
          local reaction_parts = {}
          for _, reaction in ipairs(comment.reactions) do
            if reaction.users.totalCount > 0 then
              table.insert(reaction_parts, string.format("%s %d", 
                reaction.content, reaction.users.totalCount))
            end
          end
          if #reaction_parts > 0 then
            table.insert(preview_lines, "  " .. table.concat(reaction_parts, "  "))
            table.insert(highlights, {
              line = #preview_lines - 1,
              col = 0,
              end_col = -1,
              hl_group = "Comment"
            })
          end
        end
        
        table.insert(preview_lines, "")
      end
      
      -- Set buffer content
      vim.api.nvim_buf_set_option(self.state.bufnr, "modifiable", true)
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
      vim.api.nvim_buf_set_option(self.state.bufnr, "modifiable", false)
      
      -- Apply highlights
      for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(
          self.state.bufnr,
          -1,
          hl.hl_group,
          hl.line,
          hl.col,
          hl.end_col
        )
      end
      
      -- Set filetype for better display
      vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
      
      -- Scroll to top to show code context first
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(self.state.winid) then
          vim.api.nvim_win_set_cursor(self.state.winid, { 1, 0 })
        end
      end)
    end,
  })
end

local function inline_reviews_picker(opts)
  opts = opts or {}
  
  local comment_entries = get_all_comments()
  
  if #comment_entries == 0 then
    vim.notify("No PR comments loaded. Use :InlineComments <PR_NUMBER> first.", vim.log.levels.INFO)
    return
  end
  
  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 2 },  -- Status icon
      { width = 30 }, -- File:line
      { width = 15 }, -- Author
      { remaining = true }, -- Preview
    },
  })
  
  local make_display = function(entry)
    return displayer({
      { entry.value.status_icon, entry.value.is_resolved and "TelescopeResultsComment" or "TelescopeResultsFunction" },
      { 
        string.format("%s:%d", entry.value.relative_path, entry.value.line),
        "TelescopeResultsIdentifier"
      },
      { entry.value.author, "TelescopeResultsConstant" },
      { 
        string.format("(%d) %s%s", 
          entry.value.comment_count, 
          entry.value.preview,
          entry.value.outdated
        ),
        "TelescopeResultsString"
      },
    })
  end
  
  pickers.new(opts, {
    prompt_title = "PR Review Comments",
    finder = finders.new_table({
      results = comment_entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = make_display,
          ordinal = string.format("%s:%d %s %s", 
            entry.relative_path, 
            entry.line, 
            entry.author,
            entry.preview
          ),
          filename = entry.file,
          lnum = entry.line,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = comment_previewer(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        
        if selection then
          -- Open the file
          vim.cmd("edit " .. vim.fn.fnameescape(selection.value.file))
          -- Go to the line
          vim.api.nvim_win_set_cursor(0, { selection.value.line, 0 })
          
          -- Show the comment hover
          vim.schedule(function()
            require("inline-reviews.ui").show_comment_hover({ selection.value.thread })
          end)
        end
      end)
      
      -- Add mapping to view comment without closing telescope
      map("i", "<C-v>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          -- Save current window
          local telescope_win = vim.api.nvim_get_current_win()
          
          -- Open file in a split
          vim.cmd("vsplit " .. vim.fn.fnameescape(selection.value.file))
          vim.api.nvim_win_set_cursor(0, { selection.value.line, 0 })
          
          -- Show hover
          vim.schedule(function()
            require("inline-reviews.ui").show_comment_hover({ selection.value.thread })
            -- Return to telescope
            vim.api.nvim_set_current_win(telescope_win)
          end)
        end
      end)
      
      return true
    end,
  }):find()
end

return telescope.register_extension({
  setup = function(ext_config, config)
    -- Extension setup if needed
  end,
  exports = {
    inline_reviews = inline_reviews_picker,
    comments = inline_reviews_picker,  -- Alias
  },
})