# inline-reviews.nvim

View and interact with GitHub PR comments directly in Neovim. No more context switching.

> **Note**: This plugin was mostly vibe-coded with AI assistance. It works great, but the implementation might make you laugh (or cry). PRs welcome!

## Why?

Ever lose your flow jumping between GitHub and your editor during PR reviews? This plugin keeps review comments right where they belong - next to your code. See comments, reply to them, add reactions, and resolve threads without leaving Neovim.

## Features

- See PR comments as you code - subtle indicators in the sign column
- Navigate comments with `]c` and `[c`
- View full threads in floating windows
- Reply, react, and resolve without leaving your editor
- Comments follow your code as you edit (diff-aware positioning)
- Works with Git and Jujutsu
- Auto-detects PR branches
- Background refresh for new comments

## Requirements

- Neovim >= 0.9.0
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for enhanced UI (highly recommended!)
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for comment browser (if not using snacks)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "dan/inline-reviews.nvim",
  config = function()
    require("inline-reviews").setup()
  end,
}
```

## Configuration

Default setup works great. Customize if needed:

```lua
require("inline-reviews").setup({
  auto_load = true,               -- Auto-detect PR on file open
  keymaps = {
    view_comments = "<leader>rc",
    next_comment = "]c",
    prev_comment = "[c",
  },
  display = {
    sign_text = "●",
    resolved_sign_text = "✓",
  },
  auto_refresh = {
    enabled = true,
    interval = 300,
  }
})
```

## Usage

Load comments from a PR:

```vim
:InlineComments 16956
```

Or enable auto-detection to load comments automatically:

```lua
require("inline-reviews").setup({
  auto_load = true
})
```

Works with both Git branches and jj bookmarks.

### Commands

`:InlineComments <PR>` - Load PR comments  
`:InlineCommentsReload` - Reload current PR  
`:InlineCommentsClear` - Clear comments  

### Navigation

`<leader>rc` - View comment at cursor  
`<leader>rC` - Browse all comments (Telescope)  
`]c` / `[c` - Next/prev comment  
`<leader>rt` - Toggle resolved comments  

### In the hover window

`r` - Reply to comment  
`e` - Add reaction (👍 👎 😄 🎉 😕 ❤️ 🚀 👀)  
`s` - Resolve/unresolve thread  
`<CR>` - Expand/collapse diffs  
`<Esc>` or `q` - Close  

Reply with `Ctrl-s` to submit, `Esc` to cancel.

### Comment Browser

Browse all comments with `<leader>rC` or `:InlineCommentsTelescope`.

**Telescope**:
`<Enter>` - Jump to comment  
`<C-v>` - Open in split

**Snacks.nvim picker** (when available):
`<Enter>` - Jump to comment  
`?` - Show help with all keybindings  
`<C-f>` - Filter by status  
`<C-a>` - Filter by author  
`<C-p>` - Toggle auto-close  

## How it looks

**Sign column**: `●` for open, `✓` for resolved  
**Virtual text**: `[<leader>rc: view 2 comments]` at cursor  
**Hover window**: Full thread with reactions, diffs, and actions  
**Displaced comments**: Shows `[originally line 123]` when code moves  

https://github.com/user-attachments/assets/b650ba5e-c10c-4667-98c4-21f28a55b6f9

## Smart features

### Comments follow your code

As you edit, comments stay attached to the right lines. The plugin tracks changes through git/jj diffs and updates positions automatically. Save a file and watch comments snap to their new locations.

### Auto-refresh

After you reply, comments reload automatically. Enable periodic refresh to catch new comments from teammates:

```lua
auto_refresh = {
  enabled = true,
  interval = 300  -- 5 minutes
}
```

### UI Backend (snacks.nvim integration)

The plugin integrates deeply with [snacks.nvim](https://github.com/folke/snacks.nvim) for a superior UI experience. While the plugin works without it, snacks.nvim is highly recommended for the best experience.

```lua
ui = {
  backend = "auto"  -- "auto", "snacks", or "native"
  -- auto: use snacks.nvim if available (default)
  -- snacks: always use snacks.nvim (error if not installed)
  -- native: always use built-in UI
}
```

**With snacks.nvim** you get:
- 🔔 Better notifications with stacking and progress indicators
- 🎨 Consistent UI components that match your theme
- 🔍 Advanced picker with filtering, split layouts, and live preview
- 📊 Status column integration to see comment indicators at a glance
- ⚡ Smoother interactions with proper input handling

**Without snacks.nvim**: The plugin falls back to basic Neovim UI components (floating windows, vim.ui.input, telescope for browsing).

The plugin automatically detects which UI library is available and uses the best option. You can force a specific backend with the `ui.backend` config option.

### Advanced Features

#### Status Column Integration

Show PR comments directly in your status column with snacks.nvim:

```lua
statuscolumn = {
  enabled = true,               -- Enable statuscolumn integration
  component_position = "left",  -- "left" or "right"
  show_count = true,           -- Show number when multiple comments
  show_outdated = true,        -- Show outdated indicator
  max_count = 9,               -- Show "9+" for more
  icons = {
    comment = "●",             -- Unresolved comment
    resolved = "✓",            -- Resolved comment
    outdated = "○",            -- Outdated comment
  }
}
```

#### Advanced Picker

The snacks.nvim picker supports advanced layouts and filtering:

```lua
picker = {
  layout = "float",            -- "float", "split", "vsplit"
  split_width = 40,            -- Width for vsplit
  split_height = 15,           -- Height for split
  auto_close = true,           -- Auto close on selection
  filters = {
    enabled = true,
    default = "status:unresolved",  -- Default filter
  },
  keymaps = {
    filter_status = "<C-f>",   -- Filter by status
    filter_author = "<C-a>",   -- Filter by author
    pin_window = "<C-p>",      -- Toggle auto-close
  }
}
```

**Using the picker**:
1. Open with `<leader>rC`
2. Press `?` to see all available keybindings
3. Use `<C-f>` to filter by status (resolved/unresolved)
4. Use `<C-a>` to filter by author name
5. Use `<C-p>` to keep the picker open while navigating

**Filter syntax**: `author:username status:resolved filetype:rust outdated:true`

In split/vsplit mode, the picker stays open as a sidebar while you navigate comments. The preview dynamically adjusts to show more comments when there's available space.

## Quick start

1. Open a file from a PR branch
2. `:InlineComments <PR_NUMBER>`
3. See comments in the sign column
4. `<leader>rc` to read and reply
5. Keep coding

## Troubleshooting

**Auth errors?** Run `gh auth login`

**Comments not showing?** Check you're on a PR branch and the PR has comments. Try `:InlineCommentsReload`.

**Ctrl-s not working?** Your terminal might intercept it. Try `:w` or `:Submit` in the reply window instead.

## Contributing

This plugin was built with a "make it work" philosophy and heavy AI assistance. The code is functional but could use some love. If you find something that makes you go "hmm", you're probably right - PRs are very welcome!

Areas that could use improvement:
- Error handling (currently mostly "hope for the best")
- Performance optimization (we query GitHub... a lot)
- Test coverage (what tests?)
- Code organization (vibes-based architecture)

## License

MIT
