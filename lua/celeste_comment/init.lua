---@class Celeste.Comment
local M = {}

local H = {}

---@alias Celeste.Comment.Motion 'line'|'char'|'block'

---@alias Celeste.Comment.Range2 [integer, integer] 0-indexed
---@alias Celeste.Comment.Range3 [integer, integer, integer] 0-indexed
---@alias Celeste.Comment.Range4 [integer, integer, integer, integer] 0-indexed

---@enum Celeste.Comment.CommentType
M.CMT = {
  --- Line comment type
  kLine = 1,
  --- Block comment type
  kBlock = 2,
}

---@enum Celeste.Comment.Opts.IgnoreEmptyLines
---
--- Summary:
--- | Mode  | Toggle blank lines? | Participate in alignment? | Aligned when all-blank? |
--- |-------|---------------------|---------------------------|-------------------------|
--- | never | yes                 | yes                       | yes                     |
--- | mixed | yes                 | no                        | yes                     |
--- | always| no                  | no                        | no                      |
---
M.IGN_EMT = {
  --- Comment/uncomment empty lines. Blank lines participate in
  --- indentation alignment.
  kNever = "never",
  --- Toggle empty lines but exclude them from indentation alignment.
  kMixed = "mixed",
  --- Skip empty lines entirely — they are not toggled nor aligned.
  kAlways = "always",
}

---@enum Celeste.Comment.Opts.FallbackToBlock
M.FBK2BLOCK = {
  --- Always use line comment operations. `gc` does nothing when
  --- the language has no line comment, even if it has block comment.
  kNever = "never",
  --- Fallback to block comment when the line comment is missing
  --- or when it's a wrapping pair (e.g. `<!-- -->`, `{- -}`).
  --- In those cases `gc` uses block toggle instead of line toggle.
  kIfLineCmsWrapped = "if_line_cms_wrapped",
}

---@enum Celeste.Comment.KeepSelFlag
M.KEEP_SEL_FLAG = {
  --- Do not restore the visual selection.
  kNever = 0,
  --- Restore the selection with precise per-edit tracking.
  kAccurate = 1,
  --- Extend the selection to cover the just-added block comment markers.
  kExpandBlock = 2,
  --- Force line comments to use V mode for restore.
  kExpandLine = 4,
  --- Only update marks without staying in visual mode; use `gv` to restore.
  kOnlyChangeMarks = 8,
}

H.KEEP_SEL_MAP = {
  never = M.KEEP_SEL_FLAG.kNever,
  accurate = M.KEEP_SEL_FLAG.kAccurate,
  expand_block = M.KEEP_SEL_FLAG.kExpandBlock,
  expand_line = M.KEEP_SEL_FLAG.kExpandLine,
  only_change_marks = M.KEEP_SEL_FLAG.kOnlyChangeMarks,
}

---@enum Celeste.Comment.Action
M.ACTION = {
  --- Toggle: if all lines commented → uncomment; else → comment.
  kToggle = 1,
  --- Invert: per-line toggle, each line independently commented or uncommented.
  kInvert = 2,
  --- Force add comment to all lines (already-commented lines get another layer).
  kForceAdd = 3,
  --- Force remove comment from lines that have them; skip uncommented lines.
  kForceRemove = 4,
}

---@class Celeste.Comment.TextEdit
---@field range Celeste.Comment.Range4
---@field text  string[]

---@class Celeste.Comment.TextEdits
---@field [integer] Celeste.Comment.TextEdit
---@field any_multi? boolean some edit have multiple lines
---@field need_sort? boolean need sort edits

---@class Celeste.Comment.CommentStringConf.Overrides
---@field [string] (Celeste.Comment.CommentStringConf)

---@class Celeste.Comment.CommentStringConf
---@field [1] (string|string[])?
---@field [2] (string|string[])?
---@field query? string query string
---@field overrides? Celeste.Comment.CommentStringConf.Overrides

---@class Celeste.Comment.CommentStringConfs
---@field [string] (string|Celeste.Comment.CommentStringConf|fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx))

---@class Celeste.Comment.CommentStringInfo.Pairs
---@field tesc [string, string]
---@field traw [string, string]
---@field tout [string, string]

---@class Celeste.Comment.CommentStringInfo
---@field ci          boolean -- case-insensitive
---@field wrapped     boolean -- comment string was wrapped
---@field tlcs        string  -- vim.trim(lcs)
---@field trcs        string  -- vim.trim(rcs)
---@field olcs        string  -- output: pad=true->tlcs+" ", else->lcs
---@field orcs        string  -- output: pad=true->" "+trcs, else->rcs
---@field pairs       Celeste.Comment.CommentStringInfo.Pairs[]

---@class Celeste.Comment.LineCommentInfo.Line
---@field row              integer real row in buffer
---@field lead_ws_len      integer leading whitespace len
---@field offset           integer 0-indexed byte position where comment marker should be inserted
---@field ignore           boolean should thie line be ignored?
---@field lcs_pos          Celeste.Comment.Range3? position of lcs
---@field rcs_pos          Celeste.Comment.Range3? position of rcs
---@field csi              Celeste.Comment.CommentStringInfo comment string info
---@field indent           Celeste.Comment.IndentInfo resolved indent info (shared across lines)
---@field visible_col      integer visible column count of leading whitespace
---@field min_visible_col? integer aligned target visible column (for padding calculation)
---@field commented?       boolean commented or not
---@field all_blank?       boolean blank line
---@field will_blank?      boolean not blank, but will be blank after remove lcs and rcs, current only available with ignore_empty_lines = kMixed

---@class Celeste.Comment.LineCommentInfo
---@field lines         Celeste.Comment.LineCommentInfo.Line[]
---@field should_remove boolean

---@class Celeste.Comment.IndentInfo
---@field indent_size  integer
---@field indent_style "space"|"tab"

---@class Celeste.Comment.Hooks.IndentResolver.Ctx
---@field cfg       Celeste.Comment.Opts
---@field buf       integer
---@field o_indent? Celeste.Comment.IndentInfo

---@class Celeste.Comment.BlockCommentInfo
---@field lcs_pos Celeste.Comment.Range3
---@field rcs_pos Celeste.Comment.Range3

---@class Celeste.Comment.StateTrack
---@field cursor?      vim.Pos original cursor captured by `make_state_track`, never modified
---@field endpos?      vim.Pos original visual-start mark, never modified
---@field mode?        string
---@field adj_cursor?  vim.Pos adjusted cursor
---@field adj_endpos?  vim.Pos adjusted selection anchor

---@class Celeste.Comment.Hooks.PreCommitEdits.Ctx
---@field cursor          vim.Pos
---@field range           Celeste.Comment.Range4
---@field edits           Celeste.Comment.TextEdits
---@field cfg             Celeste.Comment.Opts
---@field ctype           Celeste.Comment.CommentType
---@field action          Celeste.Comment.Action
---@field motion          Celeste.Comment.Motion
---@field csi             Celeste.Comment.CommentStringInfo
---@field lines           string[]
---@field state_track?    Celeste.Comment.StateTrack
---@field execution_opts? Celeste.Comment.ExecutionOpts
---@field comment_info?   Celeste.Comment.LineCommentInfo|Celeste.Comment.BlockCommentInfo
---@field o_use_set_text? boolean o: means output from user

---@class Celeste.Comment.Hooks.PostCommitEdits.Ctx : Celeste.Comment.Hooks.PreCommitEdits.Ctx

---@class Celeste.Comment.Hooks.CmsConfResolver.Ctx
---@field cursor      vim.Pos
---@field range?      Celeste.Comment.Range4
---@field cfg         Celeste.Comment.Opts
---@field o_cms_conf? Celeste.Comment.CommentStringConf
---@field tree?       vim.treesitter.LanguageTree

---@class Celeste.Comment.Hooks
---@field pre_commit_edits?  fun(ctx:Celeste.Comment.Hooks.PreCommitEdits.Ctx):boolean?
---@field post_commit_edits? fun(ctx:Celeste.Comment.Hooks.PostCommitEdits.Ctx):boolean?
---@field cms_conf_resolver? fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx)
---@field indent_resolver?   fun(ctx:Celeste.Comment.Hooks.IndentResolver.Ctx)

---@class Celeste.Comment.Opts.Mapping
---@field line_toggle?           string|string[] mode 'n', operator, default 'gc'
---@field line_toggle_cur?       string|string[] mode 'n', default 'gcc'
---@field line_toggle_visual?    string|string[] mode 'x', default 'gc'
---@field line_toggle_insert     string|string[] mode 'i', toggle comment at current line in insert mode, '<C-/>'
---@field block_toggle?          string|string[] mode 'n', operator, default 'gb'
---@field block_toggle_cur?      string|string[] mode 'n', default 'gbc'
---@field block_toggle_visual?   string|string[] mode 'x', default 'gb'
---@field line_textobject?       string|string[] mode 'o', linewise textobject, like 'gc', default ''
---@field block_textobject?      string|string[] mode 'o', blockwise textobject, like 'gb', default ''
---@field auto_textobject?       string|string[] mode 'o', auto detect textobject, default 'ga'
---@field line_add_below?        string|string[] mode 'n', comment below, 'gco'
---@field line_add_above?        string|string[] mode 'n', comment above, 'gcO'
---@field line_add_eol?          string|string[] mode 'n', comment eol, 'gcA'
---@field uncomment_auto?        string|string[] mode 'n', auto detect and uncomment, 'gcu'
---@field line_invert?           string|string[] mode 'nx', invert comment per line, ''
---@field line_force_add?        string|string[] mode 'nx', force add line comment, ''
---@field line_force_remove?     string|string[] mode 'nx', force remove line comment, ''
---@field dot_repeat?            string|string[] mode 'n', default '.'

---@class Celeste.Comment.Opts
---@field keep_cursor                boolean
---@field keep_selection             integer
---@field insert_space               boolean
---@field line_comment_no_indent     boolean
---@field case_insensitive           boolean
---@field textobj_treesitter_detect  boolean
---@field block_textobj_nlines       integer
---@field block_relaxed_detect       boolean
---@field ignore_empty_lines         Celeste.Comment.Opts.IgnoreEmptyLines
---@field detect_indent              boolean
---@field use_set_text               boolean
---@field fallback_to_block          Celeste.Comment.Opts.FallbackToBlock
---@field cms_confs?                 Celeste.Comment.CommentStringConfs|boolean
---@field mappings                   Celeste.Comment.Opts.Mapping
---@field hooks                      Celeste.Comment.Hooks
---@field log_level                  vim.log.levels

---@class Celeste.Comment.PartialOpts
---@field keep_cursor?                boolean default true
---@field keep_selection?             string|integer default 'never'
---@field insert_space?               boolean default true
---@field line_comment_no_indent?     boolean default false
---@field case_insensitive?           boolean default false
---@field textobj_treesitter_detect?  boolean default false
---@field block_textobj_nlines?       integer default 200
---@field block_relaxed_detect?       boolean default true
---@field ignore_empty_lines?         Celeste.Comment.Opts.IgnoreEmptyLines default 'always'
---@field detect_indent?              boolean default false
---@field use_set_text?               boolean default false
---@field fallback_to_block?          Celeste.Comment.Opts.FallbackToBlock default 'if_line_cms_wrapped'
---@field cms_confs?                  Celeste.Comment.CommentStringConfs|boolean default nil
---@field mappings?                   Celeste.Comment.Opts.Mapping
---@field hooks?                      Celeste.Comment.Hooks
---@field log_level?                  vim.log.levels

---@class Celeste.Comment.ExecutionOpts
---@field [string] any

---@type Celeste.Comment.StateTrack?
H.state_track = nil

-- stylua: ignore start
---@type Celeste.Comment.Opts
H.config = {
  keep_cursor               = true,
  keep_selection            = M.KEEP_SEL_FLAG.kNever,
  insert_space              = true,
  line_comment_no_indent    = false,
  case_insensitive          = false,
  block_relaxed_detect      = true,
  textobj_treesitter_detect = false,
  block_textobj_nlines      = 200,
  ignore_empty_lines        = M.IGN_EMT.kAlways,
  detect_indent             = false,
  use_set_text              = false,
  fallback_to_block         = M.FBK2BLOCK.kIfLineCmsWrapped,
  log_level                 = vim.log.levels.OFF,
  cms_confs                 = nil,

  mappings = {
    line_toggle             = "gc",
    line_toggle_cur         = "gcc",
    line_toggle_visual      = "gc",

    line_toggle_insert      = "",
    line_add_below          = "",
    line_add_above          = "",
    line_add_eol            = "",
    line_invert             = "",
    line_force_add          = "",
    line_force_remove       = "",

    block_toggle            = "gb",
    block_toggle_cur        = "gbc",
    block_toggle_visual     = "gb",

    line_textobject         = "gc",
    block_textobject        = "gb",
    auto_textobject         = "",

    uncomment_auto          = "",

    dot_repeat              = ".",
  },

  hooks = {
    pre_commit_edits        = nil,
    post_commit_edits       = nil,
    cms_conf_resolver       = nil,
    indent_resolver         = nil
  }
}

local CHAR_CODE = {
  TAB     = 9,  -- \t
  SPACE   = 32, -- (space)
  COMMA   = 44, -- ,
  UPPER_A = 65, -- A
  UPPER_Z = 90, -- Z
}

