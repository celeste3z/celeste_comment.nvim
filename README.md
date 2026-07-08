# celeste_comment

Toggle comments with line / block / textobject support.

> **Experimental** — Breaking changes may occur.

## Features

- Line comment toggle
- Block comment toggle
- Linewise/Blockwise/Auto-detect comment textobject (can work without treesitter)
- Vscode-style indent algorithm, line comment fallback to block comment
- Dot-repeatable, count support
- Real cursor sticky
- Invert comment per line
- Insert comment above / below / at end of line
- Case insensitive comment detection
- Relaxed block detection
- Precise edit tracking (via TextEdits)

### What it doesn't do

- **Cover all cases** — This plugin's aim is to handle the vast majority of
  common scenarios, not every possible case. Known textobject edge cases and
  unusual comment patterns are acknowledged but not planned to fix.

### Limitations

- **`keep_cursor` during dot-repeat** — Does not work with `.`; this is
  current Neovim limitation.

- **Auto-detect textobject accuracy** — `textobject_auto()` first checks
  whether the current line contains a line comment. In languages like Lua
  where `--` is used for both line comments (`--`) and block comments
  (`--[[ ]]`), a line starting with `--` may be misidentified as a line
  comment, leading to incorrect textobject selection.

- **Regex-based textobject range** — Pattern matching can produce false
  positives in certain scenarios. For example, comment-like tokens inside
  strings may be mistakenly treated as actual comments. Additionally, the
  scan range is capped by `block_textobj_nlines` (default 200), so
  textobject detection may not work beyond that limit.

- **Visual block mode (`<C-v>`)** — Selection is treated as linewise; the
  entire selected lines are block-commented rather than inserting comment
  markers per column. For column-wise comment operations, consider using
  a plugin like [multicursor.nvim](https://github.com/jake-stewart/multicursor.nvim).

## Requirements

- Neovim **>= 0.13**

## Installation

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ src = "https://github.com/celeste3z/celeste_comment.nvim", name = "celeste_comment" })

