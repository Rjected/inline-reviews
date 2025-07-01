local M = {}

local config = require("inline-reviews.config")

local NAMESPACE = vim.api.nvim_create_namespace("inline_reviews_virtual_text")
local active_extmarks = {}

function M.show_hint(bufnr, line, threads)
  -- Clear any existing virtual text
  M.clear_buffer(bufnr)
  
  local opts = config.get()
  
  -- Count total comments
  local total_comments = 0
  local resolved_count = 0
  
  for _, thread in ipairs(threads) do
    total_comments = total_comments + #thread.comments
    if thread.is_resolved then
      resolved_count = resolved_count + 1
    end
  end
  
  -- Build hint text
  local hint_parts = {}
  
  if total_comments > 0 then
    local comment_text = string.format("%d comment%s", total_comments, total_comments == 1 and "" or "s")
    if resolved_count == #threads and resolved_count > 0 then
      comment_text = comment_text .. " (resolved)"
    end
    
    table.insert(hint_parts, string.format("[%s: view %s]", 
      opts.keymaps.view_comments, comment_text))
  end
  
  if #hint_parts == 0 then return end
  
  local hint_text = opts.display.hint_prefix .. table.concat(hint_parts, " ")
  
  -- Create virtual text
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, line - 1, -1, {
    virt_text = { { hint_text, opts.display.hint_highlight } },
    virt_text_pos = "eol",
    priority = 100,
  })
  
  -- Track the extmark
  if not active_extmarks[bufnr] then
    active_extmarks[bufnr] = {}
  end
  active_extmarks[bufnr][line] = extmark_id
end

function M.clear_buffer(bufnr)
  -- Clear all virtual text for this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  
  -- Clear tracking
  active_extmarks[bufnr] = nil
end

function M.clear_line(bufnr, line)
  if active_extmarks[bufnr] and active_extmarks[bufnr][line] then
    vim.api.nvim_buf_del_extmark(bufnr, NAMESPACE, active_extmarks[bufnr][line])
    active_extmarks[bufnr][line] = nil
  end
end

return M