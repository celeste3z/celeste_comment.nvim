---@class Celeste.Comment
local M = {}

local H = {}

---@alias Celeste.Comment.Motion 'line'|'char'|'block'

---@alias Celeste.Comment.Range2 [integer, integer] 0-indexed
---@alias Celeste.Comment.Range3 [integer, integer, integer] 0-indexed
---@alias Celeste.Comment.Range4 [integer, integer, integer, integer] 0-indexed { start_row, start_col, end_row, end_col }

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

---@enum Celeste.Comment.Action
M.ACT = {
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

---@class Celeste.Comment.CommentStringConf
---@field [1] (string|string[])?
---@field [2] (string|string[])?

---@alias Celeste.Comment.CommentStringConfs {[1]:string, [2]:(Celeste.Comment.CommentStringConf|fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx))}

---@class Celeste.Comment.CommentStringInfo.Pairs
---@field tesc [string, string]
---@field traw [string, string]
---@field tout [string, string]

---@class Celeste.Comment.CommentStringInfo
---@field ci         boolean -- case-insensitive
---@field wrapped    boolean -- comment string was wrapped
---@field tlcs       string  -- vim.trim(lcs)
---@field trcs       string  -- vim.trim(rcs)
---@field olcs       string  -- output: pad=true->tlcs+" ", else->lcs
---@field orcs       string  -- output: pad=true->" "+trcs, else->rcs
---@field pairs      Celeste.Comment.CommentStringInfo.Pairs[]

---@class Celeste.Comment.LineCommentInfo.Line
---@field row         integer real row in buffer
---@field lead_ws_len integer leading whitespace len
---@field offset      integer 0-indexed column where comment marker should be inserted
---@field ignore      boolean should thie line be ignored?
---@field csi         Celeste.Comment.CommentStringInfo comment string info
---@field lcs_pos     Celeste.Comment.Range3? position of lcs
---@field rcs_pos     Celeste.Comment.Range3? position of rcs
---@field commented?  boolean
---@field all_blank?  boolean blank line
---@field will_blank? boolean not blank, but will be blank after remove lcs and rcs, current only available with ignore_empty_lines = kMixed

---@class Celeste.Comment.LineCommentInfo
---@field lines         Celeste.Comment.LineCommentInfo.Line[]
---@field should_remove boolean

---@class Celeste.Comment.BlockCommentInfo
---@field lcs_pos Celeste.Comment.Range3
---@field rcs_pos Celeste.Comment.Range3

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
---@field execution_opts? Celeste.Comment.ExecutionOpts
---@field o_use_set_text? boolean o: means output from user

---@class Celeste.Comment.Hooks.CmsConfResolver.Ctx
---@field cursor      vim.Pos
---@field range?      Celeste.Comment.Range4
---@field cfg         Celeste.Comment.Opts
---@field o_cms_conf? Celeste.Comment.CommentStringConf
---@field tree?       vim.treesitter.LanguageTree

---@class Celeste.Comment.Hooks
---@field pre_commit_edits?  fun(ctx:Celeste.Comment.Hooks.PreCommitEdits.Ctx)
---@field cms_conf_resolver? fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx)

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
---@field keep_cursor?                boolean default true
---@field insert_space?               boolean default true
---@field line_comment_no_indent?     boolean default false
---@field case_insensitive?           boolean default false
---@field textobj_treesitter_detect?  boolean default true
---@field block_textobj_nlines?       integer default 200
---@field block_relaxed_detect?       boolean default false
---@field ignore_empty_lines?         Celeste.Comment.Opts.IgnoreEmptyLines default "never"
---@field fallback_to_block?          Celeste.Comment.Opts.FallbackToBlock
---@field cms_confs?                  Celeste.Comment.CommentStringConfs|boolean
---@field mappings?                   Celeste.Comment.Opts.Mapping
---@field hooks?                      Celeste.Comment.Hooks
---@field log_level?                  vim.log.levels default `vim.log.levels.OFF`

---@class Celeste.Comment.ExecutionOpts
---@field [string] any

---@class Celeste.Comment.CursorStateTrack
---@field cursor vim.Pos

---@type Celeste.Comment.CursorStateTrack?
H.cursor_state = nil

-- stylua: ignore start
---@type Celeste.Comment.Opts
H.config = {
  keep_cursor               = true,
  insert_space              = true,
  line_comment_no_indent    = false,
  case_insensitive          = false,
  block_relaxed_detect      = true,
  textobj_treesitter_detect = false,
  block_textobj_nlines      = 200,
  ignore_empty_lines        = M.IGN_EMT.kAlways,
  fallback_to_block         = M.FBK2BLOCK.kIfLineCmsWrapped,
  log_level                 = vim.log.levels.OFF,

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
    cms_conf_resolver       = nil
  }
}

local log_level_to_name = {
  [vim.log.levels.TRACE] = "trace",
  [vim.log.levels.DEBUG] = "debug",
  [vim.log.levels.INFO]  = "info",
  [vim.log.levels.WARN]  = "warn",
  [vim.log.levels.ERROR] = "error",
}
-- stylua: ignore end

