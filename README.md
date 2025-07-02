# inline-reviews.nvim

View and interact with GitHub PR comments directly in Neovim. No more context switching.

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
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for enhanced UI

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

### Telescope

Browse all comments with `<leader>rC` or `:InlineCommentsTelescope`.

`<Enter>` - Jump to comment  
`<C-v>` - Open in split  

## How it looks

**Sign column**: `●` for open, `✓` for resolved  
**Virtual text**: `[<leader>rc: view 2 comments]` at cursor  
**Hover window**: Full thread with reactions, diffs, and actions  
**Displaced comments**: Shows `[originally line 123]` when code moves  

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

The plugin integrates with [snacks.nvim](https://github.com/folke/snacks.nvim) for improved UI components:

```lua
ui = {
  backend = "auto"  -- "auto", "snacks", or "native"
  -- auto: use snacks.nvim if available (default)
  -- snacks: always use snacks.nvim (error if not installed)
  -- native: always use built-in UI
}
```

When snacks.nvim is available:
- Notifications use snacks.notify for better styling and stacking
- Reaction picker uses snacks.select for consistent UI
- Comment input uses snacks.input for a cleaner experience
- Comment browser (`<leader>rC`) uses snacks.picker instead of telescope

The plugin automatically detects which UI library is available and uses the best option. You can force a specific backend with the `ui.backend` config option.

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

## License

MIT