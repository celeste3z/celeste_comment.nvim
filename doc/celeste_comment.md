## Introduction

celeste_comment.nvim — a **batteries-included** commenting plugin for Neovim with
line/block comment toggle, textobjects, force add/remove, real cursor tracking,
Tree-sitter context-aware comment resolution, and more.

The plugin uses a `TextEdits` edit-model where every operation is defined as
range+text pairs, making it more hackable and composable than the direct buffer
mutations used by other comment plugins. Cursor position is automatically
computed from `TextEdits`, providing precise tracking across complex multi-line
edits and full dot-repeat support.

## Features

- **Line/block comment toggle** -- fully dot-repeatable with count support
- **Real cursor sticky** -- precise cursor position tracking across `TextEdits`, cursor row and column automatically adjust for any edit
- **VSCode-style indent algorithm** -- handles mixed tabs and spaces
- **Invert/Force add/Force remove** -- per-line comment action control
- **Textobjects** -- line, block, and auto textobjects, works without Tree-sitter
- **Insert mode line comment toggle** -- with cursor sticky support
- **Insert comment above / below / at end of line**
- **Case insensitive comment detection** -- e.g. `@REM` vs `@rem` vs `@rEm`
- **Context-aware comment string resolution via Tree-sitter** -- comment string adapts to context via Tree-sitter, no extra plugins required. e.g. supports `JSX/TSX` out of the box
- **Multi-variant comment string detection** — recognizes all comment prefix variants when uncommenting (e.g. Rust `//`, `///`, `//!`)
- **`TextEdits` edit-model** -- unlike Neovim's built-in or other plugins, edits are modeled as `TextEdits`, making it more hackable and composable
- **40+ built-in language comment strings**
- **Custom comment string resolver hook**

## Comparison

| Feature              | celeste_comment.nvim | Neovim built-in | Comment.nvim | mini.comment | vim-commentary |
| -------------------- | -------------------- | --------------- | ------------ | ------------ | -------------- |
| Line comment         | yes                  | yes             | yes          | yes          | yes            |
| Block comment        | yes                  | no              | yes          | no           | no             |
| Force add comment    | yes                  | no              | no           | no           | no             |
| Force remove comment | yes                  | no              | no           | no           | no             |
| Dot-repeat           | yes                  | yes             | yes          | yes          | yes            |
| Count                | yes                  | yes             | yes          | yes          | yes            |
| Keep cursor          | yes                  | no              | partial      | no           | no             |
| Invert per line      | yes                  | no              | no           | no           | no             |
| Line textobject      | yes                  | yes             | no           | yes          | yes            |
| Block textobject     | yes                  | no              | no           | no           | no             |
| Textobject auto      | yes                  | no              | no           | no           | no             |
| Uncomment auto       | yes                  | no              | no           | no           | yes            |

## Requirements

- Neovim `>= 0.12`

## Installation