H.__has_nvim_012 = vim.fn.has("nvim-0.12") == 1
H.__has_nvim_013 = vim.fn.has("nvim-0.13") == 1
---@param silent? boolean
---@return boolean
function H.supported(silent)
  if not H.__has_nvim_012 and not silent then
    vim.api.nvim_echo(
      { { "celeste_comment.nvim", "DiagnosticSignHint" }, { " requires nvim-0.12", "WarningMsg" } },
      true,
      {}
    )
  end
  return H.__has_nvim_012
end

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

    if H.__has_nvim_013 then
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
function H.should_log(level) return level >= H.config.log_level and H.__has_nvim_013 end

---@param level vim.log.levels
---@vararg any
function H.log(level, ...)
  if not H.should_log(level) then return end
  if not H._logger then H._logger = vim.log.new({ name = "celeste_comment", level = H.config.log_level }) end
  if H._logger then H._logger[log_level_to_name[level]](...) end
end
---@diagnostic enable

---@param cfg? Celeste.Comment.Opts
---@return Celeste.Comment.Opts
function H.buf_config(cfg)
  local bcfg = vim.b.celeste_comment_config
  local tb_bcfg = type(bcfg) == "table"
  local tb_cfg = type(cfg) == "table"
  if not tb_bcfg and not tb_cfg then return H.config end
  return vim.tbl_deep_extend("force", H.config, tb_bcfg and bcfg or {}, tb_cfg and cfg or {})
end

---@type Celeste.Comment.CommentStringConfs
H.comment_string_confs = {
  bash = { { "#%s" }, nil },
  bat = { { "@REM%s" }, nil },
  c = { nil, "/*%s*/" },
  cmake = { { "#%s" }, "#[[%s]]" },
  cpp = { { "//%s" }, "/*%s*/" },
  css = { nil, "/*%s*/" },
  dockerfile = { { "#%s" }, nil },
  editorconfig = { { "#%s" }, nil },
  fish = { { "#%s" }, nil },
  gdb = { { "#%s" }, nil },
  gitignore = { { "#%s" }, nil },
  go = { { "//%s" }, "/*%s*/" },
  gomod = { { "//%s" }, nil },
  graphql = { { "#%s" }, nil },
  groovy = { { "//%s" }, "/*%s*/" },
  haskell = { { "--%s" }, "{-%s-}" },
  html = { nil, "<!--%s-->" },
  ini = { { ";%s" }, nil },
  java = { { "//%s" }, "/*%s*/" },
  javascript = { { "//%s" }, "/*%s*/" },
  json5 = { { "//%s" }, "/*%s*/" },
  jsonc = { { "//%s" }, "/*%s*/" },
  kotlin = { { "//%s" }, "/*%s*/" },
  lisp = { { ";;%s" }, "#|%s|#" },
  lua = { { "--%s", "--[[%s]]" }, "--[[%s]]" },
  make = { { "#%s" } },
  markdown = { nil, "<!--%s-->" },
  nix = { { "#%s" }, "/*%s*/" },
  nu = { { "#%s" }, nil },
  objc = { { "//%s" }, "/*%s*/" },
  objcpp = { { "//%s" }, "/*%s*/" },
  perl = { { "#%s" }, nil },
  php = { { "//%s" }, "/*%s*/" },
  python = { { "#%s" }, '"""%s"""' },
  r = { { "#%s" }, nil },
  rust = { { "//%s", "///%s", "//!%s" }, "/*%s*/" },
  scala = { { "//%s" }, "/*%s*/" },
  sh = { { "#%s" }, nil },
  sql = { { "--%s" }, "/*%s*/" },
  swift = { { "//%s" }, "/*%s*/" },
  tmux = { { "#%s" }, nil },
  toml = { { "#%s" }, nil },
  tsx = { { "//%s" }, "/*%s*/" },
  typescript = { { "//%s" }, "/*%s*/" },
  vim = { { '"%s' }, nil },
  xml = { nil, "<!--%s-->" },
  yaml = { { "#%s" }, nil },
  zig = { { "//%s" }, nil },
}

---@return boolean
function H.is_disabled()
  return vim.g.celeste_comment_disable == true or vim.b.celeste_comment_disable == true or not H.supported()
end

---@return boolean
function H.is_visual() return vim.fn.mode():match("[vV\22]") ~= nil end

---@param pat string
---@return string case-insensitive variant, e.g. "rem" -> "[rR][eE][mM]"
function H.pattern_ci(pat)
  local result = pat:gsub("%a", function(c)
    local l, u = c:lower(), c:upper()
    return l == u and c or ("[" .. l .. u .. "]")
  end)
  return result
end