require("celeste_comment").setup({})
```

### lazy.nvim

```lua
{ "celeste3z/celeste_comment.nvim", opts = {} }
```

### Dependencies

- [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) (optional) —
  Enables treesitter-aware comment textobject detection. When installed,
  `textobject_auto()`, `textobject_linewise()`, and `textobject_blockwise()`
  use the `@comment.outer` query to
  precisely locate comment boundaries. Without it, the plugin falls back
  to regex-based matching, which works correctly in most scenarios.

## Setup

```lua
require("celeste_comment").setup({})
```

### Default configuration

```lua
{
  -- Restore cursor position after commenting. Saves the cursor position
  -- before the operator runs, then computes the new position based on
  -- the edits (adjusting row/col for insertions and deletions).
  -- NOTE: Does not work during dot-repeat (`.`), this is current Neovim limitation.
  keep_cursor            = true,

  -- Insert space between comment marker and text. When `true`, a single
  -- space is appended after the trimmed comment marker. When `false`, the
  -- commentstring's original spacing is preserved as-is.
  -- Example with `commentstring = "//  %s"`:
  --   `true`  → tlcs="//", olcs="// "   → `// hello`
  --   `false` → lcs="//  ", olcs="//  " → `//  hello`
  insert_space           = true,

  -- Place comment at start of line, skip indent alignment
  line_comment_no_indent = false,

  -- Match comment markers case-insensitively (e.g. `@REM` vs `@rem` vs `@rEm`)
  case_insensitive       = false,

  -- Relaxed block detection: when true, leading and trailing whitespace
  -- is trimmed from the range before looking for block comment tokens.
  -- This helps find block comments inside selections that have extra
  -- whitespace padding. When false, block detection uses the selection
  -- range as-is.
  block_relaxed_detect   = true,

  -- Maximum number of lines (forward and backward) to search for block
  -- comment pairs when using the block textobject (`gb` in operator-pending).
  -- Only relevant when no treesitter query is available for the buffer.
  block_textobj_nlines   = 200,

  -- Controls how empty lines are handled during comment toggle:
  -- - "never":  toggle and align empty lines normally.
  -- - "indent": toggle empty lines but exclude them from indent alignment.
  --             Also trim to blank when uncommenting leaves only whitespace.
  -- - "always": skip empty lines entirely — not toggled, not aligned.
  ignore_empty_lines     = "indent",

  -- Controls when to fallback from line comment to block comment:
  -- - "never":              never fallback. A wrapping commentstring
  --                         (e.g. HTML's `<!-- %s -->`) is treated as
  --                         a line comment. Each line gets wrapped
  --                         individually on `gc`.
  -- - "if_line_cms_wrapped": fallback when the line comment string wraps
  --                         the content (`<!-- %s -->`), or when no
  --                         line comment is available at all.
  --
  -- Example: buffer with `commentstring = "<!-- %s -->"`, press `gc2j`
  -- on lines `aaa` / `bbb`:
  --
  --   "never":              "if_line_cms_wrapped":
  --   <!-- aaa -->          <!-- aaa
  --   <!-- bbb -->          bbb -->
  --
  -- With `"if_line_cms_wrapped"`, the plugin detects the wrapping nature
  -- and uses block toggle to wrap the whole region once.
  fallback_to_block      = "if_line_cms_wrapped",

  -- Log level
  log_level              = vim.log.levels.OFF,

  mappings = {
    -- Line comment by motion (n)
    comment              = "gc",
    -- Line comment current line (n)
    comment_line         = "gcc",
    -- Line comment visual selection (x)
    comment_visual       = "gc",
    -- Block comment by motion (n, x)
    block                = "gb",
    -- Block comment current line (n)
    block_line           = "gbc",
    -- Block comment visual selection (x)
    block_visual         = "gb",
    -- Linewise textobject (o)
    textobject_line      = "gc",
    -- Blockwise textobject (o)
    textobject_block     = "gb",
    -- Auto textobject (o, x)
    textobject_auto      = "",
    -- Auto uncomment (n)
    uncomment_auto       = "",
    -- Insert comment below (n)
    comment_below        = "",
    -- Insert comment above (n)
    comment_above        = "",
    -- Insert comment at end of line (n)
    comment_eol          = "",
    -- Invert comment per line (n, x)
    invert               = "",
  },

  hooks = {
    -- Called before syncing edits, receives context table
    pre_sync_edits       = nil,
    -- Custom comment string resolver function
    cms_conf_resolver    = nil,
  },
}
```

Set a mapping to `""` to disable it.

#### Buffer-local configuration

Buffer-local configuration can be set via `vim.b.celeste_comment_config`.
This allows overriding non-mapping options per buffer:

```lua
-- In an ftplugin or autocmd:
vim.b.celeste_comment_config = {
  keep_cursor = false,
  insert_space = false,
}
```

The buffer config is merged with the global config, so you only need to
specify the fields you want to override. Note: mappings cannot be
overridden per buffer — they are fixed at `setup()` time.

#### Custom comment strings

The plugin resolves comment strings through a chain of resolvers
(high to low priority):

**1. `hooks.cms_conf_resolver`** — Full control, highest priority:

```lua
-- Global
require("celeste_comment").setup({
  hooks = {
    cms_conf_resolver = function(ctx)
      -- ctx.cursor, ctx.cfg, ctx.range
      ctx.o_cms_conf = { "//%s", "/*%s*/" }  -- { line, block }
    end,
  },
})

-- Per-buffer
vim.b.celeste_comment_config = {
  hooks = {
    cms_conf_resolver = function(ctx)
      ctx.o_cms_conf = { "#%s" }
    end,
  },
}
```

**2. `cms_confs` table** — Override per filetype:

```lua
-- Global
require("celeste_comment").setup({
  cms_confs = {
    toml   = { "#%s" },                    -- line only
    html   = { nil, "<!--%s-->" },         -- block only
    python = { "#%s", '"""%s"""' },        -- both
    rust   = { { "//%s", "///%s", "//!%s" }, "/*%s*/" },  -- multi-token line
    mylang = function(ctx)                 -- dynamic resolver per filetype
      return { "//%s", "/*%s*/" }
    end,
  },
})

-- Per-buffer
vim.b.celeste_comment_config = {
  cms_confs = {
    python = { "#%s" },
  },
}
```

**3. `cms_confs = false`** — Disable the built-in table entirely:

```lua
-- Global
require("celeste_comment").setup({ cms_confs = false })

-- Per-buffer
vim.b.celeste_comment_config = { cms_confs = false }
```

**4. Built-in defaults** — 40+ languages supported out of the box.

**5. Buffer fallback** — Uses `vim.bo.commentstring` and
`vim.b.celeste_comment_block_commentstring` as the last resort:

```lua
vim.bo.commentstring = "// %s"
vim.b.celeste_comment_block_commentstring = "/* %s */"
```

## Hooks

### `hooks.pre_sync_edits`

Called before edits are applied to the buffer:

```lua
---@param ctx Celeste.Comment.Hooks.PreSyncEdits.Ctx
function(ctx)
end
```

### `hooks.cms_conf_resolver`

Called to resolve comment string configuration for a given language/buffer.
Receives a context table and should set `o_cms_conf`:

```lua
---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
function(ctx)
  ctx.o_cms_conf = { "//%s", "/*%s*/" }
end
```

## Disabling

Set `vim.g.celeste_comment_disable` globally or `vim.b.celeste_comment_disable` per buffer to `true` to disable all functionality.

```lua
vim.g.celeste_comment_disable = true
```

## Acknowledgments

- [**VSCode**](https://github.com/microsoft/vscode) — The indent algorithm
  is ported from VSCode's comment implementation. Most of its test cases
  have also been ported to this plugin's test suite. This plugin is highly
  inspired by it.

- [**mini.comment**](https://github.com/nvim-mini/mini.nvim) — Its code
  style and linewise textobject implementation served as a reference for
  this plugin's development.

- [**Comment.nvim**](https://github.com/numToStr/Comment.nvim) — Part of
  the built-in language comment string table was adapted from Comment.nvim.
