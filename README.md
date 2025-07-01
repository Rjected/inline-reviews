# inline-reviews.nvim

A Neovim plugin that displays GitHub PR review comments inline without disrupting your editing experience. Comments appear as subtle indicators with full content accessible via hover windows or keybindings.

## Features

- 🔍 **Non-intrusive display**: Comments shown as sign column markers and optional virtual text hints
- 🚀 **Quick navigation**: Jump between comments with `]c` and `[c`
- 👁️ **Hover preview**: View full comment threads in floating windows
- 🔄 **Auto-detection**: Automatically loads comments when opening files from a PR branch
- 🎯 **Focused workflow**: Stay in your editor while reviewing PR feedback
- ⚡ **Fast and cached**: Uses GitHub CLI with intelligent caching
- 🔀 **VCS Support**: Works with both Git branches and Jujutsu (jj) bookmarks

## Requirements

- Neovim >= 0.9.0
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "inline-reviews",
  dir = "~/projects/inline-reviews",
  config = function()
    require("inline-reviews").setup({
      -- your configuration
    })
  end,
}
```

## Configuration

```lua
require("inline-reviews").setup({
  auto_load = false,              -- Auto-detect PR on buffer enter
  keymaps = {
    view_comments = "<leader>rc", -- View comments for current line
    next_comment = "]c",          -- Jump to next comment
    prev_comment = "[c",          -- Jump to previous comment
    toggle_resolved = "<leader>rt", -- Toggle showing resolved comments
  },
  display = {
    show_hints = true,            -- Show virtual text hints
    hint_prefix = " ",           -- Prefix for hints
    sign_text = "●",             -- Sign for unresolved comments
    resolved_sign_text = "✓",    -- Sign for resolved comments
    show_resolved = true,         -- Show resolved comments
    show_outdated = true,         -- Show outdated comments
    max_height = 20,              -- Max height for hover window
    max_width = 80,               -- Max width for hover window
    border = "rounded",           -- Border style for hover window
  },
  github = {
    gh_cmd = "gh",                -- GitHub CLI command
    cache_ttl = 300,              -- Cache TTL in seconds
  }
})
```

## Usage

### Manual Loading

Load comments from a specific PR:

```vim
:InlineComments 16956
```

### Auto-detection

Enable `auto_load` in setup to automatically detect and load PR comments when opening files:

```lua
require("inline-reviews").setup({
  auto_load = true
})
```

This works with both:
- **Git**: Detects current branch and finds associated PR
- **Jujutsu (jj)**: Detects current bookmark and finds associated PR (automatically strips `push-` prefix if present)

### Commands

- `:InlineComments <PR_NUMBER>` - Load comments from a specific PR
- `:InlineCommentsReload` - Reload comments for current PR
- `:InlineCommentsClear` - Clear all inline comments

### Default Keybindings

- `<leader>rc` - View comments for current line in hover window
- `<leader>rC` - Browse all PR comments with Telescope
- `]c` - Jump to next comment
- `[c` - Jump to previous comment
- `<leader>rt` - Toggle showing resolved comments

### Telescope Integration

The plugin includes a Telescope extension for browsing all PR comments:

```vim
:InlineCommentsTelescope
```

Or use the default keybinding `<leader>rC`. The Telescope picker shows:
- Status icon (● for open, ✓ for resolved)
- File and line number
- Comment author
- Preview of the comment text
- Comment count for threads

Actions in Telescope:
- `<Enter>` - Jump to the comment and show hover
- `<C-v>` - Open in vertical split and show hover

## Visual Indicators

1. **Sign Column**: Shows `●` for unresolved comments, `✓` for resolved
2. **Line Highlighting**: Subtle background highlight on lines with comments
3. **Virtual Text**: Shows `[<leader>rc: view 2 comments]` when cursor is on a commented line
4. **Hover Window**: Full comment thread with author, timestamp, and reactions

## Example Workflow

1. Working on a feature branch with an open PR
2. Open Neovim in your project
3. Run `:InlineComments 123` (or enable auto-detection)
4. See comment indicators in the sign column
5. Navigate to a line with comments
6. Press `<leader>rc` to view the full comment thread
7. Use `]c`/`[c` to jump between comments
8. Continue editing with full context of PR feedback

## Troubleshooting

### GitHub CLI not authenticated

If you see authentication errors, run:

```bash
gh auth login
```

### Comments not showing

1. Ensure you're in a git repository
2. Check that the PR exists and has review comments
3. Try `:InlineCommentsReload` to refresh

### Performance

The plugin caches API responses for 5 minutes by default. Adjust `cache_ttl` in config if needed.

## License

MIT