---@param cs string|string[]
---@return {[1]:string,[2]:string}[]
function H.comment_string_unwrap(cs)
  local tp = type(cs)
  assert(tp == "table" or tp == "string", "invalid comment string")
  if tp == "string" then cs = { cs } end

  local result = {}
  for _, s in ipairs(cs) do
    local l, r = s:match("^(.-)%%s(.-)$")
    result[#result + 1] = { l or "", r or "" }
  end
  return result
end

---@param pairs {[1]:string,[2]:string}[]
---@param opts? {pad?: boolean, ci?: boolean}
---@return Celeste.Comment.CommentStringInfo?
function H.make_csi(pairs, opts)
  opts = opts or {}
  local function make_tesc(cs) return opts.ci and H.pattern_ci(vim.pesc(cs)) or vim.pesc(cs) end

  local function make_out_pair(tlcs, trcs, lcs, rcs)
    local olcs, orcs = lcs, rcs
    if opts.pad then
      olcs = tlcs == "" and "" or tlcs .. " "
      orcs = trcs == "" and "" or " " .. trcs
    end
    return olcs, orcs
  end

  local tpairs = vim.iter(pairs):map(function(p) return { vim.trim(p[1]), vim.trim(p[2]), p[1], p[2] } end):totable()
  table.sort(tpairs, function(a, b)
    local la, lb = a[1], b[1]
    if #la ~= #lb then return #la > #lb end
    return la > lb
  end)

  tpairs = vim
    .iter(tpairs)
    :filter(function(p) return p[1] ~= "" or p[2] ~= "" end)
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
  local res = {
    pairs = tpairs,
    tlcs = tplcs,
    trcs = tprcs,
    olcs = olcs,
    orcs = orcs,
    ci = opts.ci or false,
    wrapped = (tplcs ~= "" and tprcs ~= ""),
  }

  if H.should_log(vim.log.levels.TRACE) then H.log(vim.log.levels.TRACE, "csi_info", vim.inspect(res)) end

  return res
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

---@param cursor vim.Pos
---@return vim.treesitter.LanguageTree?
---@return string?
function H.language_tree_resolve(cursor)
  local ok, parser = pcall(vim.treesitter.get_parser, cursor.buf, "")
  if not ok or parser == nil then return end

  ---@type Range4
  local range = { cursor.row, cursor.col, cursor.row, cursor.col + 1 }
  local dp_tree, dp_cs, dp_level = nil, nil, 0

  ---@param ltree vim.treesitter.LanguageTree
  ---@param level integer
  local function walk(ltree, level)
    if not ltree:contains(range) then return end
    local lang = ltree:lang()

    if lang ~= "comment" then
      dp_tree = ltree

      local filetypes = vim.treesitter.language.get_filetypes(lang)
      for _, ft in ipairs(filetypes) do
        local cs = vim.filetype.get_option(ft, "commentstring")
        if type(cs) == "string" and cs ~= "" and level > dp_level then
          dp_cs, dp_level = cs, level
        end
      end

      for _, child_ltree in pairs(ltree:children()) do
        walk(child_ltree, level + 1)
      end
    end
  end

  walk(parser, 1)

  return dp_tree, dp_cs
end

---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
function H.builtin_cms_conf_resolver(ctx)
  local cursor = ctx.cursor

  ctx.o_cms_conf = {
    [M.CMT.kLine] = vim.bo[cursor.buf].commentstring,
    [M.CMT.kBlock] = vim.b[cursor.buf].celeste_comment_block_commentstring,
  }

  -- adjust to start column
  do
    local line = vim.fn.getline(cursor.row + 1)
    local start_col = line:match("^%s*()")
    if start_col then cursor = H.make_pos(cursor.buf, cursor.row, start_col - 1) end
  end

  local ltree, ts_cs = H.language_tree_resolve(cursor)
  if ts_cs and ts_cs ~= "" then ctx.o_cms_conf[M.CMT.kLine] = ts_cs end

  -- disabled builtin comment string config
  if ctx.cfg.cms_confs == false then return end

  local filetypes = {}
  if ltree then
    local lang = ltree:lang()
    filetypes = vim.treesitter.language.get_filetypes(lang)
  end
  filetypes[#filetypes + 1] = vim.bo[cursor.buf].filetype

  local is_table = type(ctx.cfg.cms_confs) == "table"
  local function get_cms_conf(ft)
    if ft == "" then return end
    local conf = is_table and ctx.cfg.cms_confs[ft] or nil
    return conf or H.comment_string_confs[ft]
  end

  for _, ft in ipairs(filetypes) do
    local v = get_cms_conf(ft)
    if v then
      if vim.is_callable(v) then
        ---@cast v fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx)
        ctx.tree = ltree
        return v(ctx)
      end

      if type(v) == "table" then
        ctx.o_cms_conf = v
        return
      end
    end
  end
end

---@param cursor vim.Pos
---@param cfg    Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
---@return Celeste.Comment.CommentStringConf?
function H.make_cms_conf(cursor, cfg, range)
  local resolvers = { cfg.hooks.cms_conf_resolver or "", H.builtin_cms_conf_resolver }

  for _, resolver in ipairs(resolvers) do
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

---@param cms_conf Celeste.Comment.CommentStringConf
---@param ctype    Celeste.Comment.CommentType
---@param cfg      Celeste.Comment.Opts
---@param silent?  boolean
---@return Celeste.Comment.CommentStringInfo?
function H.make_csi_from_cms_conf(cms_conf, ctype, cfg, silent)
  if not cms_conf then return end
  if type(cms_conf) ~= "table" then return end
  local cms = cms_conf[ctype]
  if not cms then return end
  if type(cms) == "string" and cms == "" then return end
  local pairs = H.comment_string_unwrap(cms)
  if ctype == M.CMT.kBlock then
    if vim.iter(pairs):any(function(p) return p[1] == "" or p[2] == "" end) then
      if not silent then
        vim.api.nvim_echo(
          { { "Invalid ", "WarningMsg" }, { "blockwise commentstring : " }, { ("%s"):format(vim.inspect(pairs)) } },
          true,
          {}
        )
      end
      return
    end
  end
  return H.make_csi(pairs, { pad = cfg.insert_space, ci = cfg.case_insensitive })
end

---@param cursor vim.Pos
---@param ctype  Celeste.Comment.CommentType
---@param cfg    Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
---@return Celeste.Comment.CommentStringInfo?
---@return Celeste.Comment.CommentType?
function H.resolve(cursor, ctype, cfg, range)
  local cms_conf = H.make_cms_conf(cursor, cfg, range)
  if not cms_conf then return end

  local csi = H.make_csi_from_cms_conf(cms_conf, ctype, cfg)

  if ctype == M.CMT.kLine and cfg.fallback_to_block ~= M.FBK2BLOCK.kNever then
    if not csi then
      csi = H.make_csi_from_cms_conf(cms_conf, M.CMT.kBlock, cfg)
      ctype = M.CMT.kBlock
    end
    if csi and csi.wrapped then ctype = M.CMT.kBlock end
  end

  return csi, ctype
end

---@class Celeste.Comment.MatchLineComment.Result
---@field lcs_pos?    Celeste.Comment.Range3
---@field rcs_pos?    Celeste.Comment.Range3
---@field will_blank? boolean

---@param line  string
---@param row   integer
---@param csi   Celeste.Comment.CommentStringInfo
---@param opts? {check_only?: boolean, check_will_blank?: boolean}
---@return (boolean|Celeste.Comment.MatchLineComment.Result)?
function H.match_line_comment(line, row, csi, opts)
  for _, p in ipairs(csi.pairs) do
    local tlcs_esc, trcs_esc = p.tesc[1], p.tesc[2]
    local suffix = #trcs_esc > 0 and "(.-)()" .. trcs_esc .. "()%s*$" or "(.-)%s*$"
    local s, _e, p1, p2, content, p3, p4 = line:find("^%s*()" .. tlcs_esc .. "()" .. suffix)
    if s then
      if opts and opts.check_only then return true end

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
      local res = { lcs_pos = lcs_pos, rcs_pos = rcs_pos }
      if opts and opts.check_will_blank then res.will_blank = content:match("^%s*$") ~= nil end
      return res
    end
  end
  if opts and opts.check_only then return false end
end

---@param cur_visible_col integer current visible column
---@param byte            integer byte value of current character
---@param indent_size     integer
---@return integer
function H.next_visible_column(cur_visible_col, byte, indent_size)
  if byte == 9 then return cur_visible_col + indent_size - (cur_visible_col % indent_size) end
  return cur_visible_col + 1
end

--- Walk up to `limit` chars of `line` counting visible columns,
--- return the 0-indexed offset where visible column first reaches `min_visible_col`.
--- If visible column overshoots, backtrack by 1
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
    if b ~= 32 and b ~= 9 then break end
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
      if la >= 65 and la <= 90 then la = la + 32 end
      if lb >= 65 and lb <= 90 then lb = lb + 32 end
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
---@param opts?  Celeste.Comment.ExecutionOpts
---@return Celeste.Comment.LineCommentInfo
function H.line_comment_info(lines, csi, cfg, range, action, opts)
  opts = opts or {}
  range = range or { 0 }
  ---@type Celeste.Comment.LineCommentInfo
  local all_info = { lines = {}, should_remove = true }
  local indent_size = vim.bo.tabstop
  local only_whitespace_lines = true
  local min_visible_col = math.huge

  ---@param line string
  ---@param info_line Celeste.Comment.LineCommentInfo.Line
  local function update_min_visible_col(line, info_line)
    local cur_visible_col = 0
    for j = 1, info_line.offset do
      if cur_visible_col >= min_visible_col then break end
      cur_visible_col = H.next_visible_column(cur_visible_col, line:byte(j), indent_size)
    end
    if cur_visible_col < min_visible_col then min_visible_col = cur_visible_col end
  end

  for i, line in ipairs(lines) do
    local row = range[1] + i - 1
    ---@type Celeste.Comment.LineCommentInfo.Line
    local info = { lead_ws_len = 0, offset = 0, ignore = false, csi = csi, row = row }
    local ws = line:match("^(%s*)")
    local ws_len = #ws

    if ws_len == #line then
      info.ignore = cfg.ignore_empty_lines == M.IGN_EMT.kAlways
      info.offset = cfg.line_comment_no_indent and 0 or #line
      info.lead_ws_len = ws_len
      info.all_blank = true
    else
      only_whitespace_lines = false
      info.offset = cfg.line_comment_no_indent and 0 or ws_len
      info.lead_ws_len = ws_len

      local match_res =
        H.match_line_comment(line, row, csi, { check_will_blank = cfg.ignore_empty_lines == M.IGN_EMT.kMixed })
      if match_res then
        info.lcs_pos = match_res.lcs_pos
        info.rcs_pos = match_res.rcs_pos
        info.will_blank = match_res.will_blank
        info.commented = (info.lcs_pos ~= nil or info.rcs_pos ~= nil)
      else
        all_info.should_remove = false
      end
    end

    if not info.ignore and not cfg.line_comment_no_indent then
      if not info.all_blank or cfg.ignore_empty_lines ~= M.IGN_EMT.kMixed then update_min_visible_col(line, info) end
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

    for i, info in ipairs(all_info.lines) do
      info.ignore = false

      if need_align_indent_for_blank then update_min_visible_col(lines[i], info) end
    end
  end

  -- align to min visible column
  if not cfg.line_comment_no_indent then
    min_visible_col = min_visible_col == math.huge and 0 or (math.floor(min_visible_col / indent_size) * indent_size)
    if not all_info.should_remove or action == M.ACT.kInvert then
      for i, line in ipairs(lines) do
        local info = all_info.lines[i]
        if not info.ignore then
          if info.all_blank and cfg.ignore_empty_lines == M.IGN_EMT.kMixed then
            info.offset = min_visible_col
          else
            info.offset = H.find_insert_offset(line, info.offset, min_visible_col, indent_size)
          end
        end
      end
    end
  end

  return all_info
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

  if info.all_blank and cfg.ignore_empty_lines == M.IGN_EMT.kMixed and info.offset > info.lead_ws_len then
    edits[#edits + 1] = {
      range = { row, info.lead_ws_len, row, info.lead_ws_len },
      text = { string.rep(" ", info.offset - info.lead_ws_len) .. csi.olcs },
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
function H.compute_line_edits(lines, range, motion, csi, cfg, action, opts)
  opts = opts or {}
  local all_edits = {} ---@type Celeste.Comment.TextEdits
  local all_info = H.line_comment_info(lines, csi, cfg, range, action, opts)

  for i, line in ipairs(lines) do
    local info = all_info.lines[i]
    if not info.ignore then
      local edits

      if action == M.ACT.kToggle then
        if all_info.should_remove then
          edits = H.make_uncomment_edits(info, line, cfg)
        else
          edits = H.make_comment_edits(info, line, cfg, range, opts)
        end
      elseif action == M.ACT.kInvert then
        if info.commented then
          edits = H.make_uncomment_edits(info, line, cfg)
        else
          edits = H.make_comment_edits(info, line, cfg, range, opts)
        end
      elseif action == M.ACT.kForceAdd then
        edits = H.make_comment_edits(info, line, cfg, range, opts)
      else
        -- kForceRemove
        assert(action == M.ACT.kForceRemove, "unknown action")
        if info.commented then edits = H.make_uncomment_edits(info, line, cfg) end
      end

      if edits then
        vim.list_extend(all_edits, edits)
        all_edits.need_sort = all_edits.need_sort or edits.need_sort
        all_edits.any_multi = all_edits.any_multi or edits.any_multi
      end
    end
  end

  return all_edits
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
  local fr, fc

  for i = 1, #lines do
    local line = lines[i]
    local start = i == 1 and math.min(sc + 1, #line + 1) or 1
    local pos = line:find("%S", start)
    if pos then
      fr, fc = sr + i - 1, pos - 1
      break
    end
  end
  if not fr then return end

  local fi = fr - sr + 1
  for i = #lines, fi, -1 do
    local line = lines[i]
    if i ~= fi and i ~= #lines then
      local e = line:match("^.*()%S")
      if e then return { fr, fc, sr + i - 1, e - 1 } end
    else
      local mpos = i == fi and fc + 1 or 1
      local epos = i == #lines and math.min(ec + 1, #line) or #line
      local last = H.skip_whitespace(line, epos, epos - mpos + 1, -1)
      if last >= mpos then return { fr, fc, sr + i - 1, last - 1 } end
    end
  end
end

---@param lines  string[]
---@param shrunk Celeste.Comment.Range4
---@param range  Celeste.Comment.Range4
---@param csi    Celeste.Comment.CommentStringInfo
---@param motion Celeste.Comment.Motion
---@return Celeste.Comment.BlockCommentInfo?
function H.match_block_comment(lines, shrunk, range, csi, motion)
  local start_row = shrunk[1]
  local scol, ecol = shrunk[2], shrunk[4]
  local n = shrunk[3] - start_row + 1
  local fi = start_row - range[1] + 1
  local l1 = lines[fi]
  local ln = lines[fi + n - 1]

  for _, v in ipairs(csi.pairs) do
    local tlcs_esc, trcs_esc = v.tesc[1], v.tesc[2]
    local tlcs_len = #v.traw[1]
    local trcs_len = #v.traw[2]
    local olcs, orcs = v.tout[1], v.tout[2]
    local pad_rcs = #orcs - trcs_len
    local slcs, elcs, srcs, ercs
    local matched = true

    if motion ~= "char" then
      local _, e = l1:find("^%s*" .. tlcs_esc)
      if not e then matched = false end
      if matched then
        slcs = e - tlcs_len + 1
        local mb = H.match_byte(l1, slcs - 1 + tlcs_len, olcs, tlcs_len, 1, csi.ci)
        elcs = slcs + tlcs_len + mb - 1
        srcs, ercs = ln:find(trcs_esc .. "%s*$")
        if not srcs then matched = false end
      end
      if matched then
        ercs = srcs + trcs_len - 1
        srcs = srcs - math.min(H.match_byte(ln, srcs - pad_rcs - 1, orcs, 0, 1, csi.ci), pad_rcs)
      end
    else
      local m = H.match_byte(l1, scol, olcs, 0, 1, csi.ci)
      if m < tlcs_len then matched = false end
      if matched then
        slcs = scol + 1
        elcs = scol + m
        local ec = ecol + 1
        local srcs_tmp = ec - trcs_len + 1
        if srcs_tmp < 1 or srcs_tmp > #ln then matched = false end
        if matched then
          if H.match_byte(ln, srcs_tmp - 1, v.traw[2], 0, 1, csi.ci) < trcs_len then matched = false end
        end
        if matched then
          if n == 1 and srcs_tmp <= slcs then matched = false end
        end
        if matched then
          srcs = srcs_tmp - math.min(H.match_byte(ln, math.max(srcs_tmp - pad_rcs - 1, 0), orcs, 0, 1, csi.ci), pad_rcs)
          ercs = ec
        end
      end
    end

    if matched then
      return { lcs_pos = { start_row, slcs - 1, elcs - 1 }, rcs_pos = { start_row + n - 1, srcs - 1, ercs - 1 } }
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
function H.compute_block_edits(lines, range, motion, csi, cfg, action, opts)
  local info = H.block_comment_info(lines, csi, motion, range, cfg)
  local edits ---@type Celeste.Comment.TextEdits

  if action == M.ACT.kToggle or action == M.ACT.kInvert then
    if info then
      edits = H.make_block_uncomment_edits(info)
    elseif motion == "char" then
      edits = H.make_block_partial_edits(lines, csi, range, opts)
    else
      edits = H.make_block_comment_edits(lines, csi, range, opts)
    end
  elseif action == M.ACT.kForceAdd then
    if motion == "char" then
      edits = H.make_block_partial_edits(lines, csi, range, opts)
    else
      edits = H.make_block_comment_edits(lines, csi, range, opts)
    end
  else
    -- kForceRemove
    assert(action == M.ACT.kForceRemove, "unknown action")
    if info then edits = H.make_block_uncomment_edits(info) end
  end
  return edits
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

function H.track_cursor_state() H.cursor_state = { cursor = H.make_cursor(0) } end

---@param cfg Celeste.Comment.Opts
function H.restore_cursor_state(cfg)
  if cfg.keep_cursor and H.cursor_state then vim.api.nvim_win_set_cursor(0, H.pos_to_cursor(H.cursor_state.cursor)) end
  H.cursor_state = nil
end

---@param state? Celeste.Comment.CursorStateTrack
---@param edits Celeste.Comment.TextEdits
---@param lines string[]
---@param range Celeste.Comment.Range4
---@param csi  Celeste.Comment.CommentStringInfo
function H.compute_cursor_state(state, edits, lines, range, csi)
  if not state then return end

  local orow, ocol = state.cursor.row, state.cursor.col
  local ncol, nrow = ocol, orow
  local eol_pos = #lines[orow - range[1] + 1]

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
          ncol = e.range[2]
        end
      end
    end
  end

  state.cursor = H.make_pos(state.cursor.buf, math.max(0, nrow), math.max(0, ncol))
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
  if ctype == M.CMT.kBlock then
    edits = H.compute_block_edits(lines, range, motion, csi, cfg, action, opts)
  else
    edits = H.compute_line_edits(lines, range, motion, csi, cfg, action, opts)
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
    execution_opts = opts,
  }
  if vim.is_callable(cfg.hooks.pre_commit_edits) then cfg.hooks.pre_commit_edits(ctx) end

  H.compute_cursor_state(cfg.keep_cursor and H.cursor_state or nil, ctx.edits, lines, range, ctx.csi)

  H.commit_edits(cursor.buf, ctx.range, lines, ctx.edits, ctx.o_use_set_text)

  H.restore_cursor_state(cfg)
end

---@param cfg Celeste.Comment.Opts
---@param cursor vim.Pos
---@param csi Celeste.Comment.CommentStringInfo
---@return Celeste.Comment.Range2?
function H.compute_linecomment_range(cfg, cursor, csi)
  local nlines = vim.api.nvim_buf_line_count(cursor.buf)
  local row = cursor.row + 1
  local line = vim.fn.getline(row)

  local function is_comment(lnum)
    local l = vim.fn.getline(lnum)
    if l:match("^%s*$") then return false end
    return H.match_line_comment(l, lnum - 1, csi, { check_only = true })
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

  return { lnum_from - 1, lnum_to - 1 }
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
                  plist[#plist + 1] = { ol, ocs, cl, cce }
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

---@param range? Celeste.Comment.Range2|Celeste.Comment.Range4
function H.select_range(range)
  if not range then return end

  if H.is_visual() then vim.cmd("normal! \27") end
  if #range == 2 then
    vim.cmd(("normal! %dGV%dG"):format(range[1] + 1, range[2] + 1))
  else
    vim.cmd(("normal! %dG%d|v%dG%d|"):format(range[1] + 1, range[2] + 1, range[3] + 1, range[4] + 1))
  end
end

---@param cfg Celeste.Comment.Opts
---@param cursor vim.Pos
---@return (Celeste.Comment.Range2|Celeste.Comment.Range4)?
---@return Celeste.Comment.CommentType?
---@return Celeste.Comment.CommentStringInfo?
function H.compute_x_comment_range(cfg, cursor)
  local cms_conf = H.make_cms_conf(cursor, cfg)
  if not cms_conf then return end

  local lcsi = H.make_csi_from_cms_conf(cms_conf, M.CMT.kLine, cfg, true)
  local bcsi = H.make_csi_from_cms_conf(cms_conf, M.CMT.kBlock, cfg, true)
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
  H.select_range((H.compute_x_comment_range(cfg, cursor)))
end

--- Auto-detect and remove comment
function H.uncomment_auto()
  if H.is_disabled() then return end
  H.track_cursor_state()

  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)

  local range, ctype, csi = H.compute_x_comment_range(cfg, cursor)
  if not range or not ctype or not csi then return end

  if ctype == M.CMT.kLine then range = { range[1], 0, range[2], 0 } end
  ---@cast range Celeste.Comment.Range4

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, range[1], range[3] + 1, false)
  if #lines == 0 then return end

  H.make_actionx(cfg, ctype, M.ACT.kToggle, lines, csi, range, ctype == M.CMT.kLine and "line" or "char", cursor)
end

-- Textobject: select contiguous linewise comment block
function H.textobject_linewise()
  if H.is_disabled() then return end

  local cfg = H.buf_config()

  if cfg.fallback_to_block ~= M.FBK2BLOCK.kNever then return H.textobject_auto() end

  local cursor = H.make_cursor(0)

  local csi = H.resolve(cursor, M.CMT.kLine, cfg)
  if not csi then return end
  H.select_range((H.compute_linecomment_range(cfg, cursor, csi)))
end

---Textobject: select blockwise comment that surrounds the cursor.
function H.textobject_blockwise()
  if H.is_disabled() then return end

  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)

  local csi = H.resolve(cursor, M.CMT.kBlock, cfg)
  if not csi then return end

  H.select_range((H.compute_blockcomment_range(cfg, cursor, csi)))