local LOG_LEVEL2NAME = {
  [vim.log.levels.TRACE] = "trace",
  [vim.log.levels.DEBUG] = "debug",
  [vim.log.levels.INFO]  = "info",
  [vim.log.levels.WARN]  = "warn",
  [vim.log.levels.ERROR] = "error",
}
-- stylua: ignore end

local HAS_NVIM_012 = vim.fn.has("nvim-0.12") == 1
local HAS_NVIM_013 = vim.fn.has("nvim-0.13") == 1

---TODO: delete this if we drop support for nvim-0.12
---@diagnostic disable
do
  ---@param buf integer
  ---@param pos? [integer, integer] (lnum, col) tuple
  ---@return integer, [integer, integer]
  local function normalize_cursor_args(buf, pos)
    if pos then
      if buf == 0 then buf = vim.api.nvim_get_current_buf() end
    else
      local win = buf
      if win == 0 then win = vim.api.nvim_get_current_win() end
      buf = vim.api.nvim_win_get_buf(win)
      pos = vim.api.nvim_win_get_cursor(win)
    end

    return buf, pos
  end

  ---@param pos vim.Pos
  ---@return integer
  function H.pos_to_offset(pos) return vim.api.nvim_buf_get_offset(pos.buf, pos[1]) + pos[2] end

  ---@param pos? vim.Pos
  ---@return vim.Pos?
  function H.pos_clone(pos)
    if pos then return H.make_pos(pos.buf, pos.row, pos.col) end
  end

  if vim.fn.has("nvim-0.12.2") == 1 then
    ---@param buf integer
    ---@param pos [integer, integer] (lnum, col) tuple
    ---@return vim.Pos
    ---@overload fun(win: integer): vim.Pos
    function H.make_cursor(buf, pos)
      buf, pos = normalize_cursor_args(buf, pos)
      return vim.pos.cursor(buf, pos)
    end

    ---@param buf integer
    ---@param row integer 0-indexed
    ---@param col integer 0-indexed
    function H.make_pos(buf, row, col) return vim.pos(buf, row, col) end

    if HAS_NVIM_013 then
      ---@param pos vim.Pos
      ---@return [integer, integer]
      function H.pos_to_cursor(pos) return pos:to_cursor() end
    else
      ---@param pos vim.Pos
      ---@return [integer, integer]
      function H.pos_to_cursor(pos) return { pos:to_cursor() } end
    end
  else
    ---@param buf integer
    ---@param pos [integer, integer] (lnum, col) tuple
    ---@return vim.Pos
    ---@overload fun(win: integer): vim.Pos
    function H.make_cursor(buf, pos)
      buf, pos = normalize_cursor_args(buf, pos)
      return vim.pos.cursor(pos, { buf = buf })
    end

    ---@param buf integer
    ---@param row integer 0-indexed
    ---@param col integer 0-indexed
    function H.make_pos(buf, row, col) return vim.pos(row, col, { buf = buf }) end

    ---@param pos vim.Pos
    ---@return [integer, integer]
    function H.pos_to_cursor(pos) return { pos:to_cursor() } end
  end
end

---@param level vim.log.levels
---@return boolean
function H.should_log(level) return level >= H.config.log_level and HAS_NVIM_013 end

---@param level vim.log.levels
---@vararg any
function H.log(level, ...)
  if not H.should_log(level) then return end
  if not H.logger then H.logger = vim.log.new({ name = "celeste_comment", level = H.config.log_level }) end
  if H.logger then H.logger[LOG_LEVEL2NAME[level]](...) end
end
---@diagnostic enable

---@param cfg? Celeste.Comment.PartialOpts
---@return Celeste.Comment.Opts
function H.buf_config(cfg)
  local bcfg = vim.b.celeste_comment_config
  local tb_bcfg = type(bcfg) == "table"
  local tb_cfg = type(cfg) == "table"
  if not tb_bcfg and not tb_cfg then return H.config end
  local result = vim.tbl_deep_extend("force", H.config, tb_bcfg and bcfg or {}, tb_cfg and cfg or {})
  return H.normalize_config(result)
end