> [!IMPORTANT]
>
> - Breaking changes may occur in MINOR version bumps (e.g. `0.1.0` -> `0.2.0`)
> - PATCH bumps (e.g. `0.1.0` → `0.1.1`) are backward compatible.
> - `Pinning to a specific version or commit is recommended.`

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  {
    src = "https://github.com/celeste3z/celeste_comment.nvim",
    name = "celeste_comment",
    version = vim.version.range("*"),
  }
})
require("celeste_comment").setup()
```

### lazy.nvim

```lua
{ "celeste3z/celeste_comment.nvim", lazy = false, opts = {} }
```

## Configuration

### Default config

```lua
{
  keep_cursor            = true,  -- Restore cursor position after commenting
  insert_space           = true,  -- Insert space between comment marker and text
  line_comment_no_indent = false, -- Place comment at start of line, skip indent alignment
  case_insensitive       = false, -- Match comment markers case-insensitively
  block_relaxed_detect   = true,  -- Trim whitespace before detecting block tokens
  block_textobj_nlines   = 200,   -- Max lines to search for block comment pairs
  ignore_empty_lines     = "always", -- How to handle empty lines
  fallback_to_block      = "if_line_cms_wrapped", -- Fallback line→block comment
  log_level              = vim.log.levels.OFF, -- Log level (nvim-0.13+)

  mappings = {
    line_toggle          = "gc",
    line_toggle_cur      = "gcc",
    line_toggle_visual   = "gc",
    line_toggle_insert   = "",
    block_toggle         = "gb",
    block_toggle_cur     = "gbc",
    block_toggle_visual  = "gb",
    line_textobject      = "gc",
    block_textobject     = "gb",
    auto_textobject      = "",
    uncomment_auto       = "",
    line_add_below       = "",
    line_add_above       = "",
    line_add_eol         = "",
    line_invert          = "",
    line_force_add       = "",
    line_force_remove    = "",
    dot_repeat           = ".",
  },

  hooks = {
    pre_commit_edits     = nil,
    cms_conf_resolver    = nil,
  },
}
```

### Options

All options except `mappings` can be overridden per buffer via
`vim.b.celeste_comment_config` (see `:h celeste_comment-configuration`).

#### `keep_cursor` {doc="celeste_comment-config-keep_cursor"}

Default: `true`.
Restores the cursor to its computed position after commenting.
The plugin tracks the original cursor, adjusts it through each edit operation,
and restores it. When `false`, the cursor stays where Vim places it after the
edit.

#### `insert_space` {doc="celeste_comment-config-insert_space"}

Default: `true`.
Controls whether a space is inserted between the trimmed comment marker
and the text content.
With `commentstring = "// %s"`:

- `true` → `"// hello"`
- `false` → `"//hello"`

#### `line_comment_no_indent` {doc="celeste_comment-config-line_comment_no_indent"}

Default: `false`.
When `true`, the comment marker is placed at column 0 instead of preserving
the line's indentation.
With line `"  hello"`:

- `false` → `"  // hello"` (preserve indent)
- `true` → `"//   hello"` (column 0)

#### `case_insensitive` {doc="celeste_comment-config-case_insensitive"}

Default: `false`.
When `true`, comment markers are matched case-insensitively.
This helps with languages like Batch where `@REM` and `@rem` are equivalent.
With `commentstring = "@REM %s"`:

- `false` → `"@REM"` matches only
- `true` → `"@REM"`, `"@rem"`, `"@rEm"` all match

#### `block_relaxed_detect` {doc="celeste_comment-config-block_relaxed_detect"}

Default: `true`.
When `true`, leading and trailing whitespace is trimmed from the selection
range before matching block comment tokens.
With selection `"  /* hello */  "` (extra spaces around the comment):

- `true` → comment detected, remove succeeds
- `false` → detection fails (spaces included in range)

#### `block_textobj_nlines` {doc="celeste_comment-config-block_textobj_nlines"}

Default: `200`.
Maximum number of lines to search in each direction when using the block
textobject. Only used when no treesitter query is available for the buffer.

#### `ignore_empty_lines` {doc="celeste_comment-config-ignore_empty_lines"}

Default: `"always"`.
Controls how blank/whitespace-only lines are handled during comment toggle.

| Value    | Toggle blank lines? | Participate in alignment? | Aligned when all-blank? |
| -------- | ------------------- | ------------------------- | ----------------------- |
| `never`  | yes                 | yes                       | yes                     |
| `mixed`  | yes                 | no                        | yes                     |
| `always` | no                  | no                        | no                      |

With `commentstring = "# %s"` and line `"  "` (2 spaces, no content):

- `"never"` → `"  # "` (commented, aligned)
- `"mixed"` → `"  # "` (commented, excluded from alignment)
- `"always"` → `"  "` (skipped entirely)
  VSCode equivalent: `editor.comments.ignoreEmptyLines`.
- `false` → `"never"` (toggle and align empty lines)
- `true` → `"always"` (skip empty lines entirely)

> [!NOTE]
> `"mixed"` has no VSCode equivalent — it's unique to celeste_comment.

#### `fallback_to_block` {doc="celeste_comment-config-fallback_to_block"}

Default: `"if_line_cms_wrapped"`.
Controls when the plugin falls back from line comment to block comment mode.

- `"never"`: A wrapping comment string (e.g. `<!-- %s -->`) is treated as
  a line comment. Each line is wrapped individually.
- `"if_line_cms_wrapped"`: Fallback to block comment when the line comment
  wraps content.
  With `commentstring = "<!-- %s -->"` and lines `"aaa"`, `"bbb"`:
- `"never"` — each line wrapped individually:

```lua
<!-- aaa -->
<!-- bbb -->
```

- `"if_line_cms_wrapped"` — entire region wrapped as block:

```lua
<!-- aaa
bbb -->
```

#### `log_level` {doc="celeste_comment-config-log_level"}

Default: `vim.log.levels.OFF`.
Only available on nvim-0.13+. Ignored on older versions.

### Mappings

Set a mapping to `""` to disable it.
Mappings cannot be overridden per buffer — they are fixed at `setup()` time.
Use buffer-local configuration (see `:h celeste_comment-configuration`) only for non-mapping options.

| Field                 | Mode  | Default | Description                    |
| --------------------- | ----- | ------- | ------------------------------ |
| `line_toggle`         | `n`   | `gc`    | Line comment by motion         |
| `line_toggle_cur`     | `n`   | `gcc`   | Line comment current line      |
| `line_toggle_visual`  | `x`   | `gc`    | Line comment visual selection  |
| `line_toggle_insert`  | `i`   | —       | Insert mode line toggle        |
| `block_toggle`        | `n`   | `gb`    | Block comment by motion        |
| `block_toggle_cur`    | `n`   | `gbc`   | Block comment current line     |
| `block_toggle_visual` | `x`   | `gb`    | Block comment visual selection |
| `line_textobject`     | `o`   | `gc`    | Linewise comment textobject    |
| `block_textobject`    | `o`   | `gb`    | Blockwise comment textobject   |
| `auto_textobject`     | `o,x` | —       | Auto detect textobject         |
| `uncomment_auto`      | `n`   | —       | Auto detect and uncomment      |
| `line_add_below`      | `n`   | —       | Insert comment below           |
| `line_add_above`      | `n`   | —       | Insert comment above           |
| `line_add_eol`        | `n`   | —       | Insert comment at end of line  |
| `line_invert`         | `n,x` | —       | Invert comment per line        |
| `line_force_add`      | `n,x` | —       | Force add line comment         |
| `line_force_remove`   | `n,x` | —       | Force remove line comment      |
| `dot_repeat`          | `n`   | `.`     | Cursor sticky dot-repeat       |

### Hooks

Options in the `hooks` table can be overridden per buffer (see `:h celeste_comment-configuration`).

#### `pre_commit_edits` {doc="celeste_comment-hooks-pre_commit_edits"}

Called before edits are applied to the buffer. Receives a context table:

```lua
---@class Celeste.Comment.Hooks.PreCommitEdits.Ctx
---@field cursor  vim.Pos
---@field range   Celeste.Comment.Range4
---@field edits   Celeste.Comment.TextEdits
---@field cfg     Celeste.Comment.Opts
---@field ctype   Celeste.Comment.CommentType
---@field action  Celeste.Comment.Action
---@field motion  Celeste.Comment.Motion
---@field csi     Celeste.Comment.CommentStringInfo
---@field lines   string[]
```

Example — force use `nvim_buf_set_text` instead of `lockmarks + nvim_buf_set_lines`:

```lua
vim.b.celeste_comment_config = {
  hooks = {
    pre_commit_edits = function(ctx)
      ctx.o_use_set_text = true
    end,
  },
}
```

#### `cms_conf_resolver` {doc="celeste_comment-hooks-cms_conf_resolver"}

Custom comment string resolver. Called to resolve the comment string for a
given buffer/language. Set `ctx.o_cms_conf` to override:

```lua
---@class Celeste.Comment.Hooks.CmsConfResolver.Ctx
---@field cursor      vim.Pos
---@field range?      Celeste.Comment.Range4
---@field cfg         Celeste.Comment.Opts
---@field o_cms_conf? Celeste.Comment.CommentStringConf
---@field tree?       vim.treesitter.LanguageTree
```

Example:

```lua
vim.b.celeste_comment_config = {
  hooks = {
    ---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
    cms_conf_resolver = function(ctx)
      ctx.o_cms_conf = { nil, "/* %s */" }
    end
  }
}
```

### Buffer-local configuration

Non-mapping options can be overridden per buffer via `vim.b.celeste_comment_config`.
The buffer config is merged with the global config, so you only need to specify
the fields you want to override.

```lua
vim.b.celeste_comment_config = {
  keep_cursor = false,
  insert_space = false,
}
```

Mappings and the mapping infrastructure are fixed at `setup()` time and cannot
be overridden per buffer.

### Custom comment strings (cms_confs)

The plugin resolves comment strings through a chain of resolvers (high to low
priority):

1. `hooks.cms_conf_resolver` — Full control, highest priority.
2. `cms_confs` table — Override per filetype. Supports multi-token line
   comments and dynamic resolvers:

```lua
require("celeste_comment").setup({
  cms_confs = {
    rust   = { { "//%s", "///%s", "//!%s" }, "/*%s*/" },
    mylang = function(ctx)
      return { "#%s" }
    end,
  },
})
```

3. `cms_confs = false` — Disable built-in table entirely.
4. `Built-in defaults` — 40+ languages supported.
5. `Buffer fallback` — Uses `vim.bo.commentstring` and
   `vim.b.celeste_comment_block_commentstring`.

## API

### `M.setup(config)`

Initialize the plugin with configuration. Must be called once.

```lua
require("celeste_comment").setup({ keep_cursor = true })
```

### `M.track_cursor()`

Tracks cursor position for the next edit operation. Useful in custom mappings.

```lua
vim.keymap.set("n", ".", function()
  require("celeste_comment").track_cursor()
  return "."
end, { expr = true })
```

### Action enum

```lua
---@enum Celeste.Comment.Action
M.ACTION = {
  kToggle      = 1, -- If all lines commented → uncomment; else → comment
  kInvert      = 2, -- Per-line toggle, each line independently
  kForceAdd    = 3, -- Add comment to all lines (already-commented get another layer)
  kForceRemove = 4, -- Remove comment from lines that have them; skip uncommented
}
```

### Comment type enum

```lua
---@enum Celeste.Comment.CommentType
M.CMT = {
  kLine  = 1, -- Line comment
  kBlock = 2, -- Block comment
}
```

## Recipes

### Override CMS resolution entirely

Use `hooks.cms_conf_resolver` to take full control of comment string resolution.
When set, the built-in resolver chain is bypassed entirely.

```lua
require("celeste_comment").setup({
  hooks = {
    cms_conf_resolver = function(ctx)
      -- ctx.cursor, ctx.cfg, ctx.range
      ctx.o_cms_conf = { "//%s", "/*%s*/" }  -- { line, block }
    end,
  },
})
```

Per-buffer override:

```lua
vim.b.celeste_comment_config = {
  hooks = {
    cms_conf_resolver = function(ctx)
      ctx.o_cms_conf = { "#%s" }
    end,
  },
}
```

### Override comment string per filetype

Use `cms_confs` to set comment strings for specific filetypes while keeping
the built-in table for others.

```lua
require("celeste_comment").setup({
cms_confs = {
  toml  = { "#%s" },                   -- line only
  html  = { nil, "<!--%s-->" },        -- block only
  python = { "#%s", '"""%s"""' },      -- both
  rust   = { { "//%s", "///%s", "//!%s" }, "/*%s*/" }, -- multi-token line
  mylang = function(ctx)               -- dynamic resolver
    return { "#%s" }
  end,
  },
})
```

### Always use buffer-local `commentstring`

Disable the built-in language comment string table and rely solely on
`vim.bo.commentstring` (and `vim.b.celeste_comment_block_commentstring`
for block comments):

```lua
require("celeste_comment").setup({ cms_confs = false })
```

Per-buffer:

```lua
vim.b.celeste_comment_config = { cms_confs = false }
```

### Block comment markers as standalone lines

By default, `gb` wraps the first and last lines with comment markers inline:

```cpp
    /* x=x*2;
    return x; */
