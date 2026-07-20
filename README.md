<h1 align="center">celeste_comment.nvim</h1>
<p align="center">VSCode-style commenting plugin with support for line/block comment, textobjects, real sticky cursor and more!</p>

<!--toc:start-->

- [Features](#features)
- [Comparison](#comparison)
- [Showcase](#showcase)
- [Requirements](#requirements)
- [Installation](#installation)
  - [vim.pack (Neovim 0.12+)](#vimpack-neovim-012)
  - [lazy.nvim](#lazynvim)
- [Default Configuration](#default-configuration)
- [Details](#details)
- [What it doesn't do](#what-it-doesnt-do)
- [Limitations](#limitations)
- [Future work](#future-work)
- [Acknowledgments](#acknowledgments)
<!--toc:end-->

## Features

- Line comment toggle
- Block comment toggle
- Linewise/Blockwise/Auto-detect comment textobject (can work without treesitter)
- Vscode-style indent algorithm, line comment fallback to block comment
- Dot-repeatable, count support
- Real cursor sticky
- Invert comment per line
- Force add / Force remove line comment
- Insert mode line comment toggle
- Insert comment above / below / at end of line
- Case insensitive comment detection
- Relaxed block detection
- Precise edit tracking (via TextEdits)
- Multi line comment string uncomment — detects and removes multiple line comment strings (e.g. Rust `//`, `///`, `//!`)

## Comparison

| Feature                  | [celeste_comment.nvim](https://github.com/celeste3z/celeste_comment.nvim)                                                   | [Neovim built-in](https://neovim.io/doc/user/lua.html#vim._comment) | [Comment.nvim](https://github.com/numToStr/Comment.nvim)      | [mini.comment](https://github.com/echasnovski/mini.nvim)            | [vim-commentary](https://github.com/tpope/vim-commentary) |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------- |
| **Edit model**           | **TextEdits** — edits as range+text objects<br>• commit changes via `nvim_buf_set_text` or `nvim_buf_set_lines` (lockmarks) | Direct line replacement<br>• `nvim_buf_set_lines` (lockmarks)       | Direct line replacement<br>• `nvim_buf_set_lines` (lockmarks) | Direct line replacement<br>• `nvim_buf_set_lines` (lockmarks)       | Direct line replacement<br>• Vim `setline()`              |
| **Line comment**         | ✅                                                                                                                          | ✅                                                                  | ✅                                                            | ✅                                                                  | ✅                                                        |
| **Block comment**        | ✅                                                                                                                          | ❌                                                                  | ✅                                                            | ❌                                                                  | ❌                                                        |
| **Force add comment**    | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Force remove comment** | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Dot-repeat**           | ✅                                                                                                                          | ✅                                                                  | ✅                                                            | ✅                                                                  | ✅                                                        |
| **Count**                | ✅                                                                                                                          | ✅                                                                  | ✅                                                            | ✅                                                                  | ✅                                                        |
| **Indent algorithm**     | **VSCode-style** — min visible col<br>• handle mixed tab/space                                                              | Simple — min whitespace prefix<br>• does not handle mixed tab/space | Standard — shiftwidth/tabstop                                 | Simple — min whitespace prefix<br>• does not handle mixed tab/space | Minimal — `^\s*\zs`<br>• optional startofline             |
| **Keep cursor**          | **Precise tracking** — adjust per TextEdit<br>• row/col shifts<br>• multi-line inserts                                      | ❌                                                                  | Imprecise restore — save/restore<br>• no edit adjustment      | ❌                                                                  | ❌                                                        |
| **Invert per line**      | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Line textobject**      | ✅                                                                                                                          | ✅                                                                  | ❌                                                            | ✅                                                                  | ✅                                                        |
| **Block textobject**     | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Textobject auto**      | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Uncomment auto**       | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ✅                                                        |

## Showcase

<div align="center">
<img src="https://github.com/user-attachments/assets/c4255b81-926a-4ab7-ac3e-d49b77e980a1" alt="Line/Block comment toggle, textobjects, gcu">
<p><em>Line/Block comment toggle, textobjects, gcu</em></p>
</div>

<div align="center">
<img src="https://github.com/user-attachments/assets/49812f9f-5f1b-44d7-b52a-e46fdccd322f" alt="Commenting in insert mode with keep cursor">
<p><em>Commenting in insert mode with keep cursor</em></p>
</div>

<div align="center">
<img src="https://github.com/user-attachments/assets/8cf4583c-7dcc-4794-9c18-3df36d070991" alt="Force add/remove comment and dot-repeat">
<p><em>Force add/remove comment and dot-repeat</em></p>
</div>

<div align="center">
<img src="https://github.com/user-attachments/assets/557ef444-96ee-4352-9d60-759b97153e89" alt="Invert comment status per-line">
<p><em>Invert comment status per-line</em></p>
</div>

<div align="center">
<img src="https://github.com/user-attachments/assets/bfd93574-ecef-410f-8942-8300b9999813" alt="Cursor sticky and Dot-repeat">
<p><em>Cursor sticky + Dot-repeat</em></p>
</div>

<div align="center">
<img src="https://github.com/user-attachments/assets/7af734f5-8daa-41e0-93d9-f597866d7517" alt="With multicursor.nvim">
<p><em>With <a href="https://github.com/jake-stewart/multicursor.nvim">multicursor.nvim</a></em></p>
</div>

## Requirements

- Neovim **>= 0.12**

## Installation

> [!IMPORTANT]
>
> - Breaking changes may occur in MINOR version bumps (e.g. `0.1.0` → `0.2.0`).
> - PATCH bumps (e.g. `0.1.0` → `0.1.1`) are backward compatible.
> - **Pinning to a specific version or commit is recommended.**

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ { src = "https://github.com/celeste3z/celeste_comment.nvim", name = "celeste_comment", version = vim.version.range("*") } })

require("celeste_comment").setup({})
```

### lazy.nvim

```lua
{ "celeste3z/celeste_comment.nvim", lazy = false, opts = {} }
```

## Default Configuration

```lua
{
  -- Restore cursor position after commenting.
  keep_cursor            = true,

  -- Insert space between comment marker and text.
  insert_space           = true,

  -- Place comment at start of line, skip indent alignment
  line_comment_no_indent = false,

  -- Match comment markers case-insensitively (e.g. `@REM` vs `@rem` vs `@rEm`)
  case_insensitive       = false,

  -- Trim whitespace before detecting block tokens.
  block_relaxed_detect   = true,

  -- Max lines to search for block comment pairs.
  block_textobj_nlines   = 200,

  -- How to handle empty lines during comment toggle.
  -- See `:help celeste_comment-configuration` for more details
  -- Possible values: "never" | "mixed" | "always"
  ignore_empty_lines     = "always",

  -- Fallback to block comment when line comment wraps.
  -- See `:help celeste_comment-configuration` for more details
  -- Possible values: "never" | "if_line_cms_wrapped"
  fallback_to_block      = "if_line_cms_wrapped",

  -- Log level (nvim-0.13+). Ignored on older versions.
  log_level              = vim.log.levels.OFF,

  mappings = {
    -- Line comment by motion (n)
    line_toggle          = "gc",
    -- Line comment current line (n)
    line_toggle_cur      = "gcc",
    -- Line comment visual selection (x)
    line_toggle_visual   = "gc",
    -- Insert mode line toggle (i), example `{"<M-/>", "<M-_>"}`
    line_toggle_insert   = "",

    -- Block comment by motion (n, x)
    block_toggle         = "gb",
    -- Block comment current line (n)
    block_toggle_cur     = "gbc",
    -- Block comment visual selection (x)
    block_toggle_visual  = "gb",

    -- Linewise textobject (o)
    line_textobject      = "gc",
    -- Blockwise textobject (o)
    block_textobject     = "gb",
    -- Auto textobject (o, x), example 'ga'
    auto_textobject      = "",
    -- Auto uncomment (n), example `gcu`
    uncomment_auto       = "",

    -- Insert comment below (n), example `gco`
    line_add_below       = "",
    -- Insert comment above (n), example `gcO`
    line_add_above       = "",
    -- Insert comment at end of line (n), example `gcA`
    line_add_eol         = "",

    -- Invert comment per line (n, x), example `gcI`
    line_invert          = "",
    -- Force add line comment (n, x), example `gCC`
    line_force_add       = "",
    -- Force remove line comment (n, x), example `gCU`
    line_force_remove    = "",

    -- Cursor sticky dot-repeat
    dot_repeat           = ".",
  },

  hooks = {
    -- Called before commit edits, receives context
    pre_commit_edits     = nil,
    -- Custom comment string resolver function
    cms_conf_resolver    = nil,
  },
}
```

See `:help celeste_comment-configuration` for details.

## Details

See `:help celeste_comment` for the full documentation, including all
configuration options, mappings, hooks, API reference, and usage examples.

## What it doesn't do

- **Cover all cases** — This plugin's aim is to handle the vast majority of
  common scenarios, not every possible case. Known textobject edge cases and
  unusual comment patterns are acknowledged but not planned to fix.
- **Doc comment**
- **Header comment**

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

## Future work

- Integrated with Neovim's builtin multicursor.

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

---

<p align="center"><b>Enjoying <a href="https://github.com/celeste3z/celeste_comment.nvim">celeste_comment.nvim</a>? Give it a ⭐!</b></p>
