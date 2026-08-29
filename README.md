<h1 align="center">celeste_comment.nvim</h1>
<p align="center"><b>Batteries-included</b> commenting plugin — line/block comment, textobjects, real sticky cursor, and more!</p>

<div align="center">

[![Version](https://img.shields.io/github/v/release/celeste3z/celeste_comment.nvim?style=for-the-badge&label=version)](https://github.com/celeste3z/celeste_comment.nvim/releases)
[![License](https://img.shields.io/github/license/celeste3z/celeste_comment.nvim?style=for-the-badge)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.12.0-green?style=for-the-badge)](https://neovim.io)
[![Maintained](https://img.shields.io/badge/maintenance-actively--developed-brightgreen?style=for-the-badge)](https://github.com/celeste3z/celeste_comment.nvim)

</div>

<!--toc:start-->

- [Features](#features)
- [Comparison](#comparison)
- [Requirements](#requirements)
- [Installation](#installation)
  - [vim.pack (Neovim 0.12+)](#vimpack-neovim-012)
  - [lazy.nvim](#lazynvim)
- [Default Configuration](#default-configuration)
- [Showcase](#showcase)
- [What it doesn't do](#what-it-doesnt-do)
- [Limitations](#limitations)
- [Future work](#future-work)
- [Acknowledgments](#acknowledgments)

<!--toc:end-->

## Features

- **`TextEdits`** -- unlike Noevim's built-in or other comment plugins, changes are modeled as `TextEdits`, making it more
  hackable and composable. This also means that the edits commit method is up to you -- `lockmarks` + `vim.api.nvim_buf_set_lines`
  for simplicity and performance, or `vim.api.nvim_buf_set_text` for more control (e.g. preserve regular marks and extmarks)
- **Line/block comment toggle** -- fully dot-repeatable with count support
- **Truly accurate keep cursor** -- cursor position tracks each `TextEdit` precisely
- **Truly accurate keep selection** -- selection range tracks each `TextEdit` precisely in visual mode
- **Context-aware comment string resolution via Tree-sitter** -- comment string adapts to context via Tree-sitter. e.g. supports
  `JSX/TSX` out of the box
- **Textobjects** -- line, block, and auto textobjects, works without Tree-sitter
- **VSCode-style indent algorithm** -- handles mixed tabs and spaces
- **Invert/Force add/Force remove comment** -- per-line comment action control
- **Insert mode line comment toggle** -- with cursor sticky support
- **Insert comment above / below / at end of line**
- **Case insensitive comment detection** -- e.g. `@REM` vs `@rem` vs `@rEm`
- **Multi-variant comment string detection** — recognizes all comment prefix variants when uncommenting (e.g. Rust `//`, `///`, `//!`)

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
| **Keep cursor**          | **Precise tracking** — cursor adjusts per TextEdit                                                                          | ❌                                                                  | Imprecise restore — save/restore<br>• no edit adjustment      | ❌                                                                  | ❌                                                        |
| **Keep selection**       | **Precise tracking** — selection adjusts per TextEdit                                                                       | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Invert per line**      | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Line textobject**      | ✅                                                                                                                          | ✅                                                                  | ❌                                                            | ✅                                                                  | ✅                                                        |
| **Block textobject**     | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Textobject auto**      | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ❌                                                        |
| **Uncomment auto**       | ✅                                                                                                                          | ❌                                                                  | ❌                                                            | ❌                                                                  | ✅                                                        |

## Requirements

- Neovim >= 0.12
- Tree-sitter parsers (Optional) -- for context-aware comment string resolution

## Installation

> [!IMPORTANT]
>
> - Breaking changes may occur in MINOR version bumps (e.g. `0.1.0` → `0.2.0`).
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

## Default Configuration

```lua
---@type Celeste.Comment.PartialOpts
{
  -- Restore cursor position after comment/uncomment.
  keep_cursor            = true,

  -- Restore selection after commenting.
  -- Possible values: "never" | "accurate" | "expand_block" | "expand_line" | "only_change_marks"
  -- Can also combine, e.g. "expand_line | only_change_marks" which means: force line comments to
  -- `V` mode and then exit visual mode, you can type `gv` to restore the selection
  -- See `:help celeste_comment-config-keep_selection` for more details
  keep_selection         = "never",

  -- Insert space between comment marker and text.
  insert_space           = true,

  -- Place comment at start of line, skip indent alignment
  line_comment_no_indent = false,

  -- Match comment markers case-insensitively (e.g. `@REM` vs `@rem` vs `@rEm`)
  case_insensitive       = false,

  -- Detect indent size and indent style (tabs vs spaces) from buffer content.
  -- Does not modify any buffer options. See `:help celeste_comment-config-detect_indent`
  -- for more details.
  detect_indent          = false,

  -- Whether to use `vim.api.nvim_buf_set_text` to commit edits.
  -- `nvim_buf_set_text` only modifies parts of lines, preserving regular marks and
  -- extmarks on non-modified parts.
  -- `nvim_buf_set_lines` + `lockmarks` replaces whole lines, has better performance
  -- but only preserves regular marks.
  use_set_text           = false,

  -- Relaxed block comment detection: ignore whitespace around markers.
  block_relaxed_detect   = true,

  -- Max lines to search for block comment pairs.
  block_textobj_nlines   = 200,

  -- How to handle empty lines during comment toggle.
  -- See `:help celeste_comment-config-ignore_empty_lines` for more details
  -- Possible values: "never" | "mixed" | "always"
  ignore_empty_lines     = "always",

  -- Fallback to block comment when line comment wraps.
  -- See `:help celeste_comment-config-fallback_to_block` for more details
  -- Possible values: "never" | "if_line_cms_wrapped"
  fallback_to_block      = "if_line_cms_wrapped",

  -- Log level (nvim-0.13+). Ignored on older versions.
  log_level              = vim.log.levels.OFF,

  -- Comment string configuration.
  cms_confs              = nil,

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

    -- Cursor sticky dot-repeat.
    -- If a "." mapping already exists, this will not override it.
    -- You can also call `require("celeste_comment").track_state()` in your
    -- own dot-repeat keymap to enable sticky cursor behavior.
    -- See `:help celeste_comment-api` for more details.
    dot_repeat           = ".",
  },

  hooks = {
    -- Called before commit edits, receives context
    pre_commit_edits     = nil,
    -- Called after commit edits, receives context
    post_commit_edits    = nil,
    -- Custom comment string resolver function
    cms_conf_resolver    = nil,
    -- Custom indent resolver function
    indent_resolver      = nil,
  },
}
```

See `:help celeste_comment-configuration` for details.

> [!TIP]
> Recommend set `vim.o.commentstring = ""` and `vim.o.comments = ""`

> [!TIP]
> If a language has built-in support for option `commentstring` and `comments` (e.g. `vim`, `asm`).
> you don't have to define anything here, we can fully fall back to Neovim's built-in
> `commentstring` and `comments` resolution
>
> This plugin already has built-in block comment support for most common languages.
>
> If some filetype isn't included, you can use `cms_confs`:
>
> ```lua
> -- for example, `lang` should be the Tree-sitter parser name or filetype
> require("celeste_comment").setup({
>   cms_confs = {
>     ["lang"] = {"//%s", "/*%s*/"}
>   }
> })
> ```
>
> Or, you can use options `comments` (`:help 'comments'`) to specify block comment string, for example,
> put this code:
>
> ```lua
> vim.cmd([[setlocal comments=s1:/*,ex:*/]])
> ```
>
> in your `after/ftplugin/<filetype>.lua`. we can retrieve the block comment string from option `comments`.
>
> And also you can use options `commentstring` (`:help 'commentstring'`) to specify line comment string,
> for example, put this code:
>
> ```lua
> vim.cmd([[setlocal commentstring=//\%s]])
> ```
>
> in your `after/ftplugin/<filetype>.lua`.
>
> For advanced comment string resolution, see `:help celeste_comment`.

**If you like this plugin, give it a ⭐!**

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
<img src="https://github.com/user-attachments/assets/58a8e554-cf6b-40c0-aa1b-13110bbd1dba" alt="Context-aware comment string resolution via Tree-sitter">
<p><em>Context-aware comment string resolution via Tree-sitter</em></p>
</div>

<div align="center">
<img src="https://github.com/user-attachments/assets/42deb618-74c2-4589-9c7c-2f1b8441f487" alt="Keep selection when toggle comments in visual mode">
<p><em>Keep selection when toggle comments in visual mode</em></p>
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

## What it doesn't do

- **Cover all cases** — Prioritizes common scenarios over edge cases.
  Some edge cases may not be considered for fixing.
- **Doc comment**
- **Header comment**

## Limitations

- **Ambiguous comment syntax** — Languages where line and block comments
  share the same prefix (e.g., Lua's `--` / `--[[ ]]`) may cause
  `textobject_auto()` to misidentify block comments as line comments.
  Use `line_textobject` or `block_textobject` explicitly instead.

- **Textobject limitations**
  - Comment-like tokens inside strings or literals may be mistakenly
    detected as comments (e.g., `char *s = "// not a comment";`).
  - Scan range is limited to `block_textobj_nlines` (default 200 lines).

- **Visual block mode (`<C-v>`)** — Comments are applied per-line,
  not per-column. For column-wise commenting, use a multicursor plugin
  like [multicursor.nvim](https://github.com/jake-stewart/multicursor.nvim).

## Future work

- Integrated with Neovim's builtin multicursor.

## Acknowledgments

- [**VSCode**](https://github.com/microsoft/vscode) — The indent algorithm
  is ported from VSCode's comment implementation. Most of its test cases
  have also been ported to this plugin's test suite. This plugin is highly
  inspired by it.

- [**Zed**](https://github.com/zed-industries/zed) — The capture-based overrides
  paradigm for comment scope resolution.

- [**mini.comment**](https://github.com/nvim-mini/mini.nvim) — Its code
  style and linewise textobjects implementation served as a reference for
  this plugin's development.

- [**Comment.nvim**](https://github.com/numToStr/Comment.nvim) — Part of
  the built-in language comment string table was adapted from Comment.nvim.