end

---@param kind 'above'|'below'|'eol'
function H.insert_comment(kind)
  if H.is_disabled() then return end

  local cfg = H.buf_config()
  local cursor = H.make_cursor(0)
  local buf = cursor.buf

  local csi = H.resolve(cursor, M.CMT.kLine, cfg)
  if not csi then return end

  if kind ~= "eol" then
    local target = cursor.row + (kind == "above" and 0 or 1)
    vim.api.nvim_buf_set_lines(buf, target, target, false, { csi.olcs .. csi.orcs })
    vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
    vim.cmd("normal! ==")
    local indent = #(vim.api.nvim_get_current_line():match("^(%s*)"))
    vim.api.nvim_win_set_cursor(0, { target + 1, indent + #csi.olcs })
  else
    local line = vim.api.nvim_get_current_line()
    if line:find("^%s*$") then
      vim.api.nvim_buf_set_text(buf, cursor.row, 0, cursor.row, 0, { csi.olcs .. csi.orcs })
      vim.cmd("normal! ==")
      local indent = #(vim.api.nvim_get_current_line():match("^(%s*)"))
      vim.api.nvim_win_set_cursor(0, { cursor.row + 1, indent + #csi.olcs })
    else
      vim.api.nvim_buf_set_text(buf, cursor.row, #line, cursor.row, #line, { " " .. csi.olcs .. csi.orcs })
      vim.api.nvim_win_set_cursor(0, { cursor.row + 1, #line + 1 + #csi.olcs })
    end
  end
  if csi.trcs ~= "" then
    vim.cmd("startinsert")
  else
    vim.cmd("startinsert!")
  end
end

---@param cursor vim.Pos
---@param range  Celeste.Comment.Range4
---@param ctype  Celeste.Comment.CommentType
---@param action Celeste.Comment.Action
---@param motion Celeste.Comment.Motion
---@param opts?  Celeste.Comment.ExecutionOpts
function H.make_action_range(cursor, range, ctype, action, motion, opts)
  if H.is_disabled() then return end
  opts = opts or {}

  local cfg = H.buf_config(opts.cfg)

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, range[1], range[3] + 1, false)
  if #lines == 0 then return end

  local csi, resolved_ctype = H.resolve(cursor, ctype, cfg, range)
  if not csi or not resolved_ctype then return end

  H.make_actionx(cfg, resolved_ctype, action, lines, csi, range, motion, cursor, opts)
end

--- Track cursor position
function M.track_cursor() H.track_cursor_state() end

---@param ctype Celeste.Comment.CommentType
---@param opts? Celeste.Comment.ExecutionOpts
---@return fun():string
function H.make_operator(ctype, opts)
  opts = opts or {}
  local s = type(opts.suffix) == "string" and opts.suffix or ""
  local action = opts.action or M.ACT.kToggle
  local o = { cfg = opts.cfg }

  ---@param motion Celeste.Comment.Motion
  local f = function(motion)
    -- actually, at the region start position, it may not be the same as `cursor_state`
    local cursor = H.make_cursor(0)
    local range = H.get_selection_range(cursor.buf)
    if not range then return end

    -- TODO: should we always expand selection to line boundaries if fallback to block?
    H.make_action_range(cursor, range, ctype, action, motion, o)
  end

  return function()
    if H.is_disabled() then return "" end
    H.track_cursor_state()

    _G.__celeste_comment_operator_func = f
    vim.o.operatorfunc = "v:lua.__celeste_comment_operator_func"
    return "g@" .. s
  end
end

---@param config? Celeste.Comment.Opts
function M.setup(config)
  config = vim.tbl_deep_extend("force", vim.deepcopy(H.config), config or {})
  vim.validate("keep_cursor", config.keep_cursor, "boolean", true, "boolean")
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
  end)
  vim.validate("case_insensitive", config.case_insensitive, "boolean", true, "boolean")
  vim.validate("block_relaxed_detect", config.block_relaxed_detect, "boolean", true, "boolean")
  vim.validate("block_textobj_nlines", config.block_textobj_nlines, "number", true, "number")
  vim.validate("mappings", config.mappings, "table", true, "table")
  vim.validate("cms_confs", config.cms_confs, "table", true, "table")
  vim.validate("log_level", config.log_level, "number", true, "vim.log.levels")
  for k, v in pairs(config.mappings) do
    vim.validate("mappings." .. k, v, { "string", "table" }, true, "string or string[]")
  end
  vim.validate("hooks", config.hooks, "table", true, "table")
  vim.validate("pre_commit_edits", config.hooks.pre_commit_edits, "callable", true, "callable")
  vim.validate("cms_conf_resolver", config.hooks.cms_conf_resolver, "callable", true, "callable")

  H.config = config

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
  local op_toggle           = H.make_operator(M.CMT.kLine)
  local op_toggle_cur       = H.make_operator(M.CMT.kLine, { suffix = "_" })
  local op_block_toggle     = H.make_operator(M.CMT.kBlock)
  local op_block_toggle_cur = H.make_operator(M.CMT.kBlock, { suffix = "_" })
  local op_invert           = H.make_operator(M.CMT.kLine, { action = M.ACT.kInvert })
  local op_force_add        = H.make_operator(M.CMT.kLine, { action = M.ACT.kForceAdd })
  local op_force_rmv        = H.make_operator(M.CMT.kLine, { action = M.ACT.kForceRemove })

  map("n", m.line_toggle,        op_toggle,           { expr = true, desc = "Comment by motion" })
  map("n", m.line_toggle_cur,    op_toggle_cur,       { expr = true, desc = "Comment current line" })
  map("x", m.line_toggle_visual, op_toggle,           { expr = true, desc = "Comment selection" })
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

  map("n", m.dot_repeat, function()
    H.track_cursor_state()
    return "."
  end, { expr = true, desc = "Dot-repeat track cursor for celeste_comment.nvim" })

  map("i", m.line_toggle_insert, function()
    H.track_cursor_state()
    local cursor = H.make_cursor(0)
    local range = { cursor.row, cursor.col, cursor.row, cursor.col }
    H.make_action_range(cursor, range, M.CMT.kLine, M.ACT.kToggle, "line", { insmode = true })
  end, { desc = "Toggle line comment at insert mode" })
end

-- test only
M.H = H

return M
