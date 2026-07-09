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
M.IGN_EMT = {
  --- Comment/uncomment empty lines. Blank lines participate in
  --- indentation alignment.
  kNever = "never",
  --- Toggle empty lines but exclude them from indentation alignment.
  --- Also trim a line to blank when uncommenting leaves only whitespace.
  kIndent = "indent",
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

---@class Celeste.Comment.TextEdit
---@field range Celeste.Comment.Range4
---@field text  string[]

---@class Celeste.Comment.TextEdits
---@field [integer] Celeste.Comment.TextEdit
---@field any_multi? boolean some edit have multiple lines

---@class Celeste.Comment.CommentStringConf
---@field [1] (string|string[])?
---@field [2] string?

---@alias Celeste.Comment.CommentStringConfs {[1]:string, [2]:(Celeste.Comment.CommentStringConf|fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx))}

---@class Celeste.Comment.CommentStringInfo
---@field ci         boolean                   -- case-insensitive
---@field wrapped    boolean                   -- comment string was wrapped
---@field tlcs       string                    -- vim.trim(lcs)
---@field trcs       string                    -- vim.trim(rcs)
---@field olcs       string                    -- output: pad=true->tlcs+" ", else->lcs
---@field orcs       string                    -- output: pad=true->" "+trcs, else->rcs
---@field tlrcs_esc  {[1]:string,[2]:string}[] -- esc pairs, sorted by lcs length desc
---@field tlcs_esc   string                    -- alias of tlrcs_esc[1][1]
---@field trcs_esc   string                    -- alias of tlrcs_esc[1][2]

---@class Celeste.Comment.LineCommentInfo.Line
---@field offset      integer 0-indexed column where comment marker should be inserted
---@field ignore      boolean should thie line be ignored?
---@field csi         Celeste.Comment.CommentStringInfo comment string info
---@field lcs_pos     Celeste.Comment.Range3? position of lcs
---@field rcs_pos     Celeste.Comment.Range3? position of rcs
---@field commented?  boolean
---@field all_blank?  boolean blank line
---@field will_blank? boolean not blank, but will be blank after remove lcs and rcs, current only available with ignore_empty_lines = 'indent'

---@class Celeste.Comment.LineCommentInfo
---@field lines         Celeste.Comment.LineCommentInfo.Line[]
---@field should_remove boolean

---@class Celeste.Comment.BlockCommentInfo
---@field lcs_pos Celeste.Comment.Range3
---@field rcs_pos Celeste.Comment.Range3

---@class Celeste.Comment.Hooks.PreSyncEdits.Ctx
---@field cursor          vim.Pos
---@field range           Celeste.Comment.Range4
---@field edits           Celeste.Comment.TextEdits
---@field cfg             Celeste.Comment.Opts
---@field ctype           Celeste.Comment.CommentType
---@field motion          Celeste.Comment.Motion
---@field csi             Celeste.Comment.CommentStringInfo
---@field lines           string[]
---@field o_use_set_text? boolean o: means output from user

---@class Celeste.Comment.Hooks.CmsConfResolver.Ctx
---@field cursor      vim.Pos
---@field range?      Celeste.Comment.Range4
---@field cfg         Celeste.Comment.Opts
---@field o_cms_conf? Celeste.Comment.CommentStringConf
---@field tree?       vim.treesitter.LanguageTree

---@class Celeste.Comment.Hooks
---@field pre_sync_edits?    fun(ctx:Celeste.Comment.Hooks.PreSyncEdits.Ctx)
---@field cms_conf_resolver? fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx)

---@class Celeste.Comment.Opts.Mapping
---@field comment?          string mode 'n', operator, default 'gc'
---@field comment_line?     string mode 'n', default 'gcc'
---@field comment_visual?   string mode 'x', default 'gc'
---@field block?            string mode 'n', operator, default 'gb'
---@field block_line?       string mode 'n', default 'gbc'
---@field block_visual?     string mode 'x', default 'gb'
---@field textobject_line?  string mode 'o', linewise textobject, like 'gc', default ''
---@field textobject_block? string mode 'o', blockwise textobject, like 'gb', default ''
---@field textobject_auto?  string mode 'o', auto detect textobject, default 'ga'
---@field comment_below?    string mode 'n', comment below, 'gco'
---@field comment_above?    string mode 'n', comment above, 'gcO'
---@field comment_eol?      string mode 'n', comment eol, 'gcA'
---@field uncomment_auto?   string mode 'n', auto detect and uncomment, 'gcu'
---@field invert?           string mode 'nx', invert comment per line, ''

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