---NOTE:
--- 1. The `key` can be a Tree-sitter name or a filetype. e.g. `cs` vs `c_sharp`
--- 2. If a language has just one comment style (e.g. `vim`, `asm`) and Neovim already
---    can sets its `commentstring` natively, you don't need to define anything here. Use
---    `vim.filetype.get_option("xxx", "commentstring")` to see if it's supported, we'll
---    automatically fall back to it, no extra config needed here.
---@type Celeste.Comment.CommentStringConfs
H.comment_string_confs = {
  astro = { nil, "<!--%s-->" },
  bat = { "@REM%s", nil },
  bicep = { "//%s", "/*%s*/" },
  c = { "//%s", "/*%s*/" },
  c_sharp = { "//%s", "/*%s*/" },
  cmake = { { "#%s" }, "#[[%s]]" },
  cpp = { { "//%s" }, "/*%s*/" },
  cs = "c_sharp",
  css = { nil, { "/*%s*/", "<!--%s-->" } },
  cuda = { "//%s", "/*%s*/" },
  d = { "//%s", "/*%s*/" },
  dart = { "//%s", "/*%s*/" },
  dhall = { "--%s", "{-%s-}" },
  dot = { "//%s", "/*%s*/" },
  elm = { "--%s", "{-%s-}" },
  faust = { "//%s", "/*%s*/" },
  foam = { "//%s", "/*%s*/" },
  fsharp = { { "//%s", "///%s" }, "(*%s*)" },
  gdshader = { "//%s", "/*%s*/" },
  go = { { "//%s" }, "/*%s*/" },
  gomod = { { "//%s" }, nil },
  groovy = { { "//%s" }, "/*%s*/" },
  haskell = { { "--%s" }, "{-%s-}" },
  hcl = { { "#%s", "//%s" }, "/*%s*/" },
  html = { nil, "<!--%s-->" },
  ini = { { ";%s", "#%s" }, nil },
  java = { { "//%s" }, "/*%s*/" },
  javascript = "tsx",
  json5 = { { "//%s" }, "/*%s*/" },
  jsonc = { { "//%s" }, "/*%s*/" },
  jsx = "tsx",
  julia = { "#%s", "#=%s=#" },
  kdl = { "//%s", { "/*%s*/" } },
  kotlin = { { "//%s" }, "/*%s*/" },
  latex = { "%%s", { "\\iffalse%s\\fi", "\\begin{comment}%s\\end{comment}" } },
  tex = "latex",
  lisp = { { ";;%s" }, "#|%s|#" },
  lua = { { "--%s", "--[[%s]]" }, "--[[%s]]" },
  markdown = { nil, "<!--%s-->" },
  nim = { "#", "#[%s]#" },
  nix = { { "#%s" }, "/*%s*/" },
  objc = { { "//%s" }, "/*%s*/" },
  objcpp = { { "//%s" }, "/*%s*/" },
  odin = { "//%s", "/*%s*/" },
  php = { { "//%s" }, { "/*%s*/", "<!--%s-->" } },
  powershell = { "#%s", "<#%s#>" },
  ps1 = "powershell",
  proto = { "//%s", "/*%s*/" },
  purescript = { "--%s", "{-%s-}" },
  python = { { "#%s" }, '"""%s"""' },
  racket = { ";;%s", "#|%s|#" },
  rasi = { "//%s", "/*%s*/" },
  razor = {
    { "@*%s*@" },
    { "@*%s*@" },
    query = [[
      (razor_block) @code.inner
    ]],
    overrides = { code = { "//%s", nil } },
  },
  rescript = { "//%s", "/*%s*/" },
  ron = { "//%s", "/*%s*/" },
  rust = { { "//%s", "///%s", "//!%s" }, "/*%s*/" },
  scala = { { "//%s" }, "/*%s*/" },
  scheme = { { ";;%s" }, { "#|%s|#" } },
  solidity = { "//%s", "/*%s*/" },
  sql = { { "--%s" }, "/*%s*/" },
  supercollider = { "//%s", "/*%s*/" },
  superhtml = { nil, "<!--%s-->" },
  swift = { { "//%s" }, "/*%s*/" },
  systemverilog = { "//%s", "/*%s*/" },
  tablegen = { "//%s", "/*%s*/" },
  teal = { "--%s", "--[[%s]]" },
  templ = {
    { "//%s" },
    nil,
    query = [[
      (component_block) @statement.inner
    ]],
    overrides = { statement = { "<!--%s-->", "<!--%s-->" } },
  },
  terraform = { { "#%s", "//%s" }, "/*%s*/" },
  tsx = {
    { "//%s", "{/*%s*/}" },
    { "/*%s*/", "{/*%s*/}" },
    query = [[
      (jsx_element) @jsx.end_exclusive
      (
        [
          (jsx_expression . (comment)+)
          (object . (comment)+)
          (statement_block . (comment)+)
        ] @jsx.inclusive
        (#match? @jsx.inclusive "^\\{/\\*")
      )
      [
        (jsx_opening_element)
        (jsx_closing_element)
        (jsx_self_closing_element)
        (jsx_expression)
      ] @nojsx.inner
    ]],
    overrides = { jsx = { "{/*%s*/}", "{/*%s*/}" }, nojsx = { { "//%s", "{/*%s*/}" }, { "/*%s*/", "{/*%s*/}" } } },
  },
  typescript = { { "//%s" }, "/*%s*/" },
  typespec = { "//%s", "/*%s*/" },
  typst = { "//%s", "/*%s*/" },
  v = { "//%s", "/*%s*/" },
  vala = { "//%s", "/*%s*/" },
  wgsl = { "//%s", "/*%s*/" },
  xml = { nil, "<!--%s-->" },
  zig = { { "//%s", "///%s", "//!%s" }, nil },
}

---@param opt? table<string, any>
---@return boolean
function H.is_disabled(opt)
  opt = opt or {}
  local chunks = { { "celeste_comment.nvim", "DiagnosticSignHint" } }
  if not HAS_NVIM_012 then
    chunks[#chunks + 1] = { " requires nvim-0.12", "WarningMsg" }
  elseif vim.g.celeste_comment_disable == true or vim.b.celeste_comment_disable == true then
    chunks[#chunks + 1] = { " disabled", "WarningMsg" }
  elseif opt.check_modifiable and not vim.bo.modifiable then
    chunks[#chunks + 1] = { " buffer unmodifiable", "WarningMsg" }
  end

  if not opt.silent and #chunks > 1 then vim.api.nvim_echo(chunks, true, {}) end

  return #chunks > 1
end

---@return boolean
function H.is_visual() return vim.fn.mode():match("[vV\22]") ~= nil end

---@param v string|integer
---@param map table<string, integer>
---@param name string
---@return integer flags
---@return string? error
function H.normalize_flags(v, map, name)
  local flags = 0

  if type(v) == "number" then
    flags = v
  elseif type(v) == "string" then
    for part in v:gmatch("[^|]+") do
      local word = vim.trim(part)
      if not map[word] then return 0, ("invalid part '%s' of '%s'"):format(word, name) end
      flags = bit.bor(flags, map[word])
    end
  else
    return 0, ("expected string|number for '%s' but got %s"):format(name, type(v))
  end

  local mask = vim.iter(map):fold(0, function(acc, _, f) return bit.bor(acc, f) end)
  flags = bit.band(flags, mask)

  return flags, nil
end

---@param cfg Celeste.Comment.Opts
---@return Celeste.Comment.Opts
function H.normalize_config(cfg)
  cfg.keep_selection = H.normalize_flags(cfg.keep_selection, H.KEEP_SEL_MAP, "keep_selection")
  return cfg
end

---@param cms_conf Celeste.Comment.CommentStringConf
function H.normalize_cms_conf(cms_conf)
  assert(type(cms_conf) == "table", "invalid cms_conf, must be a table value")
  local function norm(v)
    local t = type(v)
    if t == "string" then
      v = { v }
    elseif t ~= "table" or #v == 0 then
      v = { "" }
    else
      for i, k in ipairs(v) do
        if type(k) ~= "string" then v[i] = "" end
      end
    end
    return v
  end

  cms_conf[M.CMT.kLine] = norm(cms_conf[M.CMT.kLine])
  cms_conf[M.CMT.kBlock] = norm(cms_conf[M.CMT.kBlock])
end

---@param comments string
---@return string[]
function H.split_comments_parts(comments)
  if not H.COMMENTS_PARTS_PATTERN then
    local P, C, Ct = vim.lpeg.P, vim.lpeg.C, vim.lpeg.Ct
    local part = C((P("\\") * P(1) + (1 - P(","))) ^ 0)
    H.COMMENTS_PARTS_PATTERN = Ct(part * (P(",") * part) ^ 0)
  end
  return H.COMMENTS_PARTS_PATTERN:match(comments)
end

---@class Celeste.Comment.ExtractCommentsRes
---@field s?    {str:string, flags:string}
---@field m?    {str:string, flags:string}
---@field e?    {str:string, flags:string}
---@field line? {str:string, flags:string}

---@return Celeste.Comment.ExtractCommentsRes
function H.do_extract_comments(comments)
  if type(comments) ~= "string" or comments == "" then return {} end

  local res = {}
  for _, part in ipairs(H.split_comments_parts(comments)) do
    local flags, value = part:match("^([nbfsmelrOx0-9%-]*):(.*)$")
    if flags and value then
      value = value:gsub("\\([,: ])", "%1")
      if not flags:find("O", 1, true) then res[flags:match("[sme]") or "line"] = { str = value, flags = flags } end
    end
  end
  return res
end

---@param ltree vim.treesitter.LanguageTree
---@param pos vim.Pos
---@return boolean
function H.ltree_contains(ltree, pos)
  local off = H.pos_to_offset(pos)
  for _, tree in pairs(ltree:trees()) do
    local ranges = tree:included_ranges(true)
    -- HACK: `#ranges > 1` signals a combined injection; may not be accurate, but works in most scenarios?
    -- Useful for some cases, e.g. html+css (</style>) and php+html (<?php)
    local inclusive = #ranges > 1
    for _, tr in ipairs(ranges) do
      if off >= tr[3] and (off < tr[6] or (inclusive and off == tr[6])) then return true end
    end
  end
  return false
end

---@param pos vim.Pos
---@return vim.Pos
function H.adjust_to_start_column_pos(pos)
  local line = vim.fn.getline(pos.row + 1)
  local start_col = line:match("^%s*()")
  if start_col then return H.make_pos(pos.buf, pos.row, start_col - 1) end
  return pos
end

---Based on https://github.com/neovim/neovim/blob/master/runtime/lua/vim/_comment.lua
---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
function H.nvim_builtin_like_cms_conf_resolver(ctx)
  local function get_cms_opt(filetype)
    local cs = vim.filetype.get_option(filetype, "commentstring")
    if type(cs) == "string" and cs ~= "" then return cs end
  end

  local function get_bcms_opt(filetype)
    local bcs = H.do_extract_comments(vim.filetype.get_option(filetype, "comments"))
    if bcs.s and bcs.e and bcs.s.str ~= "" and bcs.e.str ~= "" then return ("%s%%s%s"):format(bcs.s.str, bcs.e.str) end
  end

  local pos = H.adjust_to_start_column_pos(ctx.cursor)
  local filetype = vim.bo[pos.buf].filetype

  ctx.o_cms_conf = {
    [M.CMT.kLine] = vim.bo[pos.buf].commentstring or get_cms_opt(filetype),
    [M.CMT.kBlock] = vim.b[pos.buf].celeste_comment_block_commentstring or get_bcms_opt(filetype),
  }

  local ok, parser = pcall(vim.treesitter.get_parser, pos.buf, "")
  if not ok or parser == nil then return end

  local caps = vim.treesitter.get_captures_at_pos(pos.buf, pos.row, pos.col)
  for i = #caps, 1, -1 do
    local id, metadata = caps[i].id, caps[i].metadata
    local md_cms = metadata["bo.commentstring"] or metadata[id] and metadata[id]["bo.commentstring"]
    if md_cms then
      ctx.o_cms_conf[M.CMT.kLine] = md_cms
      return
    end
  end

  local ts_lcs, ts_bcs, ts_ft, res_level = nil, nil, nil, 0

  ---@param ltree vim.treesitter.LanguageTree
  ---@param level integer
  local function walk(ltree, level)
    if not H.ltree_contains(ltree, pos) then return end
    local lang = ltree:lang()
    local filetypes = vim.treesitter.language.get_filetypes(lang)
    for _, ft in ipairs(filetypes) do
      local cs = get_cms_opt(ft)
      local bcs = get_bcms_opt(ft)
      if cs and level > res_level then
        ts_lcs, ts_bcs, ts_ft, res_level = cs, bcs, ft, level
      end
    end

    for _, child_ltree in pairs(ltree:children()) do
      walk(child_ltree, level + 1)
    end
  end

  walk(parser, 1)

  if ts_lcs and ts_ft ~= filetype then ctx.o_cms_conf[M.CMT.kLine] = ts_lcs end
  if ts_bcs and ts_ft ~= filetype then ctx.o_cms_conf[M.CMT.kBlock] = ts_bcs end
end

---@param cms_conf Celeste.Comment.CommentStringConf
---@param pos vim.Pos
---@param ltree? vim.treesitter.LanguageTree
function H.overrides_cms_conf(cms_conf, pos, ltree)
  local conf = cms_conf
  if not ltree then return conf end

  local overrides = cms_conf.overrides
  if not overrides then return conf end

  if type(cms_conf.query) ~= "string" then
    ---@type Range4
    local range = { pos.row, pos.col, pos.row, pos.col }
    local node = ltree:named_node_for_range(range)
    while node do
      local t = node:type()
      local v = overrides[t]
      if v then
        H.log(
          vim.log.levels.TRACE,
          ("override type:%s lang:%s cursor:[%s, %s, %s]"):format(t, ltree:lang(), pos.buf, pos.row, pos.col)
        )
        conf = v
        break
      end
      node = node:parent()
    end
    return conf
  end

  local ok, query = pcall(vim.treesitter.query.parse, ltree:lang(), cms_conf.query)
  if not ok then
    if H.should_log(vim.log.levels.ERROR) then
      H.log(vim.log.levels.ERROR, ("lang:%s error:%s"):format(ltree:lang(), vim.inspect(query)))
    end
    return conf
  end
  ---@cast query vim.treesitter.Query
  assert(query ~= nil, "fatal error, nil Query object")

  if #ltree:trees() == 0 then ltree:parse(false) end
  local root_tree = ltree:trees()[1]
  if not root_tree then
    H.log(
      vim.log.levels.TRACE,
      ("root tree nil of lang:%s pos:[%s, %s, %s]"):format(ltree:lang(), pos.buf, pos.row, pos.col)
    )
    return conf
  end

  -- PERF: limit the iter match range, window size 400
  local best_name, best_len = nil, math.huge
  local off = H.pos_to_offset(pos)
  local the_root = root_tree:root()
  local iter_from, iter_to = math.max(the_root:start(), pos.row - 200), math.min(the_root:end_(), pos.row + 200)

  for _pattern, matchs, _metadata in query:iter_matches(root_tree:root(), ltree:source(), iter_from, iter_to) do
    for capture_id, nodes in pairs(matchs) do
      local capture_name = query.captures[capture_id]
      local base, suffix = capture_name:match("^(.+)%.([^%.]+)$")
      local name = base or capture_name
      -- inclusive default
      local inclusive_start, inclusive_end = true, true

      if suffix == "inner" then
        inclusive_start, inclusive_end = false, false
      elseif suffix == "end_exclusive" then
        inclusive_end = false
      elseif suffix == "start_exclusive" then
        inclusive_start = false
      else
        -- inclusive, nothing to do here
      end

      local v = overrides[name]
      if v then
        for _, node in ipairs(nodes) do
          local _, _, s_off, _, _, e_off = node:range(true)
          local len = node:byte_length()

          local sok = off > s_off or (inclusive_start and off == s_off)
          local eok = off < e_off or (inclusive_end and off == e_off)

          if sok and eok and (not best_name or len < best_len) then
            best_name, best_len, conf = name, len, v
          end
        end
      end
    end
  end

  H.log(
    vim.log.levels.TRACE,
    ("lang:%s best_name:%s pos:[%s, %s, %s]"):format(ltree:lang(), best_name, pos.buf, pos.row, pos.col)
  )

  return conf
end

---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
function H.default_cms_conf_resolver(ctx)
  if ctx.cfg.cms_confs == false then return end

  local pos = H.adjust_to_start_column_pos(ctx.cursor)
  local dptree ---@type vim.treesitter.LanguageTree?
  local ok, parser = pcall(vim.treesitter.get_parser, pos.buf, "")
  if ok and parser ~= nil then
    dptree = parser
    ---@param ltree vim.treesitter.LanguageTree
    local function walk(ltree)
      if ltree:lang() ~= "comment" and H.ltree_contains(ltree, pos) then dptree = ltree end
      for _, child_ltree in pairs(ltree:children()) do
        walk(child_ltree)
      end
    end
    walk(parser)
  end

  local conf_getter = function(lang)
    return (type(ctx.cfg.cms_confs)) == "table" and ctx.cfg.cms_confs[lang] or H.comment_string_confs[lang]
  end

  local lang = dptree and dptree:lang() or vim.bo[pos.buf].filetype
  if not lang then return end

  local conf = conf_getter(lang)
  if type(conf) == "string" then conf = conf_getter(conf) end
  if not conf then return end

  if vim.is_callable(conf) then
    ---@cast conf fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx)
    ctx.tree = dptree
    return conf(ctx)
  end

  ---@cast conf Celeste.Comment.CommentStringConf
  ctx.o_cms_conf = H.overrides_cms_conf(conf, pos, dptree)
end

---@param cursor vim.Pos
---@param cfg    Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
function H.make_cms_conf_chainably(cursor, cfg, range)
  local chains =
    { cfg.hooks.cms_conf_resolver or "", H.default_cms_conf_resolver, H.nvim_builtin_like_cms_conf_resolver }

  for _, resolver in ipairs(chains) do
    if vim.is_callable(resolver) then
      ---@type Celeste.Comment.Hooks.CmsConfResolver.Ctx
      local ctx = { cfg = cfg, cursor = cursor, range = range }
      resolver(ctx)
      if type(ctx.o_cms_conf) == "table" then
        H.normalize_cms_conf(ctx.o_cms_conf)
        if H.should_log(vim.log.levels.TRACE) then
          H.log(vim.log.levels.TRACE, vim.bo[cursor.buf].filetype, ctx.o_cms_conf)
        end
        return ctx.o_cms_conf
      end
    end
  end
end

---@param pattern string
---@return string case-insensitive variant, e.g. "rem" -> "[rR][eE][mM]"
function H.make_pattern_case_insensitive(pattern)
  local result = pattern:gsub("%a", function(c)
    local l, u = c:lower(), c:upper()
    return l == u and c or ("[" .. l .. u .. "]")
  end)
  return result
end

---@param pairs {[1]:string,[2]:string}[]
---@param opts? {pad?: boolean, ci?: boolean, should_be_wrapped?: boolean}
---@return Celeste.Comment.CommentStringInfo?
function H.make_csi(pairs, opts)
  opts = opts or {}
  local function make_tesc(cs) return opts.ci and H.make_pattern_case_insensitive(vim.pesc(cs)) or vim.pesc(cs) end

  local function make_out_pair(tlcs, trcs, lcs, rcs)
    local olcs, orcs = lcs, rcs
    if opts.pad then
      olcs = tlcs == "" and "" or tlcs .. " "
      orcs = trcs == "" and "" or " " .. trcs
    end
    return olcs, orcs
  end

  local tpairs = vim
    .iter(pairs)
    :map(function(p) return { vim.trim(p[1]), vim.trim(p[2]), p[1], p[2] } end)
    :filter(function(p)
      if p[1] == "" and p[2] == "" then return false end
      if opts.should_be_wrapped then return p[1] ~= "" and p[2] ~= "" end
      return true
    end)
    :unique(function(p) return p[1] .. "^" .. p[2] end)
    :totable()

  table.sort(tpairs, function(a, b)
    local la, lb = a[1], b[1]
    if #la ~= #lb then return #la > #lb end
    local lcra, lcrb = a[2], b[2]
    if #lcra ~= #lcrb then return #lcra > #lcrb end
    return la > lb
  end)

  tpairs = vim
    .iter(tpairs)
    :map(
      function(p)
        return {
          tesc = { make_tesc(p[1]), make_tesc(p[2]) },
          traw = { p[1], p[2] },
          tout = { make_out_pair(p[1], p[2], p[3], p[4]) },
        }
      end
    )
    :totable()

  if #tpairs == 0 then return end

  local plcs, prcs = unpack(pairs[1], 1, 2)
  local tplcs, tprcs = vim.trim(plcs), vim.trim(prcs)
  local olcs, orcs = make_out_pair(tplcs, tprcs, plcs, prcs)

  ---@type Celeste.Comment.CommentStringInfo
  return {
    pairs = tpairs,
    tlcs = tplcs,
    trcs = tprcs,
    olcs = olcs,
    orcs = orcs,
    ci = opts.ci or false,
    wrapped = (tplcs ~= "" and tprcs ~= ""),
  }
end

---@param cs string[]
---@return ([string, string])[]
function H.unwrap_comment_strings(cs)
  local result = {}
  for _, s in ipairs(cs) do
    local l, r = s:match("^(.-)%%s(.-)$")
    result[#result + 1] = { l or "", r or "" }
  end
  return result
end

---@param cursor vim.Pos
---@param cfg Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
---@param silent? boolean
---@return Celeste.Comment.CommentStringInfo[]?
function H.make_all_csi(cursor, cfg, range, silent)
  local cms_conf = H.make_cms_conf_chainably(cursor, cfg, range)
  if not cms_conf then return end
  local all, valid = {}, false
  for _, k in pairs(M.CMT) do
    local cs = cms_conf[k]
    if type(cs) == "table" then
      local pairs = H.unwrap_comment_strings(cs)
      all[k] = H.make_csi(
        pairs,
        { pad = cfg.insert_space, ci = cfg.case_insensitive, should_be_wrapped = (k == M.CMT.kBlock) }
      )
      valid = valid or (all[k] ~= nil)
    end
  end

  if not valid then
    if not silent then
      vim.api.nvim_echo(
        { { "Invalid", "WarningMsg" }, { " CommentStringConf : " }, { ("%s"):format(vim.inspect(cms_conf)) } },
        true,
        {}
      )
    end
    return
  end

  return all
end

---@param cursor vim.Pos
---@param ctype  Celeste.Comment.CommentType
---@param cfg    Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
---@param silent? boolean
---@return Celeste.Comment.CommentStringInfo?
---@return Celeste.Comment.CommentType?
function H.resolve(cursor, ctype, cfg, range, silent)
  local all = H.make_all_csi(cursor, cfg, range, silent)
  if not all then return end

  local csi = all[ctype]
  if ctype == M.CMT.kLine and cfg.fallback_to_block ~= M.FBK2BLOCK.kNever then
    if not csi then
      csi, ctype = all[M.CMT.kBlock], M.CMT.kBlock
    elseif csi.wrapped then
      ctype = M.CMT.kBlock
    end
  end

  if not csi and not silent then
    local t = ctype == M.CMT.kLine and "line" or "block"
    vim.api.nvim_echo({ { "No available", "WarningMsg" }, { (" %s comment string config"):format(t) } }, true, {})
  end

  return csi, ctype
end

---@class Celeste.Comment.MatchLineComment.Result
---@field matched     boolean
---@field idx?        integer
---@field lcs_pos?    Celeste.Comment.Range3
---@field rcs_pos?    Celeste.Comment.Range3
---@field will_blank? boolean

---@param csi   Celeste.Comment.CommentStringInfo
---@param opts? {check_only?: boolean, check_will_blank?: boolean}
---@return Celeste.Comment.MatchLineComment.Result
function H.match_line_comment(line, row, csi, opts)
  opts = opts or {}

  for idx, p in ipairs(csi.pairs) do
    local tlcs_esc, trcs_esc = p.tesc[1], p.tesc[2]
    local suffix = #trcs_esc > 0 and "(.-)()" .. trcs_esc .. "()%s*$" or "(.-)%s*$"
    local s, _e, p1, p2, content, p3, p4 = line:find("^%s*()" .. tlcs_esc .. "()" .. suffix)
    if s then
      if opts.check_only then return { matched = true, idx = idx } end

      local olcs, orcs = p.tout[1], p.tout[2]

      local lcs_pos
      if tlcs_esc ~= "" then
        local matched = H.match_byte(line, p2 - 1, olcs, #p.traw[1], 1, csi.ci)
        lcs_pos = { row, p1 - 1, p2 + matched - 2 }
      end

      local rcs_pos
      if trcs_esc ~= "" and p3 then
        local matched = H.match_byte(line, p3 - 2, orcs, 0, -1, csi.ci)
        local rcs_start = p3 - matched
        rcs_pos = { row, rcs_start - 1, p4 - 2 }
      end

      local res = { matched = true, idx = idx, lcs_pos = lcs_pos, rcs_pos = rcs_pos }
      if opts.check_will_blank then res.will_blank = content:match("^%s*$") ~= nil end

      return res
    end
  end

  return { matched = false }
end

---@param cur_visible_col integer current visible column
---@param byte            integer byte value of current character
---@param indent_size     integer
---@return integer
function H.next_visible_column(cur_visible_col, byte, indent_size)
  if byte == CHAR_CODE.TAB then return cur_visible_col + indent_size - (cur_visible_col % indent_size) end
  return cur_visible_col + 1
end

---Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/indentationGuesser.ts
---@param a        string
---@param alen     integer
---@param b        string
---@param blen     integer
---@return boolean looks_like_alignment
---@return integer spaces_diff
function H.spaces_diff(a, alen, b, blen)
  local spaces_diff = 0
  local looks_like_alignment = false

  local i = 0
  while i < alen and i < blen do
    if a:byte(i + 1) ~= b:byte(i + 1) then break end
    i = i + 1
  end

  local a_spaces_cnt, a_tabs_count = 0, 0
  for j = i + 1, alen do
    if a:byte(j) == CHAR_CODE.SPACE then
      a_spaces_cnt = a_spaces_cnt + 1
    else
      a_tabs_count = a_tabs_count + 1
    end
  end

  local b_spaces_cnt, b_tabs_count = 0, 0
  for j = i + 1, blen do
    if b:byte(j) == CHAR_CODE.SPACE then
      b_spaces_cnt = b_spaces_cnt + 1
    else
      b_tabs_count = b_tabs_count + 1
    end
  end

  if a_spaces_cnt > 0 and a_tabs_count > 0 then return false, 0 end
  if b_spaces_cnt > 0 and b_tabs_count > 0 then return false, 0 end

  local tabs_diff = math.abs(a_tabs_count - b_tabs_count)
  local spaces_diff_abs = math.abs(a_spaces_cnt - b_spaces_cnt)

  if tabs_diff == 0 then
    spaces_diff = spaces_diff_abs
    if
      spaces_diff > 0
      and 0 <= b_spaces_cnt - 1
      and b_spaces_cnt - 1 < #a
      and b_spaces_cnt < #b
      and b:byte(b_spaces_cnt + 1) ~= CHAR_CODE.SPACE
      and a:byte(b_spaces_cnt) == CHAR_CODE.SPACE
      and a:byte(#a) == CHAR_CODE.COMMA
    then
      looks_like_alignment = true
    end
    return looks_like_alignment, spaces_diff
  end

  if spaces_diff_abs % tabs_diff == 0 then spaces_diff = spaces_diff_abs / tabs_diff end
  return looks_like_alignment, spaces_diff
end

H.ALLOWED_TAB_SIZE_GUESSES = { 2, 4, 6, 8, 3, 5, 7 }
H.MAX_ALLOWED_TAB_SIZE_GUESS = 8
H.GUESS_INDENTATION_MAX_LINES = 1000

---@class Celeste.Comment.GuessIndent.Res
---@field insert_spaces boolean
---@field tab_size integer

---Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/indentationGuesser.ts
---@param lines string[]
---@param default_tab_size integer
---@param default_insert_spaces boolean
---@return Celeste.Comment.GuessIndent.Res
---@overload fun(buf: integer, default_tab_size: integer, default_insert_spaces: boolean): Celeste.Comment.GuessIndent.Res
function H.guess_indentation(lines, default_tab_size, default_insert_spaces)
  if type(lines) == "number" then
    local n = math.min(vim.api.nvim_buf_line_count(lines), H.GUESS_INDENTATION_MAX_LINES)
    lines = vim.api.nvim_buf_get_lines(lines, 0, n, false)
  end
  local lcnt = math.min(#lines, H.GUESS_INDENTATION_MAX_LINES)

  local indented_with_tab_lcnt = 0 -- number of lines that contain at least one tab in indentation
  local indented_with_spc_cnt = 0 -- number of lines that contain only spaces in indentation

  local prev_ln_text = ""
  local prev_ln_indent = 0

  local spc_diff_cnt = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }

  for l = 1, lcnt do
    local cur_ln = lines[l]
    local cur_ln_len = #cur_ln

    local cur_ln_has_content = false
    local cur_ln_indent = 0
    local cur_ln_spc_cnt = 0
    local cur_ln_tab_cnt = 0
    for j = 1, cur_ln_len do
      local char_code = cur_ln:byte(j)
      if char_code == CHAR_CODE.TAB then
        cur_ln_tab_cnt = cur_ln_tab_cnt + 1
      elseif char_code == CHAR_CODE.SPACE then
        cur_ln_spc_cnt = cur_ln_spc_cnt + 1
      else
        cur_ln_has_content = true
        cur_ln_indent = j - 1
        break
      end
    end

    -- Ignore empty or only whitespace lines
    if cur_ln_has_content then
      if cur_ln_tab_cnt > 0 then
        indented_with_tab_lcnt = indented_with_tab_lcnt + 1
      elseif cur_ln_spc_cnt > 1 then
        indented_with_spc_cnt = indented_with_spc_cnt + 1
      end

      local looks_like_alignment, spc_diff = H.spaces_diff(prev_ln_text, prev_ln_indent, cur_ln, cur_ln_indent)

      local skip = looks_like_alignment and not (default_insert_spaces and default_tab_size == spc_diff)
      if not skip then
        if spc_diff <= H.MAX_ALLOWED_TAB_SIZE_GUESS then spc_diff_cnt[spc_diff + 1] = spc_diff_cnt[spc_diff + 1] + 1 end
        prev_ln_text = cur_ln
        prev_ln_indent = cur_ln_indent
      end
    end
  end

  local insert_spaces = default_insert_spaces
  if indented_with_tab_lcnt ~= indented_with_spc_cnt then
    insert_spaces = indented_with_tab_lcnt < indented_with_spc_cnt
  end

  local tab_size = default_tab_size
  if insert_spaces then
    local tab_size_score = 0
    for _, possible_tab_size in ipairs(H.ALLOWED_TAB_SIZE_GUESSES) do
      local possible_tab_size_score = spc_diff_cnt[possible_tab_size + 1]
      if possible_tab_size_score > tab_size_score then
        tab_size_score = possible_tab_size_score
        tab_size = possible_tab_size
      end
    end

    if tab_size == 4 and spc_diff_cnt[5] > 0 and spc_diff_cnt[3] > 0 and spc_diff_cnt[3] >= spc_diff_cnt[5] * 2 / 3 then
      tab_size = 2
    end
  end

  return { insert_spaces = insert_spaces, tab_size = tab_size }
end

---@param ctx Celeste.Comment.Hooks.IndentResolver.Ctx
function H.detect_indent_resolver(ctx)
  if not ctx.cfg.detect_indent then return end
  -- TODO: guess indent if have editorconfig, so that can fallback to default indent resolver
  local buf = ctx.buf
  ctx.o_indent = vim.b[buf].celeste_comment_guessed_indent
  if not ctx.o_indent then
    local gs = H.guess_indentation(buf, vim.bo[buf].tabstop, vim.bo[buf].expandtab)
    ctx.o_indent = { indent_style = gs.insert_spaces and "space" or "tab", indent_size = gs.tab_size }
    vim.b[buf].celeste_comment_guessed_indent = ctx.o_indent
  end
end

---@param ctx Celeste.Comment.Hooks.IndentResolver.Ctx
function H.default_indent_resolver(ctx)
  local buf = ctx.buf
  local ex, ts, sw = vim.bo[buf].expandtab, vim.bo[buf].tabstop, vim.bo[buf].shiftwidth
  sw = sw > 0 and sw or ts
  ctx.o_indent = {
    indent_size = ex and sw or ts,
    indent_style = ex and "space" or "tab",
  }
end

---@param cursor vim.Pos?
---@param cfg    Celeste.Comment.Opts
---@return Celeste.Comment.IndentInfo
function H.compute_indent_chainably(cursor, cfg)
  local buf = cursor and cursor.buf or vim.api.nvim_get_current_buf()
  local chains = { cfg.hooks.indent_resolver or "", H.detect_indent_resolver, H.default_indent_resolver }
  for _, resolver in ipairs(chains) do
    if vim.is_callable(resolver) then
      ---@type Celeste.Comment.Hooks.IndentResolver.Ctx
      local ctx = { cfg = cfg, buf = buf }
      resolver(ctx)
      if type(ctx.o_indent) == "table" then return ctx.o_indent end
    end
  end

  assert(false, "unreachable")
  return {} -- unreachable
end

---@param line            string
---@param limit           integer
---@param min_visible_col integer
---@param indent_size     integer
---@return integer
function H.find_insert_offset(line, limit, min_visible_col, indent_size)
  local cur_visible_col, i = 0, 0
  while i < limit and cur_visible_col < min_visible_col do
    cur_visible_col = H.next_visible_column(cur_visible_col, line:byte(i + 1), indent_size)
    i = i + 1
  end
  if cur_visible_col > min_visible_col then return i - 1 end
  return i
end

---@param str string
---@param pos integer 1-indexed, self-checked
---@param max integer max spaces to eat
---@param dir integer 1=forward, -1=backward
---@return integer pos + eaten * dir
function H.skip_whitespace(str, pos, max, dir)
  local len = #str
  local limit = pos + dir * (max - 1)
  local to = dir == 1 and math.min(limit, len) or math.max(limit, 1)
  for i = pos, to, dir do
    local b = str:byte(i)
    if b ~= CHAR_CODE.SPACE and b ~= CHAR_CODE.TAB then break end
    pos = i + dir
  end
  return pos
end

--- Match bytes from sa[sa_pos] against sb[sb_pos..], return matched bytes count.
---@param sa     string
---@param sa_pos integer 0-indexed
---@param sb     string
---@param sb_pos integer 0-indexed
---@param dir    integer 1=forward, -1=backward
---@param ci     boolean
---@return integer matched bytes (0 = no match)
function H.match_byte(sa, sa_pos, sb, sb_pos, dir, ci)
  local n = #sb - sb_pos
  local limit = sa_pos + dir * (n - 1)
  local to = dir == 1 and math.min(limit, #sa - 1) or math.max(limit, 0)
  local step = 0
  for i = sa_pos, to, dir do
    local la, lb = sa:byte(i + 1), sb:byte(sb_pos + step + 1)
    if ci then
      if la >= CHAR_CODE.UPPER_A and la <= CHAR_CODE.UPPER_Z then la = la + 32 end
      if lb >= CHAR_CODE.UPPER_A and lb <= CHAR_CODE.UPPER_Z then lb = lb + 32 end
    end
    if la ~= lb then return step end
    step = step + 1
  end
  return step
end

---@param lines  string[]
---@param csi    Celeste.Comment.CommentStringInfo
---@param cfg    Celeste.Comment.Opts
---@param range  Celeste.Comment.Range4
---@param action Celeste.Comment.Action
---@param cursor? vim.Pos
---@param opts?   Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.LineCommentInfo
function H.line_comment_info(lines, csi, cfg, range, action, cursor, opts)
  opts = opts or {}
  range = range or { 0 }
  ---@type Celeste.Comment.LineCommentInfo
  local all_info = { lines = {}, should_remove = true }
  -- TODO: consider not rely on cursor(include buf) here, so that can use
  -- `make_actionx` directly for non-buf lines?
  local indent = H.compute_indent_chainably(cursor, cfg)
  local indent_size = indent.indent_size
  local only_whitespace_lines = true
  local min_visible_col = math.huge

  for i, line in ipairs(lines) do
    local row = range[1] + i - 1
    ---@type Celeste.Comment.LineCommentInfo.Line
    local info = {
      lead_ws_len = 0,
      visible_col = 0,
      offset = 0,
      ignore = false,
      csi = csi,
      row = row,
      indent = indent,
    }
    local ws = line:match("^(%s*)")
    local ws_len = #ws

    for j = 1, ws_len do
      info.visible_col = H.next_visible_column(info.visible_col, line:byte(j), indent_size)
    end

    if ws_len == #line then
      info.ignore = cfg.ignore_empty_lines == M.IGN_EMT.kAlways
      info.offset = cfg.line_comment_no_indent and 0 or #line
      info.lead_ws_len = ws_len
      info.all_blank = true
    else
      only_whitespace_lines = false
      info.offset = cfg.line_comment_no_indent and 0 or ws_len
      info.lead_ws_len = ws_len

      local match_res = H.match_line_comment(line, row, csi, {
        check_will_blank = cfg.ignore_empty_lines == M.IGN_EMT.kMixed,
      })
      if match_res.matched then
        info.lcs_pos = match_res.lcs_pos
        info.rcs_pos = match_res.rcs_pos
        info.will_blank = match_res.will_blank
        info.commented = (info.lcs_pos ~= nil or info.rcs_pos ~= nil)
      else
        all_info.should_remove = false
      end
    end

    if not info.ignore and not cfg.line_comment_no_indent then
      if not info.all_blank or cfg.ignore_empty_lines ~= M.IGN_EMT.kMixed then
        min_visible_col = math.min(min_visible_col, info.visible_col)
      end
    end

    all_info.lines[#all_info.lines + 1] = info
  end

  -- force add when all non-ignored lines are blank
  if all_info.should_remove and only_whitespace_lines then
    all_info.should_remove = false

    local need_align_indent_for_blank = false
    if not cfg.line_comment_no_indent and cfg.ignore_empty_lines == M.IGN_EMT.kMixed then
      assert(min_visible_col == math.huge, "fatal error, min_visible_col != math.huge")
      need_align_indent_for_blank = true
    end

    for _, info in ipairs(all_info.lines) do
      info.ignore = false

      if need_align_indent_for_blank then min_visible_col = math.min(min_visible_col, info.visible_col) end
    end
  end

  -- align to min visible column
  if not cfg.line_comment_no_indent then
    min_visible_col = min_visible_col == math.huge and 0 or (math.floor(min_visible_col / indent_size) * indent_size)
    if not all_info.should_remove or action == M.ACTION.kInvert then
      for i, line in ipairs(lines) do
        local info = all_info.lines[i]
        if not info.ignore then
          info.offset = H.find_insert_offset(line, info.offset, min_visible_col, indent_size)
          info.min_visible_col = min_visible_col
        end
      end
    end
  end

  return all_info
end

---Referenced from https://github.com/neovim/neovim/blob/master/src/nvim/indent.c (`tabstop_fromto`)
---@param from         integer
---@param to           integer
---@param indent_size  integer
---@param indent_style "space"|"tab"
---@return string
function H.make_indent_padding(from, to, indent_size, indent_style)
  if indent_style ~= "tab" then return string.rep(" ", to - from) end
  local spaces = to - from
  local tabs = 0
  local initspc = indent_size - (from % indent_size)
  if spaces >= initspc then
    spaces = spaces - initspc
    tabs = 1
  end
  local full = math.floor(spaces / indent_size)
  tabs = tabs + full
  spaces = spaces - full * indent_size
  return string.rep("\t", tabs) .. string.rep(" ", spaces)
end

---@param info  Celeste.Comment.LineCommentInfo.Line
---@param line  string
---@param cfg   Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
---@param opts?  Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.TextEdits
function H.make_comment_edits(info, line, cfg, range, opts)
  local edits = {} ---@type Celeste.Comment.TextEdits
  local csi = info.csi
  local row = info.row
  opts = opts or {}

  if info.all_blank and opts.insmode and csi.wrapped and range and range[1] == range[3] and range[2] == range[4] then
    edits[#edits + 1] = { range = { row, range[2], row, range[2] }, text = { csi.olcs } }
    edits[#edits + 1] = { range = { row, range[2], row, range[2] }, text = { csi.orcs } }
    return edits
  end

  if info.all_blank and cfg.ignore_empty_lines == M.IGN_EMT.kMixed and info.visible_col < info.min_visible_col then
    local pad =
      H.make_indent_padding(info.visible_col, info.min_visible_col, info.indent.indent_size, info.indent.indent_style)
    edits[#edits + 1] = {
      range = { row, info.lead_ws_len, row, info.lead_ws_len },
      text = { pad .. csi.olcs },
    }
  else
    edits[#edits + 1] = { range = { row, info.offset, row, info.offset }, text = { csi.olcs } }
  end

  if csi.orcs ~= "" then edits[#edits + 1] = { range = { row, #line, row, #line }, text = { csi.orcs } } end
  return edits
end

---@param info  Celeste.Comment.LineCommentInfo.Line
---@param line  string
---@param cfg?  Celeste.Comment.Opts
---@return Celeste.Comment.TextEdits
function H.make_uncomment_edits(info, line, cfg)
  cfg = cfg or {}
  local edits = {} ---@type Celeste.Comment.TextEdits

  if info.lcs_pos then
    edits[#edits + 1] =
      { range = { info.lcs_pos[1], info.lcs_pos[2], info.lcs_pos[1], info.lcs_pos[3] + 1 }, text = { "" } }
  end

  if info.rcs_pos then
    edits[#edits + 1] =
      { range = { info.rcs_pos[1], info.rcs_pos[2], info.rcs_pos[1], info.rcs_pos[3] + 1 }, text = { "" } }
  end
  return edits
end

---@param lines  string[]
---@param range  Celeste.Comment.Range4
---@param motion Celeste.Comment.Motion
---@param csi    Celeste.Comment.CommentStringInfo
---@param cfg    Celeste.Comment.Opts
---@param action Celeste.Comment.Action
---@param opts?  Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.TextEdits
---@return Celeste.Comment.LineCommentInfo?
function H.compute_line_edits(lines, range, motion, csi, cfg, action, cursor, opts)
  opts = opts or {}
  local all_edits = {} ---@type Celeste.Comment.TextEdits
  local all_info = H.line_comment_info(lines, csi, cfg, range, action, cursor, opts)

  for i, line in ipairs(lines) do
    local info = all_info.lines[i]
    if not info.ignore then
      local edits

      if action == M.ACTION.kToggle then
        if all_info.should_remove then
          edits = H.make_uncomment_edits(info, line, cfg)
        else
          edits = H.make_comment_edits(info, line, cfg, range, opts)
        end
      elseif action == M.ACTION.kInvert then
        if info.commented then
          edits = H.make_uncomment_edits(info, line, cfg)
        else
          edits = H.make_comment_edits(info, line, cfg, range, opts)
        end
      elseif action == M.ACTION.kForceAdd then
        edits = H.make_comment_edits(info, line, cfg, range, opts)
      else
        -- kForceRemove
        assert(action == M.ACTION.kForceRemove, "unknown action")
        if info.commented then edits = H.make_uncomment_edits(info, line, cfg) end
      end

      if edits then
        vim.list_extend(all_edits, edits)
        all_edits.need_sort = all_edits.need_sort or edits.need_sort
        all_edits.any_multi = all_edits.any_multi or edits.any_multi
      end
    end
  end

  return all_edits, all_info
end

---@param lines string[]
---@param csi   Celeste.Comment.CommentStringInfo
---@param range Celeste.Comment.Range4
---@param opts? Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.TextEdits
function H.make_block_comment_edits(lines, csi, range, opts)
  local n = #lines
  local l1 = lines[1]
  local ln = lines[n]
  local edits = {} ---@type Celeste.Comment.TextEdits
  opts = opts or {}

  local lcs_col = H.skip_whitespace(l1, 1, #l1, 1) - 1
  if lcs_col == #l1 then
    if opts.insmode and range[1] == range[3] and range[2] == range[4] then
      edits[#edits + 1] = { range = { range[1], range[2], range[1], range[2] }, text = { csi.olcs } }
      edits[#edits + 1] = { range = { range[1], range[2], range[1], range[2] }, text = { csi.orcs } }
      return edits
    end
    lcs_col = 0
  end

  edits[#edits + 1] = { range = { range[1], lcs_col, range[1], lcs_col }, text = { csi.olcs } }

  if n > 1 then
    edits[#edits + 1] = { range = { range[1] + n - 1, #ln, range[1] + n - 1, #ln }, text = { csi.orcs } }
  else
    edits[#edits + 1] = { range = { range[1], #l1, range[1], #l1 }, text = { csi.orcs } }
  end

  return edits
end

---@param lines string[]
---@param csi   Celeste.Comment.CommentStringInfo
---@param range Celeste.Comment.Range4
---@param opts? Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.TextEdits
function H.make_block_partial_edits(lines, csi, range, opts)
  local n = #lines
  local edits = {} ---@type Celeste.Comment.TextEdits

  local rcs_col = math.min(range[4] + 1, #lines[n])

  edits[#edits + 1] = { range = { range[1], range[2], range[1], range[2] }, text = { csi.olcs } }
  if n == 1 then
    edits[#edits + 1] = { range = { range[1], rcs_col, range[1], rcs_col }, text = { csi.orcs } }
  else
    edits[#edits + 1] = { range = { range[1] + n - 1, rcs_col, range[1] + n - 1, rcs_col }, text = { csi.orcs } }
  end

  return edits
end

---@param info Celeste.Comment.BlockCommentInfo
---@return Celeste.Comment.TextEdits
function H.make_block_uncomment_edits(info)
  local edits = {} ---@type Celeste.Comment.TextEdits

  edits[#edits + 1] =
    { range = { info.lcs_pos[1], info.lcs_pos[2], info.lcs_pos[1], info.lcs_pos[3] + 1 }, text = { "" } }

  if info.rcs_pos then
    edits[#edits + 1] =
      { range = { info.rcs_pos[1], info.rcs_pos[2], info.rcs_pos[1], info.rcs_pos[3] + 1 }, text = { "" } }
  end

  return edits
end

---@param lines string[]
---@param range Celeste.Comment.Range4
---@return Celeste.Comment.Range4?
function H.shrink_region(lines, range)
  local sr, sc, er, ec = range[1], range[2], range[3], range[4]
  if sr > er or (sr == er and sc > ec) or #lines == 0 then return end

  --- Shrink from left: find first non-whitespace position
  ---@return integer? lrow
  ---@return integer? lcol
  local function shrink_left()
    for i = 1, #lines do
      local line = lines[i]
      local start = i == 1 and math.min(sc + 1, #line + 1) or 1
      local pos = line:find("%S", start)
      if pos then return sr + i - 1, pos - 1 end
    end
  end

  --- Shrink from right: find last non-whitespace position
  ---@param lrow integer
  ---@param lcol integer
  ---@return integer? rrow
  ---@return integer? rcol
  local function shrink_right(lrow, lcol)
    local fi = lrow - sr + 1
    for i = #lines, fi, -1 do
      local line = lines[i]
      local mpos = (i == fi) and (lcol + 1) or 1
      local epos = (i == #lines) and math.min(ec + 1, #line) or #line

      if i == fi or i == #lines then
        local last = H.skip_whitespace(line, epos, epos - mpos + 1, -1)
        if last >= mpos then return sr + i - 1, last - 1 end
      else
        local e = line:match("^.*()%S")
        if e then return sr + i - 1, e - 1 end
      end
    end
  end

  local lrow, lcol = shrink_left()
  if not lrow or not lcol then return end

  local rrow, rcol = shrink_right(lrow, lcol)
  if not rrow or not rcol then return end

  return { lrow, lcol, rrow, rcol }
end

---@param lines  string[]
---@param shrunk Celeste.Comment.Range4
---@param range  Celeste.Comment.Range4
---@param csi    Celeste.Comment.CommentStringInfo
---@param motion Celeste.Comment.Motion
---@return Celeste.Comment.BlockCommentInfo?
function H.match_block_comment(lines, shrunk, range, csi, motion)
  local loff = shrunk[1]
  local scol, ecol = shrunk[2], shrunk[4]
  local n = shrunk[3] - loff + 1
  local fi = loff - range[1] + 1
  local l1 = lines[fi]
  local ln = lines[fi + n - 1]

  ---@param p Celeste.Comment.CommentStringInfo.Pairs
  ---@return Celeste.Comment.Range2? lcs_range
  ---@return Celeste.Comment.Range2? rcs_range
  local function match_line_motion(p)
    local tlcs_esc, trcs_esc = p.tesc[1], p.tesc[2]
    local tlcs_len, trcs_len = #p.traw[1], #p.traw[2]
    local olcs, orcs = p.tout[1], p.tout[2]
    local pad_rcs = #orcs - trcs_len

    local _, e = l1:find("^%s*" .. tlcs_esc)
    if not e then return end

    local slcs = e - tlcs_len + 1
    local mb = H.match_byte(l1, slcs - 1 + tlcs_len, olcs, tlcs_len, 1, csi.ci)
    local elcs = slcs + tlcs_len + mb - 1

    local srcs, ercs = ln:find(trcs_esc .. "%s*$")
    if not srcs then return end

    ercs = srcs + trcs_len - 1
    srcs = srcs - math.min(H.match_byte(ln, srcs - pad_rcs - 1, orcs, 0, 1, csi.ci), pad_rcs)

    return { slcs, elcs }, { srcs, ercs }
  end

  ---@param p Celeste.Comment.CommentStringInfo.Pairs
  ---@return Celeste.Comment.Range2? lcs_range
  ---@return Celeste.Comment.Range2? rcs_range
  local function match_char_motion(p)
    local tlcs_len, trcs_len = #p.traw[1], #p.traw[2]
    local olcs, orcs = p.tout[1], p.tout[2]
    local pad_rcs = #orcs - trcs_len

    local m = H.match_byte(l1, scol, olcs, 0, 1, csi.ci)
    if m < tlcs_len then return end

    local slcs = scol + 1
    local elcs = scol + m

    local ec = ecol + 1
    local srcs = ec - trcs_len + 1
    if srcs < 1 or srcs > #ln then return end
    if H.match_byte(ln, srcs - 1, p.traw[2], 0, 1, csi.ci) < trcs_len then return end
    if n == 1 and srcs <= slcs then return end

    local ercs = ec
    srcs = srcs - math.min(H.match_byte(ln, math.max(srcs - pad_rcs - 1, 0), orcs, 0, 1, csi.ci), pad_rcs)

    return { slcs, elcs }, { srcs, ercs }
  end

  local matcher = (motion == "char") and match_char_motion or match_line_motion

  for _, p in ipairs(csi.pairs) do
    local lcsr, rcsr = matcher(p)

    if lcsr and rcsr then
      return {
        lcs_pos = { loff, lcsr[1] - 1, lcsr[2] - 1 },
        rcs_pos = { loff + n - 1, rcsr[1] - 1, rcsr[2] - 1 },
      }
    end
  end
end

---@param lines  string[]
---@param csi    Celeste.Comment.CommentStringInfo
---@param motion Celeste.Comment.Motion
---@param range  Celeste.Comment.Range4
---@param cfg?   Celeste.Comment.Opts
---@return Celeste.Comment.BlockCommentInfo?
function H.block_comment_info(lines, csi, motion, range, cfg)
  -- TODO: should we normalize range at get_selection_range?
  local shrunk = vim.list_slice(range)
  if motion ~= "char" then
    shrunk[2] = 0
    shrunk[4] = #lines[#lines]
  end

  if cfg and cfg.block_relaxed_detect then
    local t = H.shrink_region(lines, shrunk)
    if not t then return end
    shrunk = t
  end

  return H.match_block_comment(lines, shrunk, range, csi, motion)
end

---@param lines  string[]
---@param range  Celeste.Comment.Range4
---@param motion Celeste.Comment.Motion
---@param csi    Celeste.Comment.CommentStringInfo
---@param cfg?   Celeste.Comment.Opts
---@param action Celeste.Comment.Action
---@param opts?  Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.TextEdits
---@return Celeste.Comment.BlockCommentInfo?
function H.compute_block_edits(lines, range, motion, csi, cfg, action, cursor, opts)
  local info = H.block_comment_info(lines, csi, motion, range, cfg)
  local edits ---@type Celeste.Comment.TextEdits

  if action == M.ACTION.kToggle or action == M.ACTION.kInvert then
    if info then
      edits = H.make_block_uncomment_edits(info)
    elseif motion == "char" then
      edits = H.make_block_partial_edits(lines, csi, range, opts)
    else
      edits = H.make_block_comment_edits(lines, csi, range, opts)
    end
  elseif action == M.ACTION.kForceAdd then
    if motion == "char" then
      edits = H.make_block_partial_edits(lines, csi, range, opts)
    else
      edits = H.make_block_comment_edits(lines, csi, range, opts)
    end
  else
    -- kForceRemove
    assert(action == M.ACTION.kForceRemove, "unknown action")
    if info then edits = H.make_block_uncomment_edits(info) end
  end
  return edits, info
end

---@param edits Celeste.Comment.TextEdits
function H.sort_edits(edits)
  if edits.need_sort then
    table.sort(edits, function(a, b)
      if a.range[1] ~= b.range[1] then return a.range[1] < b.range[1] end
      return a.range[2] < b.range[2]
    end)
    edits.need_sort = nil
  end
end

---@param lines      string[]
---@param edits      Celeste.Comment.TextEdits
---@param offset_row integer? 0-indexed row offset
function H.apply_edits(lines, edits, offset_row)
  if #edits == 0 then return end
  assert(not edits.any_multi, "cannot use apply_edits for any_multi edits set")
  offset_row = offset_row or 0

  for i = #edits, 1, -1 do
    local e = edits[i]
    local rel = e.range[1] - offset_row + 1
    lines[rel] = lines[rel]:sub(1, e.range[2]) .. e.text[1] .. lines[rel]:sub(e.range[4] + 1)
  end
end

---@param buf          integer
---@param range        Celeste.Comment.Range4
---@param lines?       string[]
---@param edits        Celeste.Comment.TextEdits
---@param use_set_text boolean?
function H.commit_edits(buf, range, lines, edits, use_set_text)
  if #edits == 0 then return end

  H.sort_edits(edits)

  if use_set_text or edits.any_multi then
    local max = vim.api.nvim_buf_line_count(buf)
    for i = #edits, 1, -1 do
      local e = edits[i]
      if e.range[2] == -1 then
        vim.api.nvim_buf_set_lines(buf, e.range[1], e.range[3], false, e.text)
      elseif max <= e.range[1] then
        vim.api.nvim_buf_set_lines(buf, max, max, false, e.text)
      else
        vim.api.nvim_buf_set_text(buf, e.range[1], e.range[2], e.range[3], e.range[4], e.text)
      end
    end
  else
    assert(lines, "unexpected error, nil lines")
    H.apply_edits(lines, edits, range[1])
    vim._with(
      { lockmarks = true },
      function() vim.api.nvim_buf_set_lines(buf, range[1], range[3] + 1, false, lines) end
    )
  end
end

---@param buf integer
---@return Celeste.Comment.Range4?
function H.get_selection_range(buf)
  local sr, sc = unpack(vim.api.nvim_buf_get_mark(buf, "["))
  local er, ec = unpack(vim.api.nvim_buf_get_mark(buf, "]"))
  sr, er = sr - 1, er - 1
  if er < sr or (er == sr and ec < sc) then return end
  return { sr, sc, er, ec }
end

---@return Celeste.Comment.StateTrack
function H.make_state_track()
  local state = {} ---@type Celeste.Comment.StateTrack
  state.cursor = H.make_cursor(0)
  if H.is_visual() then
    state.mode = vim.fn.mode()
    local endpos = vim.fn.getpos("v")
    state.endpos = H.make_pos(endpos[1], endpos[2] - 1, endpos[3] - 1)
  end

  state.adj_cursor = H.pos_clone(state.cursor)
  state.adj_endpos = H.pos_clone(state.endpos)
  return state
end

---@param ctx Celeste.Comment.Hooks.PostCommitEdits.Ctx
function H.post_commit_expand_block(ctx)
  if bit.band(ctx.cfg.keep_selection, M.KEEP_SEL_FLAG.kExpandBlock) == 0 then return end
  local st = ctx.state_track
  if not st or st.mode ~= "v" or ctx.ctype ~= M.CMT.kBlock or ctx.motion ~= "char" then return end

  local lcs, rcs = ctx.edits[1], ctx.edits[2]
  if not lcs or not rcs then return end
  if lcs.text[1] ~= ctx.csi.olcs or rcs.text[1] ~= ctx.csi.orcs then return end

  local shift = (lcs.range[1] == rcs.range[1]) and #lcs.text[1] or 0
  local rcs_end = rcs.range[2] + shift + #rcs.text[1]
  if vim.o.selection ~= "exclusive" then rcs_end = rcs_end - 1 end

  local backward = (st.cursor.row < st.endpos.row) or (st.cursor.row == st.endpos.row and st.cursor.col < st.endpos.col)

  if backward then
    st.adj_endpos = H.make_pos(0, rcs.range[1], rcs_end)
    st.adj_cursor = H.make_pos(0, lcs.range[1], lcs.range[2])
  else
    st.adj_endpos = H.make_pos(0, lcs.range[1], lcs.range[2])
    st.adj_cursor = H.make_pos(0, rcs.range[1], rcs_end)
  end
end

---@param ctx Celeste.Comment.Hooks.PostCommitEdits.Ctx
function H.restore_state(ctx)
  local cfg, state = ctx.cfg, ctx.state_track
  if not state then return end

  if cfg.keep_selection ~= M.KEEP_SEL_FLAG.kNever then
    local only_change_marks = (bit.band(cfg.keep_selection, M.KEEP_SEL_FLAG.kOnlyChangeMarks) ~= 0)

    if state.mode == "\22" then
      -- not handle C-v mode, use multiple cursor is the right way
      if not only_change_marks then vim.cmd.normal({ "gv", bang = true }) end
    elseif state.mode == "V" or state.mode == "v" then
      local mode = state.mode
      if ctx.ctype == M.CMT.kLine and bit.band(cfg.keep_selection, M.KEEP_SEL_FLAG.kExpandLine) ~= 0 then mode = "V" end

      H.select_range(
        { state.adj_endpos[1], state.adj_endpos[2], state.adj_cursor[1], state.adj_cursor[2] },
        { mode = mode, exit = only_change_marks }
      )
      return
    end
  end

  if cfg.keep_cursor and state.adj_cursor then vim.api.nvim_win_set_cursor(0, H.pos_to_cursor(state.adj_cursor)) end
end

---@param pos? vim.Pos
---@param ctx Celeste.Comment.Hooks.PreCommitEdits.Ctx
---@return vim.Pos?
function H.compute_cursor_pos(pos, ctx)
  if not pos then return end
  local edits, lines, range, csi, ctype, motion = ctx.edits, ctx.lines, ctx.range, ctx.csi, ctx.ctype, ctx.motion
  local orow, ocol = pos.row, pos.col
  local ncol, nrow = ocol, orow
  local cursor_line = lines[orow - range[1] + 1]
  local eol_pos = cursor_line and #cursor_line or nil

  for i = #edits, 1, -1 do
    local e = edits[i]
    if e.range[1] <= orow then
      if e.range[2] == -1 then
        nrow = nrow + #e.text - (e.range[3] - e.range[1])
      else
        nrow = nrow + #e.text - (e.range[3] - e.range[1] + 1)
      end

      if e.range[1] == orow and e.range[2] ~= -1 then
        if #e.text > 1 then
          if ocol >= e.range[4] then ncol = ncol + #e.text[1] - (e.range[4] - e.range[2]) end
        elseif e.range[2] == e.range[4] then
          if csi.orcs ~= "" and e.text[1] == csi.orcs and ocol >= e.range[2] then
            if e.range[2] == eol_pos or ocol == e.range[2] then
              -- no shift for RHS at EOL or at cursor (insmode)
            else
              ncol = ncol + #e.text[1]
            end
          elseif ocol >= e.range[2] then
            ncol = ncol + #e.text[1]
          end
        elseif ocol >= e.range[4] then
          ncol = ncol + #e.text[1] - (e.range[4] - e.range[2])
        elseif ocol > e.range[2] then
          -- RHS marker (char-wise block): land at range[2]-1 (before the padding).
          ncol = e.range[2]
          if
            ctype == M.CMT.kBlock
            and motion == "char"
            and e.range[1] <= range[3]
            and range[3] <= e.range[3]
            and e.range[2] <= range[4]
            and range[4] < e.range[4]
          then
            ncol = math.max(0, e.range[2] - 1)
          end
        end
      end
    end
  end

  return H.make_pos(pos.buf, math.max(0, nrow), math.max(0, ncol))
end

---@param ctx Celeste.Comment.Hooks.PreCommitEdits.Ctx
function H.compute_cursor_state(ctx)
  local state = ctx.state_track
  if not state then return end
  if not ctx.cfg.keep_cursor and ctx.cfg.keep_selection == M.KEEP_SEL_FLAG.kNever then return end
  state.adj_cursor = H.compute_cursor_pos(state.adj_cursor, ctx)
  state.adj_endpos = H.compute_cursor_pos(state.adj_endpos, ctx)
end

---@param ctx Celeste.Comment.Hooks.PreCommitEdits.Ctx
function H.invoke_pre_commit_chainably(ctx)
  local hooks = { ctx.cfg.hooks.pre_commit_edits or "", H.compute_cursor_state }
  for _, hook in ipairs(hooks) do
    if vim.is_callable(hook) and hook(ctx) == true then break end
  end
end

---@param ctx Celeste.Comment.Hooks.PostCommitEdits.Ctx
function H.invoke_post_commit_chainably(ctx)
  local hooks = { ctx.cfg.hooks.post_commit_edits or "", H.post_commit_expand_block, H.restore_state }
  for _, hook in ipairs(hooks) do
    if vim.is_callable(hook) and hook(ctx) == true then break end
  end
end

---@param cfg    Celeste.Comment.Opts
---@param ctype  Celeste.Comment.CommentType
---@param action Celeste.Comment.Action
---@param lines  string[]
---@param csi    Celeste.Comment.CommentStringInfo
---@param range  Celeste.Comment.Range4
---@param motion Celeste.Comment.Motion
---@param cursor vim.Pos
---@param opts?  Celeste.Comment.ExecutionOpts
function H.make_actionx(cfg, ctype, action, lines, csi, range, motion, cursor, opts)
  opts = opts or {}
  local edits ---@type Celeste.Comment.TextEdits
  local info ---@type (Celeste.Comment.LineCommentInfo|Celeste.Comment.BlockCommentInfo)?
  if ctype == M.CMT.kBlock then
    edits, info = H.compute_block_edits(lines, range, motion, csi, cfg, action, cursor, opts)
  else
    edits, info = H.compute_line_edits(lines, range, motion, csi, cfg, action, cursor, opts)
  end
  assert(edits, "unexpected error, nil edits")

  ---@type Celeste.Comment.Hooks.PreCommitEdits.Ctx
  local ctx = {
    cfg = cfg,
    ctype = ctype,
    action = action,
    cursor = cursor,
    lines = lines,
    csi = csi,
    range = range,
    motion = motion,
    edits = edits,
    comment_info = info,
    state_track = opts.state_track,
    execution_opts = opts,
  }

  H.invoke_pre_commit_chainably(ctx)

  H.commit_edits(cursor.buf, ctx.range, ctx.lines, ctx.edits, ctx.o_use_set_text or cfg.use_set_text)

  H.invoke_post_commit_chainably(ctx --[[@as Celeste.Comment.Hooks.PostCommitEdits.Ctx]])
end

---@param cfg Celeste.Comment.Opts
---@param cursor vim.Pos
---@param csi Celeste.Comment.CommentStringInfo
---@return Celeste.Comment.Range4?
function H.compute_linecomment_range(cfg, cursor, csi)
  local nlines = vim.api.nvim_buf_line_count(cursor.buf)
  local row = cursor.row + 1
  local line = vim.fn.getline(row)

  local function is_comment(lnum)
    local l = vim.fn.getline(lnum)
    if l:match("^%s*$") then return false end
    return H.match_line_comment(l, lnum - 1, csi, { check_only = true }).matched
  end

  if line:match("^%s*$") then
    if cfg.ignore_empty_lines ~= M.IGN_EMT.kAlways then return end
    local prev = vim.fn.prevnonblank(row)
    local next = vim.fn.nextnonblank(row)
    if prev < 1 or next > nlines then return end
    if not is_comment(prev) or not is_comment(next) then return end
  elseif not is_comment(row) then
    return
  end

  local function check(lnum)
    if lnum < 1 or lnum > nlines then return false end
    local l = vim.fn.getline(lnum)
    if cfg.ignore_empty_lines == M.IGN_EMT.kAlways and l:match("^%s*$") then return true end
    return is_comment(lnum)
  end

  local lnum_from, lnum_to = row, row
  while check(lnum_from - 1) do
    lnum_from = lnum_from - 1
  end
  while check(lnum_to + 1) do
    lnum_to = lnum_to + 1
  end

  if cfg.ignore_empty_lines == M.IGN_EMT.kAlways then
    lnum_from = vim.fn.nextnonblank(lnum_from)
    lnum_to = vim.fn.prevnonblank(lnum_to)
  end

  return { lnum_from - 1, cursor.col, lnum_to - 1, cursor.col }
end

---@param lbegin integer
---@param csi    Celeste.Comment.CommentStringInfo
---@param cursor vim.Pos
---@return Celeste.Comment.Range4[]
function H.textobject_block_match_pairs(lines, lbegin, csi, cursor)
  local nlines = #lines
  local cursor_row, cursor_col = cursor.row + 1, cursor.col
  local all_pairs = {}
  local seen = {}

  local function inner(ol, ocs, cl, cce)
    if not (ol <= cursor_row and cursor_row <= cl) then return false end
    if ol == cl then return ocs <= cursor_col and cursor_col <= cce end
    if ol == cursor_row then return ocs <= cursor_col end
    if cl == cursor_row then return cursor_col <= cce end
    return true
  end

  for _, v in ipairs(csi.pairs) do
    local tlcs, trcs = v.traw[1], v.traw[2]
    if tlcs ~= "" and trcs ~= "" then
      local lcs_esc, rcs_esc = v.tesc[1], v.tesc[2]
      local lcs_len, rcs_len = #tlcs, #trcs
      local lrcs_eq = lcs_esc == rcs_esc
      local stack = {}
      local plist = {}

      for i = 1, nlines do
        local line = lines[i]
        local ln = lbegin - 1 + i
        local pos = 1

        while pos <= #line do
          local opos = line:find(lcs_esc, pos)
          local cpos = lrcs_eq and opos or line:find(rcs_esc, pos)

          if not opos and not cpos then break end

          if lrcs_eq and opos and #stack == 0 then
            table.insert(stack, { ln, opos - 1, opos + lcs_len - 2 })
            pos = opos + lcs_len
          else
            if lrcs_eq and opos then cpos = opos end

            if opos and (not cpos or opos < cpos) then
              table.insert(stack, { ln, opos - 1, opos + lcs_len - 2 })
              pos = opos + lcs_len
            elseif cpos and #stack > 0 then
              local ol, ocs = unpack(table.remove(stack))
              local cl, cce = ln, cpos + rcs_len - 2

              assert(ol <= cl)
              if inner(ol, ocs, cl, cce) then
                local key = table.concat({ ol, ocs, cl, cce }, ":")
                if not seen[key] then
                  seen[key] = true
                  plist[#plist + 1] = { ol, ocs, cl, cce, lcs_len, rcs_len }
                end
              end
              pos = cpos + rcs_len
            else
              pos = cpos + rcs_len
            end
          end
        end
      end

      vim.list_extend(all_pairs, plist)
    end
  end

  table.sort(all_pairs, function(a, b)
    -- Detect marker overlap: e.g. `{/*` (len 3) and `/*` (len 2) share bytes.
    -- This is not real nesting — prefer the larger region.
    if a[1] == b[1] then
      local a_start, a_len = a[2], a[5]
      local b_start, b_len = b[2], b[5]
      if (a_start <= b_start and b_start < a_start + a_len) or (b_start <= a_start and a_start < b_start + b_len) then
        local ra, ca = a[3] - a[1], a[4] - a[2]
        local rb, cb = b[3] - b[1], b[4] - b[2]
        if ra ~= rb then return ra > rb end
        return ca > cb
      end
    end

    -- Real nesting (or non-overlapping pairs): smaller region first.
    local ra, ca = a[3] - a[1], a[4] - a[2]
    local rb, cb = b[3] - b[1], b[4] - b[2]
    if ra ~= rb then return ra < rb end
    return ca < cb
  end)

  return all_pairs
end

---@param cursor vim.Pos
---@return Celeste.Comment.Range4?
---@return boolean?  true : treesitter available but not in comment
function H.textobject_comment_at_cursor(cursor)
  local ok, parser = pcall(vim.treesitter.get_parser, cursor.buf, nil)
  if not ok or not parser then return end
  parser:parse()

  local range = { cursor.row, cursor.col, cursor.row, cursor.col }
  local has_query
  local result

  local function walk(ltree)
    if result then return true end
    if not ltree:contains(range) then return end
    if ltree:lang() == "comment" then return end

    local query = vim.treesitter.query.get(ltree:lang(), "textobjects")
    if query then
      has_query = true
      for _, tstree in pairs(ltree:trees()) do
        for id, node in
          query:iter_captures(
            tstree:root(),
            cursor.buf,
            cursor.row,
            cursor.row,
            { start_col = cursor.col, end_col = cursor.col + 1 }
          )
        do
          if query.captures[id] == "comment.outer" then
            local srow, scol, erow, ecol = node:range()
            result = { srow, scol, erow, math.max(ecol - 1, 0) }
            return true
          end
        end
      end
    end

    for _, child in pairs(ltree:children()) do
      if walk(child) then return true end
    end
  end

  walk(parser)

  if result then return result end
  if has_query then return nil, true end
end

---@param buf       integer
---@param csi       Celeste.Comment.CommentStringInfo
---@param ts_range? Celeste.Comment.Range4
---@return Celeste.Comment.Range4?
function H.textobject_block_match_ts(buf, csi, ts_range)
  if not ts_range then return end

  local lines = vim.api.nvim_buf_get_lines(buf, ts_range[1], ts_range[3] + 1, false)
  local first, last = lines[1], lines[#lines]
  if not first or not last then return end

  for _, v in ipairs(csi.pairs) do
    local tlcs, trcs = v.traw[1], v.traw[2]
    if tlcs ~= "" and trcs ~= "" then
      if
        H.match_byte(first, ts_range[2], tlcs, 0, 1, csi.ci) == #tlcs
        and H.match_byte(last, ts_range[4] - #trcs + 1, trcs, 0, 1, csi.ci) == #trcs
      then
        return ts_range
      end
    end
  end
end

---@param cfg      Celeste.Comment.Opts
---@param cursor   vim.Pos
---@param csi      Celeste.Comment.CommentStringInfo
---@param ts_range? Celeste.Comment.Range4
---@return Celeste.Comment.Range4?
function H.compute_blockcomment_range(cfg, cursor, csi, ts_range)
  if not ts_range and cfg.textobj_treesitter_detect then
    local range, ts_no_comment = H.textobject_comment_at_cursor(cursor)
    if ts_no_comment then return end
    ts_range = range
  end

  if ts_range and #ts_range == 4 then return H.textobject_block_match_ts(cursor.buf, csi, ts_range) end

  local nlines = vim.api.nvim_buf_line_count(cursor.buf)
  local from_limit = math.max(1, cursor.row + 1 - cfg.block_textobj_nlines)
  local to_limit = math.min(nlines, cursor.row + 1 + cfg.block_textobj_nlines)

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, from_limit - 1, to_limit, false)

  local pairs = H.textobject_block_match_pairs(lines, from_limit, csi, cursor)
  if #pairs == 0 then return end
  local idx = math.min(vim.v.count1, #pairs)
  local p = pairs[idx]
  return { p[1] - 1, p[2], p[3] - 1, p[4] }
end

---@param range? Celeste.Comment.Range4
---@param opts? { mode?: 'V'|'v', end_inclusive?: boolean, exit?: boolean }
function H.select_range(range, opts)
  if not range then return end
  opts = opts or {}
  local mode = opts.mode or "v"

  if H.is_visual() then vim.cmd.normal({ "\27", bang = true }) end

  local sv = vim.fn.winsaveview()

  local cur_col = range[4]
  if opts.end_inclusive and vim.o.selection == "exclusive" then cur_col = cur_col + 1 end

  vim.api.nvim_win_set_cursor(0, { range[1] + 1, range[2] })
  vim.cmd.normal({ "zv", bang = true })
  vim.cmd.normal({ mode, bang = true })
  vim.api.nvim_win_set_cursor(0, { range[3] + 1, cur_col })
  vim.cmd.normal({ "zv", bang = true })

  vim.fn.winrestview({ leftcol = sv.leftcol, topline = sv.topline })

  if opts.exit then vim.cmd.normal({ "\27", bang = true }) end
end

---@param cfg Celeste.Comment.Opts
---@param cursor vim.Pos
---@return Celeste.Comment.Range4?
---@return Celeste.Comment.CommentType?
---@return Celeste.Comment.CommentStringInfo?
function H.compute_x_comment_range(cfg, cursor)
  local all_csi = H.make_all_csi(cursor, cfg, nil, false)
  if not all_csi then return end
  local lcsi, bcsi = all_csi[M.CMT.kLine], all_csi[M.CMT.kBlock]

  -- a little bit hack, but works in most scenarios..
  local bprefix = lcsi ~= nil
    and bcsi ~= nil
    and bcsi.tlcs ~= lcsi.tlcs
    and lcsi.tlcs ~= ""
    and bcsi.tlcs ~= ""
    and vim.startswith(bcsi.tlcs, lcsi.tlcs)

  if lcsi then
    local r
    if lcsi.wrapped and cfg.fallback_to_block == M.FBK2BLOCK.kIfLineCmsWrapped then
      r = H.compute_blockcomment_range(cfg, cursor, lcsi)
      if r then return r, M.CMT.kBlock, lcsi end
    end

    if bprefix and bcsi then
      r = H.compute_blockcomment_range(cfg, cursor, bcsi)
      if r then return r, M.CMT.kBlock, bcsi end
    end

    r = H.compute_linecomment_range(cfg, cursor, lcsi)
    if r then return r, M.CMT.kLine, lcsi end
  end

  if not bprefix and bcsi then return H.compute_blockcomment_range(cfg, cursor, bcsi), M.CMT.kBlock, bcsi end
end

--- Auto-detect linewise or blockwise textobject
function H.textobject_auto()
  if H.is_disabled() then return end
  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)
  local range, ctype = H.compute_x_comment_range(cfg, cursor)
  if not range or not ctype then return end
  H.select_range(range, { mode = ctype == M.CMT.kLine and "V" or "v", end_inclusive = true })
end

--- Auto-detect and remove comment
function H.uncomment_auto()
  if H.is_disabled({ check_modifiable = true }) then return end

  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)
  local state_track = H.make_state_track()

  local range, ctype, csi = H.compute_x_comment_range(cfg, cursor)
  if not range or not ctype or not csi then return end

  local motion = ctype == M.CMT.kLine and "line" or "char"

  if ctype == M.CMT.kLine then range = { range[1], 0, range[3], 0 } end

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, range[1], range[3] + 1, false)
  if #lines == 0 then return end

  H.make_actionx(cfg, ctype, M.ACTION.kToggle, lines, csi, range, motion, cursor, { state_track = state_track })
end

-- Textobject: select contiguous linewise comment block
function H.textobject_linewise()
  if H.is_disabled() then return end

  local cfg = H.buf_config()

  if cfg.fallback_to_block ~= M.FBK2BLOCK.kNever then return H.textobject_auto() end

  local cursor = H.make_cursor(0)

  local csi = H.resolve(cursor, M.CMT.kLine, cfg)
  if not csi then return end

  H.select_range((H.compute_linecomment_range(cfg, cursor, csi)), { mode = "V", end_inclusive = true })
end

---Textobject: select blockwise comment that surrounds the cursor.
function H.textobject_blockwise()
  if H.is_disabled() then return end

  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)

  local csi = H.resolve(cursor, M.CMT.kBlock, cfg)
  if not csi then return end

  H.select_range((H.compute_blockcomment_range(cfg, cursor, csi)), { mode = "v", end_inclusive = true })
end

---@param kind 'above'|'below'|'eol'
function H.insert_comment(kind)
  if H.is_disabled({ check_modifiable = true }) then return end

  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)
  local buf = cursor.buf

  local csi = H.resolve(cursor, M.CMT.kLine, cfg)
  if not csi then return end

  if kind ~= "eol" then
    local target = cursor.row + (kind == "above" and 0 or 1)
    vim.api.nvim_buf_set_lines(buf, target, target, false, { csi.olcs .. csi.orcs })
    vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
    vim.cmd.normal({ "==", bang = true })
    local indent = #(vim.api.nvim_get_current_line():match("^(%s*)"))
    vim.api.nvim_win_set_cursor(0, { target + 1, indent + #csi.olcs })
  else
    local line = vim.api.nvim_get_current_line()
    if line:find("^%s*$") then
      vim.api.nvim_buf_set_text(buf, cursor.row, 0, cursor.row, 0, { csi.olcs .. csi.orcs })
      vim.cmd.normal({ "==", bang = true })
      local indent = #(vim.api.nvim_get_current_line():match("^(%s*)"))
      vim.api.nvim_win_set_cursor(0, { cursor.row + 1, indent + #csi.olcs })
    else
      vim.api.nvim_buf_set_text(buf, cursor.row, #line, cursor.row, #line, { " " .. csi.olcs .. csi.orcs })
      vim.api.nvim_win_set_cursor(0, { cursor.row + 1, #line + 1 + #csi.olcs })
    end
  end
  vim.cmd.startinsert({ bang = (csi.trcs == "") })
end

---@param cursor vim.Pos
---@param range  Celeste.Comment.Range4
---@param ctype  Celeste.Comment.CommentType
---@param action Celeste.Comment.Action
---@param motion Celeste.Comment.Motion
---@param opts?  Celeste.Comment.ExecutionOpts
function H.make_action_range(cursor, range, ctype, action, motion, opts)
  if H.is_disabled({ check_modifiable = true }) then return end
  opts = opts or {}

  local cfg = H.buf_config(opts.cfg)

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, range[1], range[3] + 1, false)
  if #lines == 0 then return end

  local csi, n_ctype = H.resolve(cursor, ctype, cfg, range)
  if not csi or not n_ctype then return end

  -- Like VSCode/Zed, always expand selection to line boundaries if fallback to block
  if ctype == M.CMT.kLine and n_ctype == M.CMT.kBlock then motion = "line" end

  H.make_actionx(cfg, n_ctype, action, lines, csi, range, motion, cursor, opts)
end

--- Track cursor and selection state
function M.track_state() H.state_track = H.make_state_track() end

---@param ctype Celeste.Comment.CommentType
---@param opts? Celeste.Comment.ExecutionOpts
---@return fun():string
function H.make_operator(ctype, opts)
  opts = opts or {}
  local s = type(opts.suffix) == "string" and opts.suffix or ""
  local action = opts.action or M.ACTION.kToggle

  ---@param motion Celeste.Comment.Motion
  local f = function(motion)
    local state_track = H.state_track
    H.state_track = nil
    -- actually, at the region start position, it may not be the same as `cursor_state`
    local cursor = H.make_cursor(0)
    local range = H.get_selection_range(cursor.buf)
    if not range then return end
    H.make_action_range(cursor, range, ctype, action, motion, { cfg = opts.cfg, state_track = state_track })
  end

  return function()
    if H.is_disabled({ check_modifiable = true }) then return "" end
    H.state_track = H.make_state_track()

    if HAS_NVIM_013 then
      vim.o.operatorfunc = f
    else
      _G.__celeste_comment_operator_func = f
      vim.o.operatorfunc = "v:lua.__celeste_comment_operator_func"
    end
    return "g@" .. s
  end
end

---@param config? Celeste.Comment.PartialOpts
function M.setup(config)
  ---@diagnostic disable-next-line: cast-local-type
  config = vim.tbl_deep_extend("force", vim.deepcopy(H.config), config or {})
  vim.validate("keep_cursor", config.keep_cursor, "boolean", true, "boolean")
  vim.validate("keep_selection", config.keep_selection, function(v)
    local _, err = H.normalize_flags(v, H.KEEP_SEL_MAP, "keep_selection")
    return err == nil, err
  end, true, "string|number")
  vim.validate("insert_space", config.insert_space, "boolean", true, "boolean")
  vim.validate("line_comment_no_indent", config.line_comment_no_indent, "boolean", true, "boolean")
  vim.validate("ignore_empty_lines", config.ignore_empty_lines, function(v)
    if type(v) ~= "string" then return false, ("expected 'never'|'mixed'|'always' but got type:%s"):format(type(v)) end
    return vim.iter({ "never", "mixed", "always" }):any(function(z) return z == v end),
      ("expected 'never'|'mixed'|'always' but got %s"):format(v)
  end, true, "boolean")
  vim.validate("fallback_to_block", config.fallback_to_block, function(v)
    if type(v) ~= "string" then return false, "expected string" end
    return vim.iter({ "never", "if_line_cms_wrapped" }):any(function(z) return z == v end),
      ("expected 'never'|'if_line_cms_wrapped' but got %s"):format(v)
  end, true, "string")
  vim.validate("case_insensitive", config.case_insensitive, "boolean", true, "boolean")
  vim.validate("detect_indent", config.detect_indent, "boolean", true, "boolean")
  vim.validate("block_relaxed_detect", config.block_relaxed_detect, "boolean", true, "boolean")
  vim.validate("block_textobj_nlines", config.block_textobj_nlines, "number", true, "number")
  vim.validate("mappings", config.mappings, "table", true, "table")
  vim.validate("cms_confs", config.cms_confs, { "table", "boolean" }, true, "table")
  vim.validate("log_level", config.log_level, "number", true, "vim.log.levels")
  for k, v in pairs(config.mappings) do
    vim.validate("mappings." .. k, v, { "string", "table" }, true, "string or string[]")
  end
  vim.validate("hooks", config.hooks, "table", true, "table")
  vim.validate("pre_commit_edits", config.hooks.pre_commit_edits, "callable", true, "callable")
  vim.validate("post_commit_edits", config.hooks.post_commit_edits, "callable", true, "callable")
  vim.validate("cms_conf_resolver", config.hooks.cms_conf_resolver, "callable", true, "callable")
  vim.validate("indent_resolver", config.hooks.indent_resolver, "callable", true, "callable")

  H.config = H.normalize_config(config)

  local m = H.config.mappings --[[@as Celeste.Comment.Opts.Mapping]]

  ---@param mode string|string[]
  ---@param lhs string|string[]
  ---@param rhs string|function
  ---@param opts vim.keymap.set.Opts
  local function map(mode, lhs, rhs, opts)
    local t = type(lhs)
    if t == "table" then
      for _, slhs in ipairs(lhs) do
        map(mode, slhs, rhs, opts)
      end
      return
    end
    if t == "string" and lhs ~= "" then vim.keymap.set(mode, lhs, rhs, opts or {}) end
  end

  -- stylua: ignore start
  local op_line_toggle      = H.make_operator(M.CMT.kLine)
  local op_line_toggle_cur  = H.make_operator(M.CMT.kLine, { suffix = "_" })
  local op_block_toggle     = H.make_operator(M.CMT.kBlock)
  local op_block_toggle_cur = H.make_operator(M.CMT.kBlock, { suffix = "_" })
  local op_invert           = H.make_operator(M.CMT.kLine, { action = M.ACTION.kInvert })
  local op_force_add        = H.make_operator(M.CMT.kLine, { action = M.ACTION.kForceAdd })
  local op_force_rmv        = H.make_operator(M.CMT.kLine, { action = M.ACTION.kForceRemove })

  map("n", m.line_toggle,        op_line_toggle,      { expr = true, desc = "Line comment by motion" })
  map("n", m.line_toggle_cur,    op_line_toggle_cur,  { expr = true, desc = "Line comment current line" })
  map("x", m.line_toggle_visual, op_line_toggle,      { expr = true, desc = "Line comment selection" })
  map("n", m.block_toggle,       op_block_toggle,     { expr = true, desc = "Block comment by motion" })
  map("n", m.block_toggle_cur,   op_block_toggle_cur, { expr = true, desc = "Block comment current line" })
  map("x", m.block_toggle_visual,op_block_toggle,     { expr = true, desc = "Block comment selection" })

  map("n", m.line_add_below,  function() H.insert_comment("below") end, { desc = "Add comment below" })
  map("n", m.line_add_above,  function() H.insert_comment("above") end, { desc = "Add comment above" })
  map("n", m.line_add_eol,    function() H.insert_comment("eol")   end, { desc = "Add comment at end of line" })
  map("n", m.uncomment_auto,  function() H.uncomment_auto()        end, { desc = "Auto detect and uncomment" })

  map("n", m.line_invert, op_invert, { expr = true, desc = "Invert comment by motion" })
  map("x", m.line_invert, op_invert, { expr = true, desc = "Invert comment selection" })

  map({ "n", "x" }, m.line_force_add,    op_force_add, { expr = true, desc = "Force add line comment" })
  map({ "n", "x" }, m.line_force_remove, op_force_rmv, { expr = true, desc = "Force remove line comment" })
  -- stylua: ignore end

  map(
    m.line_toggle_visual == m.line_textobject and "o" or { "o", "x" },
    m.line_textobject,
    '<cmd>lua require("celeste_comment").H.textobject_linewise()<cr>',
    { desc = "Linewise comment textobject" }
  )
  map(
    m.block_toggle_visual == m.block_textobject and "o" or { "o", "x" },
    m.block_textobject,
    '<cmd>lua require("celeste_comment").H.textobject_blockwise()<cr>',
    { desc = "Block comment textobject" }
  )
  map(
    { "o", "x" },
    m.auto_textobject,
    '<cmd>lua require("celeste_comment").H.textobject_auto()<cr>',
    { desc = "Auto line/block textobject" }
  )

  -- TODO: eliminate this keymap by `CmdAtom`?
  map("n", m.dot_repeat, function()
    H.state_track = H.make_state_track()
    return "."
  end, { expr = true, desc = "Dot-repeat track cursor for celeste_comment.nvim" })

  map("i", m.line_toggle_insert, function()
    local cursor = H.make_cursor(0)
    local range = { cursor.row, cursor.col, cursor.row, cursor.col }
    H.make_action_range(cursor, range, M.CMT.kLine, M.ACTION.kToggle, "line", {
      insmode = true,
      state_track = H.make_state_track(),
    })
  end, { desc = "Toggle line comment at insert mode" })
end

-- test only
M.H = H

return M