```

To insert markers as separate lines instead (preserving original lines for Git
tracking), use the `pre_commit_edits` hook:

Buffer-local, combine with `FileType` autocmd to scope this hook to specific filetypes.

```lua
vim.b.celeste_comment_config = {
  hooks = {
    ---@param ctx Celeste.Comment.Hooks.PreCommitEdits.Ctx
    pre_commit_edits = function(ctx)
      local cmt = require("celeste_comment")
      if ctx.ctype ~= cmt.CMT.kBlock then return end
      if ctx.action == cmt.ACTION.kForceRemove then return end
      if ctx.motion ~= "line" then return end
      if ctx.edits[1] and ctx.edits[1].text[1] == ctx.csi.olcs then
        local indent = ctx.lines[1]:match("^(%s*)") or ""
        ctx.edits = {
          { range = { ctx.range[1], -1, ctx.range[1], -1 }, text = { indent .. ctx.csi.tlcs } },
          { range = { ctx.range[3] + 1, -1, ctx.range[3] + 1, -1 }, text = { indent .. ctx.csi.trcs } },
        }
        ctx.o_use_set_text = true
      end
    end,
  },
}
```

Then `gb` on the same selection produces:

```cpp
    /*
    x=x*2;
    return x;
    */
```

To apply globally instead, pass the same `hooks` table to `setup()`:

```lua
require("celeste_comment").setup({
  hooks = {
    pre_commit_edits = function(ctx)
      -- same as above
    end,
  },
})
```

## Limitations

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