---@type Celeste.Comment.Range2?
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
  ignore_empty_lines        = M.IGN_EMT.kIndent,
  fallback_to_block         = M.FBK2BLOCK.kIfLineCmsWrapped,
  log_level                 = vim.log.levels.OFF,

  mappings = {
    comment                 = "gc",
    comment_line            = "gcc",
    comment_visual          = "gc",

    block                   = "gb",
    block_line              = "gbc",
    block_visual            = "gb",

    textobject_line         = "gc",
    textobject_block        = "gb",
    textobject_auto         = "",
    uncomment_auto          = "",

    comment_below           = "",
    comment_above           = "",
    comment_eol             = "",
    invert                  = "",
  },

  hooks = {
    pre_sync_edits          = nil,
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

---@param level vim.log.levels
---@return boolean
function H.should_log(level) return level >= H.config.log_level end

---@param level vim.log.levels
---@vararg any
function H.log(level, ...)
  if level < H.config.log_level then return end
  if not H._logger then H._logger = vim.log.new({ name = "celeste_comment", current_level = H.config.log_level }) end
  if H._logger then H._logger[log_level_to_name[level]](...) end
end

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
function H.is_disabled() return vim.g.celeste_comment_disable == true or vim.b.celeste_comment_disable == true end

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
  local tpairs = vim.iter(pairs):map(function(p) return { vim.trim(p[1]), vim.trim(p[2]) } end):totable()

  table.sort(tpairs, function(a, b)
    local la, lb = a[1], b[1]
    if #la ~= #lb then return #la > #lb end
    return la > lb
  end)

  local tlrcs_esc = {}
  for _, p in ipairs(tpairs) do
    if p[1] ~= "" or p[2] ~= "" then
      local tlcs_esc = opts.ci and H.pattern_ci(vim.pesc(p[1])) or vim.pesc(p[1])
      local trcs_esc = opts.ci and H.pattern_ci(vim.pesc(p[2])) or vim.pesc(p[2])
      tlrcs_esc[#tlrcs_esc + 1] = { tlcs_esc, trcs_esc }
    end
  end

  if #tlrcs_esc == 0 then return end

  local olcs, orcs
  local tplcs, tprcs = vim.trim(pairs[1][1]), vim.trim(pairs[1][2])
  if opts.pad then
    olcs = tplcs == "" and "" or (tplcs .. " ")
    orcs = tprcs == "" and "" or (" " .. tprcs)
  else
    olcs, orcs = pairs[1][1], pairs[1][2]
  end

  ---@type Celeste.Comment.CommentStringInfo
  local res = {
    tlrcs_esc = tlrcs_esc,
    tlcs_esc = tlrcs_esc[1][1],
    trcs_esc = tlrcs_esc[1][2],
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
  local v_kline = cms_conf[M.CMT.kLine]
  local t_kline = type(v_kline)
  if t_kline == "string" then
    v_kline = { v_kline }
  elseif t_kline ~= "table" or #v_kline == 0 then
    v_kline = { "" }
  else
    for i, v in ipairs(v_kline) do
      if type(v) ~= "string" then v_kline[i] = "" end
    end
  end

  local v_kblock = cms_conf[M.CMT.kBlock]
  local t_kblock = type(v_kblock)
  if t_kblock ~= "string" then v_kblock = "" end
  cms_conf[M.CMT.kLine] = v_kline
  cms_conf[M.CMT.kBlock] = v_kblock
end

---@param cursor vim.Pos
---@return vim.treesitter.LanguageTree?
function H.language_tree_resolve(cursor)
  local ok, parser = pcall(vim.treesitter.get_parser, cursor.buf, "")
  if not ok or parser == nil then return end

  ---@type Range4
  local range = { cursor.row, cursor.col, cursor.row, cursor.col }
  local result = parser
  parser:for_each_tree(function(_, ltree)
    if ltree:lang() ~= "comment" and ltree:contains(range) then result = ltree end
  end)

  return result
end

---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
function H.buffer_fallback_cms_conf_resolver(ctx)
  local line_cs = vim.bo[ctx.cursor.buf].commentstring
  local block_cs = vim.b[ctx.cursor.buf].celeste_comment_block_commentstring
  if line_cs or block_cs then ctx.o_cms_conf = { line_cs, block_cs } end
end

---@param ctx Celeste.Comment.Hooks.CmsConfResolver.Ctx
function H.builtin_cms_conf_resolver(ctx)
  if ctx.cfg.cms_confs == false then return end

  local line = vim.fn.getline(ctx.cursor.row + 1)
  local start_col = line:match("^%s*()")
  if start_col then ctx.cursor = vim.pos.cursor(ctx.cursor.buf, { ctx.cursor.row + 1, start_col - 1 }) end

  local ltree = H.language_tree_resolve(ctx.cursor)
  local lang = ltree and ltree:lang() or vim.bo[ctx.cursor.buf].filetype
  if not lang then return end

  local t = (type(ctx.cfg.cms_confs) == "table" and ctx.cfg.cms_confs[lang]) or H.comment_string_confs[lang]
  if not t then return end

  if vim.is_callable(t) then
    ---@cast t fun(ctx:Celeste.Comment.Hooks.CmsConfResolver.Ctx)
    ctx.tree = ltree
    return t(ctx)
  end

  ctx.o_cms_conf = t
end

---@param cursor vim.Pos
---@param cfg    Celeste.Comment.Opts
---@param range? Celeste.Comment.Range4
---@return Celeste.Comment.CommentStringConf?
function H.make_cms_conf(cursor, cfg, range)
  local resolvers =
    { cfg.hooks.cms_conf_resolver or "", H.builtin_cms_conf_resolver, H.buffer_fallback_cms_conf_resolver }

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
  if ctype == M.CMT.kBlock and (pairs[1][1] == "" or pairs[1][2] == "") then
    if not silent then
      vim.api.nvim_echo(
        { { "Invalid ", "WarningMsg" }, { "blockwise commentstring : " }, { ("%s"):format(vim.inspect(pairs)) } },
        true,
        {}
      )
    end
    return
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
  for _, pair in ipairs(csi.tlrcs_esc) do
    local tlcs_esc, trcs_esc = pair[1], pair[2]
    local suffix = #trcs_esc > 0 and "(.-)()" .. trcs_esc .. "()%s*$" or "(.-)%s*$"
    local s, _e, p1, p2, content, p3, p4 = line:find("^%s*()" .. tlcs_esc .. "()" .. suffix)
    if s then
      if opts and opts.check_only then return true end

      local lcs_pos
      if tlcs_esc ~= "" then
        local matched = H.match_byte(line, p2 - 1, csi.olcs, #csi.tlcs, 1, csi.ci)
        lcs_pos = { row, p1 - 1, p2 + matched - 2 }
      end
      local rcs_pos
      if trcs_esc ~= "" and p3 then
        local matched = H.match_byte(line, p3 - 2, csi.orcs, 0, -1, csi.ci)
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
---@param opts?  {invert?: boolean}
---@return Celeste.Comment.LineCommentInfo
function H.line_comment_info(lines, csi, cfg, range, opts)
  opts = opts or {}
  range = range or { 0 }
  ---@type Celeste.Comment.LineCommentInfo
  local all_info = { lines = {}, should_remove = true }
  local indent_size = vim.bo.tabstop
  local only_whitespace_lines = true
  local min_visible_col = math.huge

  for i, line in ipairs(lines) do
    local row = range[1] + i - 1
    ---@type Celeste.Comment.LineCommentInfo.Line
    local info = { offset = 0, ignore = false, csi = csi }
    local ws = line:match("^(%s*)")
    local ws_len = #ws

    if ws_len == #line then
      info.ignore = cfg.ignore_empty_lines == M.IGN_EMT.kAlways
      info.offset = cfg.line_comment_no_indent and 0 or #line
      info.all_blank = true
    else
      only_whitespace_lines = false
      info.offset = cfg.line_comment_no_indent and 0 or ws_len

      local match_res =
        H.match_line_comment(line, row, csi, { check_will_blank = cfg.ignore_empty_lines == M.IGN_EMT.kIndent })
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
      if ws_len < #line or cfg.ignore_empty_lines ~= M.IGN_EMT.kIndent then
        local cur_visible_col = 0
        for j = 1, info.offset do
          if cur_visible_col >= min_visible_col then break end
          cur_visible_col = H.next_visible_column(cur_visible_col, line:byte(j), indent_size)
        end
        if cur_visible_col < min_visible_col then min_visible_col = cur_visible_col end
      end
    end

    all_info.lines[#all_info.lines + 1] = info
  end

  -- force add when all non-ignored lines are blank
  if all_info.should_remove and only_whitespace_lines then
    all_info.should_remove = false
    for _, info in ipairs(all_info.lines) do
      info.ignore = false
    end
  end

  -- align to min visible column
  if not cfg.line_comment_no_indent then
    min_visible_col = min_visible_col == math.huge and 0 or (math.floor(min_visible_col / indent_size) * indent_size)
    if not all_info.should_remove or opts.invert then
      for i, line in ipairs(lines) do
        local info = all_info.lines[i]
        if not info.ignore then
          if info.all_blank and cfg.ignore_empty_lines == M.IGN_EMT.kIndent then
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

---@param line string
---@param row  integer
---@param cfg  Celeste.Comment.Opts
---@param info Celeste.Comment.LineCommentInfo.Line
---@return Celeste.Comment.TextEdits
function H.make_comment_edits(line, row, cfg, info)
  local csi = info.csi
  local edits = {}
  local offset = cfg.line_comment_no_indent and 0 or info.offset
  if info.all_blank and cfg.ignore_empty_lines == M.IGN_EMT.kIndent and offset > 0 then
    edits[#edits + 1] = { range = { row, 0, row, 0 }, text = { string.rep(" ", offset) .. csi.olcs } }
  else
    edits[#edits + 1] = { range = { row, offset, row, offset }, text = { csi.olcs } }
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
  if info.will_blank and cfg.ignore_empty_lines == M.IGN_EMT.kIndent then
    -- like nvim builtin comment, trim blankline if ignore_empty_lines == 'indent'
    edits[#edits + 1] = { range = { info.lcs_pos[1], 0, info.lcs_pos[1], #line }, text = { "" } }
  else
    if info.lcs_pos then
      edits[#edits + 1] =
        { range = { info.lcs_pos[1], info.lcs_pos[2], info.lcs_pos[1], info.lcs_pos[3] + 1 }, text = { "" } }
    end

    if info.rcs_pos then
      edits[#edits + 1] =
        { range = { info.rcs_pos[1], info.rcs_pos[2], info.rcs_pos[1], info.rcs_pos[3] + 1 }, text = { "" } }
    end
  end
  return edits
end

---@param lines  string[]
---@param csi    Celeste.Comment.CommentStringInfo
---@param cfg    Celeste.Comment.Opts
---@param range  Celeste.Comment.Range4
---@param opts?  {invert?: boolean}
---@return Celeste.Comment.TextEdits
function H.compute_line_edits(lines, csi, cfg, range, opts)
  opts = opts or {}
  local all_edits = {} ---@type Celeste.Comment.TextEdits
  local all_info = H.line_comment_info(lines, csi, cfg, range, opts)

  for i, line in ipairs(lines) do
    local info = all_info.lines[i]
    if not info.ignore then
      local edits, should_remove
      local row = range[1] + i - 1

      if not opts.invert then
        should_remove = all_info.should_remove
      else
        should_remove = info.commented
      end

      if should_remove then
        edits = H.make_uncomment_edits(info, line, cfg)
      else
        edits = H.make_comment_edits(line, row, cfg, info)
      end

      if edits then vim.list_extend(all_edits, edits) end
    end
  end

  return all_edits
end

---@param lines string[]
---@param csi   Celeste.Comment.CommentStringInfo
---@param range Celeste.Comment.Range4
---@return Celeste.Comment.TextEdits
function H.make_block_comment_edits(lines, csi, range)
  local n = #lines
  local l1 = lines[1]
  local ln = lines[n]
  local edits = {} ---@type Celeste.Comment.TextEdits

  local lcs_col = H.skip_whitespace(l1, 1, #l1, 1) - 1
  if lcs_col == #l1 then lcs_col = 0 end

  edits[#edits + 1] = { range = { range[1], lcs_col, range[1], lcs_col }, text = { csi.olcs } }

  if n > 1 then
    edits[#edits + 1] = { range = { range[1] + n - 1, #ln, range[1] + n - 1, #ln }, text = { csi.orcs } }
  else
    edits[#edits + 1] = { range = { range[1], #l1, range[1], #l1 }, text = { csi.orcs } }
  end

  return edits
end

---@param lines     string[]
---@param csi       Celeste.Comment.CommentStringInfo
---@param scol      integer
---@param ecol      integer
---@param start_row integer 0-indexed buffer row of lines[1]
---@return Celeste.Comment.TextEdits
function H.make_block_partial_edits(lines, csi, scol, ecol, start_row)
  start_row = start_row or 0
  local n = #lines
  local edits = {} ---@type Celeste.Comment.TextEdits

  local rcs_col = math.min(ecol + 1, #lines[n])

  edits[#edits + 1] = { range = { start_row, scol, start_row, scol }, text = { csi.olcs } }
  if n == 1 then
    edits[#edits + 1] = { range = { start_row, rcs_col, start_row, rcs_col }, text = { csi.orcs } }
  else
    edits[#edits + 1] = { range = { start_row + n - 1, rcs_col, start_row + n - 1, rcs_col }, text = { csi.orcs } }
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
---@param csi    Celeste.Comment.CommentStringInfo
---@param scol   integer
---@param ecol   integer
---@param motion Celeste.Comment.Motion
---@param range  Celeste.Comment.Range4
---@param cfg?   Celeste.Comment.Opts
---@return Celeste.Comment.BlockCommentInfo?
function H.block_comment_info(lines, csi, scol, ecol, motion, range, cfg)
  range = range or { 0 }
  local n = #lines
  local l1 = lines[1]
  local ln = lines[n]

  if cfg and cfg.block_relaxed_detect then
    local shrunk = H.shrink_region(lines, range)
    if not shrunk then return end
    local fi = shrunk[1] - range[1] + 1
    n = shrunk[3] - shrunk[1] + 1
    l1 = lines[fi]
    ln = lines[fi + n - 1]
    scol, ecol = shrunk[2], shrunk[4]
    range = shrunk
  end

  local slcs, elcs, srcs, ercs

  if motion ~= "char" then
    local _, e = l1:find("^%s*" .. csi.tlcs_esc)
    if not e then return end
    slcs = e - #csi.tlcs + 1
    elcs = slcs + H.match_byte(l1, slcs - 1, csi.olcs, 0, 1, csi.ci) - 1
    srcs, ercs = ln:find(csi.trcs_esc .. "%s*$")
    if not srcs then return end
    ercs = srcs + #csi.trcs - 1
    local pad_rcs = #csi.orcs - #csi.trcs
    srcs = srcs - math.min(H.match_byte(ln, srcs - pad_rcs - 1, csi.orcs, 0, 1, csi.ci), pad_rcs)
  else
    local matched = H.match_byte(l1, scol, csi.olcs, 0, 1, csi.ci)
    if matched < #csi.tlcs then return end
    slcs = scol + 1
    elcs = scol + matched

    local ec = ecol + 1
    local srcs_tmp = ec - #csi.trcs + 1
    if srcs_tmp < 1 or srcs_tmp > #ln then return end
    if H.match_byte(ln, srcs_tmp - 1, csi.trcs, 0, 1, csi.ci) < #csi.trcs then return end
    if n == 1 and srcs_tmp <= slcs then return end
    local pad_rcs = #csi.orcs - #csi.trcs
    srcs = srcs_tmp - math.min(H.match_byte(ln, math.max(srcs_tmp - pad_rcs - 1, 0), csi.orcs, 0, 1, csi.ci), pad_rcs)
    ercs = ec
  end

  return { lcs_pos = { range[1], slcs - 1, elcs - 1 }, rcs_pos = { range[1] + n - 1, srcs - 1, ercs - 1 } }
end

---@param lines  string[]
---@param csi    Celeste.Comment.CommentStringInfo
---@param range  Celeste.Comment.Range4
---@param motion Celeste.Comment.Motion
---@param cfg?   Celeste.Comment.Opts
---@return Celeste.Comment.TextEdits
function H.compute_block_edits(lines, csi, range, motion, cfg)
  local info = H.block_comment_info(lines, csi, range[2], range[4], motion, range, cfg)
  local edits ---@type Celeste.Comment.TextEdits

  if info then
    edits = H.make_block_uncomment_edits(info)
  elseif motion == "char" then
    edits = H.make_block_partial_edits(lines, csi, range[2], range[4], range[1])
  else
    edits = H.make_block_comment_edits(lines, csi, range)
  end
  return edits
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
function H.sync_edits(buf, range, lines, edits, use_set_text)
  if #edits == 0 then return end

  if use_set_text or edits.any_multi then
    local max = vim.api.nvim_buf_line_count(buf)
    for i = #edits, 1, -1 do
      local e = edits[i]
      if max <= e.range[1] then
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

function H.track_cursor_state() H.cursor_state = vim.api.nvim_win_get_cursor(0) end

---@param cfg Celeste.Comment.Opts
function H.restore_cursor_state(cfg)
  if cfg.keep_cursor and H.cursor_state then vim.api.nvim_win_set_cursor(0, H.cursor_state) end
  H.cursor_state = nil
end

---@param cursor_state? Celeste.Comment.Range2
---@param edits Celeste.Comment.TextEdits
function H.compute_cursor_state(cursor_state, edits)
  if not cursor_state then return end

  local orow = cursor_state[1] -- 1-indexed
  local ocol = cursor_state[2]
  local ncol, nrow = ocol, orow
  for i = #edits, 1, -1 do
    local e = edits[i]
    if e.range[1] == orow - 1 then
      if #e.text > 1 then
        nrow = nrow + #e.text - 1
        if ocol >= e.range[4] then ncol = ncol + #e.text[1] - (e.range[4] - e.range[2]) end
      elseif e.range[2] == e.range[4] then
        if ocol >= e.range[2] then ncol = ncol + #e.text[1] end
      else
        if ocol >= e.range[4] then
          ncol = ncol + #e.text[1] - (e.range[4] - e.range[2])
        elseif ocol > e.range[2] then
          ncol = e.range[2]
        end
      end
    elseif e.range[1] < orow - 1 and #e.text > 1 then
      nrow = nrow + #e.text - 1
    end
  end
  cursor_state[1], cursor_state[2] = math.max(1, nrow), math.max(0, ncol)
end

---@param cfg Celeste.Comment.Opts
---@param ctype Celeste.Comment.CommentType
---@param lines string[]
---@param csi Celeste.Comment.CommentStringInfo
---@param range Celeste.Comment.Range4
---@param motion Celeste.Comment.Motion
---@param cursor vim.Pos
---@param opts? {invert:boolean}
function H.togglex(cfg, ctype, lines, csi, range, motion, cursor, opts)
  opts = opts or {}
  local edits ---@type Celeste.Comment.TextEdits
  if ctype == M.CMT.kBlock then
    edits = H.compute_block_edits(lines, csi, range, motion, cfg)
  else
    edits = H.compute_line_edits(lines, csi, cfg, range, opts)
  end
  assert(edits, "unexpected error, nil edits")

  ---@type Celeste.Comment.Hooks.PreSyncEdits.Ctx
  local ctx = {
    cursor = cursor,
    cfg = cfg,
    ctype = ctype,
    edits = edits,
    motion = motion,
    range = range,
    csi = csi,
    lines = lines,
  }
  if vim.is_callable(cfg.hooks.pre_sync_edits) then cfg.hooks.pre_sync_edits(ctx) end

  H.sync_edits(cursor.buf, ctx.range, lines, ctx.edits, ctx.o_use_set_text)

  H.compute_cursor_state(cfg.keep_cursor and H.cursor_state or nil, ctx.edits)

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
  local lcs_esc, rcs_esc = csi.tlcs_esc, csi.trcs_esc
  local lcs_len, rcs_len = #csi.tlcs, #csi.trcs
  local nlines = #lines
  local cursor_row, cursor_col = cursor.row + 1, cursor.col
  local lrcs_eq = lcs_esc == rcs_esc
  local stack = {}
  local pairs = {}

  local function inner(ol, ocs, cl, cce)
    if not (ol <= cursor_row and cursor_row <= cl) then return false end
    if ol == cl then return ocs <= cursor_col and cursor_col <= cce end
    if ol == cursor_row then return ocs <= cursor_col end
    if cl == cursor_row then return cursor_col <= cce end
    return true
  end

  for i = 1, nlines do
    local line = lines[i]
    local ln = lbegin - 1 + i
    local pos = 1

    while pos <= #line do
      local opos = line:find(lcs_esc, pos)
      local cpos = lrcs_eq and opos or line:find(rcs_esc, pos)

      if not opos and not cpos then break end

      if H.should_log(vim.log.levels.TRACE) then
        H.log(vim.log.levels.TRACE, ("ln:%s opos:%s cpos:%s stack:%s"):format(ln, opos, cpos, vim.inspect(stack)))
      end

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

          H.log(vim.log.levels.TRACE, ("open:{%s, %s} close:{%s, %s}"):format(ol, ocs, cl, cce))

          assert(ol <= cl)
          if inner(ol, ocs, cl, cce) then pairs[#pairs + 1] = { ol, ocs, cl, cce } end
          pos = cpos + rcs_len
        else
          pos = cpos + rcs_len
        end
      end
    end
  end

  return pairs
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
  if #csi.tlcs == 0 or #csi.trcs == 0 then return end

  local lines = vim.api.nvim_buf_get_lines(buf, ts_range[1], ts_range[3] + 1, false)
  local first, last = lines[1], lines[#lines]
  if not first or not last then return end

  if H.match_byte(first, ts_range[2], csi.tlcs, 0, 1, csi.ci) ~= #csi.tlcs then return end
  if H.match_byte(last, ts_range[4] - #csi.trcs + 1, csi.trcs, 0, 1, csi.ci) ~= #csi.trcs then return end

  return ts_range
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
function M.textobject_auto()
  if H.is_disabled() then return end
  local cfg = H.buf_config()
  local cursor = vim.pos.cursor(0)
  H.select_range((H.compute_x_comment_range(cfg, cursor)))
end

--- Auto-detect and remove comment
function H.uncomment_auto()
  if H.is_disabled() then return end
  H.track_cursor_state()

  local cfg = H.buf_config()
  local cursor = vim.pos.cursor(0)

  local range, ctype, csi = H.compute_x_comment_range(cfg, cursor)
  if not range or not ctype or not csi then return end

  if ctype == M.CMT.kLine then range = { range[1], 0, range[2], 0 } end
  ---@cast range Celeste.Comment.Range4

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, range[1], range[3] + 1, false)
  if #lines == 0 then return end

  H.togglex(cfg, ctype, lines, csi, range, ctype == M.CMT.kLine and "line" or "char", cursor)
end

-- Textobject: select contiguous linewise comment block
function M.textobject_linewise()
  if H.is_disabled() then return end

  local cfg = H.buf_config()

  if cfg.fallback_to_block ~= M.FBK2BLOCK.kNever then return M.textobject_auto() end

  local cursor = vim.pos.cursor(0)

  local csi = H.resolve(cursor, M.CMT.kLine, cfg)
  if not csi then return end
  H.select_range((H.compute_linecomment_range(cfg, cursor, csi)))
end

---Textobject: select blockwise comment that surrounds the cursor.
function M.textobject_blockwise()
  if H.is_disabled() then return end

  local cfg = H.buf_config()
  local cursor = vim.pos.cursor(0)

  local csi = H.resolve(cursor, M.CMT.kBlock, cfg)
  if not csi then return end

  H.select_range((H.compute_blockcomment_range(cfg, cursor, csi)))
end

---@param kind 'above'|'below'|'eol'
function M.insert_comment(kind)
  if H.is_disabled() then return end

  local cfg = H.buf_config()
  local cursor = vim.pos.cursor(0)
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

---@param ctype  Celeste.Comment.CommentType
---@param motion Celeste.Comment.Motion
---@param opts?  {invert?: boolean, cfg?:Celeste.Comment.Opts}
function H.operator_impl(ctype, motion, opts)
  opts = opts or {}
  local cfg = H.buf_config(opts.cfg)
  -- actually, at the region start position, it may not be the same as `cursor_state`
  local cursor = vim.pos.cursor(0)

  local range = H.get_selection_range(cursor.buf)
  if not range then return end

  local lines = vim.api.nvim_buf_get_lines(cursor.buf, range[1], range[3] + 1, false)
  if #lines == 0 then return end

  local csi, resolved_ctype = H.resolve(cursor, ctype, cfg, range)
  if not csi or not resolved_ctype then return end

  -- TODO: should we always expand selection to line boundaries if fallback to block?
  H.togglex(cfg, resolved_ctype, lines, csi, range, motion, cursor, opts)
end

---@param ctype Celeste.Comment.CommentType
---@param opts? {suffix?: string, invert?: boolean, cfg?: Celeste.Comment.Opts}
---@return fun():string
function M.make_operator(ctype, opts)
  opts = opts or {}
  local s = type(opts.suffix) == "string" and opts.suffix or ""
  local o = { invert = opts.invert, cfg = opts.cfg }

  ---@param motion Celeste.Comment.Motion
  local f = function(motion) H.operator_impl(ctype, motion, o) end

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
    if type(v) ~= "string" then return false, ("expected 'never'|'indent'|'always' but got type:%s"):format(type(v)) end
    return vim.iter({ "never", "indent", "always" }):any(function(z) return z == v end),
      ("expected 'never'|'indent'|'always' but got %s"):format(v)
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
    vim.validate("mappings." .. k, v, "string", true, "string")
  end
  vim.validate("hooks", config.hooks, "table", true, "table")
  vim.validate("pre_sync_edits", config.hooks.pre_sync_edits, "callable", true, "callable")

  H.config = config

  local m = H.config.mappings --[[@as Celeste.Comment.Opts.Mapping]]

  ---@param mode string|string[]
  ---@param lhs string
  ---@param rhs string|function
  ---@param opts vim.keymap.set.Opts
  local function map(mode, lhs, rhs, opts)
    if lhs == nil or lhs == "" then return end
    vim.keymap.set(mode, lhs, rhs, opts or {})
  end

  -- stylua: ignore start
  local op_line   = M.make_operator(M.CMT.kLine)
  local op_line_  = M.make_operator(M.CMT.kLine, { suffix = "_" })
  local op_block  = M.make_operator(M.CMT.kBlock)
  local op_block_ = M.make_operator(M.CMT.kBlock, { suffix = "_" })
  local op_invert = M.make_operator(M.CMT.kLine, { invert = true })

  map("n", m.comment,        op_line,   { expr = true, desc = "Comment by motion" })
  map("n", m.comment_line,   op_line_,  { expr = true, desc = "Comment current line" })
  map("x", m.comment_visual, op_line,   { expr = true, desc = "Comment selection" })
  map("n", m.block,          op_block,  { expr = true, desc = "Block comment by motion" })
  map("n", m.block_line,     op_block_, { expr = true, desc = "Block comment current line" })
  map("x", m.block_visual,   op_block,  { expr = true, desc = "Block comment selection" })

  map("n", m.comment_below,  function() M.insert_comment("below") end, { desc = "Add comment below" })
  map("n", m.comment_above,  function() M.insert_comment("above") end, { desc = "Add comment above" })
  map("n", m.comment_eol,    function() M.insert_comment("eol")   end, { desc = "Add comment at end of line" })
  map("n", m.uncomment_auto, function() H.uncomment_auto()        end, { desc = "Auto detect and uncomment" })

  map("n", m.invert, op_invert, { expr = true, desc = "Invert comment by motion" })
  map("x", m.invert, op_invert, { expr = true, desc = "Invert comment selection" })
  -- stylua: ignore end

  map(
    m.comment_visual == m.textobject_line and "o" or { "o", "x" },
    m.textobject_line,
    '<cmd>lua require("celeste_comment").textobject_linewise()<cr>',
    { desc = "Linewise comment textobject" }
  )
  map(
    m.block_visual == m.textobject_block and "o" or { "o", "x" },
    m.textobject_block,
    '<cmd>lua require("celeste_comment").textobject_blockwise()<cr>',
    { desc = "Block comment textobject" }
  )
  map(
    { "o", "x" },
    m.textobject_auto,
    '<cmd>lua require("celeste_comment").textobject_auto()<cr>',
    { desc = "Auto line/block textobject" }
  )
end

-- test only
M._H = H

return M
