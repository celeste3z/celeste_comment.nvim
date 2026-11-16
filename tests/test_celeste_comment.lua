---@diagnostic disable: inject-field, param-type-mismatch, need-check-nil, cast-local-type, missing-fields, assign-type-mismatch, undefined-field, unnecessary-assert, global-in-non-module, missing-return, unresolved-require, duplicate-require
local MiniTest = require("mini.test")
local expect = MiniTest.expect
local eq = expect.equality
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

child.setup = function()
  child.restart({
    "-u",
    "scripts/minimal_init.lua",
    "-c",
    "set shortmess+=I",
  })
end

local feed = function(...) child.type_keys(...) end

local function set_lines(lines, from, to)
  from, to = from or 0, to or -1
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local function get_lines(from, to)
  from = from or 0
  return child.api.nvim_buf_get_lines(0, from, to and (to + 1) or -1, false)
end

---@param line integer 0-indexed
---@param col? integer 0-indexed
---@param opts? { win?: integer }
---@overload fun(list: ([integer, integer])[], opts?: { win?: integer })
local function set_cursor(line, col, opts)
  opts = opts or {}
  local win = opts.win or 0

  if type(line) == "table" then
    for i, pos in ipairs(line) do
      set_cursor(pos[1], pos[2], { win = win })
      if i < #line then feed("Q") end
    end
    return
  end

  child.api.nvim_win_set_cursor(win, { line + 1, col or 0 })
end

local function clear_cursors()
  local ns = child.api.nvim_create_namespace("nvim.multicursor")
  child.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

--- Return all cursor positions, line and col are 0-indexed
---@return ([integer, integer])|([integer, integer])[]
local function get_cursor()
  local is_visual = child.api.nvim_get_mode().mode:match("[vV\22]") ~= nil
  local ns = child.api.nvim_create_namespace(is_visual and "nvim.multicursor.cursor" or "nvim.multicursor")
  local pc = child.api.nvim_win_get_cursor(0)
  local row, col = pc[1] - 1, pc[2]
  local cursors = {}
  for _, e in ipairs(child.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
    if e[2] ~= row or e[3] ~= col then cursors[#cursors + 1] = { e[2], e[3] } end
  end
  cursors[#cursors + 1] = { row, col }
  table.sort(cursors, function(e1, e2)
    if e1[1] == e2[1] then return e1[2] < e2[2] end
    return e1[1] < e2[1]
  end)
  if #cursors == 1 then return cursors[1] end
  return cursors
end

local function selection(frow, fcol, trow, tcol, mode)
  set_cursor(frow, fcol)
  feed(mode and mode or "v")
  set_cursor(trow, tcol)
end

local function get_selection()
  local visual = child.api.nvim_get_mode().mode:match("[vV\22]")
  if not visual then return {} end
  local vns = child.api.nvim_create_namespace("nvim.multicursor.visual")
  local pc = child.api.nvim_win_get_cursor(0)
  local panchor = child.api.nvim_eval("getpos('v')")
  local selections = { { panchor[2] - 1, panchor[3] - 1, pc[1] - 1, pc[2] } }

  -- TODO: for non-primary cursor, we can't get the anchor
  -- how can we get the multicursor's anchor?
  local exts = child.api.nvim_buf_get_extmarks(0, vns, 0, -1, { details = true })
  for _, e in ipairs(exts) do
    local detail = e[4]
    selections[#selections + 1] = { e[2], e[3], detail.end_row, detail.end_col - 1 }
  end
  table.sort(selections, function(a, b)
    if a[1] == b[1] then
      if a[2] == b[2] then
        if a[3] == b[3] then return a[4] < b[4] end
        return a[3] < b[3]
      end
      return a[2] < b[2]
    end
    return a[1] < b[1]
  end)

  if #selections == 1 then selections[2] = visual end

  return selections
end

---Assert buffer lines, optionally only a slice starting at `opts.from` (1-based).
---@param expected string[]
---@param opts? { from?: integer, reason?: string|fun() }
---@return boolean
local function eq_lines(expected, opts)
  opts = opts or {}

  local from = opts.from or expected.from
  local actual, want = get_lines(), expected

  if from then
    want = {}
    for i = 1, #expected do
      want[i] = expected[i]
    end
    actual = get_lines(from - 1, from - 1 + #want - 1)
  end

  return expect.equality(actual, want, { fail_reason = opts.reason })
end

---@param expected any
---@param opts? { reason?: string|fun() }
---@return boolean
local function eq_cursor(expected, opts)
  return expect.equality(get_cursor(), expected, { fail_reason = opts and opts.reason })
end

---@param expected any
---@param opts? { reason?: string|fun() }
---@return boolean
local function eq_selection(expected, opts)
  return expect.equality(get_selection(), expected, { fail_reason = opts and opts.reason })
end

---Assert buffer marks. `names` and `expected` are parallel lists; expected is `{ row, col }`.
---@param names string[]
---@param expected [integer, integer][]
---@param reason? string|fun()
local function eq_marks(names, expected, reason)
  assert(#names == #expected, "eq_marks: names and expected must have the same length")
  for i, name in ipairs(names) do
    expect.equality(child.api.nvim_buf_get_mark(0, name), expected[i], { fail_reason = reason })
  end
end

---@param ctx { bo?: table, o?: table, b?: table, g?: table, reg?: table, config?: table|fun(c: table): table? }
local function set_context(ctx)
  if ctx.bo or ctx.o or ctx.reg or (ctx.config and type(ctx.config) ~= "function") then
    child.lua_func(function(c)
      if c.bo then
        if c.bo.filetype ~= nil then vim.bo.filetype = c.bo.filetype end
        for k, v in pairs(c.bo) do
          if k ~= "filetype" then vim.bo[k] = v end
        end
      end
      if c.o then
        for k, v in pairs(c.o) do
          vim.o[k] = v
        end
      end
      if c.reg then
        for name, spec in pairs(c.reg) do
          vim.fn.setreg(name, spec.lines, spec.type)
        end
      end
      if c.config then
        vim.b.celeste_comment_config = vim.tbl_deep_extend("force", vim.b.celeste_comment_config or {}, c.config)
      end
    end, { bo = ctx.bo, o = ctx.o, reg = ctx.reg, config = type(ctx.config) == "table" and ctx.config or nil })
  end

  if type(ctx.config) == "function" then
    child.lua_func(function(src)
      local apply = assert(loadstring(src))
      local cfg = vim.b.celeste_comment_config or {}
      local patch = apply(cfg)
      vim.b.celeste_comment_config = type(patch) == "table" and vim.tbl_deep_extend("force", cfg, patch) or cfg
    end, string.dump(ctx.config))
  end

  if ctx.b then
    for k, v in pairs(ctx.b) do
      child.b[k] = v
    end
  end
  if ctx.g then
    for k, v in pairs(ctx.g) do
      child.g[k] = v
    end
  end
end

---Run a sequence of key presses, checking the buffer after each step.
---
---Each step is `{ [pos,] keys, [expect_lines], [expect_cursor], [expect_selection] }`.
---A step may also carry `lines = { ... }` to reset the buffer content first.
---`pos` is `{ row, col }`, `{ from_row, from_col, to_row, to_col, mode? }`, or a list of
---`{ row, col }` for multiple cursors. `expect_lines` is one lines array (optionally with
---`from`) or a list of such slices.
---@param lines string[]|nil  initial buffer, `nil` keeps the current lines
---@param steps table[]
---@param opts? { o?: table, bo?: table, b?: table, g?: table, reg?: table, config?: table|fun(c: table): table? }
local function validate_steps(lines, steps, opts)
  if opts then set_context(opts) end

  if lines then set_lines(lines) end

  for i, step in ipairs(steps) do
    if step.lines then set_lines(step.lines) end

    local pos, kind
    if type(step[1]) == "table" then
      if type(step[1][1]) == "number" then
        pos, kind = step[1], step[1][3] and "visual" or "cursor"
      elseif type(step[1][1]) == "table" and type(step[1][1][1]) == "number" then
        pos, kind = step[1], "multi"
      end
    end
    local base = pos and 2 or 1 -- index of `keys` in this step

    local keys, expected, expected_cursor, expected_selection =
      step[base], step[base + 1], step[base + 2], step[base + 3]

    if kind == "multi" then
      clear_cursors()
      set_cursor(pos)
    elseif kind == "visual" then
      selection(pos[1], pos[2], pos[3], pos[4], pos[5])
    elseif kind == "cursor" then
      set_cursor(pos[1], pos[2])
    end

    feed(keys)

    local keys_str = type(keys) == "table" and table.concat(keys, " ") or keys
    local reason = ("step %d: %q"):format(i, keys_str)
    if expected then
      if type(expected[1]) == "table" then
        for _, slice in ipairs(expected) do
          eq_lines(slice, { reason = reason })
        end
      else
        eq_lines(expected, { reason = reason })
      end
    end
    if expected_cursor then eq_cursor(expected_cursor, { reason = reason }) end
    if expected_selection then eq_selection(expected_selection, { reason = reason }) end
  end
end

local make_pos = function(buf, row, col) return vim.pos(row, col, { buf = buf }) end
if vim.fn.has("nvim-0.12.2") == 1 then make_pos = function(buf, row, col) return vim.pos(buf, row, col) end end

local function mock_child_msg()
  child.lua_func(function()
    _G.__echo_info = {}
    _G.__old_nvim_echo = vim.api.nvim_echo
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_echo = function(chunks, _, _)
      local msg = vim.iter(chunks):fold("", function(acc, chunk)
        acc = acc .. chunk[1]
        return acc
      end)
      __echo_info[#__echo_info + 1] = msg
    end
  end)
end

local function unmock_child_msg()
  child.lua_func(function()
    _G.__echo_info = nil
    vim.api.nvim_echo = _G.__old_nvim_echo
  end)
end

local function clear_child_msg()
  child.lua_func(function() _G.__echo_info = {} end)
end

local function child_msg() return child.lua_get([[__echo_info]]) end

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      set_context({ bo = { tabstop = 4, shiftwidth = 0, expandtab = true, commentstring = "# %s" } })
      child.lua_func(
        function()
          require("celeste_comment").setup({
            keep_cursor = true,
            insert_space = true,
            line_comment_no_indent = false,
            case_insensitive = false,
            block_relaxed_detect = false,
            ignore_empty_lines = "never",
            fallback_to_block = "never",
            block_textobj_nlines = 200,
            log_level = vim.log.levels.OFF,
            mappings = {
              line_toggle = "gc",
              line_toggle_cur = "gcc",
              line_toggle_visual = "gc",
              line_toggle_insert = { "<c-/>", "<c-_>" },

              block_toggle = "gb",
              block_toggle_cur = "gbc",
              block_toggle_visual = "gb",

              line_textobject = { "gc", "agc" },
              block_textobject = { "gb", "agb" },
              auto_textobject = { "ga", "ac" },
              uncomment_auto = "gcu",

              line_textobject_inner = "gic",
              block_textobject_inner = "gib",
              auto_textobject_inner = { "gia", "ic" },

              line_add_below = "gco",
              line_add_above = "gcO",
              line_add_eol = "gcA",
              line_invert = "gcI",
              line_force_add = "gC",
              line_force_remove = "gU",
              line_paste_before = "gcP",
              line_paste_after = "gcp",
              block_paste_before = "gbP",
              block_paste_after = "gbp",
            },
            hooks = nil,
          })
        end
      )
    end,
    post_once = child.stop,
  },
})

local H = require("celeste_comment").H
local M = require("celeste_comment")

local function c_pos(pos, edits, lines, range, csi)
  return H.compute_pos(pos, {
    edits = edits,
    lines = lines,
    range = range,
    csi = csi,
  }, { strategy = "cursor" })
end

local function c_state(state, edits, lines, range, csi, ctype, motion)
  return H.compute_state({
    __ = { state_track = state },
    cfg = { keep_cursor = true },
    edits = edits,
    lines = lines,
    range = range,
    csi = csi,
    ctype = ctype,
    motion = motion,
  })
end

local function apply_edits(line, edits)
  local lines = { line }
  H.apply_edits(lines, edits or {})
  return lines[1]
end

local function validate_edits(edits, expected)
  assert(edits, "expected edits")
  eq(#edits, #expected)
  for i, e in ipairs(expected) do
    if e.range then eq(edits[i].range, e.range) end
    if e.text then eq(edits[i].text, e.text) end
  end
end

local function make_line_info(opts)
  opts = opts or {}
  return {
    offset = opts.offset or 0,
    csi = opts.csi,
    ignore = opts.ignore or false,
    lcs_pos = opts.lcs_pos,
    rcs_pos = opts.rcs_pos,
    row = opts.row or 0,
    indent = opts.indent or { indent_size = 8, indent_style = "space" },
  }
end

-- Base tests ──────────────────────────────────────────────────────────────────

T["base"] = new_set()

T["base"]["unwrap_comment_strings"] = function()
  local function validate(a, exp) eq(H.unwrap_comment_strings(a), exp) end
  validate({ "//%s" }, { { "//", "" } })
  validate({ "/*%s*/" }, { { "/*", "*/" } })
  validate({ "// %s" }, { { "// ", "" } })
  validate({ "<!-- %s -->" }, { { "<!-- ", " -->" } })
  validate({ "# %s" }, { { "# ", "" } })
  validate({ "hello" }, { { "", "" } })
  validate({ "{-%s-}" }, { { "{-", "-}" } })
  validate({ "=begin%s=end" }, { { "=begin", "=end" } })
  validate({ "//%s", "///%s", "//!%s" }, { { "//", "" }, { "///", "" }, { "//!", "" } })
end

T["base"]["next_visible_column"] = function()
  local function validate(col, byte, tab, exp) eq(H.next_visible_column(col, byte, tab), exp) end
  validate(0, string.byte(" "), 4, 1)
  validate(1, string.byte(" "), 4, 2)
  validate(0, string.byte("\t"), 4, 4)
  validate(3, string.byte("\t"), 4, 4)
  validate(4, string.byte("\t"), 4, 8)
end

T["base"]["to_inclusive_pos"] = function()
  local function validate(row, col, exp)
    eq(
      child.lua_func(
        function(pos) return { require("celeste_comment").H.to_inclusive_pos(0, pos[1], pos[2]) } end,
        { row, col }
      ),
      exp
    )
  end

  set_context({ o = { selection = "exclusive" } })
  set_lines({ "a你b", "cd", "" })
  validate(0, 4, { 0, 3 }) -- boundary end
  validate(0, 5, { 0, 4 }) -- eol
  validate(0, 99, { 0, 4 }) -- beyond
  validate(0, 2, { 0, 3 }) -- mid
  validate(0, 1, { 0, 0 }) -- before_cjk
  validate(0, 0, { 0, 0 }) -- origin
  validate(1, 0, { 0, 4 }) -- prev line
  validate(2, 0, { 1, 1 }) -- prev line ascii
  validate(2, 3, { 2, 0 }) -- empty line
end

T["base"]["find_insert_offset"] = function()
  local function validate(line, limit, col, size, exp) eq(H.find_insert_offset(line, limit, col, size), exp) end
  validate("  code", 2, 0, 4, 0)
  validate("  code", 2, 1, 4, 1)
  validate("  code", 2, 2, 4, 2)
  validate("\tcode", 1, 0, 4, 0)
  validate("\tcode", 1, 1, 4, 0)
  validate("\tcode", 1, 4, 4, 1)
  validate("    code", 4, 2, 4, 2)
  validate(" \t code", 3, 3, 4, 1)
end

T["base"]["make_pattern_case_insensitive"] = function()
  local function pattern(s) return H.make_pattern_case_insensitive(vim.pesc(s)) end
  local function validate(a, exp) eq(H.make_pattern_case_insensitive(a), exp) end
  local function validate_find(line, exp) eq(line:find("^%s*" .. pattern("rem")), exp) end
  local function validate_match(line, exp) eq({ line:match("^(%s*)" .. pattern("rem") .. "(.*)") }, exp) end

  validate("rem", "[rR][eE][mM]")
  validate("REM", "[rR][eE][mM]")
  validate("/%*", "/%*")
  validate("", "")

  validate_find("REM hello", 1)
  validate_find("rem hello", 1)
  validate_find("  ReM hello", 1)
  validate_find("nope", nil)

  validate_match("  REM hello", { "  ", " hello" })
end

T["base"]["skip_whitespace"] = function()
  local function validate(line, pos, max, dir, exp) eq(H.skip_whitespace(line, pos, max, dir), exp) end
  -- forward
  validate("  abc", 3, 5, 1, 3)
  validate("  abc", 1, 2, 1, 3)
  validate("  abc", 1, 1, 1, 2)
  validate("\t\tabc", 1, 2, 1, 3)
  validate("abc", 1, 5, 1, 1)
  validate("", 1, 5, 1, 1)
  -- backward
  validate("abc  ", 5, 3, -1, 3)
  validate("abc  ", 5, 2, -1, 3)
  validate("abc\t\t", 5, 2, -1, 3)
  validate("abc", 3, 5, -1, 3)
  -- mix
  validate(" \t x", 1, 3, 1, 4)
  validate("x \t ", 4, 3, -1, 1)
end

T["base"]["shrink_region"] = function()
  local function validate(lines, range, exp) eq(H.shrink_region(lines, range), exp) end
  -- single line, no padding
  validate({ "abc" }, { 0, 0, 0, 2 }, { 0, 0, 0, 2 })
  -- single line, leading spaces
  validate({ "  abc" }, { 0, 0, 0, 4 }, { 0, 2, 0, 4 })
  -- single line, leading+trailing spaces
  validate({ "  abc  " }, { 0, 0, 0, 6 }, { 0, 2, 0, 4 })
  -- all whitespace
  validate({ "   ", "  " }, { 0, 0, 1, 1 }, nil)
  -- multi-line, first line blank, last line blank
  validate({ "", "  a", "b  ", "" }, { 0, 0, 3, 1 }, { 1, 2, 2, 0 })
  -- only on first line
  validate({ "  x", "", "" }, { 0, 0, 2, 0 }, { 0, 2, 0, 2 })
  -- only on last line
  validate({ "", "", "y  " }, { 0, 0, 2, 3 }, { 2, 0, 2, 0 })
  -- selection has leading+trailing whitespace
  validate({ "  /* 1 */  " }, { 0, 0, 0, 10 }, { 0, 2, 0, 8 })
  -- selection already within content
  validate({ "  /* 1 */  " }, { 0, 2, 0, 8 }, { 0, 2, 0, 8 })
  -- selecting just subset of content
  validate({ "  /* 1 */  " }, { 0, 3, 0, 7 }, { 0, 3, 0, 7 })
  -- multi-line both lines with padding
  validate({ "  a  ", "  b  " }, { 0, 0, 1, 5 }, { 0, 2, 1, 2 })
  -- multi-line, selection mid-content on each line
  validate({ "  a  ", "  b  " }, { 0, 2, 1, 3 }, { 0, 2, 1, 2 })
  -- only first line selected
  validate({ "  a  " }, { 0, 0, 0, 4 }, { 0, 2, 0, 2 })
  -- blank first line, content on subsequent lines
  validate({ "", "a" }, { 0, 0, 1, 0 }, { 1, 0, 1, 0 })
  -- content with blank line between
  validate({ "a", "", "c" }, { 0, 0, 2, 0 }, { 0, 0, 2, 0 })
  -- single non-whitespace char
  validate({ "x" }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
  -- tab character in whitespace
  validate({ "\tx" }, { 0, 0, 0, 1 }, { 0, 1, 0, 1 })
  -- multiple blank lines before content
  validate({ "", "", "  a  " }, { 0, 0, 2, 4 }, { 2, 2, 2, 2 })
  -- selection ends at whitespace after last content
  validate({ "a  ", "b" }, { 0, 0, 1, 0 }, { 0, 0, 1, 0 })
  -- empty lines array
  validate({}, { 0, 0, 0, 0 }, nil)
  -- rows reversed
  validate({ "a" }, { 1, 0, 0, 0 }, nil)
  -- single line, scol > ecol
  validate({ "a" }, { 0, 2, 0, 0 }, nil)
  -- multi-line, rows ok but single-line col reversed
  validate({ "a" }, { 0, 2, 0, 2 }, nil)
end

T["base"]["match_byte"] = function()
  local function validate(sa, i, sb, j, dir, exp, ci) eq(H.match_byte(sa, i, sb, j, dir, ci or false), exp) end
  -- forward exact match
  validate("abc", 0, "abc", 0, 1, 3)
  validate("abc", 0, "ab", 0, 1, 2)
  validate("abc", 1, "bc", 0, 1, 2)
  -- forward partial match (fails partway)
  validate("abc", 0, "abd", 0, 1, 2) -- "ab" matches, then "c" != "d"
  validate("abc", 0, "x", 0, 1, 0)
  -- forward past end of sa
  validate("ab", 0, "abc", 0, 1, 2) -- "ab" matches, can't read more
  validate("ab", 2, "a", 0, 1, 0)
  -- forward offset in sb
  validate("abc", 0, "xabc", 1, 1, 3) -- sb from pos 1 = "abc"
  validate("abc", 1, "xbc", 1, 1, 2)
  -- forward ci
  validate("ABC", 0, "abc", 0, 1, 3, true)
  validate("aBc", 1, "bC", 0, 1, 2, true)
  validate("abc", 0, "abD", 0, 1, 2, true) -- "ab" matches, "c" != "D"
  -- backward exact match
  validate("abc", 2, "cb", 0, -1, 2)
  validate("abc", 2, "cba", 0, -1, 3)
  validate("a #", 2, "# ", 0, -1, 2)
  -- backward partial match (fails partway)
  validate("a #", 2, "# ", 0, -1, 2) -- pos 2,1 in "a #" = "# "
  validate("a #", 2, "# x", 0, -1, 2) -- "# " matches, sb longer than matched
  validate("a b", 2, " #", 0, -1, 0) -- "b" != " "
  -- backward past start of sa
  validate("ab", 0, "a", 0, -1, 1)
  validate("ab", 0, "x", 0, -1, 0)
  -- backward ci
  validate("ABC", 2, "cb", 0, -1, 2, true)
  validate("aBc", 2, "cB", 0, -1, 2, true)
  -- forward empty sb
  validate("abc", 1, "", 0, 1, 0)
  -- backward empty sb
  validate("abc", 1, "", 0, -1, 0)
  -- mixed chars forward
  validate("a1b2c", 1, "1b2", 0, 1, 3)
  validate("/* comment */", 0, "/* ", 0, 1, 3)
  -- tab vs space (exact match, no whitespace skipping)
  validate("#\ttext", 0, "#\t", 0, 1, 2)
  validate("#\ttext", 1, " ", 0, 1, 0) -- tab != space
  validate("# text", 1, " ", 0, 1, 1)
  validate("# text", 1, "\t", 0, 1, 0) -- space != tab
  -- unicode (byte comparison)
  validate("f", 0, "f", 0, 1, 1)
  validate("ü", 0, "ü", 0, 1, 2)
end

T["base"]["match_line_comment"] = function()
  local function validate(line, off, expected, opts)
    opts = opts or {}
    local cms = opts.cms or { { "//", "" }, { "///", "" }, { "//!", "" } }
    local csi = H.make_csi(cms, opts.pad ~= nil and { pad = opts.pad } or nil)
    local r = H.match_line_comment(line, off, csi, {
      check_only = opts.check_only,
      check_will_blank = opts.check_will_blank,
      with_inner = opts.with_inner,
    })
    eq(
      { r.matched, r.lcs_pos, r.rcs_pos, r.will_blank, r.inner },
      { expected.matched, expected.lcs_pos, expected.rcs_pos, expected.will_blank, expected.inner }
    )
  end

  -- check_only mode
  validate("/// doc", 0, { matched = true }, { check_only = true })
  validate("//! note", 0, { matched = true }, { check_only = true })
  validate("// comment", 0, { matched = true }, { check_only = true })
  validate("not a comment", 0, { matched = false }, { check_only = true })

  -- full mode: lcs_pos
  validate("  /// doc", 1, { matched = true, lcs_pos = { 1, 2, 4 } })
  validate("  //! note", 1, { matched = true, lcs_pos = { 1, 2, 4 } })
  validate("  // comment", 1, { matched = true, lcs_pos = { 1, 2, 3 } })

  -- no match
  validate("  foo", 0, { matched = false })
  validate("  foo", 0, { matched = false }, { check_only = true })

  -- single token (backward compat)
  validate("// foo", 0, { matched = true }, { cms = { { "//", "" } }, check_only = true })
  validate("/// foo", 0, { matched = true }, { cms = { { "//", "" } }, check_only = true })
  validate("foo", 0, { matched = false }, { cms = { { "//", "" } }, check_only = true })

  -- rcs-only comment string (%s # style)
  validate("line #", 0, { matched = true }, { cms = { { "", " #" } }, check_only = true })
  validate("line # ", 0, { matched = true }, { cms = { { "", " #" } }, check_only = true })
  validate("line", 0, { matched = false }, { cms = { { "", " #" } }, check_only = true })

  -- rcs-only full mode
  validate("  a # b #", 1, { matched = true, rcs_pos = { 1, 7, 8 } }, { cms = { { "", " #" } } })

  -- rcs-only: line with multiple ##, only last one matched
  validate("line ##", 1, { matched = true, rcs_pos = { 1, 6, 6 } }, { cms = { { "", " #" } } })

  -- lcs+rcs with pad
  validate(
    "  /* hello */",
    1,
    { matched = true, lcs_pos = { 1, 2, 4 }, rcs_pos = { 1, 10, 12 } },
    { cms = { { "/*", "*/" } }, pad = true }
  )

  -- lcs+rcs without pad
  validate(
    "  /*hello*/",
    1,
    { matched = true, lcs_pos = { 1, 2, 3 }, rcs_pos = { 1, 9, 10 } },
    { cms = { { "/*", "*/" } }, pad = false }
  )

  -- multi-word content after lcs with rcs
  validate("  // hello world", 1, { matched = true, lcs_pos = { 1, 2, 4 } }, { cms = { { "// ", "" } } })

  -- tab indentation
  validate("\t// indented", 1, { matched = true, lcs_pos = { 1, 1, 3 } }, { cms = { { "// ", "" } } })
  validate("// foo", 1, { matched = true, lcs_pos = { 1, 0, 2 } }, { cms = { { "// ", "" } } })

  -- lcs+rcs: content with nested lcs pattern
  validate(
    "  /* a /* b */",
    1,
    { matched = true, lcs_pos = { 1, 2, 4 }, rcs_pos = { 1, 11, 13 } },
    { cms = { { "/*", "*/" } }, pad = true }
  )

  -- will_blank with check_will_blank
  validate("  //", 1, { matched = true, lcs_pos = { 1, 2, 3 }, will_blank = true }, { check_will_blank = true })
  validate("  /// doc", 1, { matched = true, lcs_pos = { 1, 2, 4 }, will_blank = false }, { check_will_blank = true })

  -- with_inner
  local inner_opts = { cms = { { "//", "" } }, pad = true, with_inner = true }
  validate("// xxx", 0, { matched = true, lcs_pos = { 0, 0, 2 }, inner = { 0, 3, 5 } }, inner_opts)
  validate("//  abc", 0, { matched = true, lcs_pos = { 0, 0, 2 }, inner = { 0, 3, 6 } }, inner_opts)
  -- trailing whitespace preserved
  validate("// xxx   ", 0, { matched = true, lcs_pos = { 0, 0, 2 }, inner = { 0, 3, 8 } }, inner_opts)
  -- empty content → no inner
  validate("//", 0, { matched = true, lcs_pos = { 0, 0, 1 } }, inner_opts)

  -- with_inner: wrapped lcs+rcs
  validate(
    "<!-- xxx -->",
    0,
    { matched = true, lcs_pos = { 0, 0, 4 }, rcs_pos = { 0, 8, 11 }, inner = { 0, 5, 7 } },
    { cms = { { "<!--", "-->" } }, pad = true, with_inner = true }
  )

  -- with_inner: rcs-only
  validate(
    "line #",
    0,
    { matched = true, rcs_pos = { 0, 4, 5 }, inner = { 0, 0, 3 } },
    { cms = { { "", " #" } }, pad = true, with_inner = true }
  )

  -- with_inner: insert_space=false respects raw lcs
  validate(
    "//abc",
    0,
    { matched = true, lcs_pos = { 0, 0, 1 }, inner = { 0, 2, 4 } },
    { cms = { { "// ", "" } }, pad = false, with_inner = true }
  )
end

T["base"]["compute_pos"] = function()
  local xs = { "x", "x", "x", "x", "x" }
  local function validate(pos, edits, expected, opts)
    opts = opts or {}
    local lines = opts.lines or { "hello" }
    local range = opts.range or { 0, 0, 0, 3 }
    local csi = opts.csi or { orcs = "" }
    eq(c_pos(make_pos(0, pos[1], pos[2]), edits, lines, range, csi), make_pos(0, expected[1], expected[2]))
  end

  -- insertion on same row, cursor after insert point
  validate({ 0, 2 }, { { range = { 0, 0, 0, 0 }, text = { "# " } } }, { 0, 4 })

  -- insertion on same row, cursor at insert point
  validate({ 0, 0 }, { { range = { 0, 0, 0, 0 }, text = { "# " } } }, { 0, 2 })

  -- insertion on same row, cursor before insert point
  validate({ 0, 0 }, { { range = { 0, 3, 0, 3 }, text = { "//" } } }, { 0, 0 })

  -- insertion on different row, no col shift
  validate({ 1, 2 }, { { range = { 0, 0, 0, 0 }, text = { "# " } } }, { 1, 2 }, { lines = xs, range = { 0 } })

  -- deletion, cursor after deleted range
  validate({ 0, 5 }, { { range = { 0, 0, 0, 3 }, text = { "" } } }, { 0, 2 })

  -- deletion, cursor within deleted range → clamped to start
  validate({ 0, 2 }, { { range = { 0, 0, 0, 3 }, text = { "" } } }, { 0, 0 })

  -- deletion, cursor before deleted range
  validate({ 0, 0 }, { { range = { 0, 3, 0, 5 }, text = { "" } } }, { 0, 0 })

  -- multi-line replacement on same row, cursor after end
  validate({ 0, 6 }, { { range = { 0, 3, 0, 5 }, text = { "longer", "b", "c" } } }, { 2, 10 })

  -- multi-line replacement on same row, cursor inside replaced range
  validate({ 0, 4 }, { { range = { 0, 3, 0, 5 }, text = { "/*", "*/" } } }, { 1, 4 })

  -- multi-line replacement before cursor row
  validate({ 2, 2 }, { { range = { 0, 0, 0, 0 }, text = { "a", "b" } } }, { 3, 2 }, { lines = xs, range = { 0 } })

  -- multi-line replacement after cursor row
  validate({ 0, 2 }, { { range = { 3, 0, 3, 0 }, text = { "a", "b" } } }, { 0, 2 }, { lines = xs, range = { 0 } })

  -- multiple edits: insert + delete
  validate({ 0, 5 }, {
    { range = { 0, 3, 0, 3 }, text = { "//" } },
    { range = { 0, 0, 0, 2 }, text = { "" } },
  }, { 0, 5 })

  -- multiple edits: two inserts
  validate({ 0, 3 }, {
    { range = { 0, 0, 0, 0 }, text = { "# " } },
    { range = { 0, 5, 0, 5 }, text = { " //" } },
  }, { 0, 5 })

  -- sentinel insert 1 line before cursor
  validate({ 1, 0 }, { { range = { 0, -1, 0, -1 }, text = { "/*" } } }, { 2, 0 }, { lines = xs, range = { 0 } })

  -- sentinel insert 1 line on cursor row
  validate({ 0, 0 }, { { range = { 0, -1, 0, -1 }, text = { "/*" } } }, { 1, 0 }, { lines = xs, range = { 0 } })

  -- sentinel insert after cursor row
  validate({ 0, 0 }, { { range = { 2, -1, 2, -1 }, text = { "/*" } } }, { 0, 0 }, { lines = xs, range = { 0 } })

  -- sentinel delete before cursor
  validate({ 2, 0 }, { { range = { 0, -1, 1, -1 }, text = {} } }, { 1, 0 }, { lines = xs, range = { 0 } })

  -- multiple edits: delete + insert (reversed order)
  validate({ 0, 5 }, {
    { range = { 0, 0, 0, 2 }, text = { "" } },
    { range = { 0, 3, 0, 3 }, text = { "//" } },
  }, { 0, 5 })

  -- multiple edits: two multi-line inserts stacking
  validate({ 4, 0 }, {
    { range = { 0, 0, 0, 0 }, text = { "a", "b" } },
    { range = { 1, 0, 1, 0 }, text = { "c", "d" } },
  }, { 6, 0 }, { lines = xs, range = { 0 } })

  -- multiple edits: insert on same row + multi-line before row
  validate({ 2, 2 }, {
    { range = { 1, 0, 1, 0 }, text = { "x", "y" } },
    { range = { 2, 0, 2, 0 }, text = { "# " } },
  }, { 3, 4 }, { lines = xs, range = { 0 } })

  -- sentinel insert 2 lines before cursor
  validate({ 1, 0 }, { { range = { 0, -1, 0, -1 }, text = { "a", "b" } } }, { 3, 0 }, { lines = xs, range = { 0 } })

  -- sentinel delete 1 line on cursor row
  validate({ 0, 0 }, { { range = { 0, -1, 1, -1 }, text = {} } }, { 0, 0 }, { lines = xs, range = { 0 } })

  -- sentinel delete 1 line after cursor
  validate({ 0, 0 }, { { range = { 2, -1, 3, -1 }, text = {} } }, { 0, 0 }, { lines = xs, range = { 0 } })

  -- sentinel delete 2 lines before cursor
  validate({ 3, 0 }, { { range = { 0, -1, 2, -1 }, text = {} } }, { 1, 0 }, { lines = xs, range = { 0 } })

  -- EOL + RHS insert: skip shift
  validate(
    { 0, 7 },
    { { range = { 0, 7, 0, 7 }, text = { " */" } } },
    { 0, 7 },
    { lines = { "  hello" }, range = { 0, 0, 0, 7 }, csi = { orcs = " */" } }
  )

  -- EOL + LHS insert: normal shift
  validate(
    { 0, 7 },
    { { range = { 0, 7, 0, 7 }, text = { "/* " } } },
    { 0, 10 },
    { lines = { "  hello" }, range = { 0, 0, 0, 7 }, csi = { orcs = " */" } }
  )

  -- EOL + RHS with orcs="" (LHS-only): normal shift
  validate(
    { 0, 7 },
    { { range = { 0, 7, 0, 7 }, text = { "// " } } },
    { 0, 10 },
    { lines = { "  hello" }, range = { 0, 0, 0, 7 } }
  )

  -- non-EOL + RHS insert: no shift (cursor before insert point)
  validate(
    { 0, 3 },
    { { range = { 0, 7, 0, 7 }, text = { " */" } } },
    { 0, 3 },
    { lines = { "  hello" }, range = { 0, 0, 0, 7 }, csi = { orcs = " */" } }
  )

  -- EOL + LHS+RHS: LHS shifts, RHS skips
  validate({ 0, 7 }, {
    { range = { 0, 2, 0, 2 }, text = { "/* " } },
    { range = { 0, 7, 0, 7 }, text = { " */" } },
  }, { 0, 10 }, { lines = { "  hello" }, range = { 0, 0, 0, 7 }, csi = { orcs = " */" } })
end

T["base"]["compute_state"] = function()
  local xs = { "x", "x", "x", "x", "x" }
  local function validate(st, edits, expected, opts)
    local function P(rc) return rc and make_pos(0, rc[1], rc[2]) end
    local cs = { ncursor = P(st.cursor), nanchor = P(st.anchor) }
    opts = opts or {}
    local lines = opts.lines or { "hello" }
    local range = opts.range or { 0, 0, 0, 3 }
    local csi = opts.csi or { orcs = "" }
    c_state(cs, edits, lines, range, csi, opts.ctype, opts.motion)
    eq({ cs.ncursor, cs.nanchor }, { P(expected.cursor), P(expected.anchor) })
  end

  -- nil state
  local cs
  c_state(nil, {}, xs, { 0 }, { orcs = "" })
  eq(cs, nil)

  -- empty edits
  validate({ cursor = { 0, 3 } }, {}, { cursor = { 0, 3 } }, { lines = xs, range = { 0 } })

  -- cursor only, no end_pos
  validate({ cursor = { 0, 3 } }, { { range = { 0, 0, 0, 0 }, text = { "# " } } }, { cursor = { 0, 5 } })

  -- cursor + end_pos on same line
  validate(
    { cursor = { 0, 2 }, anchor = { 0, 5 } },
    { { range = { 0, 0, 0, 0 }, text = { "# " } } },
    { cursor = { 0, 4 }, anchor = { 0, 7 } }
  )

  -- cursor + end_pos on different lines, both shifted
  validate(
    { cursor = { 0, 2 }, anchor = { 1, 4 } },
    { { range = { 0, 0, 0, 0 }, text = { "# " } } },
    { cursor = { 0, 4 }, anchor = { 1, 4 } },
    { lines = { "hello", "world" }, range = { 0, 0, 1, 5 } }
  )

  -- cursor + end_pos with multiple edits
  validate({ cursor = { 0, 3 }, anchor = { 0, 5 } }, {
    { range = { 0, 0, 0, 0 }, text = { "# " } },
    { range = { 0, 5, 0, 5 }, text = { " //" } },
  }, { cursor = { 0, 5 }, anchor = { 0, 7 } }, { csi = { orcs = " //" } })

  -- cursor + end_pos where end_pos is on a different row with line insert
  validate(
    { cursor = { 1, 0 }, anchor = { 2, 0 } },
    { { range = { 0, -1, 0, -1 }, text = { "/*" } } },
    { cursor = { 2, 0 }, anchor = { 3, 0 } },
    { lines = { "a", "b", "c" }, range = { 0, 0, 2, 0 } }
  )

  -- block comment char-wise: RHS end_pos lands at content end
  -- `12--[[ 3456789\n123 ]]456789`, selection {0,2,1,5}, uncomment
  local block_edits = {
    { range = { 0, 2, 0, 7 }, text = { "" } },
    { range = { 1, 3, 1, 6 }, text = { "" } },
  }
  local block_lines = { "12--[[ 3456789", "123 ]]456789" }
  -- cursor on `--` → content start (col 2); end_pos on `]]` → last content char (col 2)
  validate(
    { cursor = { 0, 2 }, anchor = { 1, 5 } },
    block_edits,
    { cursor = { 0, 2 }, anchor = { 1, 2 } },
    { lines = block_lines, range = { 0, 2, 1, 5 }, csi = { orcs = " ]]" }, ctype = M.CMT.kBlock, motion = "char" }
  )

  -- same block uncomment but line-wise motion → RHS keeps default clamp
  validate(
    { cursor = { 0, 2 }, anchor = { 1, 5 } },
    block_edits,
    { cursor = { 0, 2 }, anchor = { 1, 3 } },
    { lines = block_lines, range = { 0, 2, 1, 5 }, csi = { orcs = " ]]" }, ctype = M.CMT.kBlock, motion = "line" }
  )
end

T["base"]["make_csi"] = function()
  local function validate(cms, opts, exp)
    local csi = H.make_csi(cms, opts)
    assert(csi, "expected csi")
    local got = {
      n = #csi.pairs,
      traw = vim.tbl_map(function(p) return p.traw[1] end, csi.pairs),
      tesc = vim.tbl_map(function(p) return p.tesc[1] end, csi.pairs),
      tout = vim.tbl_map(function(p) return p.tout[1] end, csi.pairs),
      tlcs = csi.tlcs,
      trcs = csi.trcs,
      olcs = csi.olcs,
      orcs = csi.orcs,
      wrapped = csi.wrapped,
    }
    for k, v in pairs(exp) do
      eq(got[k], v)
    end
  end

  -- single pair, no pad
  validate({ { "//", "" } }, nil, {
    n = 1,
    traw = { "//" },
    tesc = { vim.pesc("//") },
    tout = { "//" },
    tlcs = "//",
    olcs = "//",
  })

  -- with pad
  validate({ { "//", "" } }, { pad = true }, { olcs = "// " })

  -- multi pair sorted by length descending
  validate({ { "//", "" }, { "///", "" }, { "//!", "" } }, nil, {
    n = 3,
    traw = { "///", "//!", "//" },
    tesc = { vim.pesc("///"), vim.pesc("//!"), vim.pesc("//") },
  })

  -- block pair with pad
  validate({ { "/*", "*/" } }, { pad = true }, { wrapped = true, olcs = "/* ", orcs = " */" })

  -- block pair without pad
  validate({ { "/*", "*/" } }, { pad = false }, { olcs = "/*", orcs = "*/", wrapped = true })

  -- case insensitive
  validate({ { "@REM", "" } }, { ci = true }, { n = 1, tesc = { "@[rR][eE][mM]" } })

  -- rcs only
  validate({ { "", " #" } }, nil, { n = 1, tlcs = "", trcs = "#", wrapped = false })

  -- raw strings preserved when no pad
  validate({ { "/* ", " */" } }, nil, { olcs = "/* ", orcs = " */" })

  -- empty pair filtered out
  validate({ { "//", "" }, { "", "" } }, nil, { n = 1 })

  -- no valid pairs
  eq(H.make_csi({ { "", "" } }), nil)
end

T["base"]["split_comments_parts"] = function()
  local function validate(a, exp) eq(H.split_comments_parts(a), exp) end
  validate("", { "" })
  validate("abc", { "abc" })
  validate("s1:/*,mb:*,ex:*/", { "s1:/*", "mb:*", "ex:*/" })
  validate([[s:a\,b,e:c\,d]], { [[s:a\,b]], [[e:c\,d]] })
  validate("s:/*,", { "s:/*", "" })
  validate(",", { "", "" })
  validate([[n:#,s:<!--,e:-->]], { "n:#", "s:<!--", "e:-->" })
  validate([[a\\b]], { [[a\\b]] })
  validate([[a\\,b]], { [[a\\]], "b" })
end

T["base"]["make_indent_padding"] = function()
  local function validate(a, b, c, d, exp) eq(H.make_indent_padding(a, b, c, d), exp) end
  validate(0, 4, 4, "space", "    ")
  validate(0, 4, 4, "tab", "\t")
  validate(0, 8, 4, "tab", "\t\t")
  validate(3, 8, 4, "tab", "\t\t")
  validate(0, 2, 4, "tab", "  ")
  validate(0, 0, 4, "tab", "")
  validate(2, 6, 4, "space", "    ")
  validate(4, 8, 4, "tab", "\t")
  validate(1, 4, 4, "tab", "\t")
end

T["base"]["extract_comments_option"] = function()
  local function validate(input, expected)
    local exp = {}
    for k, v in pairs(expected) do
      exp[k] = { str = v[1], flags = v[2] }
    end
    eq(H.do_extract_comments(input), exp)
  end

  -- global default
  validate([[s1:/*,mb:*,ex:*/,://,b:#,:%,:XCOMM,n:>,fb:-,fb:•]], {
    s = { "/*", "s1" },
    m = { "*", "mb" },
    e = { "*/", "ex" },
    line = { "•", "fb" },
  })

  -- c.vim:37 (same as arduino/jsonc/soy)
  validate([[sO:*\ -,mO:*\ \ ,exO:*/,s1:/*,mb:*,ex:*/,:///,://]], {
    s = { "/*", "s1" },
    m = { "*", "mb" },
    e = { "*/", "ex" },
    line = { "//", "" },
  })

  -- nim.vim:11 (s flag not first: `fs1`)
  validate([[exO:]#,fs1:#[,mb:*,ex:]#,:#]], {
    s = { "#[", "fs1" },
    m = { "*", "mb" },
    e = { "]#", "ex" },
    line = { "#", "" },
  })

  -- sway.vim:13 (duplicate s sections, last wins)
  validate([[s0:/*!,ex:*/,s1:/*,mb:*,ex:*/,:///,://!,://]], {
    s = { "/*", "s1" },
    m = { "*", "mb" },
    e = { "*/", "ex" },
    line = { "//", "" },
  })

  -- mediawiki.vim:28 (last s/e; `\:` and `\ ` unescaped)
  validate([[n:#,n:*,n:\:,s:{\|,m:\|,ex:\|},s:<!--,m:\ \ \ \ ,e:-->]], {
    line = { ":", "n" },
    s = { "<!--", "s" },
    m = { "    ", "m" },
    e = { "-->", "e" },
  })

  -- xml.vim:21
  validate([[s:<!--,e:-->]], { s = { "<!--", "s" }, e = { "-->", "e" } })

  -- sml.vim:20 (r flag)
  validate([[sr:(*,mb:*,ex:*)]], { s = { "(*", "sr" }, m = { "*", "mb" }, e = { "*)", "ex" } })

  -- rust.vim:38 (duplicate s/m/e, last wins, `\ ` unescaped)
  validate([[s1:/*,mb:*,ex:*/,s0:/*,mb:\ ,ex:*/,:///,://!,://]], {
    s = { "/*", "s0" },
    m = { " ", "mb" },
    e = { "*/", "ex" },
    line = { "//", "" },
  })

  -- ld.vim:17 (minimal C-style block)
  validate([[s1:/*,mb:*,ex:*/]], { s = { "/*", "s1" }, m = { "*", "mb" }, e = { "*/", "ex" } })

  -- idris2.vim:28 (`\|` not unescaped)
  validate([[s1:{-,mb:-,ex:-},:\|\|\|,:--]], {
    s = { "{-", "s1" },
    m = { "-", "mb" },
    e = { "-}", "ex" },
    line = { "--", "" },
  })

  -- tera.vim:19
  validate([[s:{#,e:#}]], { s = { "{#", "s" }, e = { "#}", "e" } })

  -- wat.vim:13
  validate([[s:(;,e:;),:;;]], { s = { "(;", "s" }, e = { ";)", "e" }, line = { ";;", "" } })

  -- scheme.vim:19
  validate([[:;;;;,:;;;,:;;,:;,sr:#\|,mb:\|,ex:\|#]], {
    line = { ";", "" },
    s = { "#\\|", "sr" },
    m = { "\\|", "mb" },
    e = { "\\|#", "ex" },
  })

  -- modula3.vim:15 (count flag s0)
  validate([[s0:(*,mb:\ ,ex:*)]], { s = { "(*", "s0" }, m = { " ", "mb" }, e = { "*)", "ex" } })

  -- aap.vim:25 (`\ ` unescaped in s/m)
  validate([[s:#\ -,m:#\ \ ,e:#,n:#,fb:-]], {
    s = { "# -", "s" },
    m = { "#  ", "m" },
    e = { "#", "e" },
    line = { "-", "fb" },
  })

  -- purescript.vim:11
  validate([[s1f:{-,mb:\ ,ex:-},:--\ \|,:--]], {
    s = { "{-", "s1f" },
    m = { " ", "mb" },
    e = { "-}", "ex" },
    line = { "--", "" },
  })

  -- org.vim:20 (`\:` unescaped)
  validate([[b:\:]], { line = { ":", "b" } })

  -- hgcommit.vim:17 (`\:` unescaped)
  validate([[:HG\:]], { line = { "HG:", "" } })

  -- clojure.vim:31
  validate([[n:;]], { line = { ";", "n" } })

  -- text.vim:17 (line only, last wins)
  validate([[fb:-,fb:*,n:>]], { line = { ">", "n" } })

  -- spec.vim:19
  validate([[b:#]], { line = { "#", "b" } })

  -- synthetic: s-only (no e)
  validate([[s:/*]], { s = { "/*", "s" } })

  -- synthetic: escaped comma
  validate([[s:a\,b,e:c\,d]], { s = { "a,b", "s" }, e = { "c,d", "e" } })

  -- synthetic: trailing comma
  validate([[s:/*,]], { s = { "/*", "s" } })

  -- empty
  validate("", {})
end

T["base"]["block_comment_info"] = function()
  local function validate(lines, scol, ecol, motion, expected, opts)
    opts = opts or {}
    local cms = opts.cms or { { opts.lcs or "/* ", opts.rcs or " */" } }
    local csi = H.make_csi(cms, opts.pad ~= nil and { pad = opts.pad } or nil)
    local range = { 0, scol, #lines - 1, ecol }
    local cfg = opts.relaxed and { block_relaxed_detect = true } or nil
    local info = H.block_comment_info(lines, csi, motion, range, cfg)
    eq(info and { info.lcs_pos, info.rcs_pos }, expected)
  end

  -- Line mode: complete block
  validate({ "  /* hello */" }, 0, 11, "line", { { 0, 2, 4 }, { 0, 10, 12 } })

  -- Line mode: no block
  validate({ "hello" }, 0, 4, "line", nil)

  -- Line mode: has lcs but no trailing rcs
  validate({ "  /* hello" }, 0, 9, "line", nil)

  -- Char mode: selected pair
  validate({ "he/* llo */ld" }, 2, 10, "char", { { 0, 2, 4 }, { 0, 8, 10 } })

  -- Char mode: no lcs
  validate({ "hello" }, 2, 4, "char", nil)

  -- Char mode: lcs present but no rcs within bounds
  validate({ "/* a */ b()" }, 0, 2, "char", nil)

  -- Block mode (same as line)
  validate({ "  /* hello */" }, 0, 11, "block", { { 0, 2, 4 }, { 0, 10, 12 } })

  -- Relaxed: leading blank line (line motion)
  validate({ "", "  /* hello */" }, 0, 11, "line", { { 1, 2, 4 }, { 1, 10, 12 } }, { relaxed = true })

  -- Relaxed: trailing blank line (line motion)
  validate({ "  /* hello */", "" }, 0, 11, "line", { { 0, 2, 4 }, { 0, 10, 12 } }, { relaxed = true })

  -- Relaxed: both sides blank (line motion)
  validate({ "", "  /* hello */", "" }, 0, 11, "line", { { 1, 2, 4 }, { 1, 10, 12 } }, { relaxed = true })

  -- Relaxed: all blank lines (line motion)
  validate({ "", "" }, 0, 0, "line", nil, { relaxed = true })

  -- Relaxed: char mode, leading whitespace before lcs
  validate({ "  /* 1 */  " }, 0, 10, "char", { { 0, 2, 4 }, { 0, 6, 8 } }, { relaxed = true })

  -- Relaxed: char mode, all whitespace
  validate({ "      " }, 0, 5, "char", nil, { relaxed = true })

  -- Relaxed: multi-line, blank first line (char mode)
  validate({ "", "/* 1 */" }, 0, 6, "char", { { 1, 0, 2 }, { 1, 4, 6 } }, { relaxed = true })

  -- Non-relaxed should still fail when leading blank
  validate({ "", "  /* hello */" }, 0, 11, "line", nil)

  -- Relaxed: multi-line block comment, linewise ec=0 (line motion)
  validate(
    { "  --[[ xxx", "  yyy ]] " },
    0,
    0,
    "line",
    { { 0, 2, 6 }, { 1, 5, 7 } },
    { lcs = "--[[ ", rcs = " ]]", relaxed = true }
  )

  -- Relaxed: block motion, multi-line (same as line)
  validate(
    { "  --[[ xxx", "  yyy ]] " },
    0,
    0,
    "block",
    { { 0, 2, 6 }, { 1, 5, 7 } },
    { lcs = "--[[ ", rcs = " ]]", relaxed = true }
  )

  -- Relaxed: three-line block comment (line motion)
  validate(
    { "  --[[ xxx", "  yyy", "  zzz ]] " },
    0,
    0,
    "line",
    { { 0, 2, 6 }, { 2, 5, 7 } },
    { lcs = "--[[ ", rcs = " ]]", relaxed = true }
  )

  local mb_cms = { { "{-", "-}" }, { "{#", "#}" } }

  -- Multi-pair: pair 1
  validate({ "{- hello -}" }, 0, 10, "line", { { 0, 0, 2 }, { 0, 8, 10 } }, { cms = mb_cms, pad = true })

  -- Multi-pair: pair 2
  validate({ "{# hello #}" }, 0, 10, "line", { { 0, 0, 2 }, { 0, 8, 10 } }, { cms = mb_cms, pad = true })
end

T["base"]["match_block_comment"] = function()
  local function validate(lines, range, motion, expected, opts)
    opts = opts or {}
    local csi = H.make_csi(opts.cms or { { "{-", "-}" }, { "{#", "#}" } }, { pad = true })
    local info = H.match_block_comment(lines, range, range, csi, motion)
    eq(info and { info.lcs_pos, info.rcs_pos }, expected)
  end

  -- single line, line motion, pair 1
  validate({ "{- hello -}" }, { 0, 0, 0, 9 }, "line", { { 0, 0, 2 }, { 0, 8, 10 } })

  -- single line, line motion, pair 2
  validate({ "{# hello #}" }, { 0, 0, 0, 9 }, "line", { { 0, 0, 2 }, { 0, 8, 10 } })

  -- multi line: LCS on line 1, RCS on line 2
  validate({ "{- a", "b -}" }, { 0, 0, 1, 4 }, "line", { { 0, 0, 2 }, { 1, 1, 3 } })

  -- multi line (n=3): LCS on line 1, RCS on line 3
  validate({ "{- a", "b", "c -}" }, { 0, 0, 2, 4 }, "line", { { 0, 0, 2 }, { 2, 1, 3 } })

  -- with leading whitespace
  validate({ "  {- hello -}" }, { 0, 0, 0, 11 }, "line", { { 0, 2, 4 }, { 0, 10, 12 } })

  -- char motion
  validate({ "/* hello */" }, { 0, 0, 0, 10 }, "char", { { 0, 0, 2 }, { 0, 8, 10 } }, { cms = { { "/*", "*/" } } })

  -- no match
  validate({ "hello" }, { 0, 0, 0, 4 }, "line", nil)

  -- no match (only LCS, no RCS)
  validate({ "{- hello" }, { 0, 0, 0, 7 }, "line", nil)

  -- different markers (same prefix, different content)
  validate(
    { "{+ hello +}" },
    { 0, 0, 0, 9 },
    "line",
    { { 0, 0, 2 }, { 0, 8, 10 } },
    { cms = { { "{-", "-}" }, { "{+", "+}" } } }
  )
end

T["base"]["resolve"] = function()
  local function validate(ft, cs, ctype, insert_space, exp)
    set_context({ bo = { filetype = ft, commentstring = cs } })
    local r = child.lua_func(function(ctype_, insert_space_)
      local _H = require("celeste_comment").H
      local cfg = { insert_space = insert_space_ ~= false, hooks = {} }
      local csi = assert(_H.resolve(_H.make_pos(0, 0, 0), ctype_, cfg, { 1, 1, 1, 1 }))
      return { csi.tlcs, csi.trcs }
    end, ctype, insert_space)
    eq(r, exp)
  end

  validate("cpp", "// %s", 2, true, { "/*", "*/" })
  validate("cpp", "// %s", 1, true, { "//", "" })
  validate("lua", "-- %s", 2, true, { "--[[", "]]" })
  validate("lua", "-- %s", 1, true, { "--", "" })
  validate("html", "<!-- %s -->", 2, true, { "<!--", "-->" })
  validate("cpp", "// %s", 2, false, { "/*", "*/" })
end

T["base"]["normalize_flags"] = function()
  local function validate(v, exp) eq({ H.normalize_flags(v, { a = 1, b = 2, c = 4 }, "test") }, exp) end
  validate("a", { 1 })
  validate("b", { 2 })
  validate("c", { 4 })
  validate("a | b", { 3 })
  validate("a | b | c", { 7 })
  validate("a  |  b  |  c", { 7 })
  validate(" a | b | c ", { 7 })
  validate(0, { 0 })
  validate(1, { 1 })
  validate(5, { 5 })
  validate(7, { 7 })
  validate(99, { 3 })
  validate(-1, { 7 })
  validate("", { 0 })
  validate("a | invalid", { 0, "invalid part 'invalid' of 'test'" })
  validate("invalid | a", { 0, "invalid part 'invalid' of 'test'" })
  validate("a | b | invalid", { 0, "invalid part 'invalid' of 'test'" })
  validate("x", { 0, "invalid part 'x' of 'test'" })
  validate({}, { 0, "expected string|number for 'test' but got table" })
  validate(true, { 0, "expected string|number for 'test' but got boolean" })
end

-- Edits tests ────────────────────────────────────────────────────────────────

T["edits"] = new_set()

T["edits"]["sort"] = function()
  local edits = {
    { range = { 2, 3, 2, 3 }, text = { "Y" } },
    { range = { 0, 1, 0, 1 }, text = { "X" } },
    { range = { 1, 0, 1, 0 }, text = { "Z" } },
    { range = { 2, 0, 2, 0 }, text = { "W" } },
  }
  edits.need_sort = true

  H.sort_edits(edits)

  eq(edits.need_sort, nil)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 1)
  eq(edits[2].range[1], 1)
  eq(edits[2].range[2], 0)
  eq(edits[3].range[1], 2)
  eq(edits[3].range[2], 0)
  eq(edits[4].range[1], 2)
  eq(edits[4].range[2], 3)
end

T["edits"]["sort and commit"] = function()
  local edits = {
    { range = { 2, 1, 2, 1 }, text = { "X" } },
    { range = { 0, 0, 0, 0 }, text = { "Z" } },
    { range = { 1, 2, 1, 2 }, text = { "Y" } },
  }

  set_lines({ "ab", "cd", "ef" })
  child.lua_func(function(e)
    e.need_sort = true
    e.any_multi = true
    require("celeste_comment").H.commit_edits(0, nil, nil, e, false)
  end, edits)
  eq_lines({ "Zab", "cdY", "eXf" })
end

T["edits"]["commit_edits"] = function()
  local function commit(edits, opts)
    opts = opts or {}
    child.lua_func(function(e, need_sort, any_multi)
      if need_sort then e.need_sort = true end
      if any_multi then e.any_multi = true end
      require("celeste_comment").H.commit_edits(0, nil, nil, e, false)
    end, edits, opts.need_sort == true, opts.any_multi == true)
  end

  -- 1. any_multi + set_text: multi-element text, expand 1 line to 3
  set_lines({ "hello" })
  commit({ { range = { 0, 0, 0, 5 }, text = { "/*", "hello", "*/" } } }, { any_multi = true })
  eq_lines({ "/*", "hello", "*/" })

  -- 2. any_multi + set_text: multi-line range replaced with fewer lines (delete 2 lines)
  set_lines({ "a", "b", "c", "d" })
  commit({ { range = { 1, 0, 3, 1 }, text = { "x" } } }, { any_multi = true })
  eq_lines({ "a", "x" })

  -- 3. any_multi + set_text: append beyond buffer (max <= range[1])
  set_lines({ "aa", "bb" })
  commit({ { range = { 2, 0, 2, 0 }, text = { "cc" } } }, { any_multi = true })
  eq_lines({ "aa", "bb", "cc" })

  -- 4. sentinel: insert 1 line at start
  set_lines({ "aa", "bb" })
  commit({ { range = { 0, -1, 0, -1 }, text = { "/*" } } }, { any_multi = true })
  eq_lines({ "/*", "aa", "bb" })

  -- 5. sentinel: insert 1 line in middle
  set_lines({ "aa", "bb" })
  commit({ { range = { 1, -1, 1, -1 }, text = { "/*" } } }, { any_multi = true })
  eq_lines({ "aa", "/*", "bb" })

  -- 6. sentinel: insert 2 lines at start
  set_lines({ "aa" })
  commit({ { range = { 0, -1, 0, -1 }, text = { "/*", "*/" } } }, { any_multi = true })
  eq_lines({ "/*", "*/", "aa" })

  -- 7. sentinel: delete 1 line
  set_lines({ "aa", "bb", "cc" })
  commit({ { range = { 1, -1, 2, -1 }, text = {} } }, { any_multi = true })
  eq_lines({ "aa", "cc" })

  -- 8. sentinel: delete 2 lines
  set_lines({ "aa", "bb", "cc" })
  commit({ { range = { 0, -1, 2, -1 }, text = {} } }, { any_multi = true })
  eq_lines({ "cc" })

  -- 9. sentinel + need_sort: insert both /* and */ around content
  set_lines({ "aa", "bb" })
  commit({
    { range = { 2, -1, 2, -1 }, text = { "*/" } },
    { range = { 0, -1, 0, -1 }, text = { "/*" } },
  }, { need_sort = true, any_multi = true })
  eq_lines({ "/*", "aa", "bb", "*/" })

  -- 10. non-any_multi: apply_edits path
  set_lines({ "hello" })
  child.lua_func(
    function(e) require("celeste_comment").H.commit_edits(0, { 0, 0, 0, 5 }, { "hello" }, e, false) end,
    { { range = { 0, 0, 0, 0 }, text = { "# " } } }
  )
  eq_lines({ "# hello" })
end

T["edits"]["make_comment_edits"] = function()
  local csi = H.make_csi({ { "# ", "" } })
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "hello", {})
  assert(edits)
  eq(apply_edits("hello", edits), "# hello")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "# " } } })
end

T["edits"]["make_comment_edits_with_indent"] = function()
  local csi = H.make_csi({ { "# ", "" } })
  local edits = H.make_comment_edits(make_line_info({ offset = 2, csi = csi }), "  hello", {})
  assert(edits)
  eq(apply_edits("  hello", edits), "  # hello")
  validate_edits(edits, { { range = { 0, 2, 0, 2 }, text = { "# " } } })
end

T["edits"]["make_uncomment_edits"] = function()
  local info = make_line_info({ lcs_pos = { 0, 0, 1 } })
  local edits = H.make_uncomment_edits(info, "# hello", {})
  assert(edits)
  eq(apply_edits("# hello", edits), "hello")
  validate_edits(edits, { { range = { 0, 0, 0, 2 }, text = { "" } } })
end

T["edits"]["make_comment_edits_with_rcs"] = function()
  local csi = H.make_csi({ { "<!-- ", " -->" } }, { pad = true })
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "hello", {})
  assert(edits)
  eq(apply_edits("hello", edits), "<!-- hello -->")
  validate_edits(edits, {
    { range = { 0, 0, 0, 0 }, text = { "<!-- " } },
    { range = { 0, 5, 0, 5 }, text = { " -->" } },
  })
end

T["edits"]["make_uncomment_edits_with_rcs"] = function()
  local info = make_line_info({ lcs_pos = { 0, 0, 4 }, rcs_pos = { 0, 10, 13 } })
  local edits = H.make_uncomment_edits(info, "<!-- hello -->", {})
  assert(edits)
  eq(apply_edits("<!-- hello -->", edits), "hello")
  validate_edits(edits, { { range = { 0, 0, 0, 5 }, text = { "" } }, { range = { 0, 10, 0, 14 }, text = { "" } } })
end

T["edits"]["make_comment_edits_blank_line"] = function()
  local csi = H.make_csi({ { "# ", "" } })
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "", {})
  assert(edits)
  eq(apply_edits("", edits), "# ")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "# " } } })
end

T["edits"]["make_comment_edits_noindent"] = function()
  local csi = H.make_csi({ { "// ", "" } })
  local cfg = { line_comment_no_indent = true }
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "  code", cfg)
  assert(edits)
  eq(apply_edits("  code", edits), "//   code")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "// " } } })
end

T["edits"]["make_block_comment_edits_two_lines"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "hello", "world" }
  local edits = H.make_block_comment_edits(lines, csi, { 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* hello")
  eq(lines[2], "world */")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 1, 5, 1, 5 }, text = { " */" } } })
end

T["edits"]["make_block_comment_edits_empty_lines"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "  " }
  local edits = H.make_block_comment_edits(lines, csi, { 0, 0, 0, 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*    */")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 0, 2, 0, 2 }, text = { " */" } } })

  lines = { "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 1, 0, 1 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*    */")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 0, 2, 0, 2 }, text = { " */" } } })

  lines = { "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 2, 0, 2 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*    */")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 0, 2, 0, 2 }, text = { " */" } } })

  -- insmode
  lines = { "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 0, 0, 0 }, { insmode = true })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*  */  ")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 0, 0, 0, 0 }, text = { " */" } } })

  lines = { "  ", "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 0, 1, 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines, { "/*   ", "   */" })
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 1, 2, 1, 2 }, text = { " */" } } })
end

T["edits"]["make_block_comment_edits_single_line"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "hello" }
  local edits = H.make_block_comment_edits(lines, csi, { 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* hello */")
  validate_edits(edits, { { range = { 0, 0, 0, 0 }, text = { "/* " } }, { range = { 0, 5, 0, 5 }, text = { " */" } } })
end

T["edits"]["make_block_uncomment_edits_multi_line"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "/* hello", "world */" }
  local info = H.block_comment_info(lines, csi, "line", { 0, 0, 1, 11 })
  assert(info)
  local edits = H.make_block_uncomment_edits(info)
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "hello")
  eq(lines[2], "world")
  validate_edits(edits, { { range = { 0, 0, 0, 3 }, text = { "" } }, { range = { 1, 5, 1, 8 }, text = { "" } } })
end

T["edits"]["make_block_uncomment_edits_single_line"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "/* hello */" }
  local info = H.block_comment_info(lines, csi, "char", { 0, 0, 0, 10 })
  assert(info)
  local edits = H.make_block_uncomment_edits(info)
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "hello")
  validate_edits(edits, { { range = { 0, 0, 0, 3 }, text = { "" } }, { range = { 0, 8, 0, 11 }, text = { "" } } })
end

T["edits"]["make_block_partial_edits"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "hello world" }
  local edits = H.make_block_partial_edits(lines, csi, { 0, 3, 0, 7 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "hel/* lo wo */rld")
  validate_edits(edits, { { range = { 0, 3, 0, 3 }, text = { "/* " } }, { range = { 0, 8, 0, 8 }, text = { " */" } } })
end

T["edits"]["compute_line_edits_actions"] = function()
  local ACT = M.ACTION
  local csi = H.make_csi({ { "// ", "" } })
  local cfg = { hooks = {} }

  -- kToggle: all uncommented → all comment
  local lines = { "hello", "world" }
  local edits = H.compute_line_edits(lines, { 0, 0, 1, 5 }, "line", csi, cfg, ACT.kToggle)
  H.apply_edits(lines, edits)
  eq(lines, { "// hello", "// world" })

  -- kToggle: all commented → all uncomment
  lines = { "// hello", "// world" }
  edits = H.compute_line_edits(lines, { 0, 0, 1, 11 }, "line", csi, cfg, ACT.kToggle)
  H.apply_edits(lines, edits)
  eq(lines, { "hello", "world" })

  -- kToggle: mixed → all comment
  lines = { "hello", "// world" }
  edits = H.compute_line_edits(lines, { 0, 0, 1, 9 }, "line", csi, cfg, ACT.kToggle)
  H.apply_edits(lines, edits)
  eq(lines, { "// hello", "// // world" })

  -- kInvert: per-line toggle
  lines = { "hello", "// world" }
  edits = H.compute_line_edits(lines, { 0, 0, 1, 9 }, "line", csi, cfg, ACT.kInvert)
  H.apply_edits(lines, edits)
  eq(lines, { "// hello", "world" })

  -- kForceAdd: all get comment (already-commented get another layer)
  lines = { "hello", "// world" }
  edits = H.compute_line_edits(lines, { 0, 0, 1, 9 }, "line", csi, cfg, ACT.kForceAdd)
  H.apply_edits(lines, edits)
  eq(lines, { "// hello", "// // world" })

  -- kForceRemove: only commented lines get uncommented
  lines = { "hello", "// world" }
  edits = H.compute_line_edits(lines, { 0, 0, 1, 9 }, "line", csi, cfg, ACT.kForceRemove)
  H.apply_edits(lines, edits)
  eq(lines, { "hello", "world" })
end

T["edits"]["compute_block_edits_actions"] = function()
  local ACT = M.ACTION
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local cfg = {}

  -- kToggle: no existing block → add
  local lines = { "hello" }
  local edits = H.compute_block_edits(lines, { 0, 0, 0, 5 }, "line", csi, cfg, ACT.kToggle)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* hello */")

  -- kToggle: existing block → remove
  lines = { "/* hello */" }
  edits = H.compute_block_edits(lines, { 0, 0, 0, 11 }, "line", csi, cfg, ACT.kToggle)
  H.apply_edits(lines, edits)
  eq(lines[1], "hello")

  -- kForceAdd: no existing → add
  lines = { "hello" }
  edits = H.compute_block_edits(lines, { 0, 0, 0, 5 }, "line", csi, cfg, ACT.kForceAdd)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* hello */")

  -- kForceAdd: existing block → add nested
  lines = { "/* hello */" }
  edits = H.compute_block_edits(lines, { 0, 0, 0, 11 }, "line", csi, cfg, ACT.kForceAdd)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* /* hello */ */")

  -- kForceRemove: existing block → remove
  lines = { "/* hello */" }
  edits = H.compute_block_edits(lines, { 0, 0, 0, 11 }, "line", csi, cfg, ACT.kForceRemove)
  H.apply_edits(lines, edits)
  eq(lines[1], "hello")

  -- kForceRemove: no block → skip
  lines = { "hello" }
  edits = H.compute_block_edits(lines, { 0, 0, 0, 5 }, "line", csi, cfg, ACT.kForceRemove)
  eq(edits, nil)
end

-- Guess indentation───────────────────────────────────────────────────────────

T["guess_indentation"] = new_set()

T["guess_indentation"]["port of VSCode indentationGuesser"] = function()
  local function tg(di, dt, ei, et, lines, msg)
    local r = H.guess_indentation(lines, dt, di)
    eq(r.insert_spaces, ei, msg)
    eq(r.tab_size, et, msg)
  end
  local function ag(ei, et, lines, msg)
    if ei == nil then
      -- cannot guess insertSpaces
      if et == nil then
        -- cannot guess tabSize
        tg(true, 13370, true, 13370, lines, msg)
        tg(false, 13371, false, 13371, lines, msg)
      elseif type(et) == "number" then
        -- can guess tabSize
        tg(true, 13370, true, et, lines, msg)
        tg(false, 13371, false, et, lines, msg)
      else
        -- can only guess tabSize when insertSpaces is true
        tg(true, 13370, true, et[1], lines, msg)
        tg(false, 13371, false, 13371, lines, msg)
      end
    else
      -- can guess insertSpaces
      if et == nil then
        tg(true, 13370, ei, 13370, lines, msg)
        tg(false, 13371, ei, 13371, lines, msg)
      elseif type(et) == "number" then
        tg(true, 13370, ei, et, lines, msg)
        tg(false, 13371, ei, et, lines, msg)
      else
        -- can only guess tabSize when insertSpaces is true
        if ei == true then
          tg(true, 13370, ei, et[1], lines, msg)
          tg(false, 13371, ei, et[1], lines, msg)
        else
          tg(true, 13370, ei, 13370, lines, msg)
          tg(false, 13371, ei, 13371, lines, msg)
        end
      end
    end
  end

  -- guess indentation 1 (ported from VSCode textModel.test.ts)
  ag(nil, nil, { "x", "x", "x", "x", "x", "x", "x" }, "no clues")
  ag(false, nil, { "\tx", "x", "x", "x", "x", "x", "x" }, "no spaces, 1xTAB")
  ag(true, 2, { "  x", "x", "x", "x", "x", "x", "x" }, "1x2")
  ag(false, nil, { "\tx", "\tx", "\tx", "\tx", "\tx", "\tx", "\tx" }, "7xTAB")
  ag(nil, { 2 }, { "\tx", "  x", "\tx", "  x", "\tx", "  x", "\tx", "  x" }, "4x2, 4xTAB")
  ag(false, nil, { "\tx", " x", "\tx", " x", "\tx", " x", "\tx", " x" }, "4x1, 4xTAB")
  ag(false, nil, { "\tx", "\tx", "  x", "\tx", "  x", "\tx", "  x", "\tx", "  x" }, "4x2, 5xTAB")
  ag(false, nil, { "\tx", "\tx", "x", "\tx", "x", "\tx", "x", "\tx", "  x" }, "1x2, 5xTAB")
  ag(false, nil, { "\tx", "\tx", "x", "\tx", "x", "\tx", "x", "\tx", "    x" }, "1x4, 5xTAB")
  ag(false, nil, { "\tx", "\tx", "x", "\tx", "x", "\tx", "  x", "\tx", "    x" }, "1x2, 1x4, 5xTAB")
  ag(nil, nil, { "x", " x", " x", " x", " x", " x", " x", " x" }, "7x1 - 1 space is never guessed as an indentation")
  ag(true, nil, { "x", "          x", " x", " x", " x", " x", " x", " x" }, "1x10, 6x1")
  ag(
    nil,
    nil,
    { "", "  ", "    ", "      ", "        ", "          ", "            ", "              " },
    "whitespace lines don't count"
  )
  ag(true, 3, { "x", "   x", "   x", "    x", "x", "   x", "   x", "    x", "x", "   x", "   x", "    x" }, "6x3, 3x4")
  ag(
    true,
    5,
    { "x", "     x", "     x", "    x", "x", "     x", "     x", "    x", "x", "     x", "     x", "    x" },
    "6x5, 3x4"
  )
  ag(true, 7, {
    "x",
    "       x",
    "       x",
    "     x",
    "x",
    "       x",
    "       x",
    "    x",
    "x",
    "       x",
    "       x",
    "    x",
  }, "6x7, 1x5, 2x4")
  ag(true, 2, { "x", "  x", "  x", "  x", "  x", "x", "  x", "  x", "  x", "  x" }, "8x2")
  ag(true, 2, { "x", "  x", "  x", "x", "  x", "  x", "x", "  x", "  x", "x", "  x", "  x" }, "8x2")
  ag(true, 2, { "x", "  x", "    x", "x", "  x", "    x", "x", "  x", "    x", "x", "  x", "    x" }, "4x2, 4x4")
  ag(true, 2, { "x", "  x", "  x", "    x", "x", "  x", "  x", "    x", "x", "  x", "  x", "    x" }, "6x2, 3x4")
  ag(true, 2, { "x", "  x", "  x", "    x", "    x", "x", "  x", "  x", "    x", "    x" }, "4x2, 4x4")
  ag(true, 2, { "x", "  x", "    x", "    x", "x", "  x", "    x", "    x" }, "2x2, 4x4")
  ag(true, 4, { "x", "    x", "    x", "x", "    x", "    x", "x", "    x", "    x", "x", "    x", "    x" }, "8x4")
  ag(true, 2, { "x", "  x", "    x", "    x", "      x", "x", "  x", "    x", "    x", "      x" }, "2x2, 4x4, 2x6")
  ag(true, 2, { "x", "  x", "    x", "    x", "      x", "      x", "        x" }, "1x2, 2x4, 2x6, 1x8")
  ag(true, 4, {
    "x",
    "    x",
    "    x",
    "    x",
    "     x",
    "        x",
    "x",
    "    x",
    "    x",
    "    x",
    "     x",
    "        x",
  }, "6x4, 2x5, 2x8")
  ag(true, 4, { "x", "    x", "    x", "    x", "     x", "        x", "        x" }, "3x4, 1x5, 2x8")
  ag(true, 4, {
    "x",
    "x",
    "    x",
    "    x",
    "     x",
    "        x",
    "        x",
    "x",
    "x",
    "    x",
    "    x",
    "     x",
    "        x",
    "        x",
  }, "6x4, 2x5, 4x8")
  ag(true, 3, { "x", " x", " x", " x", " x", " x", "x", "   x", "    x", "    x" }, "5x1, 2x0, 1x3, 2x4")
  ag(false, nil, { "\t x", " \t x", "\tx" }, "mixed whitespace 1")
  ag(false, nil, { "\tx", "\t    x" }, "mixed whitespace 2")

  -- issue #44991
  ag(true, 4, {
    "a = 10             # 0 space indent",
    "b = 5              # 0 space indent",
    "if a > 10:         # 0 space indent",
    "    a += 1         # 4 space indent      delta 4 spaces",
    "    if b > 5:      # 4 space indent",
    "        b += 1     # 8 space indent      delta 4 spaces",
    "        b += 1     # 8 space indent",
    "        b += 1     # 8 space indent",
    "# comment line 1   # 0 space indent      delta 8 spaces",
    "# comment line 2   # 0 space indent",
    "# comment line 3   # 0 space indent",
    "        b += 1     # 8 space indent      delta 8 spaces",
    "        b += 1     # 8 space indent",
    "        b += 1     # 8 space indent",
  })
  -- issue #55818
  ag(true, 2, {
    "",
    "/* REQUIRE */",
    "",
    "const foo = require ( 'foo' ),",
    "      bar = require ( 'bar' );",
    "",
    "/* MY FN */",
    "",
    "function myFn () {",
    "",
    "  const asd = 1,",
    "        dsa = 2;",
    "",
    "  return bar ( foo ( asd ) );",
    "",
    "}",
    "",
    "/* EXPORT */",
    "",
    "module.exports = myFn;",
    "",
  })
  -- issue #70832
  ag(false, nil, {
    "x",
    "x",
    "x",
    "x",
    "\tx",
    "\t\tx",
    "    x",
    "\t\tx",
    "\tx",
    "\t\tx",
    "\tx",
    "\tx",
    "\tx",
    "\tx",
    "x",
  })
  -- issue #62143
  ag(true, 2, { "x", "x", "  x", "  x" })
  ag(true, 2, { "x", "  - item2", "  - item3" })
  tg(true, 2, true, 2, { "x x", "  x", "  x" })
  tg(true, 2, true, 2, { "x x", "  x", "  x", "    x" })
  tg(true, 2, true, 2, { "<!--test1.md -->", "- item1", "  - item2", "    - item3" })
  -- issue #84217
  ag(true, 4, { "def main():", "    print('hello')" })
  ag(true, 4, { "def main():", "    with open('foo') as fp:", "        print(fp.read())" })
  -- issue #65668 (YAML 2 spaces)
  ag(true, 2, {
    "version: 2",
    "",
    "jobs:",
    "  build:",
    "    docker:",
    "      - circleci/golang:1.11",
    "",
    "  environment:",
    "    TEST_RESULTS: /tmp/test-results",
    "",
    "  steps:",
    "    - checkout",
    "    - run: mkdir -p $TEST_RESULTS",
    "",
    "    - restore_cache:",
    "        keys:",
    "          - v1-pkg-cache",
    "",
    "    - run:",
    "        name: dep ensure",
    "        command: dep ensure -v",
    "",
    "    - run:",
    "        name: Run unit tests",
    "        command: |",
    '          trap "go-junit-report <${TEST_RESULTS}/go-test.out > ${TEST_RESULTS}/go-test-report.xml" EXIT',
    "          go test -v ./... | tee ${TEST_RESULTS}/go-test.out",
    "",
    "    - run:",
    "        name: Build",
    "        command: go build -v",
    "",
    "    - save_cache:",
    "        key: v1-pkg-cache",
    "        paths:",
    '          - "/go/pkg"',
    "",
    "    - store_artifacts:",
    "        path: /tmp/test-results",
    "        destination: raw-test-output",
    "",
    "    - store_test_results:",
    "        path: /tmp/test-results",
  })
  -- issue #249040 (4-space wins over 2-space when predominant)
  ag(true, 4, {
    "function foo() {",
    "    let a = 1;",
    "    let b = 2;",
    "    if (true) {",
    "        console.log(a);",
    "        console.log(b);",
    "    }",
    "    const obj = {",
    "      x: 1,",
    "      y: 2",
    "    };",
    "    return obj;",
    "}",
  })

  -- bufnr path
  set_lines({ "x", "  x", "  x", "  x" })
  local r = child.lua_func(function() return require("celeste_comment").H.guess_indentation(0, 13370, true) end)
  eq(r.insert_spaces, true)
  eq(r.tab_size, 2)
end

-- line_comment_no_indent tests ───────────────────────────────────────────────

T["line_comment_no_indent"] = new_set()

T["line_comment_no_indent"]["gcc on tab-indented line"] = function()
  validate_steps({ "\ta" }, {
    { "gcc", { "#\ta" } },
    { "gcc", { "\ta" } },
  }, { bo = { commentstring = "#%s" }, config = { line_comment_no_indent = true, insert_space = false } })
end

T["line_comment_no_indent"]["gcc on whitespace-only line adds comment at col 0"] = function()
  validate_steps({ "  " }, { { "gcc", { "#  " } } }, {
    bo = { commentstring = "#%s" },
    config = { line_comment_no_indent = true, insert_space = false },
  })
end

T["line_comment_no_indent"]["gcc puts // at col 0"] = function()
  validate_steps({ "  aa", "    bb" }, {
    { "gcc", { "#   aa", "    bb" } },
    { "gcc", { "  aa", "    bb" } },
  }, { bo = { commentstring = "#%s" }, b = { celeste_comment_config = {} } })
end

T["line_comment_no_indent"]["gc motion puts // at col 0"] = function()
  validate_steps({ "  aa", "  bb", "  cc" }, {
    { { "gc", "2j" }, { "--   aa", "--   bb", "--   cc" } },
    { { "gc", "2j" }, { "  aa", "  bb", "  cc" } },
  }, { bo = { commentstring = "--%s" }, b = { celeste_comment_config = {} } })
end

T["line_comment_no_indent"]["recognition: indented comment not uncommented"] = function()
  validate_steps({ "  %% aa", "%%     bb" }, {
    { "gcc", { "   aa", "%%     bb" } },
    { { 1, 5 }, "gcc", { "   aa", "     bb" } },
  }, { bo = { commentstring = "%%%s" }, config = { insert_space = false } })
end

T["line_comment_no_indent"]["gcj motion"] = function()
  validate_steps({ "##   aa", "##   bb" }, {
    { { "gc", "j" }, { "  aa", "  bb" } },
    { { "gc", "j" }, { "##   aa", "##   bb" } },
  }, { bo = { commentstring = "##%s" }, b = { celeste_comment_config = {} } })
end

T["line_comment_no_indent"]["gcgc textobject"] = function()
  validate_steps({ "<!-- hello -->", "<!-- world -->" }, {
    { { 1, 3 }, "gcgc", { "hello", "world" } },
  }, { bo = { commentstring = "<!--%s-->" }, config = { fallback_to_block = "never" } })

  validate_steps({ "<!-- hello -->", "<!-- world -->" }, {
    { { 0, 4 }, "gcgc", { " hello ", "<!-- world -->" } },
  }, { config = { insert_space = false, fallback_to_block = "if_line_cms_wrapped" } })
end

T["line_comment_no_indent"]["indent_algo:vscode + noindent: sol with normalize"] = function()
  validate_steps({ "  aa", "    bb" }, {
    { "gcc", { ";  aa", "    bb" } },
    { "gcc", { "  aa", "    bb" } },
  }, { bo = { commentstring = ";%s" }, config = { insert_space = false } })
end

-- ignore empty lines tests ──────────────────────────────────────────────────

T["ignore_empty_lines"] = new_set()

T["ignore_empty_lines"]["textobject treats blank as uncommented boundary"] = function()
  validate_steps({ "bb", "# aa", "", "# bb", "# cc", "end" }, {
    { { 2, 0 }, "gcgc", { "bb", "# aa", "", "# bb", "# cc", "end" } },
  }, { config = { ignore_empty_lines = "never" } })
end

T["ignore_empty_lines"]["textobject cursor on comment skips blanks when false"] = function()
  validate_steps({ "# a", "", "# b", "end" }, {
    { { 0, 0 }, "dgc", { "", "# b", "end" } },
  }, { config = { ignore_empty_lines = "never" } })
end

T["ignore_empty_lines"]["never: works with empty lines"] = function()
  validate_steps({ "", "  " }, {
    { "gcc", { "# ", "  " } },
    { { 1, 0 }, ".", { "# ", "  # " } },
    { "gck", { "", "  " } },
    { ".", { "# ", "#   " } },
  }, { bo = { tabstop = 2, expandtab = true }, config = { ignore_empty_lines = "never" } })
end

T["ignore_empty_lines"]["always: works with empty lines"] = function()
  validate_steps({ "", "  " }, {
    { "gcc", { "# ", "  " } },
    { { 1, 0 }, ".", { "# ", "#   " } },
    { "gck", { "", "  " } },
    { ".", { "# ", "#   " } },
  }, { bo = { tabstop = 2, expandtab = true }, config = { ignore_empty_lines = "always" } })
end

T["ignore_empty_lines"]["textobject includes blanks when ignore_empty_lines=always"] = function()
  validate_steps({ "# aa", " ", "\t\t", "\t ", "# bb", "  \t", "#cc" }, {
    { { 2, 2 }, "gcgc", { "aa", " ", "\t\t", "\t ", "bb", "  \t", "cc" } },
  }, { config = { ignore_empty_lines = "always" } })
end

T["ignore_empty_lines"]["textobject trims blanks at edges"] = function()
  validate_steps({ "", "# a", "", "# b", "", "# c", "" }, {
    { { 2, 0 }, "dgc", { "", "" } },
  }, { config = { ignore_empty_lines = "always" } })
end

T["ignore_empty_lines"]["mixed: works with empty lines"] = function()
  validate_steps({ "  ", "    " }, {
    { "gcc", { "  # ", "    " } },
    { { 1, 0 }, ".", { "  # ", "    # " } },
    { "gck", { "  ", "    " } },
  }, { bo = { tabstop = 2, expandtab = true }, config = { ignore_empty_lines = "mixed" } })

  -- (3 / 2) * 2 = 2
  validate_steps({ "   " }, {
    { "gcc", { "  #  " } },
    { ".", { "   " } },
  })
end

T["ignore_empty_lines"]["mixed: blank line not participate in indent calc but can be commented"] = function()
  validate_steps({ "    aa", "", "    bb" }, {
    { { "gc", "2j" }, { "    # aa", "    # ", "    # bb" } },
    { { "gc", "2j" }, { "    aa", "    ", "    bb" } },
  }, { config = { ignore_empty_lines = "mixed" } })
end

T["ignore_empty_lines"]["mixed: blank line should not be trimmed after uncomment"] = function()
  validate_steps({ "    # aa", "    # ", "    # bb" }, {
    { { 1, 0 }, "gcc", { "    # aa", "    ", "    # bb" } },
  }, { config = { ignore_empty_lines = "mixed" } })
end

T["ignore_empty_lines"]["mixed: extobject select works"] = function()
  validate_steps({ "    # aa", "    # ", "    # bb" }, {
    { { 1, 0 }, { "v", "ga", "d" }, { "" } },
  }, { config = { ignore_empty_lines = "mixed" } })
end

T["ignore_empty_lines"]["mixed: textobject not skip blanks"] = function()
  validate_steps({ "", "# a", "", "# b", "" }, {
    { { 1, 2 }, "gcgc", { "", "a", "", "# b", "" }, { 1, 0 } },
    { "u", { "", "# a", "", "# b", "" } },
    { { 2, 0 }, "gcgc", { "", "# a", "", "# b", "" }, { 2, 0 } },
  }, { config = { ignore_empty_lines = "mixed" } })

  validate_steps(nil, {
    { { "vga", "d" }, { "", "" } },
    { "u", { "", "# a", "", "# b", "" } },
    { "gcgc", { "", "a", "", "b", "" } },
  }, { config = { ignore_empty_lines = "always" } })
end

T["ignore_empty_lines"]["mixed: gc2j respects indent from non-blank lines"] = function()
  validate_steps({ "    a", "", "    b" }, {
    { { "gc", "2j" }, { "    # a", "    # ", "    # b" } },
  }, { config = { ignore_empty_lines = "mixed" } })
end

T["ignore_empty_lines"]["works with set_text"] = function()
  validate_steps({
    "local M = {",
    "  config = {",
    "    a = 1,",
    "    b = 2,",
    "",
    "    c = 3,",
    "    d = 4,",
    "",
    "    e = 5,",
    "    f = 6,",
    "  }",
    "}",
  }, {
    {
      { 2, 6 },
      "gci{",
      {
        "local M = {",
        "  config = {",
        "    # a = 1,",
        "    # b = 2,",
        "    # ",
        "    # c = 3,",
        "    # d = 4,",
        "    # ",
        "    # e = 5,",
        "    # f = 6,",
        "  }",
        "}",
      },
      { 2, 8 },
    },
  }, {
    config = function()
      return {
        ignore_empty_lines = "mixed",
        hooks = {
          pre_commit_edits = function(ctx) ctx.o_use_set_text = true end,
        },
      }
    end,
  })
end

-- insert_space tests ──────────────────────────────────────────────────────────────

T["insert_space"] = new_set()

T["insert_space"]["insert_space=false linewise"] = function()
  validate_steps({ "hello" }, {
    { "gcc", { "#hello" } },
    { "gcc", { "hello" } },
  }, { bo = { filetype = "python" }, config = { insert_space = false } })
end

T["insert_space"]["insert_space=false blockwise"] = function()
  validate_steps({ "hello" }, {
    { "gbc", { "/*hello*/" } },
    { "gbc", { "hello" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" }, config = { insert_space = false } })
end

T["insert_space"]["insert_space=false does not strip inner space"] = function()
  validate_steps({ "#    hello" }, { { "gcc", { "    hello" } } }, {
    bo = { filetype = "python" },
    config = { insert_space = false },
  })
end

T["insert_space"]["wrapped commentstring (lcs+rcs)"] = function()
  validate_steps({ "hello" }, {
    { "gcc", { "<!--hello-->" } },
    { "gcc", { "hello" } },
  }, {
    bo = { commentstring = "<!--%s-->" },
    config = { cms_confs = false, insert_space = false, fallback_to_block = "if_line_cms_wrapped" },
  })
end

T["insert_space"]["rcs-only commentstring"] = function()
  validate_steps({ "hello" }, {
    { "gcc", { "hello#" } },
    { "gcc", { "hello" } },
  }, { bo = { commentstring = "%s#" }, config = { cms_confs = false, insert_space = false } })
end

-- extra keymap (gco, gcO, gcA) ───────────────────────────────────────────────

T["extra"] = new_set()

T["extra"]["gco inserts comment below"] = function()
  validate_steps({ "aa", "bb", "cc" }, {
    { { 1, 0 }, "gco", { "aa", "bb", "# ", "cc" }, { 2, 2 } },
    { "<Esc>" },
    { { 3, 0 }, "gco", { "aa", "bb", "# ", "cc", "# " }, { 4, 2 } },
  })
end

T["extra"]["gcO inserts comment above"] = function()
  validate_steps({ "aa", "bb", "cc" }, {
    { "gcO", { "# ", "aa", "bb", "cc" }, { 0, 2 } },
    { "<Esc>" },
  })
end

T["extra"]["gcA adds comment at end of line"] = function()
  validate_steps({ "hello" }, { { "gcA", { "hello # " }, { 0, 8 } } })
end

T["extra"]["gcA on empty line"] = function() validate_steps({ "" }, { { "gcA", { "# " }, { 0, 2 } } }) end

T["extra"]["gco inserts --[[ ]] below"] = function()
  validate_steps({ "aa", "bb", "cc" }, {
    { { 1, 0 }, "gco", { "aa", "bb", "--[[  ]]", "cc" }, { 2, 5 } },
    { "1", { "aa", "bb", "--[[ 1 ]]", "cc" } },
  }, {
    bo = { filetype = "wraptest", commentstring = "# %s" },
    config = { cms_confs = { wraptest = { "--[[%s]]" } } },
  })
end

T["extra"]["gcO inserts --[[ ]] above"] = function()
  validate_steps({ "aa", "bb", "cc" }, {
    { { 1, 0 }, "gcO", { "aa", "--[[  ]]", "bb", "cc" }, { 1, 5 } },
    { "1", { "aa", "--[[ 1 ]]", "bb", "cc" }, { 1, 6 } },
  }, {
    bo = { filetype = "wraptest", commentstring = "# %s" },
    config = { cms_confs = { wraptest = { "--[[%s]]" } } },
  })
end

T["extra"]["gcA appends --[[ ]] at eol"] = function()
  validate_steps({ "hello" }, {
    { "gcA", { "hello --[[  ]]" }, { 0, 11 } },
    { "1", { "hello --[[ 1 ]]" }, { 0, 12 } },
  }, {
    bo = { filetype = "wraptest", commentstring = "# %s" },
    config = { cms_confs = { wraptest = { "--[[%s]]" } } },
  })
end

T["extra"]["gcA on empty line with wrapped comment"] = function()
  validate_steps({ "" }, {
    { "gcA", { "--[[  ]]" }, { 0, 5 } },
    { "1", { "--[[ 1 ]]" }, { 0, 6 } },
    { "<Esc>" },
  }, {
    bo = { filetype = "wraptest", commentstring = "# %s" },
    config = { cms_confs = { wraptest = { "--[[%s]]" } } },
  })
end

T["extra"]["rcs-only gco inserts marker below"] = function()
  validate_steps({ "aa", "bb" }, {
    { "gco", { "aa", "#", "bb" }, { 1, 0 } },
    { "x", { "aa", "x#", "bb" }, { 1, 1 } },
    { "<Esc>" },
  }, { bo = { commentstring = "%s#" }, config = { cms_confs = false } })
end

T["extra"]["rcs-only gcO inserts marker above"] = function()
  validate_steps({ "aa", "bb" }, {
    { { 1, 0 }, "gcO", { "aa", "#", "bb" }, { 1, 0 } },
    { "x", { "aa", "x#", "bb" }, { 1, 1 } },
    { "<Esc>" },
  }, { bo = { commentstring = "%s#" }, config = { cms_confs = false } })
end

T["extra"]["rcs-only gcA appends marker at eol"] = function()
  validate_steps({ "hello" }, {
    { "gcA", { "hello  #" }, { 0, 6 } },
    { "x", { "hello x #" }, { 0, 7 } },
    { "<Esc>" },
  }, { bo = { commentstring = "%s#" }, config = { cms_confs = false } })
end

-- linewise tests ─────────────────────────────────────────────────────────────

T["linewise"] = new_set()

T["linewise"]["gcc toggles current line"] = function()
  validate_steps({ "aa", " bb", "  cc" }, {
    { { 1, 0 }, "gcc", { "aa", "#  bb", "  cc" } },
    { "gcc", { "aa", " bb", "  cc" } },
  })
end

T["linewise"]["gc + motion works"] = function()
  validate_steps({ "aa", "bb", "cc", "dd" }, {
    { { "gc", "j" }, { "# aa", "# bb", "cc", "dd" } },
    { { "gc", "j" }, { "aa", "bb", "cc", "dd" } },
  })
end

T["linewise"]["gcc with count"] = function()
  validate_steps({ "a", "b", "c", "d" }, {
    { { 1, 0 }, "2gcc", { "a", "# b", "# c", "d" } },
  })
end

T["linewise"]["visual mode gc"] = function()
  validate_steps({ "aa", "bb", "cc" }, {
    { { 0, 0, 1, 0, "V" }, "gc", { "# aa", "# bb", "cc" } },
  })
end

T["linewise"]["works with folded lines"] = function()
  set_context({ bo = { filetype = "lua" } })
  child.wo.foldmethod = "manual"
  validate_steps({ "  a", "  b", "  c", "  d", "  e", "  f" }, {
    { "zf3j" },
    { "2gcc", { "--   a", "--   b", "--   c", "--   d", "--   e", "  f" } },
    { "gcgc", { "  a", "  b", "  c", "  d", "  e", "  f" } },
  })
end

-- Case-insensitive tests ─────────────────────────────────────────────────────

T["case_insensitive"] = new_set()

T["case_insensitive"]["case_insensitive gcc on @REM variants"] = function()
  -- @REM (uppercase): comment then uncomment
  validate_steps({ "hello" }, {
    { "gcc", { "@REM hello" } },
    { "gcc", { "hello" } },
  }, { bo = { filetype = "bat" }, config = { case_insensitive = true } })

  -- @rem (lowercase): comment produces @REM from config token
  validate_steps({ "world" }, {
    { "gcc", { "@REM world" } },
    { "gcc", { "world" } },
  })

  -- @Rem (mixed case): uncomment, then comment uses config token @REM
  validate_steps({ "@Rem foo" }, {
    { "gcc", { "foo" } },
    { "gcc", { "@REM foo" } },
  })

  -- without case_insensitive
  validate_steps({ "@rEm 123" }, { { "gcc", { "@REM @rEm 123" } } }, { config = { case_insensitive = false } })
end

T["case_insensitive"]["case_insensitive textobject dgc on @REM/@rem"] = function()
  validate_steps({ "code", "@REM hello", "@rem world", "end" }, {
    { { 1, 0 }, "dgc", { "code", "end" } },
  }, { bo = { filetype = "bat" }, config = { case_insensitive = true } })
end

T["case_insensitive"]["case_insensitive gc on mixed case @REM lines"] = function()
  validate_steps({ "@REM a", "@rem b", "@Rem c" }, {
    { { "gc", "2j" }, { "a", "b", "c" } },
    -- Comment back: all get uppercase @REM from config token
    { { "gc", "2j" }, { "@REM a", "@REM b", "@REM c" } },
  }, { bo = { filetype = "bat" }, config = { case_insensitive = true } })
end

-- blockwise tests ────────────────────────────────────────────────────────────

T["blockwise"] = new_set()

T["blockwise"]["gbc on single line"] = function()
  validate_steps({ "hello world" }, {
    { "gbc", { "/* hello world */" } },
    { "gbc", { "hello world" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["gbc on blank and whitespace lines"] = function()
  validate_steps({ "" }, { { "gbc", { "/*  */" } } }, { bo = { filetype = "cpp" } })
  validate_steps({ "   " }, { { "gbc", { "/*     */" } } })
  validate_steps({ "" }, { { { "\\<C-v>", "gb" }, { "/*  */" } } })
  validate_steps({ "" }, { { { "v", "gb" }, { "/*  */" } } })
end

T["blockwise"]["gb + ap on paragraph"] = function()
  validate_steps({ "start", "line1", "line2", "line3", "end" }, {
    { { 1, 0 }, { "gb", "ap" }, { "/* start", "line1", "line2", "line3", "end */" } },
    { { "gb", "ap" }, { "start", "line1", "line2", "line3", "end" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["visual line gb"] = function()
  validate_steps({ "aa", "bb", "cc" }, {
    { { 0, 0, 1, 0, "V" }, "gb", { "/* aa", "bb */", "cc" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["visual block C-v + gb per line"] = function()
  validate_steps({ "aaaa", "bbbb", "cccc" }, {
    { { "\\<C-v>", "2j", "$", "gb" }, { "/* aaaa", "bbbb", "cccc */" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["C-v mid-column gb per line"] = function()
  validate_steps({ "aaaabbbb", "aaaabbbb", "aaaabbbb" }, {
    { { 0, 4 }, { "\\<C-v>", "2j", "l", "l", "gb" }, { "/* aaaabbbb", "aaaabbbb", "aaaabbbb */" } },
    { { 0, 4 }, { "\\<C-v>", "2j", "l", "l", "gb" }, { "aaaabbbb", "aaaabbbb", "aaaabbbb" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["C-v with variable line lengths wraps first/last"] = function()
  -- comment.nvim behavior: /* after indent on first line, */ at end of last line
  validate_steps({
    "local a = vim.fn.doSomething()",
    "  local b = vim.fn.otherFunc(arg1)",
    "  return a + b",
  }, {
    {
      { 0, 12 },
      { "\\<C-v>", "j", "j", "$", "gb" },
      { "/* local a = vim.fn.doSomething()", "  local b = vim.fn.otherFunc(arg1)", "  return a + b */" },
    },
    {
      { 0, 12 },
      { "\\<C-v>", "j", "j", "$", "gb" },
      { "local a = vim.fn.doSomething()", "  local b = vim.fn.otherFunc(arg1)", "  return a + b" },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["C-v tab indent and mixed scenarios"] = function()
  -- Tab indent at tabstop=4
  validate_steps({ "\t\taaa", "\t\tbbb" }, {
    { { 0, 0 }, { "\\<C-v>", "j", "$", "gb" }, { "\t\t/* aaa", "\t\tbbb */" } },
    { { 0, 0 }, { "\\<C-v>", "j", "$", "gb" }, { "\t\taaa", "\t\tbbb" } },
  }, { bo = { tabstop = 4, filetype = "cpp", commentstring = "// %s" } })

  -- Mixed indent (spaces of different widths)
  validate_steps({ "    aaa", "  bbb", "    ccc" }, {
    { { 0, 0 }, { "\\<C-v>", "j", "j", "$", "gb" }, { "    /* aaa", "  bbb", "    ccc */" } },
    { { 0, 0 }, { "\\<C-v>", "j", "j", "$", "gb" }, { "    aaa", "  bbb", "    ccc" } },
  })

  -- Different tab widths, consistent tab indentation
  validate_steps({ "\taaa", "\t\tbbb", "\tccc" }, {
    { { 0, 0 }, { "\\<C-v>", "j", "j", "$", "gb" }, { "\t/* aaa", "\t\tbbb", "\tccc */" } },
    { { 0, 0 }, { "\\<C-v>", "j", "j", "$", "gb" }, { "\taaa", "\t\tbbb", "\tccc" } },
  })
end

T["blockwise"]["v multi-line mid-column gb wraps first/last"] = function()
  validate_steps({ "  start", "  middle text", "  more lines", "  end line" }, {
    { { 1, 2 }, { "vjj", "$", "gb" }, { "  start", "  /* middle text", "  more lines", "  end line */" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v single-line mid-column gb wraps selection"] = function()
  validate_steps({ "hello world" }, {
    { { 0, 2 }, { "v", "6l", "gb" }, { "he/* llo wor */ld" } },
    { { 0, 4 }, "gbgb", { "hello world" } },
    { lines = { "a你b" }, { 0, 0 }, { "v", "l", "gb" }, { "/* a你 */b" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v multi-line both mid-column gb wraps first/last"] = function()
  validate_steps({ "aa", "bbbbbbbb", "cccccccc", "dd" }, {
    { { 1, 2 }, { "v", "j", "3l", "gb" }, { "aa", "bb/* bbbbbb", "cccccc */cc", "dd" } },
    { { 1, 4 }, { "gbgb" }, { "aa", "bbbbbbbb", "cccccccc", "dd" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["gbgb toggles block comment via textobject"] = function()
  validate_steps({ "  --[[ line 1", "  line 2", "  line 3 ]]" }, {
    { { "gb", "ap" }, { "  line 1", "  line 2", "  line 3" } },
  }, { bo = { filetype = "lua", commentstring = "-- %s" } })
end

T["blockwise"]["block_nesting=false: nested /* */ is uncommented"] = function()
  validate_steps({ "/* a /* b */ c */" }, { { { 0, 5 }, "gbc", { "a /* b */ c" } } }, {
    bo = { filetype = "cpp", commentstring = "// %s" },
  })
end

T["blockwise"]["gbc then gbgb on inline block comment restores original"] = function()
  local input = "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),"
  validate_steps({ input }, {
    {
      { 0, 30 },
      "gbc",
      { "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */" },
    },
    { { 0, 30 }, "gbgb", { input } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v selects partial inner /* */ adds comment layer"] = function()
  local line = "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */"
  validate_steps({ line }, {
    {
      { 0, 10 },
      { "v", "19l", "gb" },
      { "        /*/*  /* key */ EncodeAsS */tring(k), /* timestamp */ EncodeAsUint64(k + 1), */" },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v selects /* key */ Enco without rcs adds layer, not remove"] = function()
  local line = "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),"
  validate_steps({ line }, {
    {
      { 0, 8 },
      { "v", "10l", "gb" },
      { "        /* /* key */ E */ncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1)," },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v selects /* key */ with trailing space wraps not remove"] = function()
  local line = "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),"
  validate_steps({ line }, {
    {
      { 0, 8 },
      { "v", "9l", "gb" },
      { "        /* /* key */  */EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1)," },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v selects exact /* timestamp */ removes inner pair"] = function()
  local line = "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */"
  validate_steps({ line }, {
    {
      { 0, 36 },
      { "v", "16l", "gb" },
      { "        /* /* key */ EncodeAsString(/* k), /* timestamp  */*/ EncodeAsUint64(k + 1), */" },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["v selects /* timestamp */ with trailing space tolerates whitespace"] = function()
  local line = "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */"
  validate_steps({ line }, {
    {
      { 0, 36 },
      { "v", "17l", "gb" },
      { "        /* /* key */ EncodeAsString(/* k), /* timestamp * *// EncodeAsUint64(k + 1), */" },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["gbgb outermost content on nested line removes outer"] = function()
  validate_steps({ "/* a /* b */ c */" }, { { { 0, 4 }, "gbgb", { "a /* b */ c" } } }, {
    bo = { filetype = "cpp", commentstring = "// %s" },
  })
end

T["blockwise"]["gbgb inside innermost nested removes only inner"] = function()
  validate_steps({ "/* a /* b */ c */" }, { { { 0, 11 }, "gbgb", { "/* a b c */" } } }, {
    bo = { filetype = "cpp", commentstring = "// %s" },
  })
end

T["blockwise"]["gbgb outermost content targets outermost pair"] = function()
  validate_steps({ "/* a /* b */ c */" }, { { { 0, 4 }, "gbgb", { "a /* b */ c" } } }, {
    bo = { filetype = "cpp", commentstring = "// %s" },
  })
end

T["blockwise"]["gbgb between two block comments returns"] = function()
  validate_steps({ "/* a */ str() /* b */" }, { { { 0, 9 }, "gbgb", { "/* a */ str() /* b */" } } }, {
    bo = { filetype = "cpp", commentstring = "// %s" },
  })
end

T["blockwise"]["gbgb three-level nested various cursor positions"] = function()
  -- Cursor in innermost (c) → removes innermost pair
  validate_steps({ "/* a /* b /* c */ d */ e */" }, {
    { { 0, 16 }, "gbgb", { "/* a /* b c d */ e */" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
  -- Cursor in intermediate (b) → also removes innermost pair (gb count=1)
  validate_steps({ "/* a /* b /* c */ d */ e */" }, {
    { { 0, 10 }, "gbgb", { "/* a /* b c d */ e */" } },
  })
  -- Cursor in outermost (a) → only outermost pair found, removes it
  validate_steps({ "/* a /* b /* c */ d */ e */" }, {
    { { 0, 4 }, "gbgb", { "a /* b /* c */ d */ e" } },
  })
end

T["blockwise"]["d2gb deletes middle pair in 3-level nested"] = function()
  validate_steps({ "/* a /* b /* c */ d */ e */" }, {
    { { 0, 11 }, { "d", "2", "gb" }, { "/* a  e */" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["d3gb deletes outermost pair"] = function()
  validate_steps({ "/* a /* b /* c */ d */ e */" }, {
    { { 0, 11 }, { "d", "3", "gb" }, { "" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["gbap multi-line nested with block_nesting=false"] = function()
  validate_steps({ "/* a", "  /* b */", "c */" }, {
    { { 0, 1 }, { "gb", "ap" }, { "a", "  /* b */", "c" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["blockwise"]["gbgb on python docstring"] = function()
  validate_steps({ '"""', "hello", '"""' }, {
    { { 1, 0 }, "gbgb", { "", "hello", "" } },
  }, { bo = { filetype = "python" } })
end

T["blockwise"]["empty selection and use set_text"] = function()
  validate_steps({ "begin", "", "", "", "", "", "end" }, {
    -- case1:
    { { 1, 1 }, { "v", "gb" }, { "begin", "/*  */", "", "", "", "", "end" } },
    { "u", { "begin", "", "", "", "", "", "end" } },
    -- case2:
    { { 1, 1 }, { "\\<C-v>", "gb" }, { "begin", "/*  */", "", "", "", "", "end" } },
    { "u" },
    -- case3:
    { { 1, 1 }, { "v", "3j", "gb" }, { "begin", "/* ", "", "", " */", "", "end" } },
    { "u", { "begin", "", "", "", "", "", "end" } },
    -- case4:
    { { 1, 1 }, { "\\<C-v>", "3j", "gb" }, { "begin", "/* ", "", "", " */", "", "end" } },
    { "u", { "begin", "", "", "", "", "", "end" } },
  }, {
    bo = { filetype = "cpp" },
    config = function()
      return { hooks = { pre_commit_edits = function(ctx) ctx.o_use_set_text = true end } }
    end,
  })
end

T["blockwise"]["multi block cms works"] = function()
  validate_steps({ "hello" }, {
    { { 0, 0 }, "gbc", { "{- hello -}" } },
    { "gbc", { "hello" } },
    { lines = { "a", "b", "c" }, { 0, 0 }, { "gb", "2j" }, { "{- a", "b", "c -}" } },
    { { 0, 3 }, "gbgb", { "a", "b", "c" } },
    { lines = { "{+ a", "b", "c +}" }, { 0, 0 }, "gbgb", { "a", "b", "c" } },
    { lines = { "hello" }, { 0, 0 }, "gbc", { "{- hello -}" } },
    { { 0, 3 }, "gbgb", { "hello" } },
    { lines = { "{+ hello +}" }, { 0, 3 }, "gbc", { "hello" } },
    { lines = { "before hello after" }, { 0, 7 }, { "v", "4l", "gb" }, { "before {- hello -} after" } },
    { { 0, 8 }, "gbgb", { "before hello after" } },
    { lines = { "x {- a", "b -} y" }, { 0, 3 }, "dgb", { "x  y" } },
    { lines = { "a b ", "c d e" }, { 0, 2 }, { "v", "j", "2l", "gb" }, { "a {- b ", "c d e -}" } },
    { lines = { "{- a -}  {+ b +}" }, { 0, 2 }, "gbgb", { "a  {+ b +}" } },
    { lines = { "{- a -}  {+ b +}" }, { 0, 12 }, "gbgb", { "{- a -}  b" } },
    { lines = { "{- a {+ b +} c -}" }, { 0, 8 }, "gbgb", { "{- a b c -}" } },
    { { 0, 3 }, "gbgb", { "a b c" } },
    { lines = { "  {- a", "  b -}  c" }, { 0, 5 }, "dgb", { "    c" } },
  }, { bo = { filetype = "unknown" }, b = { celeste_comment_block_commentstring = { "{-%s-}", "{+%s+}" } } })
end

T["blockwise"]["overlapping markers with /*/{}"] = function()
  -- overlapping markers: {/* (len3) vs /* (len2), */} (len3) vs */ (len2)
  validate_steps({ "x = {/* aaa */}" }, {
    { { 0, 7 }, "gbgb", { "x = aaa" } },
    { lines = { "{/* aaa */}  /* bbb */" }, { 0, 4 }, "gbgb", { "aaa  /* bbb */" } },
    { lines = { "{/* aaa */}  /* bbb */" }, { 0, 15 }, "gbgb", { "{/* aaa */}  bbb" } },
  }, { bo = { filetype = "unknown" }, b = { celeste_comment_block_commentstring = { "{/*%s*/}", "/*%s*/" } } })
end

T["blockwise"]["overlapping markers with {{/{{{"] = function()
  validate_steps({ "{{{ a }}}" }, {
    -- gbgb on {{{ a }}} → selects the outer pair (longer opener wins)
    { { 0, 3 }, "gbgb", { "a" } },
    { lines = { "{{ a }}" }, { 0, 2 }, "gbgb", { "a" } },
    { lines = { "{{{ a }}}  {{ b }}" }, { 0, 3 }, "gbgb", { "a  {{ b }}" } },
    { lines = { "{{{ a }}}  {{ b }}" }, { 0, 12 }, "gbgb", { "{{{ a }}}  b" } },
  }, { bo = { filetype = "unknown" }, b = { celeste_comment_block_commentstring = { "{{%s}}", "{{{%s}}}" } } })
end

-- block_relaxed_detect tests ──────────────────────────────────────────────────

T["block_relaxed_detect"] = new_set({
  hooks = {
    pre_case = function() set_context({ config = { block_relaxed_detect = true } }) end,
  },
})

T["block_relaxed_detect"]["works"] = function()
  set_context({ bo = { filetype = "cpp" } })
  local lines = {
    "   \t\t\t   \t\t\t    ",
    "             ",
    "\t\t               \t",
    "              /*\t\t\t\t    z",
    "       \t\t   b   ",
    "    h    ",
    "a",
    "\t*/    ",
    "                         \t\t\t",
  }
  validate_steps(lines, {
    {
      { 0, 0, 3, 13 },
      "gb",
      {
        "/*    \t\t\t   \t\t\t    ",
        "             ",
        "\t\t               \t",
        "               *//*\t\t\t\t    z",
        "       \t\t   b   ",
        "    h    ",
        "a",
        "\t*/    ",
        "                         \t\t\t",
      },
      { 3, 13 },
    },
    { "u" },
    {
      { 0, 6, 4, 0 },
      "gb",
      {
        "   \t\t\t/*    \t\t\t    ",
        "             ",
        "\t\t               \t",
        "              /*\t\t\t\t    z",
        "  */      \t\t   b   ",
        "    h    ",
        "a",
        "\t*/    ",
        "                         \t\t\t",
      },
      { 4, 0 },
    },
    { "u" },
    {
      { 1, 3, 8, 7 },
      "gb",
      {
        "   \t\t\t   \t\t\t    ",
        "             ",
        "\t\t               \t",
        "              \t\t\t\t    z",
        "       \t\t   b   ",
        "    h    ",
        "a",
        "\t    ",
        "                         \t\t\t",
      },
      { 8, 7 },
    },
  })
end

T["block_relaxed_detect"]["bugfix for gbip"] = function()
  set_context({ bo = { filetype = "lua", tabstop = 2, expandtab = true }, config = { block_relaxed_detect = true } })
  local lines = {
    "function test()",
    "",
    '  map("n", ".", "xxx", {})',
    '  map("n", ".", "yyy", {})',
    "",
    "end",
  }
  validate_steps(lines, {
    {
      { 2, 3 },
      "gbip",
      {
        "function test()",
        "",
        '  --[[ map("n", ".", "xxx", {})',
        '  map("n", ".", "yyy", {}) ]]',
        "",
        "end",
      },
      { 2, 8 },
    },
    { ".", lines, { 2, 3 } },
  })
end

-- textobject tests ───────────────────────────────────────────────────────────

T["textobject"] = new_set()

local function validate_mp(lines, lbegin, csi_pair, pos_pair, exp)
  local pos = make_pos(unpack(pos_pair))
  local csi = H.make_csi(csi_pair)
  local all = H.textobject_block_match_pairs(lines, lbegin, csi, pos)
  for i, r in ipairs(exp) do
    eq(r, all[i].range)
  end
end

T["textobject"]["block_match_pairs"] = function()
  local cs = { { "/* ", " */" } }

  -- Single pair → 1 result
  validate_mp({ "/* a */" }, 1, cs, { 0, 0, 1 }, { { 0, 0, 0, 6 } })

  -- No pair
  validate_mp({ "hello" }, 1, cs, { 0, 0, 1 }, {})

  -- Cursor between two blocks → no pair
  validate_mp({ "/* a */ code /* b */" }, 1, cs, { 0, 0, 10 }, {})

  -- Orphan rcs
  validate_mp({ "hello */ world" }, 1, cs, { 0, 0, 1 }, {})

  -- Three levels, cursor at innermost → 3 pairs, innermost first
  -- * innermost: /* c */
  -- * middle: /* b /* c */ d */
  -- * outermost: /* a /* b /* c */ d */ e */
  validate_mp(
    { "/* a /* b /* c */ d */ e */" },
    1,
    cs,
    { 0, 0, 11 },
    { { 0, 10, 0, 16 }, { 0, 5, 0, 21 }, { 0, 0, 0, 26 } }
  )

  -- Three levels, cursor at outermost → 1 pair (outermost only)
  validate_mp({ "/* a /* b /* c */ d */ e */" }, 1, cs, { 0, 0, 0 }, { { 0, 0, 0, 26 } })

  -- Three levels, cursor in middle → 2 pairs (middle + outer)
  validate_mp({ "/* a /* b /* c */ d */ e */" }, 1, cs, { 0, 0, 7 }, { { 0, 5, 0, 21 }, { 0, 0, 0, 26 } })

  -- Cross-line nested
  validate_mp({ "/* a", "/* b */", "c */" }, 1, cs, { 0, 1, 3 }, { { 1, 0, 1, 6 }, { 0, 0, 2, 3 } })

  -- Lua --[[ ]] style
  validate_mp({ "--[[ a ", "  b ]] " }, 1, { { "--[[ ", " ]]" } }, { 0, 1, 3 }, { { 0, 0, 1, 5 } })
end

T["textobject"]["block_match_pairs multi block cms"] = function()
  local cs = { { "{-", "-}" }, { "{#", "#}" } }

  -- single line, pair 1
  validate_mp({ "{- hello -}" }, 1, cs, { 0, 0, 3 }, { { 0, 0, 0, 10 } })

  -- single line, pair 2
  validate_mp({ "{# hello #}" }, 1, cs, { 0, 0, 3 }, { { 0, 0, 0, 10 } })

  -- multi line, pair 1 spans two lines
  validate_mp({ "{- a", "b -}" }, 1, cs, { 0, 1, 1 }, { { 0, 0, 1, 3 } })

  -- two inline blocks on one line, cursor in first
  validate_mp({ "{- a -} code {# b #}" }, 1, cs, { 0, 0, 2 }, { { 0, 0, 0, 6 } })

  -- two inline blocks on one line, cursor in second
  validate_mp({ "{- a -} code {# b #}" }, 1, cs, { 0, 0, 14 }, { { 0, 13, 0, 19 } })

  -- nested both markers, cursor in outer pair
  validate_mp({ "{- a {# b #} c -}" }, 1, cs, { 0, 0, 2 }, { { 0, 0, 0, 16 } })

  -- nested both markers, cursor in inner pair
  validate_mp({ "{- a {# b #} c -}" }, 1, cs, { 0, 0, 8 }, { { 0, 5, 0, 11 }, { 0, 0, 0, 16 } })

  -- cursor between two blocks, no match
  validate_mp({ "{- a -}  {# b #}" }, 1, cs, { 0, 0, 7 }, {})

  -- no match
  validate_mp({ "hello" }, 1, cs, { 0, 0, 1 }, {})
end

T["textobject"]["block_match_pairs overlapping markers"] = function()
  local cs = { { "{/*", "*/}" }, { "/*", "*/" } }

  -- Single line, cursor inside → both match, outer first
  validate_mp({ "{/* aaa */}" }, 1, cs, { 0, 0, 5 }, { { 0, 0, 0, 10 }, { 0, 1, 0, 9 } })

  -- Standalone /* */ → only the inner pair matches
  validate_mp({ "/* bbb */" }, 1, cs, { 0, 0, 5 }, { { 0, 0, 0, 8 } })

  -- Two blocks inline, cursor in the second
  validate_mp({ "{/* aaa */}  /* bbb */" }, 1, cs, { 0, 0, 15 }, { { 0, 13, 0, 21 } })

  -- Two blocks inline, cursor in the first → outer first
  validate_mp({ "{/* aaa */}  /* bbb */" }, 1, cs, { 0, 0, 5 }, { { 0, 0, 0, 10 }, { 0, 1, 0, 9 } })

  -- Multi-line {/*  */}, cursor on first line → outer first
  validate_mp({ "{/* aaa", "bbb */}" }, 1, cs, { 0, 0, 5 }, { { 0, 0, 1, 6 }, { 0, 1, 1, 5 } })

  -- Multi-line standalone /* */ → only inner pair matches
  validate_mp({ "/* bbb", "ccc */" }, 1, cs, { 0, 1, 3 }, { { 0, 0, 1, 5 } })
end

T["textobject"]["block_match_pairs ordering"] = function()
  validate_mp(
    { "[bc]C....B" },
    1,
    { { "[", "]" }, { "c", "B" }, { "bc", "C" } },
    { 0, 0, 2 },
    { { 0, 0, 0, 3 }, { 0, 2, 0, 9 }, { 0, 1, 0, 4 } }
  )

  validate_mp(
    { "bXcA...B....C" },
    1,
    { { "X", "A" }, { "bXc", "B" }, { "c", "C" } },
    { 0, 0, 3 },
    { { 0, 2, 0, 12 }, { 0, 0, 0, 7 }, { 0, 1, 0, 3 } }
  )

  validate_mp(
    { "     <-c2.1.3" },
    1,
    { { "<-", "1" }, { "-", "2" }, { "c", "3" } },
    { 0, 0, 7 },
    { { 0, 5, 0, 10 }, { 0, 6, 0, 8 }, { 0, 7, 0, 12 } }
  )

  validate_mp({ "a..bA..B" }, 1, { { "a", "A" }, { "b", "B" } }, { 0, 0, 4 }, { { 0, 3, 0, 7 }, { 0, 0, 0, 4 } })

  validate_mp({ "## a ##" }, 1, { { "##", "##" } }, { 0, 0, 3 }, { { 0, 0, 0, 6 } })

  validate_mp({ "aA" }, 1, { { "a", "A" }, { "a", "A" } }, { 0, 0, 0 }, { { 0, 0, 0, 1 } })
end

T["textobject"]["block_inner_range"] = function()
  local bir = H.block_inner_range
  local pad = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local nopad = H.make_csi({ { "/*", "*/" } }, { pad = false })
  local pair_pad, pair_nopad = pad.pairs[1], nopad.pairs[1]

  -- user examples: pad strips exactly one space
  eq(bir({ "/*abc */" }, { 0, 0, 0, 7 }, pair_pad, false), { 0, 2, 0, 4 })
  eq(bir({ "/*abc*/" }, { 0, 0, 0, 6 }, pair_pad, false), { 0, 2, 0, 4 })
  eq(bir({ "/* abc */" }, { 0, 0, 0, 8 }, pair_pad, false), { 0, 3, 0, 5 })
  eq(bir({ "/*  abc */" }, { 0, 0, 0, 9 }, pair_pad, false), { 0, 3, 0, 6 })

  -- empty content → nil
  eq(bir({ "/**/" }, { 0, 0, 0, 3 }, pair_pad, false), nil)

  -- insert_space=false: no padding stripped
  eq(bir({ "/* abc */" }, { 0, 0, 0, 8 }, pair_nopad, false), { 0, 2, 0, 6 })

  -- multi-line: intermediate line preserved fully
  eq(bir({ "/* a", "  b  ", " c */" }, { 0, 0, 2, 4 }, pair_pad, false), { 0, 3, 2, 1 })
end

T["textobject"]["block_match_ts inner"] = function()
  local bmts = H.textobject_block_match_ts
  local pad = H.make_csi({ { "/*", "*/" } }, { pad = true })

  -- single line
  eq(bmts({ "/* hello world */" }, pad, { 0, 0, 0, 16 }, true), { 0, 3, 0, 13 })

  -- no inner → returns ts_range as-is
  eq(bmts({ "/* hello world */" }, pad, { 0, 0, 0, 16 }, false), { 0, 0, 0, 16 })

  -- multi-line
  eq(bmts({ "/* a", "  b  ", " c */" }, pad, { 0, 0, 2, 4 }, true), { 0, 3, 2, 1 })

  -- multi-line with empty trailing line
  eq(bmts({ "/* a", " */" }, pad, { 0, 0, 1, 2 }, true), { 0, 3, 0, 3 })

  -- empty content
  eq(bmts({ "/**/" }, pad, { 0, 0, 0, 3 }, true), nil)

  -- marker mismatch → nil (ts_range doesn't match any pair)
  eq(bmts({ "/* hello world */" }, pad, { 0, 0, 0, 15 }, true), nil)
end

T["textobject"]["line textobject works"] = function()
  validate_steps({ "aa", "#bb", "# cc", "dd", "#ee", "#ff" }, {
    { { 1, 2 }, { "d", "gc" }, { "aa", "dd", "#ee", "#ff" } },
    { { 3, 0 }, ".", { "aa", "dd" } },
    { { 0, 0 }, ".", { "aa", "dd" } },
  })
end

T["textobject"]["block textobject works"] = function()
  validate_steps({ "aaa", "--[[bbb]] ccc --[[ddd  ]] eeee", "ffff --[[ggg   ", "", "hh", "ii ]] jjj" }, {
    {
      { 1, 14 },
      { "d", "gb" },
      { "aaa", "--[[bbb]] ccc  eeee", "ffff --[[ggg   ", "", "hh", "ii ]] jjj" },
    },
    { { 2, 6 }, ".", { "aaa", "--[[bbb]] ccc  eeee", "ffff  jjj" } },
    { { 1, 9 }, ".", { "aaa", "--[[bbb]] ccc  eeee", "ffff  jjj" } }, -- do nothing
  }, { b = { celeste_comment_block_commentstring = "--[[%s]]" } })
end

T["textobject"]["linewise inner"] = function()
  validate_steps({ "# hello world", "# hello world   ", "#" }, {
    { { 0, 3 }, { "d", "gic" }, { "# ", "# hello world   ", "#" } },
    { { 1, 3 }, { "d", "gic" }, { "# ", "# ", "#" } },
    { { 2, 0 }, { "d", "gic" }, { "# ", "# ", "#" } }, -- empty content: do nothing
  })
end

T["textobject"]["blockwise inner"] = function()
  validate_steps({ "/* hello world */", "/* a", "  b  ", " c */" }, {
    { { 0, 4 }, { "d", "gib" }, { "/*  */", "/* a", "  b  ", " c */" } },
    { { 1, 2 }, { "d", "gib" }, { "/*  */", "/*  */" } },
  }, { b = { celeste_comment_block_commentstring = "/*%s*/" } })

  -- empty content
  validate_steps({ "/**/" }, { { { 0, 0 }, { "d", "gib" }, { "/**/" } } })
end

T["textobject"]["auto inner"] = function()
  validate_steps({ "# hello world", "/* hello world */" }, {
    { { 0, 3 }, { "d", "gia" }, { "# ", "/* hello world */" } },
    { { 1, 4 }, { "d", "gia" }, { "# ", "/*  */" } },
  }, { b = { celeste_comment_block_commentstring = "/*%s*/" } })
end

T["textobject"]["auto eol line comment"] = function()
  local lines = { "x = 1 # hello world" }

  validate_steps(lines, {
    { { 0, 9 }, { "v", "ga" }, nil, nil, { { 0, 6, 0, 18 }, "v" } },
    { "<Esc>" },
    { { 0, 9 }, { "v", "gia" }, nil, nil, { { 0, 8, 0, 18 }, "v" } },
    { "<Esc>" },
    { { 0, 9 }, { "d", "ga" }, { "x = 1 " } },
  })

  validate_steps(lines, { { { 0, 9 }, { "d", "gia" }, { "x = 1 # " } } })

  -- cursor on code or on the whitespace before the marker: no match
  validate_steps(lines, {
    { { 0, 0 }, { "d", "ga", "<Esc>" }, lines },
    { { 0, 5 }, { "d", "ga", "<Esc>" }, lines },
  })

  -- marker must be preceded by whitespace
  validate_steps({ "x=1#hi" }, {
    { { 0, 4 }, { "d", "ga", "<Esc>" }, { "x=1#hi" } },
  })

  -- skip a marker not preceded by whitespace, match the next one
  validate_steps({ "a#b # c" }, {
    { { 0, 6 }, { "v", "ga" }, nil, nil, { { 0, 4, 0, 6 }, "v" } },
    { "<Esc>" },
  })

  -- lua: -- and --[[ share the same prefix
  set_context({ bo = { filetype = "lua" } })
  local lua_lines = { "local x = 1 -- hello" }

  validate_steps(lua_lines, {
    { { 0, 16 }, { "v", "ga" }, nil, nil, { { 0, 12, 0, 19 }, "v" } },
    { "<Esc>" },
    { { 0, 16 }, { "v", "gia" }, nil, nil, { { 0, 15, 0, 19 }, "v" } },
    { "<Esc>" },
  })

  -- trailing block comment is skipped, only the line comment after it is matched
  validate_steps({ "local x = 1 --[[ a ]] -- tail" }, {
    { { 0, 26 }, { "v", "ga" }, nil, nil, { { 0, 22, 0, 28 }, "v" } },
    { "<Esc>" },
    { { 0, 26 }, { "v", "gia" }, nil, nil, { { 0, 25, 0, 28 }, "v" } },
    { "<Esc>" },
  })

  -- empty content: outer selects the marker, inner does nothing
  validate_steps({ "x --" }, {
    { { 0, 3 }, { "v", "ga" }, nil, nil, { { 0, 2, 0, 3 }, "v" } },
    { "<Esc>" },
    { { 0, 3 }, { "d", "gia", "<Esc>" }, { "x --" } },
  })

  -- block comment at end of line, cursor after it: no match
  validate_steps({ "local x = 1 --[[ hi ]] " }, {
    { { 0, 22 }, { "d", "ga", "<Esc>" }, { "local x = 1 --[[ hi ]] " } },
  })

  -- unclosed block comment (no closer in the whole buffer): no match
  validate_steps({ "local x = 1 --[[ open" }, {
    { { 0, 18 }, { "d", "ga", "<Esc>" }, { "local x = 1 --[[ open" } },
    { { 0, 18 }, { "d", "gia", "<Esc>" }, { "local x = 1 --[[ open" } },
  })

  -- block comment closed on a later line: block wins, EOL fallback is not used
  validate_steps({ "local x = 1 --[[ open", "still", " ]]" }, {
    { { 0, 18 }, { "v", "ga" }, nil, nil, { { 0, 12, 2, 2 }, "v" } },
    { "<Esc>" },
    { { 0, 18 }, { "v", "gia" }, nil, nil, { { 0, 17, 1, 4 }, "v" } },
    { "<Esc>" },
  })

  -- once an unclosed block is seen, later markers on the line are not line comments
  validate_steps({ "local x = 1 --[[ // not comment" }, {
    { { 0, 21 }, { "d", "ga", "<Esc>" }, { "local x = 1 --[[ // not comment" } },
  })

  -- uncomment_auto does not handle eol comments
  validate_steps(lua_lines, { { { 0, 16 }, "gcu", lua_lines } })

  -- cpp: multi-char closer adjacency and block skipping
  set_context({ bo = { filetype = "cpp" } })
  local cpp_lines = { "int x = 1; /* a // b */ // tail" }

  validate_steps(cpp_lines, {
    { { 0, 28 }, { "v", "ga" }, nil, nil, { { 0, 24, 0, 30 }, "v" } },
    { "<Esc>" },
    { { 0, 28 }, { "v", "gia" }, nil, nil, { { 0, 27, 0, 30 }, "v" } },
    { "<Esc>" },
    { { 0, 28 }, { "d", "ga" }, { "int x = 1; /* a // b */ " } },
  })

  -- block comment starting at the first non-blank: skipped, no match
  validate_steps({ "/* a // b */ x" }, {
    { { 0, 13 }, { "d", "ga", "<Esc>" }, { "/* a // b */ x" } },
  })

  -- multi-char closer followed immediately by code (regression)
  validate_steps({ "/* a */*p = 1; // tail" }, {
    { { 0, 18 }, { "v", "ga" }, nil, nil, { { 0, 15, 0, 21 }, "v" } },
    { "<Esc>" },
    { { 0, 18 }, { "v", "gia" }, nil, nil, { { 0, 18, 0, 21 }, "v" } },
    { "<Esc>" },
  })
end

-- Referenced from: https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L797
T["textobject"]["respect tree-sitter injections"] = function()
  set_context({ bo = { filetype = "vim" } })
  child.lua_func(function() vim.treesitter.start() end)
  validate_steps({
    '"set background=dark',
    '"set termguicolors',
    "lua << EOF",
    "-- print(1)",
    "-- print(2)",
    "EOF",
  }, {
    { { 0, 0 }, { "d", "gc" }, { "lua << EOF", "-- print(1)", "-- print(2)", "EOF" } },
    { { 1, 0 }, ".", { "lua << EOF", "EOF" } },
  })
end

T["textobject"]["auto_linewise_detect"] = function()
  validate_steps({ "aaa", "# bbb", "# ccc", "# ddd", "eee" }, {
    { { 1, 3 }, { "v", "ga" }, nil, { 3, 3 } },
    { "gc", { "aaa", "bbb", "ccc", "ddd", "eee" }, { 3, 1 } },
    { "u", { "aaa", "# bbb", "# ccc", "# ddd", "eee" } },
    { "dga", { "aaa", "eee" } },
  })
end

T["textobject"]["auto_linewise_detect with ignore_empty_lines=always"] = function()
  local original = { " \t", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" }

  validate_steps(original, {
    { { 3, 0 }, "vgad", { " \t", "# aaa", "\t \t ", "", "   ", "#bbb", "\t\t\t" }, { 3, 0 } },
    { "u", original },
  }, { config = { ignore_empty_lines = "never" } })

  validate_steps(nil, {
    { { 4, 1 }, "vgad", { " \t", "# aaa", "\t \t ", " ", "  ", "#bbb", "\t\t\t" }, { 4, 1 } },
    { "u", original },
  }, { config = { ignore_empty_lines = "mixed" } })

  validate_steps(nil, {
    { { 4, 2 }, "vgad", { " \t", "\t\t\t" }, { 1, 0 } },
    { "u", original },
  }, { config = { ignore_empty_lines = "always" } })
  validate_steps(nil, {
    { { 0, 1 }, "vgad", { " ", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" }, { 0, 0 } },
  })
end

T["textobject"]["auto_blockwise_detect"] = function()
  validate_steps({ "start", "/* comment", "\t\t", " \t", "block */", "end" }, {
    { { 2, 2 }, { "v", "ga" }, nil, { 4, 7 } },
    { "gb", { "start", "comment", "\t\t", " \t", "block", "end" }, { 4, 4 } },
    { "u", { "start", "/* comment", "\t\t", " \t", "block */", "end" } },
    { "dga", { "start", "", "end" } },
  }, { bo = { filetype = "cpp" } })
end

T["textobject"]["block textobject works with selection=exclusive"] = function()
  validate_steps({ "  /* hello */  tail", "  after" }, {
    { { 0, 4 }, { "d", "gb" }, { "    tail", "  after" } },
  }, { o = { selection = "exclusive" }, b = { celeste_comment_block_commentstring = "/*%s*/" } })
end

T["textobject"]["auto textobject works with selection=exclusive"] = function()
  validate_steps({ "  /* hello */  tail", "  after" }, {
    { { 0, 4 }, { "d", "ga" }, { "    tail", "  after" } },
  }, { bo = { filetype = "cpp" }, o = { selection = "exclusive" } })
end

T["textobject"]["line textobject works with selection=exclusive"] = function()
  validate_steps({ "aa", "#bb", "# cc", "dd" }, {
    { { 1, 2 }, { "d", "gc" }, { "aa", "dd" } },
  }, { o = { selection = "exclusive" } })
end

T["textobject"]["tabstop + noexpandtab"] = function()
  validate_steps({
    "\tpublic function test(): void {",
    "\t\techo 'hi';",
    "\t}",
  }, {
    {
      { 0, 1, 2, 1 },
      "gb",
      { "\t/* public function test(): void {", "\t\techo 'hi';", "\t} */" },
    },
    {
      "gbgb",
      { "\tpublic function test(): void {", "\t\techo 'hi';", "\t}" },
    },
  }, { bo = { filetype = "php", tabstop = 2, expandtab = false } })
end

T["textobject"]["nested linewise and blockwise comment auto detect"] = function()
  validate_steps({
    "  aaa",
    "  /* bbb",
    "  \t\t\t\t\t\t\t\t",
    "  // cc",
    "  // dd",
    "\t\t\t\t\t\t\t\t\t",
    "  // ee",
    "",
    "   */",
  }, {
    { { 5, 6 }, "vga", nil, { 6, 6 } },
    { "d", { "  aaa", "  /* bbb", "  \t\t\t\t\t\t\t\t", "", "   */" } },
    { "u" },
    {
      { 5, 6 },
      "gcu",
      { "  aaa", "  /* bbb", "  \t\t\t\t\t\t\t\t", "  cc", "  dd", "\t\t\t\t\t\t\t\t\t", "  ee", "", "   */" },
      { 5, 6 },
    },
    {
      "gcu",
      { "  aaa", "  bbb", "  \t\t\t\t\t\t\t\t", "  cc", "  dd", "\t\t\t\t\t\t\t\t\t", "  ee", "", "  " },
      { 5, 6 },
    },
  }, { bo = { filetype = "cpp", tabstop = 2 }, config = { ignore_empty_lines = "always" } })
end

T["textobject"]["auto_uncomment_do_nothing"] = function()
  validate_steps({ "aaa", "bbb", "ccc" }, {
    { { 1, 1 }, "gcu", { "aaa", "bbb", "ccc" }, { 1, 1 } },
  })
  validate_steps({ "aaa", "", "ccc" }, {
    { { 1, 0 }, "gcu", { "aaa", "", "ccc" }, { 1, 0 } },
  })

  validate_steps({ "--1-- 2 -- 3 --" }, {
    { { 0, 5 }, "gcu", { "--1-- 2 -- 3 --" }, { 0, 5 } },
    { { 0, 6 }, "gcu", { "--1-- 2 -- 3 --" }, { 0, 6 } },
    { { 0, 7 }, "gcu", { "--1-- 2 -- 3 --" }, { 0, 7 } },
    { { 0, 8 }, "gcu", { "--1-- 2 3" }, { 0, 8 } },
    { { 0, 4 }, "gcu", { "1 2 3" }, { 0, 0 } },
  }, {
    bo = { filetype = "unknown", commentstring = "" },
    b = { celeste_comment_block_commentstring = "--%s--" },
  })

  validate_steps({ "aaa", "# bbb", "ccc" }, {
    { { 1, 1 }, "gcu", { "aaa", "# bbb", "ccc" }, { 1, 1 } },
  }, { bo = { filetype = "unknown", commentstring = "" } })
end

T["textobject"]["gcu respect ignore_empty_lines"] = function()
  local original = { "aaa", "# bbb", "# ccc", " ", "# eee" }

  validate_steps(original, {
    { { 1, 1 }, "gcu", { "aaa", "bbb", "ccc", " ", "eee" }, { 1, 0 } },
  }, { config = { ignore_empty_lines = "always" } })

  validate_steps(nil, {
    { "u" },
    { { 1, 1 }, "gcu", { "aaa", "bbb", "ccc", " ", "# eee" }, { 1, 0 } },
  }, { config = { ignore_empty_lines = "never" } })

  validate_steps(nil, {
    { "u" },
    { { 1, 1 }, "gcu", { "aaa", "bbb", "ccc", " ", "# eee" }, { 1, 0 } },
  }, { config = { ignore_empty_lines = "mixed" } })
end

T["textobject"]["gcu special case1"] = function()
  validate_steps({ "--[[aaa]]", "---@param xx", "-- test" }, {
    { { 2, 4 }, "gcu", { "aaa", "@param xx", "test" }, { 2, 1 } },
  }, { bo = { filetype = "lua" }, config = { cms_confs = { lua = { { "--%s", "---%s", "--[[%s]]" }, "--[[%s]]" } } } })
end

T["textobject"]["gcu special case2 : block lcs startswith line lcs"] = function()
  validate_steps({ "  hello", "  world" }, {
    { { 0, 2 }, "gbj", { "  --[[ hello", "  world ]]" }, { 0, 7 } },
    { "gcu", { "  hello", "  world" }, { 0, 2 } },
  }, { bo = { filetype = "lua", tabstop = 2 }, config = { cms_confs = { lua = { { "--%s" }, "--[[%s]]" } } } })
end

T["textobject"]["gcu dot repeatable"] = function()
  validate_steps({ "a", "b", "", "c", "d" }, {
    { { 0, 0 }, "gcj" },
    { { 3, 0 }, "gbj", { "-- a", "-- b", "", "--[[ c", "d ]]" } },
    { { 1, 3 }, "gcu", { "a", "b", "", "--[[ c", "d ]]" }, { 1, 0 } },
    { { 3, 3 }, ".", { "a", "b", "", "c", "d" }, { 3, 0 } },
  }, { bo = { filetype = "lua" } })
end

-- textobject treesitter ──────────────────────────────────────────────────────

T["textobject treesitter"] = new_set()

local ts_comment_at_cursor = function(pos)
  if pos then set_cursor(unpack(pos)) end
  return child.lua_func(function()
    local _H = require("celeste_comment").H
    local cursor = _H.make_cursor(0)
    return _H.textobject_comment_at_cursor(cursor)
  end)
end

T["textobject treesitter"]["works"] = function()
  set_context({
    bo = { filetype = "cpp", tabstop = 2, expandtab = true },
    config = { textobj_treesitter_detect = true },
  })
  child.lua_func(function()
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
  end)
  set_lines({
    "int func() {",
    '  printf("/* hello, world */");',
    "",
    "  /* this is a test ...........",
    "     really a test ............",
    "   */  ",
    "",
    "  // hello world!",
    "}",
  })
  eq(ts_comment_at_cursor({ 1, 13 }), vim.NIL)
  eq(ts_comment_at_cursor({ 3, 1 }), vim.NIL)
  eq(ts_comment_at_cursor({ 3, 2 }), { 3, 2, 5, 4 })
  eq(ts_comment_at_cursor({ 5, 4 }), { 3, 2, 5, 4 })
  eq(ts_comment_at_cursor({ 5, 5 }), vim.NIL)
  eq(ts_comment_at_cursor({ 7, 2 }), { 7, 2, 7, 16 })

  validate_steps({
    "int func() {",
    '  printf("/* hello, world */");',
    "",
    "  /* this is a test ...........",
    "     really a test ............",
    "   */  ",
    "",
    "  // hello world!",
    "}",
  }, {
    { { 1, 13 }, "gbgb", { from = 2, '  printf("/* hello, world */");' }, { 1, 13 } },
    {
      { 3, 2 },
      ".",
      {
        "int func() {",
        '  printf("/* hello, world */");',
        "",
        "  this is a test ...........",
        "     really a test ............",
        "    ",
        "",
        "  // hello world!",
        "}",
      },
    },
    { { 7, 2 }, "gcgc", { from = 8, "  hello world!" }, { 7, 2 } },
  })
end

T["textobject treesitter"]["works in markdown"] = function()
  set_context({
    bo = { filetype = "markdown", tabstop = 2, expandtab = true },
    config = { textobj_treesitter_detect = true },
  })
  child.lua_func(function()
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("markdown")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
  end)
  set_lines({
    "# title1",
    "```cpp",
    'printf("/*hello world*/!");',
    "/* hello",
    "   world",
    " */",
    " // 123",
    "```",
    "<!-- aaa -->",
  })
  eq(ts_comment_at_cursor({ 0, 0 }), vim.NIL)
  eq(ts_comment_at_cursor({ 8, 0 }), { 8, 0, 8, 11 })
  eq(ts_comment_at_cursor({ 2, 7 }), vim.NIL)
  eq(ts_comment_at_cursor({ 2, 8 }), vim.NIL)
  eq(ts_comment_at_cursor({ 3, 0 }), { 3, 0, 5, 2 })
  eq(ts_comment_at_cursor({ 6, 1 }), { 6, 1, 6, 6 })

  validate_steps(nil, {
    { { 8, 0 }, "gcu", { from = 9, "aaa" }, { 8, 0 } },
    { { 6, 4 }, "gcu", { from = 7, " 123" }, { 6, 1 } },
    { { 4, 3 }, "gcu", { from = 4, "hello", "   world", "" }, { 4, 3 } },
    { { 2, 8 }, "gcu", { from = 3, 'printf("/*hello world*/!");' }, { 2, 8 } },
  })
end

T["textobject treesitter"]["fallback to text match impl while no query"] = function()
  validate_steps({
    "int func() {",
    '  printf("/* hello, world */");',
    "",
    "  /* this is a test ...........",
    "     really a test ............",
    "   */  ",
    "",
    "  // hello world!",
    "}",
  }, {
    { { 1, 10 }, "gcu", { from = 2, '  printf("hello, world");' }, { 1, 10 } },
  }, { bo = { filetype = "cpp", tabstop = 2, expandtab = true } })
end

T["textobject treesitter"]["fallback to text match impl while disable textobj_treesitter_detect"] = function()
  set_context({ bo = { filetype = "cpp", tabstop = 2, expandtab = true } })
  child.lua_func(function()
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
  end)
  validate_steps({ "// hello /* world */" }, {
    { { 0, 9 }, "gbgb", { "// hello /* world */" }, { 0, 9 } },
  }, { config = { textobj_treesitter_detect = true } })

  validate_steps(nil, { { "gbgb", { "// hello world" } } }, { config = { textobj_treesitter_detect = false } })
end

T["textobject treesitter"]["inner works on block comment"] = function()
  set_context({
    bo = { filetype = "cpp", tabstop = 2, expandtab = true },
    config = { textobj_treesitter_detect = true },
  })
  child.lua_func(function()
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
  end)
  validate_steps({ "/* hello world */" }, {
    { { 0, 7 }, { "d", "gib" }, { from = 1, "/*  */" } },
  })
end

T["textobject treesitter"]["inner works on line comment"] = function()
  set_context({
    bo = { filetype = "cpp", tabstop = 2, expandtab = true },
    config = { textobj_treesitter_detect = true },
  })
  child.lua_func(function()
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
  end)
  validate_steps({ "// hello world" }, {
    { { 0, 7 }, { "d", "gic" }, { from = 1, "// " } },
  })
end

-- keep cursor tests ──────────────────────────────────────────────────────────

T["keep_cursor"] = new_set()

T["keep_cursor"]["gcc comment/uncomment restore cursor"] = function()
  validate_steps({ "aaa", "  bbbb", "ccc" }, {
    { { 1, 2 }, "gcc", { "aaa", "#   bbbb", "ccc" }, { 1, 4 } },
    { "gcc", { "aaa", "  bbbb", "ccc" }, { 1, 2 } },
  })
end

T["keep_cursor"]["gcc uncomment special, match vscode's NeverGroupAtTypeEdge"] = function()
  set_context({ bo = { filetype = "lua" } })
  local lines = { "  -- print('here')" }
  validate_steps(lines, { { { 0, 2 }, "gcc", { "  print('here')" }, { 0, 2 } } })
  validate_steps(lines, { { { 0, 3 }, "gcc", { "  print('here')" }, { 0, 2 } } })
  validate_steps(lines, { { { 0, 3 }, "gcc", { "  print('here')" }, { 0, 2 } } })
  validate_steps(lines, { { { 0, 4 }, "gcc", { "  print('here')" }, { 0, 2 } } })
end

T["keep_cursor"]["gcc keep_cursor=false not restore cursor"] = function()
  validate_steps({ "aaa", "bbbb", "ccc" }, {
    { { 1, 2 }, "gcc", { "aaa", "# bbbb", "ccc" }, { 1, 0 } },
    { "gcc", { "aaa", "bbbb", "ccc" }, { 1, 0 } },
  }, { config = { keep_cursor = false } })
end

T["keep_cursor"]["visual-line mode gc restore cursor"] = function()
  validate_steps({ "aaaaa", "bbbb", "ccc" }, {
    { { 0, 2 }, { "V", "j" }, nil, { 1, 2 } },
    { "gc", { "# aaaaa", "# bbbb", "ccc" }, { 1, 4 } },
  })
end

T["keep_cursor"]["visual mode gb restore cursor"] = function()
  validate_steps({ "aaaaa", "bbbb", "ccc" }, {
    { { 0, 2 }, { "v", "j", "l" }, nil, { 1, 3 } },
    { "gb", { "aa/* aaa", "bbbb */", "ccc" }, { 1, 3 } },
  }, { bo = { filetype = "cpp" } })
end

T["keep_cursor"]["C-v mode gb restore cursor"] = function()
  validate_steps({ "aaaaaa", "bbbbbbb", "cccccccc" }, {
    { { 0, 3 }, { "\\<C-v>", "2j" }, nil, { 2, 3 } },
    { "gb", { "/* aaaaaa", "bbbbbbb", "cccccccc */" }, { 2, 3 } },
  }, { bo = { filetype = "cpp" } })
end

T["keep_cursor"]["gcc cursor before offset no shift"] = function()
  validate_steps({ "  hello" }, { { { 0, 1 }, "gcc", { "#   hello" }, { 0, 3 } } })
end

T["keep_cursor"]["gbc comment/uncomment restore cursor"] = function()
  validate_steps({ "hello" }, {
    { { 0, 2 }, "gbc", { "/* hello */" }, { 0, 5 } },
    { "gbc", { "hello" }, { 0, 2 } },
  }, { bo = { filetype = "cpp" } })
end

T["keep_cursor"]["gbgb uncomment restore cursor"] = function()
  validate_steps({ "/* hello */" }, { { { 0, 7 }, "gbgb", { "hello" }, { 0, 4 } } }, { bo = { filetype = "cpp" } })
end

T["keep_cursor"]["gc2j restore cursor"] = function()
  validate_steps({ "aaaa", "bbbb", "cccc" }, {
    { { 0, 2 }, { "gc", "2j" }, { "# aaaa", "# bbbb", "# cccc" }, { 0, 4 } },
  })
end

T["keep_cursor"]["gbiw restore cursor"] = function()
  validate_steps({ "aaaa bbb cccc" }, {
    { { 0, 6 }, "gbiw", { "aaaa !@# bbb #@! cccc" }, { 0, 10 } },
  }, { b = { celeste_comment_block_commentstring = "!@#%s#@!" } })
end

T["keep_cursor"]["dot-repeat works"] = function()
  validate_steps({ "  hello", "  world" }, {
    { { 0, 4 }, "gcc", { "  # hello", "  world" }, { 0, 6 } },
    { ".", { "  hello", "  world" }, { 0, 4 } },
    { { 1, 5 }, ".", { "  hello", "  # world" }, { 1, 7 } },
    { ".", { "  hello", "  world" }, { 1, 5 } },
    { { 0, 5 }, "gbip", { "  !@# hello", "  world #@!" }, { 0, 9 } },
    { ".", { "  hello", "  world" }, { 0, 5 } },
  }, { bo = { tabstop = 2 }, b = { celeste_comment_block_commentstring = "!@#%s#@!" } })
end

T["keep_cursor"]["bugfix restore the cursor not in textobj range"] = function()
  child.lua_func(function()
    vim.keymap.set("o", "ii", function()
      vim.api.nvim_win_set_cursor(0, { 2, 3 })
      vim.cmd.normal({ "V", bang = true })
      vim.api.nvim_win_set_cursor(0, { 3, 4 })
      vim.bo.filetype = "lua"
    end)
  end)
  local lines = { "first liens", "second line", "third line" }
  validate_steps(lines, {
    { { 0, 2 }, { "gc", "<esc>", "gb", "<esc>" }, lines, { 0, 2 } },
    { "gcii", { "first liens", "-- second line", "-- third line" }, { 0, 2 } },
    { { "gc", "<esc>" }, nil, { 0, 2 } },
    { ".", lines, { 0, 2 } },
    { "g@ii", { "first liens", "-- second line", "-- third line" }, { 0, 2 } },
  })
end

T["keep_cursor"]["bugfix cancel operator not impact visual gb"] = function()
  -- cancel operator
  validate_steps({ "first lines", "second lines", "third lines" }, {
    { { 0, 2 }, { "gc", "<esc>" } },
    { { 2, 4, 1, 6 }, "gb", { "first lines", "second--[[  lines", "third ]] lines" }, { 1, 11 } },
    { "gv", nil, nil, { { 2, 7, 1, 6 }, "v" } },
  }, { bo = { filetype = "lua" }, config = { keep_selection = "adjust | expand_block" } })
end

-- Keep selection ─────────────────────────────────────────────────────────────

T["keep_selection"] = new_set({
  hooks = {
    pre_case = function()
      set_context({ bo = { filetype = "cpp", tabstop = 2 }, config = { keep_selection = "adjust | keep_visual" } })
    end,
  },
})

T["keep_selection"]["works in `v` mode"] = function()
  local lines = {
    "  first line, 11",
    "  second line, 2222",
  }
  validate_steps(lines, {
    {
      { 0, 0, 1, 18 },
      "gc",
      { "  // first line, 11", "  // second line, 2222" },
      { 1, 21 },
      { { 0, 0, 1, 21 }, "v" },
    },
    { "gc", lines, { 1, 18 }, { { 0, 0, 1, 18 }, "v" } },
    {
      "gb",
      { "/*   first line, 11", "  second line, 2222 */" },
      { 1, 18 },
      { { 0, 3, 1, 18 }, "v" },
    },
    { "<Esc>" },
    { "gbgb", lines, { 1, 18 } },
    {
      { 0, 4, 1, 6 },
      "gb",
      { "  fi/* rst line, 11", "  secon */d line, 2222" },
      { 1, 6 },
      { { 0, 7, 1, 6 }, "v" },
    },
    { "<Esc>" },
    { "gbgb", lines, { 1, 6 } },
  })
end

T["keep_selection"]["works in `v` mode with selection=exclusive"] = function()
  local lines = { "  first line, 11", "  second line, 2222" }
  validate_steps(lines, {
    {
      { 0, 0, 1, 18 },
      "gc",
      { "  // first line, 11", "  // second line, 2222" },
      { 1, 21 },
      { { 0, 0, 1, 21 }, "v" },
    },
    { "gc", lines, { 1, 18 }, { { 0, 0, 1, 18 }, "v" } },
    { "<Esc>" },
    {
      { 0, 4, 1, 6 },
      "gb",
      { "  fi/* rst line, 11", "  seco */nd line, 2222" },
      { 1, 6 },
      { { 0, 7, 1, 6 }, "v" },
    },
    { "d", { "  fi/*  */nd line, 2222" } },
    { "u", { "  fi/* rst line, 11", "  seco */nd line, 2222" } },
    { { 0, 4, 1, 9 }, "gb", lines, nil, { { 0, 4, 1, 6 }, "v" } },
  }, { o = { selection = "exclusive" } })
end

T["keep_selection"]["restores exact selection content with selection=exclusive"] = function()
  set_context({ o = { selection = "exclusive" } })
  set_lines({ "  first line, 11", "  second line, 2222" })

  -- original exclusive selection: cursor at (2,18) excludes the last `2`
  selection(0, 0, 1, 18)
  feed('"zy')
  eq(child.fn.getreg("z"), "  first line, 11\n  second line, 222")

  feed("gv")
  feed("gc")

  -- restored selection must cover the same effective range (no char lost/gained)
  feed('"zy')
  eq(child.fn.getreg("z"), "  // first line, 11\n  // second line, 222")
end

T["keep_selection"]["works in `V` mode"] = function()
  local lines = { "  first line, 11", "  second line, 2222" }
  validate_steps(lines, {
    {
      { 0, 0, 1, 18, "V" },
      "gc",
      { "  // first line, 11", "  // second line, 2222" },
      { 1, 21 },
      { { 0, 0, 1, 21 }, "V" },
    },
    { "gc", lines, { 1, 18 }, { { 0, 0, 1, 18 }, "V" } },
    {
      "gb",
      { "  /* first line, 11", "  second line, 2222 */" },
      { 1, 18 },
      { { 0, 0, 1, 18 }, "V" },
    },
    { "gb", lines, { 1, 18 }, { { 0, 0, 1, 18 }, "V" } },
    { "<Esc>" },
    {
      { 0, 4, 1, 6, "V" },
      "gc",
      { "  // first line, 11", "  // second line, 2222" },
      { 1, 9 },
      { { 0, 7, 1, 9 }, "V" },
    },
    { "gc", lines, { 1, 6 }, { { 0, 4, 1, 6 }, "V" } },
  })
end

T["keep_selection"]["works with multibyte marker and selection=exclusive"] = function()
  local lines = { "  hello你好  tail" }
  validate_steps(lines, {
    { { 0, 2, 0, 13 }, "d", { "    tail" } },
    { "u", lines },
    {
      { 0, 2, 0, 13 },
      "gb",
      { "  ※ hello你好 ※  tail" },
      { 0, 17 },
      { { 0, 6, 0, 17 }, "v" },
    },
    { "d", { "  ※  ※  tail" } },
    { "u", { "  ※ hello你好 ※  tail" } },
    { { "v", "ga" }, nil, nil, { { 0, 2, 0, 21 }, "v" } },
    { "d", { "    tail" } },
    { "u", { "  ※ hello你好 ※  tail" } },
    { { "v", "ga" }, nil, nil, { { 0, 2, 0, 21 }, "v" } },
    { "gb", lines, { 0, 13 }, { { 0, 2, 0, 13 }, "v" } },
    { "d", { "    tail" } },
  }, {
    o = { selection = "exclusive" },
    bo = { filetype = "unknown", tabstop = 2 },
    b = { celeste_comment_block_commentstring = "※%s※" },
    config = { keep_selection = "adjust | keep_visual" },
  })
end

T["keep_selection"]["expand_block includes multibyte markers"] = function()
  validate_steps({ "a你b" }, {
    {
      { 0, 1, 0, 4 },
      "gb",
      { "a※ 你 ※b" },
      { 0, 12 },
      { { 0, 1, 0, 12 }, "v" },
    },
  }, {
    bo = { filetype = "unknown" },
    o = { selection = "exclusive" },
    config = { keep_selection = "expand_block | keep_visual" },
    b = { celeste_comment_block_commentstring = "※%s※" },
  })
end

T["keep_selection"]["expand_block includes multibyte markers (backward)"] = function()
  -- Backward selection whose document-order end is the multibyte `※` marker;
  -- marks must still point at the character's first byte.
  validate_steps({ "a你b" }, {
    { { 0, 1, 0, 0 }, "gb", { "※ a你 ※b" }, { 0, 0 }, { { 0, 9, 0, 0 }, "v" } },
  }, {
    bo = { filetype = "unknown" },
    config = { keep_selection = "expand_block | keep_visual" },
    b = { celeste_comment_block_commentstring = "※%s※" },
  })
  eq_marks({ "<", ">" }, { { 1, 0 }, { 1, 9 } })

  feed("<Esc>")
  validate_steps({ "a你b" }, {
    { { 0, 1, 0, 0 }, "gb", { "※ a ※你b" }, { 0, 9 }, { { 0, 0, 0, 9 }, "v" } },
  }, { o = { selection = "exclusive" } })
  eq_marks({ "<", ">" }, { { 1, 0 }, { 1, 9 } })
end

T["keep_selection"]["expand_block includes block comment markers"] = function()
  -- with selection == 'inclusive'
  validate_steps({ "  hello world", "  second" }, {
    { { 0, 2, 0, 13 }, "gb", { "  /* hello world */", "  second" }, nil, { { 0, 2, 0, 18 }, "v" } },
  }, { o = { selection = "inclusive" }, config = { keep_selection = "expand_block | keep_visual" } })
  feed('"zy')
  eq(child.fn.getreg("z"), "/* hello world */")

  validate_steps({ "  hello world", "  second" }, {
    { { 0, 0, 1, 0, "V" }, "gb", { "  /* hello world", "  second */" } },
  })
  feed('"zy')
  eq(child.fn.getreg("z"), "  /* hello world\n  second */\n")

  validate_steps(nil, {
    { { 1, 0 }, "gbgb", { "  hello world", "  second" } },
    {
      { 0, 4, 1, 6 },
      "gb",
      { "  he/* llo world", "  secon */d" },
      { 1, 9 },
      { { 0, 4, 1, 9 }, "v" },
    },
    { "gb", { "  hello world", "  second" }, { 1, 6 }, { { 0, 4, 1, 6 }, "v" } },
    { "gb", { "  he/* llo world", "  secon */d" }, { 1, 9 }, { { 0, 4, 1, 9 }, "v" } },
    { "gb", { "  hello world", "  second" }, { 1, 6 }, { { 0, 4, 1, 6 }, "v" } },
    { "<Esc>" },
  })

  -- with selection == 'exclusive'
  validate_steps(nil, {
    { { 0, 4, 1, 7 }, "gb", { "  he/* llo world", "  secon */d" }, { 1, 10 }, { { 0, 4, 1, 10 }, "v" } },
    { "gb", { "  hello world", "  second" }, { 1, 7 }, { { 0, 4, 1, 7 }, "v" } },
    { "gb", { "  he/* llo world", "  secon */d" }, { 1, 10 }, { { 0, 4, 1, 10 }, "v" } },
    { "gb", { "  hello world", "  second" }, { 1, 7 }, { { 0, 4, 1, 7 }, "v" } },
  }, { o = { selection = "exclusive" } })
end

T["keep_selection"]["expand_block does not expand fallback-to-block"] = function()
  -- selection == 'inclusive'
  validate_steps({ "  hello world", "  second" }, {
    -- charwise "hello"; content-only, not expanded
    { { 0, 2, 0, 6 }, "gc", { "  <# hello world #>", "  second" }, nil, { { 0, 5, 0, 9 }, "v" } },
    { "<Esc>" },
  }, {
    config = {
      keep_selection = "expand_block | keep_visual",
      cms_confs = false, -- rely on `commentstring` so the wrapped `<#%s#>` is used
      fallback_to_block = "if_line_cms_wrapped",
    },
    -- wrapped line comment string: `gc` falls back to block (motion forced to "line")
    bo = { commentstring = "<#%s#>" },
    b = { celeste_comment_block_commentstring = "<%#%s%#>" },
    o = { selection = "inclusive" },
  })

  -- exclusive also stays content-only
  validate_steps({ "  hello world", "  second" }, {
    { { 0, 2, 0, 6 }, "gc", { "  <# hello world #>", "  second" }, nil, { { 0, 5, 0, 9 }, "v" } },
  }, { o = { selection = "exclusive" } })
end

T["keep_selection"]["expand_block does not expand wrapped line comment"] = function()
  validate_steps({ "  hello world", "  second" }, {
    -- charwise "hello"; expand_block is block-only, keep_visual restores original
    { { 0, 2, 0, 6 }, "gc", { "  <# hello world #>", "  second" }, nil, { { 0, 2, 0, 6 }, "v" } },
  }, {
    config = {
      keep_selection = "expand_block | keep_visual",
      cms_confs = false, -- rely on `commentstring` so the wrapped `<#%s#>` is used
      fallback_to_block = "never", -- use the wrapped line comment directly (ctype=kLine)
    },
    bo = { commentstring = "<#%s#>" },
    b = { celeste_comment_block_commentstring = "<%#%s%#>" },
    o = { selection = "inclusive" },
  })
end

T["keep_selection"]["o-swapped charwise keeps cursor at the start"] = function()
  -- accurate: cursor keeps the shifted start-side position
  validate_steps({ "  first line", "  second line" }, {
    { { 0, 2, 1, 5 }, { "o", "gb" }, { "  /* first line", "  seco */nd line" }, { 0, 5 }, { { 1, 5, 0, 5 }, "v" } },
    { "<Esc>" },
  }, { bo = { filetype = "cpp" } })

  -- expand_block: cursor stays at the LHS marker
  validate_steps({ "  first line", "  second line" }, {
    { { 0, 2, 1, 5 }, { "o", "gb" }, { "  /* first line", "  seco */nd line" }, { 0, 2 }, { { 1, 8, 0, 2 }, "v" } },
  }, { config = { keep_selection = "expand_block | keep_visual" } })
end

T["keep_selection"]["o-swapped V with horizontal move does not collapse"] = function()
  validate_steps({ "  first line", "  second line" }, {
    -- bottom-up selection then o: cursor stays at the bottom
    {
      { 1, 4, 0, 5, "V" },
      { "o", "l", "gb" },
      { "  /* first line", "  second line */" },
      { 1, 5 },
      { { 0, 8, 1, 5 }, "V" },
    },
    { "<Esc>" },
    -- top-down selection then o: cursor stays at the top
    {
      lines = { "  first line", "  second line" },
      { 0, 5, 1, 4, "V" },
      { "o", "l", "gb" },
      { "  /* first line", "  second line */" },
      { 0, 9 },
      { { 1, 4, 0, 9 }, "V" },
    },
    { "<Esc>" },
    -- top-down + o + gc (line comment)
    {
      lines = { "  first line", "  second line" },
      { 0, 5, 1, 4, "V" },
      { "o", "l", "gc" },
      { "  // first line", "  // second line" },
      { 0, 9 },
      { { 1, 7, 0, 9 }, "V" },
    },
  }, { bo = { filetype = "cpp" } })
end

T["keep_selection"]["backward V selection restores cursor at the top"] = function()
  validate_steps({ "  first line", "  second line" }, {
    -- backward: cursor ends at the top
    { { 1, 4, 0, 3, "V" }, "gc", { "  // first line", "  // second line" }, { 0, 6 }, { { 1, 7, 0, 6 }, "V" } },
  }, { bo = { filetype = "cpp" } })
end

T["keep_selection"]["o-swapped charwise keeps cursor at the start with selection=exclusive"] = function()
  -- accurate
  validate_steps({ "  first line", "  second line" }, {
    { { 0, 2, 1, 5 }, { "o", "gb" }, { "  /* first line", "  sec */ond line" }, { 0, 5 }, { { 1, 5, 0, 5 }, "v" } },
    { "<Esc>" },
  }, { bo = { filetype = "cpp" }, o = { selection = "exclusive" } })

  -- expand_block
  validate_steps({ "  first line", "  second line" }, {
    { { 0, 2, 1, 5 }, { "o", "gb" }, { "  /* first line", "  sec */ond line" }, { 0, 2 }, { { 1, 8, 0, 2 }, "v" } },
  }, { config = { keep_selection = "expand_block | keep_visual" } })
end

T["keep_selection"]["o-swapped V with horizontal move does not collapse with selection=exclusive"] = function()
  validate_steps({ "  first line", "  second line" }, {
    -- bottom-up + o: cursor stays at the bottom
    {
      { 1, 4, 0, 5, "V" },
      { "o", "l", "gb" },
      { "  /* first line", "  second line */" },
      { 1, 5 },
      { { 0, 8, 1, 5 }, "V" },
    },
    { "<Esc>" },
    -- top-down + o: cursor stays at the top
    {
      lines = { "  first line", "  second line" },
      { 0, 5, 1, 4, "V" },
      { "o", "l", "gb" },
      { "  /* first line", "  second line */" },
      { 0, 9 },
      { { 1, 4, 0, 9 }, "V" },
    },
    { "<Esc>" },
    -- top-down + o + gc
    {
      lines = { "  first line", "  second line" },
      { 0, 5, 1, 4, "V" },
      { "o", "l", "gc" },
      { "  // first line", "  // second line" },
      { 0, 9 },
      { { 1, 7, 0, 9 }, "V" },
    },
  }, { bo = { filetype = "cpp" }, o = { selection = "exclusive" } })
end

T["keep_selection"]["backward V selection restores cursor at the top with selection=exclusive"] = function()
  validate_steps({ "  first line", "  second line" }, {
    { { 1, 4, 0, 3, "V" }, "gc", { "  // first line", "  // second line" }, { 0, 6 }, { { 1, 7, 0, 6 }, "V" } },
  }, { bo = { filetype = "cpp" }, o = { selection = "exclusive" } })
end

T["keep_selection"]["expand_line o-swapped and backward V"] = function()
  validate_steps({ "  first line", "  second line" }, {
    -- o-swapped charwise: v mode → o → gc → V mode
    { { 0, 2, 1, 5 }, { "o", "gc" }, { "  // first line", "  // second line" }, { 0, 5 }, { { 1, 8, 0, 5 }, "V" } },
    { "<Esc>" },
    -- o-swapped V + horizontal move: bottom-up → o → l → gc → V mode
    {
      lines = { "  first line", "  second line" },
      { 1, 4, 0, 5, "V" },
      { "o", "l", "gc" },
      { "  // first line", "  // second line" },
      { 1, 8 },
      { { 0, 8, 1, 8 }, "V" },
    },
    { "<Esc>" },
    -- backward V: bottom-up → gc → V mode at top
    {
      lines = { "  first line", "  second line" },
      { 1, 4, 0, 3, "V" },
      "gc",
      { "  // first line", "  // second line" },
      { 0, 6 },
      { { 1, 7, 0, 6 }, "V" },
    },
  }, { bo = { filetype = "cpp" }, config = { keep_selection = "expand_line | keep_visual" } })
end

T["keep_selection"]["bugfix : only expand_block should restore cursor, gv should select all block"] = function()
  validate_steps({ "  first line", "  second line" }, {
    { { 0, 3, 1, 5 }, "gb", { "  f/* irst line", "  seco */nd line" }, { 1, 5 }, {} },
    { "gv", nil, { 1, 8 }, { { 0, 3, 1, 8 }, "v" } },
    { "o", nil, { 0, 3 } },
    { "gb", { "  first line", "  second line" }, { 0, 3 }, {} },
    { "gv", nil, { 0, 3 }, { { 1, 5, 0, 3 }, "v" } },
  }, { bo = { filetype = "cpp" }, config = { keep_selection = "expand_block" } })
end

-- Equivalence classes: cover all 16 flag combinations, verifying per-axis
-- (Line / Block) behavior matches the "-+ev" decomposition table.
--
--   shorthand: a = adjust, b = expand_block, l = expand_line, v = keep_visual
--   axis code: - (none) | + (adjust) | +e (expand) | -v (keep_visual)
--              | +v (adjust+keep) | +ev (expand+keep)
local KEEP_SEL_EQ = {
  { "never", "never", "-", "-" },
  { "a", "adjust", "+", "+" },
  { "b", "expand_block", "-", "+e" },
  { "ab", "adjust | expand_block", "+", "+e" },
  { "l", "expand_line", "+e", "-" },
  { "al", "adjust | expand_line", "+e", "+" },
  { "bl", "expand_block | expand_line", "+e", "+e" },
  { "abl", "adjust | expand_block | expand_line", "+e", "+e" },
  { "v", "keep_visual", "-v", "-v" },
  { "av", "adjust | keep_visual", "+v", "+v" },
  { "bv", "expand_block | keep_visual", "-v", "+ev" },
  { "abv", "adjust | expand_block | keep_visual", "+v", "+ev" },
  { "lv", "expand_line | keep_visual", "+ev", "-v" },
  { "alv", "adjust | expand_line | keep_visual", "+ev", "+v" },
  { "blv", "expand_block | expand_line | keep_visual", "+ev", "+ev" },
  { "ablv", "adjust | expand_block | expand_line | keep_visual", "+ev", "+ev" },
}

local KEEP_SEL_EQ_OPS = {
  {
    name = "v mode gc",
    axis = "line",
    cmd = "gc",
    select = function() selection(0, 2, 0, 13) end,
    lines = { "  // hello world", "  second" },
    cursor = { 0, 15 },
    content = { { 0, 5, 0, 16 }, "v" },
    original = { { 0, 2, 0, 13 }, "v" },
    expand = { { 0, 5, 0, 16 }, "V" },
  },
  {
    name = "v mode gb",
    axis = "block",
    cmd = "gb",
    select = function() selection(0, 2, 0, 13) end,
    lines = { "  /* hello world */", "  second" },
    cursor = { 0, 16 },
    content = { { 0, 5, 0, 16 }, "v" },
    original = { { 0, 2, 0, 13 }, "v" },
    expand = { { 0, 2, 0, 18 }, "v" },
    check_yank = "/* hello world */",
  },
  {
    name = "V mode gc",
    axis = "line",
    cmd = "gc",
    select = function() selection(0, 2, 1, 0, "V") end,
    lines = { "  // hello world", "  // second" },
    cursor = { 1, 0 },
    content = { { 0, 5, 1, 0 }, "V" },
    original = { { 0, 2, 1, 0 }, "V" },
    expand = { { 0, 5, 1, 0 }, "V" },
  },
  {
    name = "V mode gb",
    axis = "block",
    cmd = "gb",
    select = function() selection(0, 2, 1, 0, "V") end,
    lines = { "  /* hello world", "  second */" },
    cursor = { 1, 0 },
    content = { { 0, 5, 1, 0 }, "V" },
    original = { { 0, 2, 1, 0 }, "V" },
    expand = { { 0, 5, 1, 0 }, "V" },
  },
}

local function keep_sel_run_equiv(flags, code, op)
  set_context({ config = { keep_selection = flags } })
  set_lines({ "  hello world", "  second" })
  op.select()
  feed(op.cmd)
  eq_lines(op.lines)

  if code == "-" then
    eq_cursor(op.cursor)
    eq(child.fn.mode(), "n")
    return
  end

  if code == "-v" then
    eq_selection(op.original)
    return
  end

  if code == "+" or code == "+e" then
    eq(child.fn.mode(), "n")
    feed("gv")
  end

  local sel = (code == "+e" or code == "+ev") and op.expand or op.content
  eq_selection(sel)
  if op.check_yank and (code == "+e" or code == "+ev") then
    feed('"zy')
    eq(child.fn.getreg("z"), op.check_yank)
  end
end

T["keep_selection"]["equivalence"] = new_set()
for _, spec in ipairs(KEEP_SEL_EQ) do
  local name, flags, line, block = spec[1], spec[2], spec[3], spec[4]
  local cls = new_set({ parametrize = { { line, block } } })
  for _, op in ipairs(KEEP_SEL_EQ_OPS) do
    cls[op.name] = function(l, b) keep_sel_run_equiv(flags, op.axis == "line" and l or b, op) end
  end
  T["keep_selection"]["equivalence"][name] = cls
end

-- PreCommitEdits tests ───────────────────────────────────────────────────────

T["pre_commit_edits"] = new_set()

T["pre_commit_edits"]["multi_line edit with pre_commit_edits restores cursor"] = function()
  validate_steps({ "  aaa", "  bbb", "  ccc" }, {
    { { 0, 2 }, { "gb", "2j" }, nil, { 1, 2 } },
  }, {
    bo = { filetype = "cpp" },
    config = function()
      return {
        hooks = {
          pre_commit_edits = function(ctx)
            if ctx.ctype ~= 2 then return end
            local lines = vim.api.nvim_buf_get_lines(0, ctx.range[1], ctx.range[3] + 1, false)
            local e = ctx.edits
            e[1] = {
              range = { e[1].range[1], 0, e[1].range[1], #lines[1] },
              text = { (lines[1]:match("^(%s*)") or "") .. "/*", lines[1] },
            }
            e[2] = {
              range = { e[2].range[1], 0, e[2].range[1], #lines[#lines] },
              text = { lines[#lines], (lines[#lines]:match("^(%s*)") or "") .. "*/" },
            }
            e.any_multi = true
            ctx.o_use_set_text = true
          end,
        },
      }
    end,
  })
end

T["pre_commit_edits"]["multi_line edit keep_cursor=false does not restore cursor"] = function()
  validate_steps({ "aaa", "bbb", "ccc" }, {
    { { 0, 0 }, { "gb", "j" }, nil, { 0, 0 } },
  }, {
    bo = { filetype = "cpp" },
    config = function()
      return {
        keep_cursor = false,
        hooks = {
          pre_commit_edits = function(ctx)
            if ctx.ctype ~= 2 then return end
            local lines = vim.api.nvim_buf_get_lines(0, ctx.range[1], ctx.range[3] + 1, false)
            local e = ctx.edits
            e[1] = { range = { e[1].range[1], 0, e[1].range[1], #lines[1] }, text = { "/*", lines[1] } }
            e[2] = { range = { e[2].range[1], 0, e[2].range[1], #lines[#lines] }, text = { lines[#lines], "*/" } }
            e.any_multi = true
            ctx.o_use_set_text = true
          end,
        },
      }
    end,
  })
end

T["pre_commit_edits"]["pre_commit_edits above/below lines"] = function()
  validate_steps({ "  void f() {", "    int a;", "  }" }, {
    { { 0, 0 }, "3gbc", { "  /*", "  void f() {", "    int a;", "  }", "  */" } },
  }, {
    bo = { filetype = "cpp" },
    config = function()
      return {
        hooks = {
          pre_commit_edits = function(ctx)
            if ctx.ctype ~= 2 then return end
            local lines = ctx.lines
            local l1, ln = lines[1], lines[#lines]
            local e = ctx.edits
            e[1] =
              { range = { e[1].range[1], 0, e[1].range[1], #l1 }, text = { (l1:match("^(%s*)") or "") .. "/*", l1 } }
            e[2] =
              { range = { e[2].range[1], 0, e[2].range[1], #ln }, text = { ln, (ln:match("^(%s*)") or "") .. "*/" } }
            e.any_multi = true
            ctx.o_use_set_text = true
          end,
        },
      }
    end,
  })
end

T["pre_commit_edits"]["pre_commit_edits edge: last line selection"] = function()
  validate_steps({ "line1", "line2" }, {
    { { 1, 0 }, "gbc", { "line1", "/*", "line2", "*/" } },
  }, {
    bo = { filetype = "cpp" },
    config = function()
      return {
        hooks = {
          pre_commit_edits = function(ctx)
            if ctx.ctype ~= 2 then return end
            local lines = ctx.lines
            local e = ctx.edits
            e[1] = { range = { e[1].range[1], 0, e[1].range[1], #lines[1] }, text = { "/*", lines[1] } }
            e[2] = { range = { e[2].range[1], 0, e[2].range[1], #lines[#lines] }, text = { lines[#lines], "*/" } }
            e.any_multi = true
            ctx.o_use_set_text = true
          end,
        },
      }
    end,
  })
end

T["pre_commit_edits"]["out of range fallback to set lines"] = function()
  validate_steps({ "aaa", "bbb" }, {
    { { 0, 0 }, "gcj", { "# aaa", "# bbb", "ccc" } },
  }, {
    config = function()
      return {
        hooks = {
          pre_commit_edits = function(ctx)
            ctx.edits[#ctx.edits + 1] = {
              range = { 2, 0, 2, 3 },
              text = { "ccc" },
            }
            ctx.o_use_set_text = true
          end,
        },
      }
    end,
  })
end

T["pre_commit_edits"]["o_use_set_text preserves extmarks inside the range"] = function()
  set_context({ bo = { filetype = "c" } })
  set_lines({ "aaa", "bbb", "ccc", "ddd" })
  set_context({
    config = function()
      return {
        hooks = {
          pre_commit_edits = function(ctx) ctx.o_use_set_text = true end,
        },
      }
    end,
  })
  child.lua_func(function()
    local ns = vim.api.nvim_create_namespace("celeste_test")
    _G.__em = {
      first_pt = vim.api.nvim_buf_set_extmark(0, ns, 0, 1, {}),
      mid_pt = vim.api.nvim_buf_set_extmark(0, ns, 1, 1, {}),
      mid_span = vim.api.nvim_buf_set_extmark(0, ns, 1, 0, { end_col = 3 }),
      last_pt = vim.api.nvim_buf_set_extmark(0, ns, 2, 1, {}),
      outside = vim.api.nvim_buf_set_extmark(0, ns, 3, 1, {}),
    }
  end)
  selection(0, 0, 2, 0, "V")
  feed("gb")
  eq_lines({ "/* aaa", "bbb", "ccc */", "ddd" })

  local res = child.lua_func(function()
    local ns = vim.api.nvim_create_namespace("celeste_test")
    local get = function(id) return vim.api.nvim_buf_get_extmark_by_id(0, ns, id, {}) end
    return {
      first_pt = get(__em.first_pt),
      mid_pt = get(__em.mid_pt),
      last_pt = get(__em.last_pt),
      outside = get(__em.outside),
      mid_span = vim.api.nvim_buf_get_extmark_by_id(0, ns, __em.mid_span, { details = true }),
    }
  end)

  -- marker line: extmark follows the inserted `/* ` (shifts right)
  eq(res.first_pt, { 0, 4 })
  -- untouched content line: preserved exactly
  eq(res.mid_pt, { 1, 1 })
  -- span extmark on untouched content line: start and end both preserved
  eq(res.mid_span[1], 1)
  eq(res.mid_span[2], 0)
  eq(res.mid_span[3].end_col, 3)
  -- RHS insert is after the extmark on the last line: preserved
  eq(res.last_pt, { 2, 1 })
  -- line outside the range: untouched
  eq(res.outside, { 3, 1 })
end

T["pre_commit_edits"]["default commit displaces extmarks inside the range"] = function()
  set_context({ bo = { filetype = "c" } })
  set_lines({ "aaa", "bbb", "ccc", "ddd" })
  child.lua_func(function()
    _G.__ns = vim.api.nvim_create_namespace("celeste_test")
    _G.__mid = vim.api.nvim_buf_set_extmark(0, _G.__ns, 1, 1, {})
  end)
  selection(0, 0, 2, 0, "V")
  feed("gb")
  eq_lines({ "/* aaa", "bbb", "ccc */", "ddd" })
  local pos = child.lua_func(function() return vim.api.nvim_buf_get_extmark_by_id(0, _G.__ns, _G.__mid, {}) end)
  -- default whole-range `set_lines` displaces in-range extmarks to the range end
  eq(pos, { 3, 0 })
end

-- treesitter tests ───────────────────────────────────────────────────────────

T["treesitter"] = new_set()

T["treesitter"]["gcc/gbc respects injected languages in vim heredoc"] = function()
  local lines =
    { "set background=dark", "lua << EOF", "  print(1)", "  vim.cmd('set bg=light')", "EOF", "set nocursorline" }
  set_context({ bo = { tabstop = 2, filetype = "vim" } })
  child.treesitter.start()

  validate_steps(lines, {
    { { 2, 2 }, "gcc", { from = 3, "  -- print(1)" }, { 2, 5 } },
    { { 1, 0 }, ".", { from = 2, '" lua << EOF' } },
    { "." },
    { { 5, 0 }, ".", { from = 6, '" set nocursorline' } },
    { "." },
    { { 2, 5 }, ".", { from = 3, "  print(1)" }, { 2, 2 } },
    { "gbc", { from = 3, "  --[[ print(1) ]]" }, { 2, 7 } },
    { ".", { from = 3, "  print(1)" }, { 2, 2 } },
    { { 0, 4 }, ".", { from = 1, "set background=dark" } }, -- vim does not have block comment string
  })
end

T["treesitter"]["gco/gcO/gcA respect injected languages"] = function()
  set_lines({
    "set bg=dark",
    "lua << EOF",
    "  print(1)",
    "EOF",
    "set nocursorline",
  })
  set_context({ bo = { filetype = "vim" } })
  child.treesitter.start()

  local lines = { "set bg=dark", "lua << EOF", "  print(1)", "EOF", "set nocursorline" }
  validate_steps(lines, {
    { { 2, 2 }, "gco", { from = 4, "  -- " }, { 3, 5 } },
    { { "<Esc>", "u" } },
    { { 2, 2 }, "gcA", { from = 3, "  print(1) -- " }, { 2, 14 } },
    { { "<Esc>", "u" } },
    { { 2, 2 }, "gcO", { from = 3, "-- " }, { 2, 3 } },
    { { "<Esc>", "u" } },
    { { 0, 0 }, "gcO", { from = 1, '" ' }, { 0, 2 } },
    { { "<Esc>", "u" } },
    { { 4, 0 }, "gco", { from = 6, '" ' }, { 5, 2 } },
    { { "<Esc>", "u" } },
    { { 4, 0 }, "gcA", { from = 5, 'set nocursorline " ' }, { 4, 19 } },
    { { "<Esc>", "u" } },
  })
end

T["treesitter"]["handles mismatch between parser name and filetype"] = function()
  set_context({ bo = { filetype = "celeste_test_filetype", commentstring = "" }, config = { cms_confs = false } })
  child.lua_func(function()
    vim.treesitter.language.add("c")
    vim.treesitter.language.register("c", { "celeste_test_filetype" })
  end)
  eq(child.lua_get([[ vim.treesitter.language.get_filetypes("c") ]]), { "c", "celeste_test_filetype" })

  validate_steps({ "hello" }, { { { 0, 0 }, "gcc", { "hello" } } })

  child.lua_func(function() vim.treesitter.start() end)

  validate_steps(nil, { { ".", { "// hello" }, { 0, 3 } } })
  eq(child.bo.commentstring, "")
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L592
T["treesitter"]["respects tree-sitter commentstring metadata : nvim-like builtin resolver"] = function()
  set_context({ bo = { tabstop = 2, filetype = "vim" }, config = { cms_confs = false } })
  child.lua_func(function()
    vim.treesitter.query.set(
      "vim",
      "highlights",
      [[
        ((list) @_list (#set! @_list bo.commentstring "!! %s"))
      ]]
    )
    vim.treesitter.start()
  end)

  local lines = {
    "set background=dark",
    "let mylist = [",
    [[  \"a",]],
    [[  \"b",]],
    [[  \"c",]],
    "  \\]",
  }
  validate_steps(lines, {
    {
      { 0, 0 },
      "gcc",
      { '" set background=dark', "let mylist = [", [[  \"a",]], [[  \"b",]], [[  \"c",]], "  \\]" },
      { 0, 2 },
    },
    -- should work with dot-repeat
    {
      { 3, 0 },
      ".",
      { '" set background=dark', "let mylist = [", [[  \"a",]], [[  !! \"b",]], [[  \"c",]], "  \\]" },
      { 3, 0 },
    },
  })
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L630
T["treesitter"]["only applies the innermost tree-sitter commentstring metadata : nvim-like builtin resolver"] = function()
  set_context({ bo = { tabstop = 2, filetype = "vim" }, config = { cms_confs = false } })
  child.lua_func(function()
    vim.treesitter.query.set(
      "vim",
      "highlights",
      [[
          ((list) @_list (#gsub! @_list "(.*)" "%1") (#set! bo.commentstring "!! %s"))
          ((script_file) @_src (#set! @_src bo.commentstring "## %s"))
      ]]
    )
    vim.treesitter.start()
  end)

  local lines = {
    "set background=dark",
    "let mylist = [",
    [[  \"a",]],
    [[  \"b",]],
    [[  \"c",]],
    "  \\]",
  }
  validate_steps(lines, {
    {
      { 0, 0 },
      "gcc",
      { "## set background=dark", "let mylist = [", [[  \"a",]], [[  \"b",]], [[  \"c",]], "  \\]" },
      { 0, 3 },
    },
    -- should work with dot-repeat
    {
      { 3, 0 },
      ".",
      { "## set background=dark", "let mylist = [", [[  \"a",]], [[  !! \"b",]], [[  \"c",]], "  \\]" },
      { 3, 0 },
    },
  })
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L673
T["treesitter"]["respects injected tree-sitter commentstring metadata : nvim-like builtin resolver"] = function()
  set_context({ bo = { tabstop = 2, filetype = "vim" }, config = { cms_confs = false } })
  child.lua_func(function()
    vim.treesitter.query.set(
      "lua",
      "highlights",
      [[
        ((string) @string (#set! @string bo.commentstring "; %s"))
      ]]
    )
    vim.treesitter.start()
  end)
  validate_steps({ "set background=dark", "lua << EOF", "print[[", "Inside string", "]]", "EOF" }, {
    {
      { 0, 0 },
      "gcc",
      { '" set background=dark', "lua << EOF", "print[[", "Inside string", "]]", "EOF" },
      { 0, 2 },
    },
    -- Should work with dot-repeat
    {
      { 3, 0 },
      ".",
      { '" set background=dark', "lua << EOF", "print[[", "; Inside string", "]]", "EOF" },
      { 3, 2 },
    },
    {
      { 2, 0 },
      ".",
      { '" set background=dark', "lua << EOF", "-- print[[", "; Inside string", "]]", "EOF" },
      { 2, 3 },
    },
  })
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L725
T["treesitter"]["works across combined injections"] = function()
  set_context({ bo = { filetype = "lua" } })
  child.lua_func(function()
    vim.treesitter.query.set(
      "lua",
      "injections",
      [[
      ((function_call
        name: (_) @_vimcmd_identifier
        arguments: (arguments
          (string
            content: _ @injection.content)))
        (#eq? @_vimcmd_identifier "vim.cmd")
        (#set! injection.language "vim")
        (#set! injection.combined))
    ]]
    )
    vim.treesitter.start()
  end)

  validate_steps({
    'vim.cmd([[" some text]])',
    "local a = 123",
    'vim.cmd([[" some more text]])',
  }, {
    {
      { 1, 0 },
      "gcc",
      { 'vim.cmd([[" some text]])', "-- local a = 123", 'vim.cmd([[" some more text]])' },
      { 1, 3 },
    },
  })
end

T["treesitter"]["use correct position to get comment string"] = function()
  mock_child_msg()
  set_context({ bo = { filetype = "lua" } })
  child.lua_func(function()
    vim.treesitter.query.set(
      "lua",
      "injections",
      [[
      ((function_call
        name: (_) @_vimcmd_identifier
        arguments: (arguments
          (string
            content: _ @injection.content)))
        (#eq? @_vimcmd_identifier "vim.cmd")
        (#set! injection.language "vim")
        (#set! injection.combined))
    ]]
    )
    vim.treesitter.start()
  end)
  local lines = { "vim.cmd([[some text]])" }
  set_lines(lines)
  set_cursor(0, 9)
  feed("gcc")
  eq_lines({ "-- vim.cmd([[some text]])" })
  eq_cursor({ 0, 12 })
  feed("gcc")
  eq_lines(lines)
  eq_cursor({ 0, 9 })
  feed("gbiw")
  eq_lines({ "vim.cmd--[[ ([[ ]]some text]])" })
  eq_cursor({ 0, 14 })
  feed("gbgb")
  eq_lines(lines)
  eq_cursor({ 0, 9 })
  eq(child_msg(), {})

  set_cursor(0, 10)
  feed("gbiw")
  eq_lines(lines)
  eq_cursor({ 0, 10 })
  eq(child_msg(), { "No available block comment string config" })
  clear_child_msg()
  feed("gciw")
  eq_lines({ "-- vim.cmd([[some text]])" })
  eq_cursor({ 0, 13 })
  eq(child_msg(), {})

  unmock_child_msg()
end

-- extract from options comments ──────────────────────────────────────────────

T["from_options_comments"] = new_set()

T["from_options_comments"]["works"] = function()
  validate_steps({ "  some text" }, {
    { "gcc", { "--   some text" } },
    { ".", { "  some text" } },
    { "gbc", { "  {- some text -}" } },
  }, { bo = { filetype = "haskell" }, config = { cms_confs = false } })
end

T["from_options_comments"]["works with injection"] = function()
  set_context({ bo = { filetype = "markdown", tabstop = 2, expandtab = false }, config = { cms_confs = false } })
  child.lua_func(function()
    vim.treesitter.language.add("cpp")
    vim.treesitter.language.add("bash")
    vim.treesitter.start()
  end)

  validate_steps({
    "# H1",
    "```cpp",
    '  printf("hello");',
    "```",
    "",
    "```bash",
    "echo hello",
    "```",
  }, {
    { { 2, 0 }, "gcc", { from = 3, '  // printf("hello");' } },
    { ".", { from = 3, '  printf("hello");' } },
    { "gbc", { from = 3, '  /* printf("hello"); */' } },
    { ".", { from = 3, '  printf("hello");' } },
    { { 6, 0 }, ".", { from = 7, "echo hello" } },
    { "gcc", { from = 7, "# echo hello" } },
    { ".", { from = 7, "echo hello" } },
  })
end

-- markdown injected language tests ───────────────────────────────────────────

T["markdown"] = new_set()

T["markdown"]["gcc toggle line works"] = function()
  set_context({ bo = { filetype = "markdown" }, config = { fallback_to_block = "if_line_cms_wrapped" } })
  child.lua_func(function() vim.treesitter.language.add("bash") end)
  child.treesitter.start()
  validate_steps({ "aaa", "```bash", "echo here", "```", "bbb" }, {
    { "gcc", { from = 1, "<!-- aaa -->" } },
    { "gcc", { from = 1, "aaa" } },
    { { 2, 0 }, "gcc", { from = 3, "# echo here" } },
    { "gcc", { from = 3, "echo here" } },
  })
end

T["markdown"]["gcc works"] = function()
  set_context({ bo = { filetype = "markdown" }, config = { fallback_to_block = "if_line_cms_wrapped" } })
  child.treesitter.start()
  validate_steps({ "aaa", "```lua", "print('hello')", "```", "bbb" }, {
    { "gcc", { from = 1, "<!-- aaa -->" } },
    { "gcc", { from = 1, "aaa" } },
    { { 2, 0 }, "gcc", { from = 3, "-- print('hello')" } },
    { "gcc", { from = 3, "print('hello')" } },
  })
end

T["markdown"]["gcc on code block lua line uses --"] = function()
  set_context({
    bo = { filetype = "markdown", commentstring = "<!-- %s -->" },
    config = { fallback_to_block = "if_line_cms_wrapped" },
  })
  child.lua([[
    vim.treesitter.language.add("lua")
    vim.treesitter.start()
  ]])

  validate_steps({
    "# Title",
    "",
    "Some text.",
    "",
    "```lua",
    "local x = 1",
    "function foo()",
    "  return x",
    "end",
    "```",
    "",
    "More text.",
  }, {
    -- Inside lua code block → "-- "
    { { 5, 0 }, "gcc", { from = 6, "-- local x = 1" } },
    { { 6, 0 }, "gcc", { from = 7, "-- function foo()" } },
    -- Outside code block → commentstring fallback
    { { 0, 0 }, "gcc", { from = 1, "<!-- # Title -->" } },
    { { 11, 0 }, "gcc", { from = 12, "<!-- More text. -->" } },
  })
end

T["markdown"]["gcc on code fence marker uses markdown comment"] = function()
  set_context({
    bo = { filetype = "markdown", commentstring = "<!-- %s -->" },
    config = { fallback_to_block = "if_line_cms_wrapped" },
  })
  child.lua([[
    vim.treesitter.language.add("lua")
    vim.treesitter.start()
  ]])

  validate_steps({ "", "```lua", "local x = 1", "```", "" }, {
    -- Code fence marker line → resolve_language_tree returns markdown root
    { { 1, 0 }, "gcc", { from = 2, "<!-- ```lua -->" } },
    -- Closing fence
    { { 3, 0 }, "gcc", { from = 4, "<!-- ``` -->" } },
  })
end

T["markdown"]["gco respects injected language in code block"] = function()
  set_context({ bo = { filetype = "markdown", commentstring = "<!-- %s -->" } })
  child.lua([[
    vim.treesitter.language.add("lua")
    vim.treesitter.start()
  ]])

  -- gco inside code block → new line with "-- "
  validate_steps({ "", "```lua", "local x = 1", "```", "" }, {
    { { 2, 0 }, { "gco", "<Esc>" }, { from = 4, "-- " } },
  })
end

T["markdown"]["visual mode works"] = function()
  set_context({ bo = { tabstop = 2, filetype = "markdown" }, config = { fallback_to_block = "if_line_cms_wrapped" } })
  local original = { "## head", "aaa", "```lua", "  local x = 1", "  local y = 2", "```", "bbb" }
  validate_steps(original, {
    {
      { 0, 0, 3, 12 },
      "gc",
      { "<!-- ## head", "aaa", "```lua", "  local x = 1 -->", "  local y = 2", "```", "bbb" },
      { 3, 12 },
    },
    { "gcu", original, { 3, 12 } },
    {
      { 2, 0, 3, 0 },
      "gc",
      { "## head", "aaa", "<!-- ```lua", "  local x = 1 -->", "  local y = 2", "```", "bbb" },
      { 3, 0 },
    },
    { "gcu", original },
    {
      { 3, 0, 4, 12 },
      "gc",
      { "## head", "aaa", "```lua", "--   local x = 1", "--   local y = 2", "```", "bbb" },
      { 4, 15 },
    },
    { "gcu", original, { 4, 12 } },
  })
end

-- disable tests ───────────────────────────────────────────────────────────────

T["disable"] = new_set()

T["disable"]["vim.g disables mappings"] = function()
  validate_steps({ "aa" }, { { "gcc", { "aa" } } }, { g = { celeste_comment_disable = true } })
end

T["disable"]["vim.b disables for buffer"] = function()
  validate_steps({ "aa" }, { { "gcc", { "aa" } } }, { b = { celeste_comment_disable = true } })
end

T["disable"]["use_default_mappings = false blanks default mappings"] = function()
  child.setup()
  child.lua_func(function()
    -- Drop Neovim's built-in comment mappings so only the plugin's remain.
    for _, spec in ipairs({ { "n", "gc" }, { "n", "gcc" }, { "x", "gc" } }) do
      pcall(vim.keymap.del, spec[1], spec[2])
    end

    require("celeste_comment").setup({
      use_default_mappings = false,
      mappings = { line_toggle = "gxc", line_toggle_cur = "gxq" },
    })
  end)

  -- explicit mappings still work
  eq(child.fn.maparg("gxc", "n") ~= "", true)
  eq(child.fn.maparg("gxq", "n") ~= "", true)

  -- untouched built-ins are blanked
  for _, spec in ipairs({
    { "gc", "n" },
    { "gcc", "n" },
    { "gc", "x" },
    { "gb", "n" },
    { "gbc", "n" },
    { "gb", "x" },
  }) do
    eq(child.fn.maparg(spec[1], spec[2]), "")
  end
end

-- warning msg tests ──────────────────────────────────────────────────────────

T["warning"] = new_set({
  hooks = {
    pre_case = function()
      mock_child_msg()
      set_context({
        config = { cms_confs = false, fallback_to_block = "never" },
        bo = { filetype = "unknown", commentstring = "" },
        b = { celeste_comment_block_commentstring = "" },
      })
    end,
    post_case = function() unmock_child_msg() end,
  },
})

T["warning"]["all invalid"] = function()
  set_lines({ "a" })
  set_cursor(0, 0)
  feed("gcc")
  eq_lines({ "a" })
  eq_cursor({ 0, 0 })
  eq(child_msg(), { 'Invalid CommentStringConf : { { "" }, { "" } }' })
end

T["warning"]["no available"] = function()
  set_lines({ "a" })
  set_cursor(0, 0)
  set_context({ b = { celeste_comment_block_commentstring = "{%s}" } })
  feed("gcc")
  eq_lines({ "a" })
  eq_cursor({ 0, 0 })
  eq(child_msg(), { "No available line comment string config" })
  clear_child_msg()

  feed("gbc")
  eq_lines({ "{ a }" })
  eq_cursor({ 0, 2 })
  feed(".")
  eq(child_msg(), {})
  set_context({ bo = { commentstring = "//%s" }, b = { celeste_comment_block_commentstring = "" } })
  feed("gbc")
  eq_lines({ "a" })
  eq_cursor({ 0, 0 })
  eq(child_msg(), { "No available block comment string config" })

  clear_child_msg()
  set_context({
    config = { cms_confs = false, fallback_to_block = "if_line_cms_wrapped" },
    b = { celeste_comment_block_commentstring = "!@#%s#@!" },
    bo = { commentstring = "" },
  })
  feed("gcc")
  eq_lines({ "!@# a #@!" })
  eq_cursor({ 0, 4 })
  eq(child_msg(), {})
end

T["warning"]["unmodifiable"] = function()
  set_context({ bo = { filetype = "lua" } })
  set_lines({ "a" })
  set_cursor(0, 0)
  set_context({ bo = { modifiable = false } })

  local f = function(k, msg)
    msg = msg or { "celeste_comment.nvim buffer unmodifiable" }
    feed(k)
    eq_lines({ "a" })
    eq(child_msg(), msg)
    clear_child_msg()
  end

  f("gcc")
  f("gbc")
  f("gcu")
  f("vga", {})
end

T["warning"]["disabled"] = function()
  set_context({ b = { celeste_comment_disable = true } })
  feed("gcc")
  eq(child_msg(), { "celeste_comment.nvim disabled" })
  clear_child_msg()
  set_context({ b = { celeste_comment_disable = false } })
  set_context({ g = { celeste_comment_disable = true } })
  feed("gcc")
  eq(child_msg(), { "celeste_comment.nvim disabled" })
end

-- Referenced from vscode ─────────────────────────────────────────────────────

T["referenced_from_vscode"] = new_set({
  hooks = {
    pre_case = function()
      set_context({
        config = {
          ignore_empty_lines = "never",
          insert_space = true,
          case_insensitive = true,
          fallback_to_block = "if_line_cms_wrapped",
        },
      })
      set_context({ bo = { commentstring = "!@#%s", filetype = "vscode-comment-test", tabstop = 4 } })
    end,
  },
})

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L56
T["referenced_from_vscode"]["comment single line"] = function()
  validate_steps({ "some text", "\tsome more text" }, {
    { "gcc", { "!@# some text", "\tsome more text" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L71
T["referenced_from_vscode"]["case insensitive"] = function()
  validate_steps({ "REM some text" }, { { "gcc", { "some text" } } }, { bo = { commentstring = "rem%s" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L89
T["referenced_from_vscode"]["comment with token column fixed"] = function()
  validate_steps({ "some text", "\tsome more text" }, {
    { { 1, 3 }, "gcc", { "some text", "!@# \tsome more text" } },
  }, { config = { line_comment_no_indent = true } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L198
T["referenced_from_vscode"]["normalize_insertion_point"] = function()
  local orig_ts = vim.bo.tabstop
  local function run(mixed, tabstop, expected, cfg)
    cfg = cfg or {}
    cfg.hooks = {}
    vim.bo.tabstop = tabstop
    local lines = {}
    for i = 1, #mixed, 2 do
      lines[#lines + 1] = mixed[i]
    end
    local csi = H.make_csi({ { "# ", "" } })
    local info = H.line_comment_info(lines, csi, cfg, { 0 }, 1)
    local off = vim.tbl_map(function(li) return li.offset end, info.lines)
    eq(off, expected)
  end

  -- Bug 16696: comments not aligned
  -- stylua: ignore start
  run({
    "  XX", 2,
    "    YY", 4,
  }, 4, { 0, 0 })

  -- Test1: various mixed indent
  run({
    "\t\t\tXX", 3,
    "    \tYY", 5,
    "        ZZ", 8,
    "\t\tTT", 2,
  }, 4, { 2, 5, 8, 2 })

  -- Test2: deeper mixed
  run({
    "\t\t\t   XX", 6,
    "    \t\t\t\tYY", 8,
    "        ZZ", 8,
    "\t\t    TT", 6,
  }, 4, { 2, 5, 8, 2 })

  -- Test3: blank rows → normalized to min viscol
  run({
    "\t\t", 2,
    "\t\t\t", 3,
    "\t\t\t\t", 4,
    "\t\t\t", 3,
  }, 4, { 2, 2, 2, 2 })

  -- Test4: blank rows, tabstop 2
  run(
    {
      "\t\t", 2,
      "\t\t\t", 3,
      "\t\t\t\t", 4,
      "\t\t\t", 3,
      "    ", 4,
    },
    2, { 2, 2, 2, 2, 4 }
  )

  -- Test5: blank rows, tabstop 4
  run(
    {
      "\t\t", 2,
      "\t\t\t", 3,
      "\t\t\t\t", 4,
      "\t\t\t", 3,
      "    ", 4,
    },
    4, { 1, 1, 1, 1, 4 }
  )

  -- Test6: whitespace lines, offset = #line
  run({
    " \t", 2,
    "  \t", 3,
    "   \t", 4,
    "    ", 4,
    "\t", 1,
  }, 4, { 2, 3, 4, 4, 1 })

  -- Test7: whitespace lines, offset = #line
  run(
    {
      " \t\t", 3,
      "  \t\t", 4,
      "   \t\t", 5,
      "    \t", 5,
      "\t", 1,
    },     4, { 2, 3, 4, 4, 1 }
  )

  -- Test8: ws_len == #line
  run({
    "\t", 1,
    "    ", 4
  }, 4, {1, 4})

  -- Test8: ws_len == #line
  run({
    "\t", 1,
    "   ", 3
  }, 4, {0, 0})

  -- Test8: ws_len == #line
  run({
    "\t", 1,
    "  ", 2
  }, 4, {0, 0})

  -- Test8: ws_len == #line
  run({
    "\t", 1,
    " ", 1
  }, 4, {0, 0})

  -- Test8: ws_len == #line
  run({
    "\t", 1,
    " ", 1
  }, 4, {0, 0})

  vim.bo.tabstop = orig_ts
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L294
T["referenced_from_vscode"]["detect indentation: gck"] = function()
  validate_steps({ "\tsome text", "\tsome more text" }, {
    { { 1, 2 }, "gck", { "\t!@# some text", "\t!@# some more text" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L309
T["referenced_from_vscode"]["detect indentation: gcj"] = function()
  validate_steps({ "\tsome text", "    some more text" }, {
    { { 0, 2 }, "gcj", { "\t!@# some text", "    !@# some more text" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L324
T["referenced_from_vscode"]["ignores whitespace lines"] = function()
  validate_steps({ "\tsome text", "\t   ", "", "\tsome more text" }, {
    { { 3, 2 }, "gc3k", { "\t!@# some text", "\t   ", "", "\t!@# some more text" } },
  }, { config = { ignore_empty_lines = "always" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L343
T["referenced_from_vscode"]["remove its own"] = function()
  validate_steps({ "\t!@# some text", "\t   ", "\t\t!@# some more text" }, {
    { { 2, 4 }, "gc2k", { "\tsome text", "\t   ", "\t\tsome more text" } },
  }, { config = { ignore_empty_lines = "always" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L360
T["referenced_from_vscode"]["works in only whitespace"] = function()
  validate_steps({ "\t    ", "\t", "\t\tsome more text" }, {
    { "2gcc", { "\t!@#     ", "\t!@# ", "\t\tsome more text" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L377
T["referenced_from_vscode"]["whitespace before comment token"] = function()
  validate_steps({ "\t !@#first", "\tsecond line" }, {
    { "gcc", { "\t first", "\tsecond line" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L392
T["referenced_from_vscode"]["line comment before caret"] = function()
  validate_steps({ "first!@#", "\tsecond line" }, {
    { "gcc", { "!@# first!@#", "\tsecond line" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L407
T["referenced_from_vscode"]["comment signle line"] = function()
  validate_steps({ "first!@#", "\tsecond line" }, {
    { { 1, 0 }, "gcc", { "first!@#", "\t!@# second line" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L443
T["referenced_from_vscode"]["multiple lines"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    { "gcj", { "!@# first", "!@# \tsecond line", "third line", "fourth line", "fifth" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L464
T["referenced_from_vscode"]["multiple modes on multiple lines"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    { { 3, 4, 2, 1 }, "gc", { "first", "\tsecond line", "!@# third line", "!@# fourth line", "fifth" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L485
T["referenced_from_vscode"]["toggle signle line"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    { { 0, 1, 0, 1 }, "gc", { "!@# first", "\tsecond line", "third line", "fourth line", "fifth" } },
    { { 0, 4, 0, 4 }, "gc", { "first", "\tsecond line", "third line", "fourth line", "fifth" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L525
T["referenced_from_vscode"]["toggle multiple lines"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    { { 1, 4, 0, 1 }, "gc", { "!@# first", "!@# \tsecond line", "third line", "fourth line", "fifth" } },
    { { 1, 7, 0, 4 }, "gc", { "first", "\tsecond line", "third line", "fourth line", "fifth" } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L565
T["referenced_from_vscode"]["cursor is at the beginning of the line"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    {
      { 0, 1, 0, 1 },
      "gc",
      { "!@# first", "\tsecond line", "third line", "fourth line", "fifth" },
      { 0, 5 },
    },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L586
T["referenced_from_vscode"]["comment hotkeys throws the cursor before the comment"] = function()
  validate_steps({ "first", "", "\tsecond line", "third line", "fourth line", "fifth" }, {
    {
      { 1, 0 },
      "gcc",
      { "first", "!@# ", "\tsecond line", "third line", "fourth line", "fifth" },
      { 1, 3 },
    },
  })
  validate_steps({ "first", "\t", "\tsecond line", "third line", "fourth line", "fifth" }, {
    {
      { 1, 2 },
      "gcc",
      { "first", "\t!@# ", "\tsecond line", "third line", "fourth line", "fifth" },
    },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L630
T["referenced_from_vscode"]["Add line comment fault when blank lines involved"] = function()
  validate_steps({
    '    if displayName == "":',
    "        displayName = groupName",
    '    description = getAttr(attributes, "description")',
    '    mailAddress = getAttr(attributes, "mail")',
    "",
    '    print "||Group name|%s|" % displayName',
    '    print "||Description|%s|" % description',
    '    print "||Email address|[mailto:%s]|" % mailAddress`',
  }, {
    {
      { 0, 1, 7, 56 },
      "gc",
      {
        '    !@# if displayName == "":',
        "    !@#     displayName = groupName",
        '    !@# description = getAttr(attributes, "description")',
        '    !@# mailAddress = getAttr(attributes, "mail")',
        "",
        '    !@# print "||Group name|%s|" % displayName',
        '    !@# print "||Description|%s|" % description',
        '    !@# print "||Email address|[mailto:%s]|" % mailAddress`',
      },
    },
  }, { config = { ignore_empty_lines = "always" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L657
T["referenced_from_vscode"]["toggle comments shouldn't move cursor"] = function()
  validate_steps({ "    A line", "    Another line" }, {
    { { 1, 7 }, "gck", { "    !@# A line", "    !@# Another line" }, { 1, 11 } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L672
T["referenced_from_vscode"]["insertSpace false"] = function()
  validate_steps({ "some text" }, {
    { { 0, 1 }, "gcc", { "!@#some text" }, { 0, 4 } },
  }, { config = { insert_space = false } })
end

-- NOTE: might differ with vscode, when insertSpace false, we respect the origin commentstring format
-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L690
T["referenced_from_vscode"]["insertSpace false does not remove space"] = function()
  validate_steps({ "!@#    some text" }, {
    { { 0, 1 }, "gcc", { "    some text" } },
  }, { config = { insert_space = false } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L718
T["referenced_from_vscode"]["does not ignore whitespace lines"] = function()
  validate_steps({ "\tsome text", "\t   ", "", "\tsome more text" }, {
    {
      { 3, 2, 0, 1 },
      "gc",
      { "!@# \tsome text", "!@# \t   ", "!@# ", "!@# \tsome more text" },
    },
  }, { config = { ignore_empty_lines = "never" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L718
T["referenced_from_vscode"]["ignore_empty_lines removes its own"] = function()
  validate_steps({ "\t!@# some text", "\t   ", "\t\t!@# some more text" }, {
    { { 2, 2, 0, 1 }, "gc", { "\tsome text", "\t   ", "\t\tsome more text" } },
  }, { config = { ignore_empty_lines = "never" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L754
T["referenced_from_vscode"]["ignore_empty_lines works in only whitespace"] = function()
  validate_steps({ "\t    ", "\t", "\t\tsome more text" }, {
    { "gcj", { "\t!@#     ", "\t!@# ", "\t\tsome more text" } },
  }, { config = { ignore_empty_lines = "never" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L771
T["referenced_from_vscode"]["ignore_empty_lines comments single line: first line"] = function()
  validate_steps({ "some text", "\tsome more text" }, {
    { { 0, 1, 0, 1 }, "gcc", { "!@# some text", "\tsome more text" } },
  }, { config = { ignore_empty_lines = "never" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L786
T["referenced_from_vscode"]["ignore_empty_lines comments single line: multiple lines"] = function()
  validate_steps({ "\tsome text", "\tsome more text" }, {
    { { 1, 2, 0, 1 }, "gcc", { "\t!@# some text", "\t!@# some more text" } },
  }, { config = { ignore_empty_lines = "never" } })
end

T["referenced_from_vscode"]["commenting code in JSX files"] = function()
  set_context({ bo = { filetype = "javascript" } })
  child.lua_func(function()
    vim.treesitter.language.add("javascript")
    vim.treesitter.start()
  end)

  local jsx = {
    "import React from 'react';",
    "const Loader = () => (",
    "  <div>",
    "    Loading...",
    "  </div>",
    ");",
    "export default Loader;",
  }
  validate_steps(jsx, {
    {
      "gc6j",
      {
        "// import React from 'react';",
        "// const Loader = () => (",
        "//   <div>",
        "//     Loading...",
        "//   </div>",
        "// );",
        "// export default Loader;",
      },
      { 0, 3 },
    },
    { "gcgc", jsx, { 0, 0 } },
    {
      { 3, 0 },
      "gcc",
      {
        "import React from 'react';",
        "const Loader = () => (",
        "  <div>",
        "    {/* Loading... */}",
        "  </div>",
        ");",
        "export default Loader;",
      },
    },
  })
end

-- Referenced from:
-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L811
-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L832
-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L853
T["referenced_from_vscode"]["fallback to block comment command"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    {
      { 0, 3 },
      "gcc",
      { "( first )", "\tsecond line", "third line", "fourth line", "fifth" },
      { 0, 5 },
    },
    { "gcc", { "first", "\tsecond line", "third line", "fourth line", "fifth" } },
  }, { bo = { commentstring = "" }, b = { celeste_comment_block_commentstring = "(%s)" } })
end

-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L874
T["referenced_from_vscode"]["always expand selection to line boundaries"] = function()
  validate_steps({ "first", "\tsecond line", "third line", "fourth line", "fifth" }, {
    {
      { 2, 2, 0, 3 },
      "gc",
      { "( first", "\tsecond line", "third line )", "fourth line", "fifth" },
    },
  }, { bo = { commentstring = "" }, b = { celeste_comment_block_commentstring = "(%s)" } })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L924
T["referenced_from_vscode"]["fallback to block : no selection => uses indentation"] = function()
  set_context({ bo = { commentstring = "" }, b = { celeste_comment_block_commentstring = "<!@#%s#@!>" } })
  local lines = {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  }
  validate_steps(lines, {
    {
      { 0, 3 },
      "gcc",
      { "\t\t<!@# first\t     #@!>", "\t\tsecond line", "\tthird line", "fourth line", "\t\t<!@#fifth#@!>\t\t" },
      { 0, 8 },
    },
    { "gcc", lines, { 0, 3 } },
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L964
T["referenced_from_vscode"]["fallback to block : can remove"] = function()
  set_context({ bo = { commentstring = "" }, b = { celeste_comment_block_commentstring = "<!@#%s#@!>" } })
  local lines = {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  }
  local expected = {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\tfifth\t\t",
  }
  validate_steps(lines, { { { 4, 1 }, "gcc", expected } })
  validate_steps(lines, { { { 4, 3 }, "gcc", expected } })
  validate_steps(lines, { { { 4, 4 }, "gcc", expected } })
end

--- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L1080
T["referenced_from_vscode"]["fallback to block : Remove comment not work consistently in HTML"] = function()
  validate_steps({ "     asd qwe", "     asd qwe", "" }, {
    { "gcj", { "     <!@# asd qwe", "     asd qwe #@!>", "" } },
  }, { bo = { commentstring = "" }, b = { celeste_comment_block_commentstring = "<!@#%s#@!>" } })
  validate_steps({ "     <!@#asd qwe", "     asd qwe#@!>", "" }, {
    { "gcj", { "     asd qwe", "     asd qwe", "" } },
  })
end

-- Regression tests ───────────────────────────────────────────────────────────

T["inline_multi_block"] = new_set()

T["inline_multi_block"]["gbc on line with inline block wraps whole line"] = function()
  validate_steps({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," }, {
    { { 0, 30 }, "gbc", { "        /* /* value */ EncodeAsString(k * 2), /* is_delete */ false, */" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["block_is_partial checks exact position"] = function()
  validate_steps({ "  /* a */ b(), /* c */ d()," }, {
    { { 0, 2 }, { "v", "6l", "gb" }, { "  a b(), /* c */ d()," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["dgb multi-line mid-column deletes precisely"] = function()
  validate_steps({ "x /* a", "b */ y" }, {
    { { 0, 3 }, "dgb", { "x  y" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbgb toggles inline block comment"] = function()
  validate_steps({ "  /* value */ code" }, {
    { { 0, 4 }, "gbgb", { "  value code" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbiw toggles specific word only"] = function()
  validate_steps({ "  /* val */ str(), /* del */ true," }, {
    { { 0, 13 }, "gbiw", { "  /* val */ /* str */(), /* del */ true," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["vib selects multi-line block precisely"] = function()
  set_context({ bo = { filetype = "cpp", commentstring = "// %s" } })
  child.lua([[
    vim.keymap.set("x", "ib", '<Cmd>lua require("celeste_comment").H.textobject_blockwise()<CR>')
  ]])
  set_lines({ "pre /* comment starts", "middle line", "ends here */ post" })
  set_cursor(1, 5)
  feed("v", "i", "b", "<Esc>")

  eq_marks({ "<", ">" }, { { 1, 4 }, { 3, 11 } })
end

T["inline_multi_block"]["gbgb outside inline block does nothing"] = function()
  -- Cursor on EncodeAsString, outside any /* */ block
  validate_steps({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," }, {
    { { 0, 23 }, "gbgb", { "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbgb inside inline block works"] = function()
  -- Cursor on 'value' inside /* value */; is_delete unaffected
  validate_steps({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," }, {
    { { 0, 12 }, "gbgb", { "        value EncodeAsString(k * 2), /* is_delete */ false," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbgb on second inline block works"] = function()
  -- Cursor on 'is_delete' inside /* is_delete */
  validate_steps({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," }, {
    { { 0, 48 }, "gbgb", { "        /* value */ EncodeAsString(k * 2), is_delete false," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbgb on marker chars works"] = function()
  -- Cursor on '/' in /* value */
  validate_steps({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," }, {
    { { 0, 8 }, "gbgb", { "        value EncodeAsString(k * 2), /* is_delete */ false," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbgb on empty line below inline block does nothing"] = function()
  validate_steps({ "        /* use_contiguous_buffer */ true);", "", "    /* is_delete */ true," }, {
    { { 1, 0 }, "gbgb", { "        /* use_contiguous_buffer */ true);", "", "    /* is_delete */ true," } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["inline_multi_block"]["gbgb beyond block_textobj_nlines does nothing"] = function()
  validate_steps({ "/* far */ code", "", "", "", "content" }, {
    { { 4, 0 }, "gbgb", { from = 1, "/* far */ code" } },
  }, { bo = { filetype = "cpp", commentstring = "// %s" }, config = { block_textobj_nlines = 1 } })
end

T["inline_multi_block"]["gbgb on first inline block in multi-line works"] = function()
  validate_steps({
    "input_descs.emplace_back(",
    "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k),",
    "        /* value */ EncodeAsString(k), /* is_delete */ false,",
    "        /* use_contiguous_buffer */ false);",
  }, {
    {
      { 1, 14 },
      "gbgb",
      {
        "input_descs.emplace_back(",
        "        key EncodeAsString(k), /* timestamp */ EncodeAsUint64(k),",
        "        /* value */ EncodeAsString(k), /* is_delete */ false,",
        "        /* use_contiguous_buffer */ false);",
      },
    },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

-- multi line comment string tests ─────────────────────────────────────────────

T["multi_line_comment_string"] = new_set()

T["multi_line_comment_string"]["tomake_csi_single_string_backward_compat"] = function()
  local H2 = require("celeste_comment").H
  local csi = H2.make_csi({ { "//", "" } })
  eq(type(csi.pairs), "table")
  eq(#csi.pairs, 1)
  eq(csi.pairs[1].tesc[1], vim.pesc("//"))
  eq(csi.pairs[1].tesc[2], "")
end

T["multi_line_comment_string"]["tomake_csi_multi_token_sorted"] = function()
  local H2 = require("celeste_comment").H
  local csi = H2.make_csi({ { "//", "" }, { "///", "" }, { "//!", "" } })
  eq(csi.pairs[1].tesc[1], vim.pesc("///"))
  eq(csi.pairs[2].tesc[1], vim.pesc("//!"))
  eq(csi.pairs[3].tesc[1], vim.pesc("//"))
  eq(#csi.pairs, 3)
end

T["multi_line_comment_string"]["gcc_removes_longest_token"] = function()
  -- removes "/// " leaving "doc comment"
  validate_steps({ "/// doc comment" }, { { "gcc", { "doc comment" } } }, {
    bo = { filetype = "rust" },
    config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } },
  })
end

T["multi_line_comment_string"]["gcc_removes_correct_token"] = function()
  validate_steps({ "//! inner doc" }, { { "gcc", { "inner doc" } } }, {
    bo = { filetype = "rust" },
    config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } },
  })
end

T["multi_line_comment_string"]["gcc_adds_primary_token"] = function()
  -- primary is "//"
  validate_steps({ "normal code" }, { { "gcc", { "// normal code" } } }, {
    bo = { filetype = "rust" },
    config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } },
  })
end

T["multi_line_comment_string"]["gcgc_selects_mixed_tokens"] = function()
  validate_steps({ "/// doc", "// normal", "//! inner", "end" }, {
    { { 1, 0 }, "dgc", { "end" } },
  }, { bo = { filetype = "rust" }, config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } } })
end

-- fallback_to_block tests ─────────────────────────────────────────────────────

T["fallback_to_block"] = new_set()

T["fallback_to_block"]["never: works"] = function()
  validate_steps({ "aaa", "bbb" }, {
    { "gcc", { "aaa", "bbb" } },
  }, { bo = { filetype = "test" }, config = { fallback_to_block = "never", cms_confs = { test = { nil, "/*%s*/" } } } })

  validate_steps(nil, {
    { ".", { "<!-- aaa -->", "bbb" } },
    { "u" },
    { { "gc", "2j" }, { "<!-- aaa -->", "<!-- bbb -->" }, { 0, 5 } },
    { ".", { "aaa", "bbb" } },
  }, { config = { fallback_to_block = "never", cms_confs = { test = { "<!--%s-->", "/*%s*/" } } } })
end

T["fallback_to_block"]["if_line_cms_wrapped: works1"] = function()
  validate_steps({ "hello" }, {
    { { 0, 3 }, "gcc", { "/* hello */" }, { 0, 6 } },
    { ".", { "hello" } },
  }, {
    bo = { filetype = "test" },
    config = { fallback_to_block = "if_line_cms_wrapped", cms_confs = { test = { nil, "/*%s*/" } } },
  })

  validate_steps({ "    aaa", "    /* bbb */", "    /*ccc*/" }, {
    { { 1, 4 }, { "gc", "gc" }, { "    aaa", "    bbb", "    /*ccc*/" }, { 1, 4 } },
    { { 2, 6 }, ".", { "    aaa", "    bbb", "    ccc" } },
  })

  validate_steps({ "aaa", "bbb", "ccc" }, {
    { { 0, 0 }, "gcj", { "/* aaa", "bbb */", "ccc" } },
    { "gcgc", { "aaa", "bbb", "ccc" } },
  })

  validate_steps({ "/* aaa", "bbb */", "ccc" }, {
    { { 0, 0 }, "gcj", { "aaa", "bbb", "ccc" } },
  })

  -- always expand selection to line boundaries when fallback_to_block
  validate_steps({ "hello world", "foo bar baz" }, {
    { { 0, 6, 1, 4 }, "gc", { "/* hello world", "foo bar baz */" } },
    -- round-trip: gcgc uncomments
    { "gcgc", { "hello world", "foo bar baz" } },
    { "u" },
    { { 0, 8 }, "gcu", { "hello world", "foo bar baz" } },
  })
end

T["fallback_to_block"]["if_line_cms_wrapped: works2"] = function()
  validate_steps({ "a" }, {
    { "gcc", { "# a" }, { 0, 2 } },
    { ".", { "a" } },
  }, {
    bo = { filetype = "test" },
    config = { fallback_to_block = "if_line_cms_wrapped", cms_confs = { test = { "#%s", "/*%s*/" } } },
  })

  validate_steps({ "a" }, {
    { "gcc", { "!@# a #@!" }, { 0, 4 } },
  }, {
    config = {
      fallback_to_block = "if_line_cms_wrapped",
      cms_confs = { test = { "!@#%s#@!", "/*%s*/" } },
    },
  })

  validate_steps({ "aaa", "bbb", "ccc" }, {
    { { 0, 0 }, "gcj", { "!@# aaa", "bbb #@!", "ccc" }, { 0, 4 } },
    { { "gc", "gc" }, { "aaa", "bbb", "ccc" }, { 0, 0 } },
    { "u" },
    { { 0, 6 }, "gcj", { "aaa", "bbb", "ccc" }, { 0, 2 } },
  })

  -- always expand selection to linewise
  validate_steps({ "hello world", "foo bar baz" }, {
    { { 0, 6, 1, 4 }, "gc", { "!@# hello world", "foo bar baz #@!" } },
    -- round-trip: gcgc uncomments
    { "gcgc", { "hello world", "foo bar baz" } },
    { "u" },
    { { 0, 8 }, "gcu", { "hello world", "foo bar baz" } },
  })
end

-- Toggle current line comment at insert mode ─────────────────────────────────

T["toggle_line_comment_at_insert_mode"] = new_set({
  parametrize = { { "never" }, { "if_line_cms_wrapped" } },
})

local function ins_f(col, etcol, start_line, end_line, expected_after_at)
  set_lines({ start_line })
  set_cursor(0, col)
  feed("<c-/>")
  eq_lines({ end_line })
  eq_cursor({ 0, etcol })
  feed("@")
  eq_lines({ expected_after_at })
  eq_cursor({ 0, etcol + 1 })
  feed("<c-h>")
  eq_cursor({ 0, etcol })
end

T["toggle_line_comment_at_insert_mode"]["works for lcs only cms"] = function(fallback)
  set_context({
    config = { fallback_to_block = fallback },
    bo = { tabstop = 2, expandtab = true, filetype = "unknown", commentstring = "// %s" },
  })
  feed("i")

  -- stylua: ignore start
  ins_f(0, 0,  "  hello",      "  // hello",    "@  // hello")
  ins_f(1, 1,  "  hello",      "  // hello",    " @ // hello")
  ins_f(2, 5,  "  hello",      "  // hello",    "  // @hello")
  ins_f(3, 6,  "  hello",      "  // hello",    "  // h@ello")
  ins_f(4, 7,  "  hello",      "  // hello",    "  // he@llo")
  ins_f(5, 8,  "  hello",      "  // hello",    "  // hel@lo")
  ins_f(6, 9,  "  hello",      "  // hello",    "  // hell@o")
  ins_f(7, 10, "  hello",      "  // hello",    "  // hello@")

  ins_f(0,  0, "  // hello",   "  hello",       "@  hello")
  ins_f(1,  1, "  // hello",   "  hello",       " @ hello")
  ins_f(2,  2, "  // hello",   "  hello",       "  @hello")
  ins_f(3,  2, "  // hello",   "  hello",       "  @hello")
  ins_f(4,  2, "  // hello",   "  hello",       "  @hello")
  ins_f(5,  2, "  // hello",   "  hello",       "  @hello")
  ins_f(6,  3, "  // hello",   "  hello",       "  h@ello")
  ins_f(7,  4, "  // hello",   "  hello",       "  he@llo")
  ins_f(8,  5, "  // hello",   "  hello",       "  hel@lo")
  ins_f(9,  6, "  // hello",   "  hello",       "  hell@o")
  ins_f(10, 7, "  // hello",   "  hello",       "  hello@")

  -- blank lines
  ins_f(0, 3, "",   "// ",   "// @")
  ins_f(0, 0, "  ", "  // ", "@  // ")
  ins_f(1, 1, "  ", "  // ", " @ // ")
  ins_f(2, 5, "  ", "  // ", "  // @")

  ins_f(0, 0, "// ",   "",   "@")
  ins_f(1, 0, "// ",   "",   "@")
  ins_f(2, 0, "// ",   "",   "@")
  ins_f(0, 0, "  // ", "  ", "@  ")
  ins_f(1, 1, "  // ", "  ", " @ ")
  ins_f(2, 2, "  // ", "  ", "  @")
  ins_f(3, 2, "  // ", "  ", "  @")
  ins_f(4, 2, "  // ", "  ", "  @")
  ins_f(5, 2, "  // ", "  ", "  @")

  ins_f(0, 0, "  //  ", "   ", "@   ")
  ins_f(1, 1, "  //  ", "   ", " @  ")
  ins_f(2, 2, "  //  ", "   ", "  @ ")
  ins_f(3, 2, "  //  ", "   ", "  @ ")
  ins_f(4, 2, "  //  ", "   ", "  @ ")
  ins_f(5, 2, "  //  ", "   ", "  @ ")
  ins_f(6, 3, "  //  ", "   ", "   @")
  -- stylua: ignore end
end

T["toggle_line_comment_at_insert_mode"]["works for lcs-rcs cms"] = function(fallback)
  set_context({
    config = { fallback_to_block = fallback },
    bo = { tabstop = 2, expandtab = true, filetype = "unknown", commentstring = "/* %s */" },
  })
  feed("i")

  -- stylua: ignore start
  ins_f(0, 0,  "  hello",      "  /* hello */",  "@  /* hello */")
  ins_f(1, 1,  "  hello",      "  /* hello */",  " @ /* hello */")
  ins_f(2, 5,  "  hello",      "  /* hello */",  "  /* @hello */")
  ins_f(3, 6,  "  hello",      "  /* hello */",  "  /* h@ello */")
  ins_f(4, 7,  "  hello",      "  /* hello */",  "  /* he@llo */")
  ins_f(5, 8,  "  hello",      "  /* hello */",  "  /* hel@lo */")
  ins_f(6, 9,  "  hello",      "  /* hello */",  "  /* hell@o */")
  ins_f(7, 10, "  hello",      "  /* hello */",  "  /* hello@ */")

  ins_f(0,  0, "  /* hello */", "  hello",       "@  hello")
  ins_f(1,  1, "  /* hello */", "  hello",       " @ hello")
  ins_f(2,  2, "  /* hello */", "  hello",       "  @hello")
  ins_f(3,  2, "  /* hello */", "  hello",       "  @hello")
  ins_f(4,  2, "  /* hello */", "  hello",       "  @hello")
  ins_f(5,  2, "  /* hello */", "  hello",       "  @hello")
  ins_f(6,  3, "  /* hello */", "  hello",       "  h@ello")
  ins_f(7,  4, "  /* hello */", "  hello",       "  he@llo")
  ins_f(8,  5, "  /* hello */", "  hello",       "  hel@lo")
  ins_f(9,  6, "  /* hello */", "  hello",       "  hell@o")
  ins_f(10, 7, "  /* hello */", "  hello",       "  hello@")
  ins_f(11, 7, "  /* hello */", "  hello",       "  hello@")
  ins_f(12, 7, "  /* hello */", "  hello",       "  hello@")
  ins_f(13, 7, "  /* hello */", "  hello",       "  hello@")

  -- blank lines
  ins_f(0, 3, "",   "/*  */",   "/* @ */")
  ins_f(0, 3, "  ", "/*  */  ", "/* @ */  ")
  ins_f(1, 4, "  ", " /*  */ ", " /* @ */ ")
  ins_f(2, 5, "  ", "  /*  */", "  /* @ */")

  ins_f(0, 0, "/*  */", "", "@")
  ins_f(1, 0, "/*  */", "", "@")
  ins_f(2, 0, "/*  */", "", "@")
  ins_f(3, 0, "/*  */", "", "@")
  ins_f(4, 0, "/*  */", "", "@")
  ins_f(5, 0, "/*  */", "", "@")
  ins_f(6, 0, "/*  */", "", "@")

  ins_f(0, 0, "  /*  */", "  ", "@  ")
  ins_f(1, 1, "  /*  */", "  ", " @ ")
  ins_f(2, 2, "  /*  */", "  ", "  @")
  ins_f(3, 2, "  /*  */", "  ", "  @")
  ins_f(4, 2, "  /*  */", "  ", "  @")
  ins_f(5, 2, "  /*  */", "  ", "  @")
  ins_f(6, 2, "  /*  */", "  ", "  @")
  ins_f(7, 2, "  /*  */", "  ", "  @")
  ins_f(8, 2, "  /*  */", "  ", "  @")

  ins_f(0, 0,  "  /*  */  ", "    ", "@    ")
  ins_f(1, 1,  "  /*  */  ", "    ", " @   ")
  ins_f(2, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(3, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(4, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(5, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(6, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(7, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(8, 2,  "  /*  */  ", "    ", "  @  ")
  ins_f(9, 3,  "  /*  */  ", "    ", "   @ ")
  ins_f(10, 4, "  /*  */  ", "    ", "    @")
  -- stylua: ignore end
end

T["toggle_line_comment_at_insert_mode"]["works for rcs only cms"] = function(fallback)
  set_context({
    config = { fallback_to_block = fallback },
    bo = { tabstop = 2, expandtab = true, filetype = "unknown", commentstring = "%s --" },
  })
  feed("i")

  -- stylua: ignore start
  ins_f(0, 0, "  hello",      "  hello --",    "@  hello --")
  ins_f(1, 1, "  hello",      "  hello --",    " @ hello --")
  ins_f(2, 2, "  hello",      "  hello --",    "  @hello --")
  ins_f(3, 3, "  hello",      "  hello --",    "  h@ello --")
  ins_f(4, 4, "  hello",      "  hello --",    "  he@llo --")
  ins_f(5, 5, "  hello",      "  hello --",    "  hel@lo --")
  ins_f(6, 6, "  hello",      "  hello --",    "  hell@o --")
  ins_f(7, 7, "  hello",      "  hello --",    "  hello@ --")

  ins_f(0,  0, "  hello --",   "  hello",       "@  hello")
  ins_f(1,  1, "  hello --",   "  hello",       " @ hello")
  ins_f(2,  2, "  hello --",   "  hello",       "  @hello")
  ins_f(3,  3, "  hello --",   "  hello",       "  h@ello")
  ins_f(4,  4, "  hello --",   "  hello",       "  he@llo")
  ins_f(5,  5, "  hello --",   "  hello",       "  hel@lo")
  ins_f(6,  6, "  hello --",   "  hello",       "  hell@o")
  ins_f(7,  7, "  hello --",   "  hello",       "  hello@")
  ins_f(8,  7, "  hello --",   "  hello",       "  hello@")
  ins_f(9,  7, "  hello --",   "  hello",       "  hello@")
  ins_f(10, 7, "  hello --",   "  hello",       "  hello@")

  -- blank lines
  ins_f(0, 0, "",   " --",   "@ --")
  ins_f(0, 0, "  ", "   --", "@   --")
  ins_f(1, 1, "  ", "   --", " @  --")
  ins_f(2, 2, "  ", "   --", "  @ --")

  ins_f(0, 0, " --", "", "@")
  ins_f(1, 0, " --", "", "@")
  ins_f(2, 0, " --", "", "@")
  ins_f(3, 0, " --", "", "@")

  ins_f(0, 0, "   --", "  ", "@  ")
  ins_f(1, 1, "   --", "  ", " @ ")
  ins_f(2, 2, "   --", "  ", "  @")
  ins_f(3, 2, "   --", "  ", "  @")
  ins_f(4, 2, "   --", "  ", "  @")
  ins_f(5, 2, "   --", "  ", "  @")
  -- stylua: ignore end
end

-- Force add/remove comment ───────────────────────────────────────────────────

T["force_comment"] = new_set()

T["force_comment"]["force add works"] = function()
  validate_steps({ "hello", "// world" }, {
    { { "gC", "j" }, { "// hello", "// // world" }, { 0, 3 } },
    { ".", { "// // hello", "// // // world" }, { 0, 6 } },
    { { "V", "j", "gC" }, { "// // // hello", "// // // // world" }, { 1, 9 } },
  }, { bo = { commentstring = "// %s" } })
end

T["force_comment"]["force remove works"] = function()
  validate_steps({ "hello", "// world" }, {
    { { 1, 3 }, { "gU", "k" }, { "hello", "world" }, { 1, 0 } },
    { ".", { "hello", "world" }, { 1, 0 } },
  }, { bo = { commentstring = "// %s" } })
  validate_steps({ "// hello", "  // ", "  ", "    // world" }, {
    { { 0, 2 }, { "V", "3j", "gU" }, { "hello", "  ", "  ", "    world" }, { 3, 2 } },
  })
end

T["force_comment"]["respect ignore_empty_lines"] = function()
  -- ForceAdd + always: blank lines skipped
  validate_steps({ "hello", "  ", "// world" }, {
    { { 0, 0 }, { "V", "2j", "gC" }, { "// hello", "  ", "// // world" } },
  }, { bo = { tabstop = 2, commentstring = "// %s" }, config = { ignore_empty_lines = "always" } })

  -- ForceRemove + always: blank lines skipped, commented lines uncommented
  validate_steps({ "// hello", "  ", "// world" }, {
    { { 0, 0 }, { "V", "2j", "gU" }, { "hello", "  ", "world" } },
  })

  -- ForceAdd + never: blank lines participate in alignment, rounding to tabstop
  validate_steps({ "   hello", " " }, {
    { { 0, 0 }, { "V", "j", "gC" }, { "//    hello", "//  " } },
  }, { config = { ignore_empty_lines = "never" } })

  -- ForceAdd + mixed: blank lines excluded from alignment, min col from content
  validate_steps({ "   hello", " " }, {
    { { 0, 0 }, { "V", "j", "gC" }, { "  //  hello", "  // " } },
  }, { config = { ignore_empty_lines = "mixed" } })
end

-- invert tests ────────────────────────────────────────────────────────────────

T["invert"] = new_set()

T["invert"]["works"] = function()
  validate_steps({ "// a" }, {
    { { 0, 3 }, "gcI_", { "a" }, { 0, 0 } },
    { "gcI_", { "// a" }, { 0, 3 } },
  }, { bo = { filetype = "cpp" } })
  validate_steps({ "//a", "b", "//c", "d", "//d" }, {
    { { 0, 2 }, { "gcI", "4j" }, { "a", "// b", "c", "// d", "d" }, { 0, 0 } },
    { { "gcI", "4j" }, { "// a", "b", "// c", "d", "// d" }, { 0, 3 } },
  })
end

T["invert"]["works with special cms"] = function()
  validate_steps({ "a", "<!--b-->", " c" }, {
    { { 2, 1 }, { "gcI", "2k" }, { "<!-- a -->", "b", "<!--  c -->" }, { 2, 6 } },
  }, { bo = { filetype = "unknown", commentstring = "<!--%s-->" }, config = { fallback_to_block = "never" } })

  validate_steps({ "aaaa", "bbbb!@#", "ccc" }, {
    { { 0, 0, 2, 2 }, "gcI", { "aaaa !@#", "bbbb", "ccc !@#" }, { 2, 2 } },
  }, { bo = { commentstring = "%s !@#" } })
end

T["invert"]["respect ignore_empty_lines"] = function()
  validate_steps({ "    # a", "", "    # b" }, {
    { { 0, 6 }, { "gcI", "2j" }, { "    a", "# ", "    b" } },
  }, { config = { ignore_empty_lines = "never" } })

  validate_steps({ "    # a", "", "    # b" }, {
    { { 0, 6 }, { "gcI", "2j" }, { "    a", "    # ", "    b" }, { 0, 4 } },
    { { "gcI", "2j" }, { "    # a", "    ", "    # b" }, { 0, 6 } },
  }, { config = { ignore_empty_lines = "mixed" } })

  validate_steps(nil, {
    { { "gcI", "2j" }, { "    a", "    ", "    b" }, { 0, 4 } },
    { { "gcI", "2j" }, { "    # a", "    ", "    # b" }, { 0, 6 } },
  }, { config = { ignore_empty_lines = "always" } })
end

-- Vue files test ─────────────────────────────────────────────────────────────

T["vue"] = new_set({
  hooks = {
    pre_case = function()
      set_context({ config = { fallback_to_block = "if_line_cms_wrapped" } })
      child.lua_func(function()
        vim.treesitter.language.add("vue")
        vim.treesitter.language.add("html")
        vim.treesitter.language.add("css")
        vim.treesitter.language.add("javascript")
      end)
    end,
  },
})

T["vue"]["works"] = function()
  set_context({ bo = { filetype = "vue", tabstop = 2 } })
  local lines = {
    "<template>",
    "  <!-- template comment -->",
    "  <div>{{ msg }}</div>",
    "</template>",
    "",
    "<script setup>",
    "// script single-line comment",
    "/* script multi-line comment */",
    "const msg = 'hello'",
    "</script>",
    "",
    "<style scoped>",
    "/* style comment */",
    "div { color: red; }",
    "</style>",
  }
  set_lines(lines)
  child.lua_func(function() vim.treesitter.start() end)

  validate_steps(nil, {
    { { 1, 0 }, "gcc", { from = 2, "  template comment" } },
    { { 2, 0 }, ".", { from = 3, "  <!-- <div>{{ msg }}</div> -->" } },
    { { 6, 0 }, ".", { from = 7, "script single-line comment" } },
    { { 7, 0 }, "gbc", { from = 8, "script multi-line comment" } },
    { { 12, 0 }, ".", { from = 13, "style comment" } },
    { { 13, 0 }, "gcc", { from = 14, "/* div { color: red; } */" } },
  })
end

-- PHP files test ─────────────────────────────────────────────────────────────

T["php"] = new_set({
  hooks = {
    pre_case = function()
      set_context({ bo = { filetype = "php" }, config = { fallback_to_block = "if_line_cms_wrapped" } })
      child.lua_func(function()
        vim.treesitter.language.add("php")
        vim.treesitter.start()
      end)
    end,
  },
})

T["php"]["works"] = function()
  local lines = {
    "<html>",
    "<?php",
    "for ($i = 0; $i < 10; $i++)",
    "    print_r($i)",
    "}",
    "?>",
    "</html>",
  }
  validate_steps(lines, {
    {
      { 2, 0 },
      "gc2j",
      { from = 3, "// for ($i = 0; $i < 10; $i++)", "//     print_r($i)", "// }" },
      { 2, 3 },
    },
    {
      "gcgc",
      { from = 3, "for ($i = 0; $i < 10; $i++)", "    print_r($i)", "}" },
      { 2, 0 },
    },
    {
      "gb2j",
      { from = 3, "/* for ($i = 0; $i < 10; $i++)", "    print_r($i)", "} */" },
      { 2, 3 },
    },
    {
      ".",
      { from = 3, "for ($i = 0; $i < 10; $i++)", "    print_r($i)", "}" },
      { 2, 0 },
    },
    {
      { 1, 0 },
      "gc4j",
      {
        from = 2,
        "<!-- <?php",
        "for ($i = 0; $i < 10; $i++)",
        "    print_r($i)",
        "}",
        "?> -->",
      },
      { 1, 5 },
    },
    {
      "gcgc",
      {
        from = 2,
        "<?php",
        "for ($i = 0; $i < 10; $i++)",
        "    print_r($i)",
        "}",
        "?>",
      },
      { 1, 0 },
    },
  })
end

-- HTML tests ─────────────────────────────────────────────────────────────────

T["html"] = new_set({
  hooks = {
    pre_case = function()
      set_context({ bo = { filetype = "html", tabstop = 2 }, config = { fallback_to_block = "if_line_cms_wrapped" } })
      child.lua_func(function()
        vim.treesitter.language.add("html")
        vim.treesitter.language.add("css")
        vim.treesitter.start()
      end)
    end,
  },
})

T["html"]["works"] = function()
  validate_steps({
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<body>",
    "  <style>",
    "    p {",
    "      color:'#36f482'",
    "    }",
    "  </style>",
    "</body>",
    "</html>",
  }, {
    { { 3, 4 }, "gcc", { from = 4, "  <!-- <style> -->" }, { 3, 9 } },
    { ".", { from = 4, "  <style>" } },
    { { 7, 4 }, "gcc", { from = 8, "  <!-- </style> -->" }, { 7, 9 } },
    { ".", { from = 8, "  </style>" } },
    {
      { 4, 0, 6, 0 },
      "gc",
      { from = 5, "    /* p {", "      color:'#36f482'", "    } */" },
    },
    {
      "gcgc",
      { from = 5, "    p {", "      color:'#36f482'", "    }" },
    },
  })
end

-- JSX/TSX files test ─────────────────────────────────────────────────────────

T["jsx/tsx"] = new_set({
  hooks = {
    pre_case = function()
      set_context({ bo = { tabstop = 2 }, config = { fallback_to_block = "if_line_cms_wrapped" } })
      child.lua_func(function()
        vim.treesitter.language.add("tsx")
        vim.treesitter.language.add("javascript")
        vim.treesitter.language.add("markdown")
      end)
    end,
  },
})

T["jsx/tsx"]["works"] = function()
  local lines = {
    "export default function App() {",
    "  return (",
    '    <div className="app">',
    "      <h1>Hello</h1>",
    "      <Foo bar={1} />",
    "    </div>",
    "  );",
    "}",
  }
  set_lines(lines)
  set_context({ bo = { filetype = "tsx" } })
  child.lua_func(function() vim.treesitter.start() end)

  local function fl(l, exp_lines, cmd)
    set_cursor(l, 0)
    feed(cmd or "gcc")
    eq(get_lines(l, l), exp_lines)
    feed(".")
    eq_lines(lines)
  end

  local function fs(range, exp_lines, cmd)
    selection(unpack(range))
    feed(cmd or "gc")
    eq(get_lines(range[1], range[3]), exp_lines)
    feed(cmd and cmd .. cmd or "gcgc")
    eq_lines(lines)
  end

  fl(0, { "// export default function App() {" })
  fl(1, { "  // return (" })
  fl(2, { '    {/* <div className="app"> */}' })
  fl(3, { "      {/* <h1>Hello</h1> */}" })
  fl(4, { "      {/* <Foo bar={1} /> */}" })
  fl(5, { "    {/* </div> */}" })
  fl(6, { "  // );" })
  fl(7, { "// }" })

  fl(0, { "/* export default function App() { */" }, "gbc")
  fl(1, { "  /* return ( */" }, "gbc")
  fl(2, { '    {/* <div className="app"> */}' }, "gbc")
  fl(3, { "      {/* <h1>Hello</h1> */}" }, "gbc")
  fl(4, { "      {/* <Foo bar={1} /> */}" }, "gbc")
  fl(5, { "    {/* </div> */}" }, "gbc")
  fl(6, { "  /* ); */" }, "gbc")
  fl(7, { "/* } */" }, "gbc")

  fs({ 2, 0, 5, 0 }, {
    '    {/* <div className="app">',
    "      <h1>Hello</h1>",
    "      <Foo bar={1} />",
    "    </div> */}",
  })

  fs({ 3, 0, 4, 0 }, {
    "      {/* <h1>Hello</h1>",
    "      <Foo bar={1} /> */}",
  })

  fs({ 2, 0, 5, 9 }, {
    '{/*     <div className="app">',
    "      <h1>Hello</h1>",
    "      <Foo bar={1} />",
    "    </div> */}",
  }, "gb")

  fs({ 3, 0, 4, 20 }, {
    "{/*       <h1>Hello</h1>",
    "      <Foo bar={1} /> */}",
  }, "gb")
end

T["jsx/tsx"]["works in markdown"] = function()
  local lines = {
    "```tsx",
    "export default function App() {",
    "  return (",
    '    <div className="app">',
    "      <h1>Hello</h1>",
    "      <Foo bar={1} />",
    "    </div>",
    "  );",
    "}",
    "```",
  }
  set_lines(lines)
  set_context({ bo = { filetype = "markdown", tabstop = 2, shiftwidth = 2 } })
  child.lua_func(function() vim.treesitter.start() end)

  validate_steps(nil, {
    { { 0, 0 }, "gcc", { from = 1, "<!-- ```tsx -->" } },
    { ".", { from = 1, "```tsx" } },
    { { 3, 0 }, ".", { from = 4, '    {/* <div className="app"> */}' } },
    { ".", { from = 4, '    <div className="app">' } },
    { { 4, 0 }, ".", { from = 5, "      {/* <h1>Hello</h1> */}" } },
    { ".", { from = 5, "      <h1>Hello</h1>" } },
    {
      { 3, 0, 6, 10 },
      "gc",
      {
        "```tsx",
        "export default function App() {",
        "  return (",
        '    {/* <div className="app">',
        "      <h1>Hello</h1>",
        "      <Foo bar={1} />",
        "    </div> */}",
        "  );",
        "}",
        "```",
      },
    },
    { "gcgc", lines },
    {
      { 2, 0, 7, 3 },
      "gc",
      {
        "```tsx",
        "export default function App() {",
        "  // return (",
        '  //   <div className="app">',
        "  //     <h1>Hello</h1>",
        "  //     <Foo bar={1} />",
        "  //   </div>",
        "  // );",
        "}",
        "```",
      },
    },
    { "gcgc", lines },
    {
      { 2, 0, 7, 3 },
      "gb",
      {
        "```tsx",
        "export default function App() {",
        "/*   return (",
        '    <div className="app">',
        "      <h1>Hello</h1>",
        "      <Foo bar={1} />",
        "    </div>",
        "  ); */",
        "}",
        "```",
      },
    },
    { "gbgb", lines },
  })
end

T["jsx/tsx"]["special case1"] = function()
  local lines = {
    "function Test() {",
    "  return (",
    "    <Component",
    '      propA="propA"',
    '      propB="propB"',
    '      propC="propC"',
    '      propD="propD"',
    '      propE="propE"',
    '      propF="propF"',
    "    >",
    "      children",
    "    </Component>",
    "  )",
    "}",
  }
  set_lines(lines)
  set_context({ bo = { filetype = "tsx", tabstop = 2 } })
  child.lua_func(function() vim.treesitter.start() end)

  validate_steps(nil, {
    { { 3, 0 }, "gcc", { from = 4, '      // propA="propA"' } },
    { ".", { from = 4, '      propA="propA"' } },
    { { 10, 0 }, ".", { from = 11, "      {/* children */}" } },
    { ".", { from = 11, "      children" } },
    {
      { 2, 0, 9, 4 },
      "gc",
      {
        from = 3,
        "    {/* <Component",
        '      propA="propA"',
        '      propB="propB"',
        '      propC="propC"',
        '      propD="propD"',
        '      propE="propE"',
        '      propF="propF"',
        "    > */}",
      },
    },
    {
      "gcgc",
      {
        from = 3,
        "    <Component",
        '      propA="propA"',
        '      propB="propB"',
        '      propC="propC"',
        '      propD="propD"',
        '      propE="propE"',
        '      propF="propF"',
        "    >",
      },
    },
    {
      { 1, 0, 9, 4 },
      "gc",
      {
        from = 2,
        "  // return (",
        "  //   <Component",
        '  //     propA="propA"',
        '  //     propB="propB"',
        '  //     propC="propC"',
        '  //     propD="propD"',
        '  //     propE="propE"',
        '  //     propF="propF"',
        "  //   >",
      },
    },
    {
      "gcgc",
      {
        from = 2,
        "  return (",
        "    <Component",
        '      propA="propA"',
        '      propB="propB"',
        '      propC="propC"',
        '      propD="propD"',
        '      propE="propE"',
        '      propF="propF"',
        "    >",
      },
    },
    {
      { 1, 0, 9, 4 },
      "gb",
      {
        from = 2,
        "/*   return (",
        "    <Component",
        '      propA="propA"',
        '      propB="propB"',
        '      propC="propC"',
        '      propD="propD"',
        '      propE="propE"',
        '      propF="propF"',
        "    > */",
      },
    },
    {
      "gbgb",
      {
        from = 2,
        "  return (",
        "    <Component",
        '      propA="propA"',
        '      propB="propB"',
        '      propC="propC"',
        '      propD="propD"',
        '      propE="propE"',
        '      propF="propF"',
        "    >",
      },
    },
  })
end

-- detect_indent integration ──────────────────────────────────────────────────

T["detect_indent"] = new_set()

T["detect_indent"]["off: shiftwidth grid for space files"] = function()
  -- floor(4 / 8) * 8 = 0
  validate_steps({ "    code", "    code" }, {
    { "gcc", { "#     code", "    code" } },
  }, {
    bo = { tabstop = 8, shiftwidth = 8, expandtab = true, commentstring = "#%s" },
    b = { celeste_comment_config = {} },
  })
end

T["detect_indent"]["off: shiftwidth=4 grid for space files"] = function()
  -- floor(4 / 4) * 4 = 4
  validate_steps({ "    code", "    code" }, {
    { "gcc", { "    # code", "    code" } },
  }, {
    bo = { tabstop = 8, shiftwidth = 4, expandtab = true, commentstring = "#%s" },
    b = { celeste_comment_config = {} },
  })
end

T["detect_indent"]["on: guessed 4-space grid"] = function()
  validate_steps({ "    code", "    code" }, {
    { "gcc", { "    # code", "    code" } },
  }, { bo = { tabstop = 8, expandtab = true, commentstring = "#%s" }, config = { detect_indent = true } })
end

T["detect_indent"]["on: tab file blank-line padding uses tabs"] = function()
  validate_steps({ "\t\taa", "", "\t\tbb" }, {
    { { "gc", "2j" }, { "\t\t# aa", "\t\t# ", "\t\t# bb" } },
    { { "gc", "2j" }, { "\t\taa", "\t\t", "\t\tbb" } },
  }, {
    bo = { tabstop = 4, expandtab = false, commentstring = "#%s" },
    config = { detect_indent = true, ignore_empty_lines = "mixed" },
  })
end

T["detect_indent"]["on: tab file toggle does not accumulate blank-line padding"] = function()
  validate_steps({ "\t\taa", "", "\t\tbb" }, {
    { { "gc", "2j" }, { "\t\t// aa", "\t\t// ", "\t\t// bb" } },
    { { "gc", "2j" }, { "\t\taa", "\t\t", "\t\tbb" } },
    { { "gc", "2j" }, { "\t\t// aa", "\t\t// ", "\t\t// bb" } },
  }, {
    bo = { tabstop = 4, expandtab = false, commentstring = "//%s" },
    config = { detect_indent = true, ignore_empty_lines = "mixed" },
  })
end

T["detect_indent"]["on: tab file non-empty line comment placement"] = function()
  validate_steps({ "\t\tfoo", "\t\tbar" }, {
    { "gcc", { "\t\t// foo", "\t\tbar" } },
    { "gcc", { "\t\tfoo", "\t\tbar" } },
  }, { bo = { tabstop = 4, expandtab = false, commentstring = "//%s" }, config = { detect_indent = true } })
end

T["detect_indent"]["on: user hook overrides detection"] = function()
  validate_steps({ "    foo", "    bar" }, {
    { "gcc", { "    // foo", "    bar" } },
  }, {
    bo = { tabstop = 8, expandtab = true, commentstring = "//%s" },
    config = function()
      return {
        detect_indent = true,
        hooks = {
          indent_resolver = function(ctx) ctx.o_indent = { indent_size = 2, indent_style = "space" } end,
        },
      }
    end,
  })
end

T["detect_indent"]["on: blank line whitespace at and above aligned offset"] = function()
  -- blank lines: 3tabs(exceeds), 2tabs(equals), 1tab+4spaces(equals), 2tabs+4spaces(exceeds)
  validate_steps({ "\t\tfoo", "\t\t\t", "\t\t", "\t    ", "\t\t    ", "\t\tbar" }, {
    {
      { "gc", "5j" },
      { "\t\t// foo", "\t\t// \t", "\t\t// ", "\t    // ", "\t\t//     ", "\t\t// bar" },
    },
    { { "gc", "5j" }, { "\t\tfoo", "\t\t\t", "\t\t", "\t    ", "\t\t    ", "\t\tbar" } },
  }, {
    bo = { tabstop = 4, expandtab = false, commentstring = "//%s" },
    config = { detect_indent = true, ignore_empty_lines = "mixed" },
  })
end

-- Forced-motion tests ─────────────────────────────────────────────────────────

T["forced_motion"] = new_set()

T["forced_motion"]["gb V forces linewise on charwise motions"] = function()
  validate_steps({ "hello world foo" }, {
    { { "gb", "V", "iw" }, { "/* hello world foo */" } },
    { "u" },
    { { "gb", "V", "2w" }, { "/* hello world foo */" } },
    { "u" },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
  validate_steps({ "a", "b", "c", "d" }, {
    { { "gb", "V", "2j" }, { "/* a", "b", "c */", "d" } },
    { "u" },
    { { "gb", "V", "ip" }, { "/* a", "b", "c", "d */" } },
    { "u" },
  })
end

T["forced_motion"]["gb v forces charwise on linewise motions"] = function()
  validate_steps({ "a", "", "b" }, {
    { { "gb", "v", "ip" }, { "/* a */", "", "b" } },
    { "u" },
  }, { bo = { filetype = "cpp", commentstring = "// %s" } })
end

T["forced_motion"]["gc V forces linewise on charwise motions"] = function()
  validate_steps({ "hello world foo" }, {
    { { "gc", "V", "iw" }, { "# hello world foo" } },
    { "u" },
  })
  validate_steps({ "a", "b", "c", "d" }, {
    { { "gc", "V", "j" }, { "# a", "# b", "c", "d" } },
    { "u" },
    { { "gc", "V", "2j" }, { "# a", "# b", "# c", "d" } },
    { "u" },
    { { "gc", "V", "ip" }, { "# a", "# b", "# c", "# d" } },
    { "u" },
  })
end

T["forced_motion"]["gc v forces charwise on linewise motions"] = function()
  validate_steps({ "a", "b", "c", "d" }, {
    { { "gc", "v", "ip" }, { "# a", "# b", "# c", "d" } },
    { "u" },
  })
end

T["forced_motion"]["gC V forces linewise"] = function()
  validate_steps({ "hello", "// world", "foo" }, {
    { { "gC", "V", "j" }, { "// hello", "// // world", "foo" } },
    { "u" },
    { { "gC", "V", "2j" }, { "// hello", "// // world", "// foo" } },
    { "u" },
  }, { bo = { commentstring = "// %s" } })
end

T["forced_motion"]["gU V forces linewise"] = function()
  validate_steps({ "// hello", "// world", "foo" }, {
    { { "gU", "V", "j" }, { "hello", "world", "foo" } },
    { "u" },
  }, { bo = { commentstring = "// %s" } })
  validate_steps({ "// hello", "// world", "// foo" }, {
    { { "gU", "V", "2j" }, { "hello", "world", "foo" } },
    { "u" },
  })
end

-- paste comment tests ─────────────────────────────────────────────────────────

T["paste"] = new_set({
  hooks = {
    pre_case = function()
      set_context({
        bo = { tabstop = 2, shiftwidth = 0, expandtab = true, commentstring = "// %s" },
        b = { celeste_comment_block_commentstring = "/*%s*/" },
      })
    end,
  },
})

T["paste"]["line below and above"] = function()
  validate_steps({ "  aaa", "bbb" }, {
    { { 0, 2 }, '"agcp', { "  aaa", "  // function f()", "  //   return 1", "  // end", "bbb" }, { 3, 2 } },
  }, { reg = { a = { lines = { "function f()", "  return 1", "end" }, type = "V" } } })

  validate_steps({ "  aaa", "bbb" }, {
    { { 1, 2 }, '"agcP', { "  aaa", "// function f()", "//   return 1", "// end", "bbb" }, { 3, 0 } },
  }, { reg = { a = { lines = { "function f()", "  return 1", "end" }, type = "V" } } })

  -- block paste honors the register type: charwise `v` stays inline
  validate_steps({ "abcdef" }, {
    { { 0, 2 }, '"agbp', { "abc/* XY */def" }, { 0, 4 } },
  }, { reg = { a = { lines = { "XY" }, type = "v" } } })
  eq_marks({ "[", "]" }, { { 1, 3 }, { 1, 10 } })

  validate_steps({ "abcdef" }, {
    { { 0, 2 }, '"agbP', { "ab/* XY */cdef" }, { 0, 3 } },
  }, { reg = { a = { lines = { "XY" }, type = "v" } } })
  eq_marks({ "[", "]" }, { { 1, 2 }, { 1, 9 } })

  -- linewise register: block comment spans whole lines
  validate_steps({ "  aaa", "bbb" }, {
    { { 0, 2 }, '"agbp', { "  aaa", "  /* L1", "  L2 */", "bbb" }, { 2, 2 } },
  }, { reg = { a = { lines = { "L1", "L2" }, type = "V" } } })
  eq_marks({ "[", "]" }, { { 2, 0 }, { 3, 6 } })

  -- blockwise register is treated as linewise
  validate_steps({ "  aaa", "bbb" }, {
    { { 0, 2 }, '"agbp', { "  aaa", "  /* ab", "  cd */", "bbb" } },
  }, { reg = { a = { lines = { "ab", "cd" }, type = "\22" .. "2" } } })
  eq_marks({ "[", "]" }, { { 2, 0 }, { 3, 6 } })

  -- multi-line charwise register is pasted inline
  validate_steps({ "abcdef" }, {
    { { 0, 2 }, '"agbp', { "abc/* a", "b */def" }, { 0, 3 } },
  }, { reg = { a = { lines = { "a", "b" }, type = "v" } } })
  eq_marks({ "[", "]" }, { { 1, 3 }, { 2, 3 } })
end

T["paste"]["default_reg"] = function()
  child.lua_func(function()
    local cmt = require("celeste_comment")
    vim.keymap.set(
      "n",
      "gcq",
      cmt.H.make_operator(cmt.CMT.kLine, { motion = "0", action = cmt.ACTION.kForceAdd, paste = { default_reg = "a" } }),
      { expr = true }
    )
  end)
  child.fn.setreg("a", { "X" }, "V")
  validate_steps({ "  aaa", "bbb" }, { { { 0, 2 }, "gcq", { "  aaa", "  // X", "bbb" } } })
end

T["paste"]["count"] = function()
  child.fn.setreg("a", { "X" }, "V")
  validate_steps({ "  aaa", "bbb" }, { { { 0, 2 }, '2"agcp', { "  aaa", "  // X", "  // X", "bbb" }, { 2, 2 } } })

  child.fn.setreg("a", { "X" }, "V")
  validate_steps({ "a", "b" }, { { { 1, 0 }, '3"agcp', { "a", "b", "// X", "// X", "// X" }, { 4, 0 } } })

  -- charwise block paste uses the native count of `p`
  child.fn.setreg("a", { "X" }, "v")
  validate_steps({ "abcdef" }, { { { 0, 2 }, '3"agbp', { "abc/* XXX */def" } } })

  -- count repeats a multi-line charwise register the same way as `p`
  child.fn.setreg("a", { "a", "b" }, "v")
  validate_steps({ "abcdef" }, { { { 0, 2 }, '2"agbp', { "abc/* a", "ba", "b */def" } } })
end

T["paste"]["dot repeat"] = function()
  validate_steps({ "z" }, {
    { { 0, 0 }, '"agcp', { "z", "// X" } },
    { { 1, 0 }, ".", { "z", "// X", "// X" } },
  }, { reg = { a = { lines = { "X" }, type = "V" } } })

  child.fn.setreg("a", { "X" }, "V")
  set_lines({ "z" })
  set_cursor(0, 0)
  feed('3"agcp')
  eq_lines({ "z", "// X", "// X", "// X" })
  feed(".")
  eq(#get_lines(), 7)
  feed("5.")
  eq(#get_lines(), 12)

  -- charwise block paste repeats the whole paste + comment
  child.fn.setreg("a", { "X" }, "v")
  set_lines({ "abcdef", "ghijkl" })
  set_cursor(0, 2)
  feed('"agbp')
  eq_lines({ "abc/* X */def", "ghijkl" })
  set_cursor(1, 2)
  feed(".")
  if vim.fn.has("nvim-0.13") == 1 then
    eq_lines({ "abc/* X */def", "ghi/* X */jkl" })
  else
    -- nvim-0.12 repeats only the inner put, see neovim/neovim#41594
    eq_lines({ "abc/* X */def", "ghiXjkl" })
  end
end

T["paste"]["empty register is no-op"] = function()
  child.fn.setreg("a", {}, "V")
  validate_steps({ "  aaa", "bbb" }, { { { 0, 2 }, '"agcp', { "  aaa", "bbb" } } })

  child.fn.setreg("a", {}, "V")
  validate_steps({ "  aaa", "bbb" }, { { { 0, 2 }, '"agbp', { "  aaa", "bbb" } } })

  -- charwise register with no text pastes nothing
  child.fn.setreg("a", { "" }, "v")
  validate_steps({ "abcdef" }, { { { 0, 2 }, '"agbp', { "abcdef" } } })
end

T["paste"]["change marks"] = function()
  validate_steps({ "  aaa", "bbb" }, {
    { { 0, 2 }, '"b2gcp', { "  aaa", "  // 1111", "  // 22222", "  // 1111", "  // 22222", "bbb" } },
  }, { reg = { b = { lines = { "1111", "22222" }, type = "V" } } })
  eq_marks({ "[", "]" }, { { 2, 0 }, { 5, 9 } })

  validate_steps({ "abcdef" }, {
    { { 0, 2 }, '"bgbp', { "abc/* XY */def" } },
  }, { reg = { b = { lines = { "XY" }, type = "v" } } })
  eq_marks({ "[", "]" }, { { 1, 3 }, { 1, 10 } })
end

T["paste"]["change marks with selection=exclusive"] = function()
  validate_steps({ "  aaa", "bbb" }, {
    { { 0, 2 }, '"b2gcp', { "  aaa", "  // 1111", "  // 22222", "  // 1111", "  // 22222", "bbb" } },
  }, {
    o = { selection = "exclusive" },
    reg = { b = { lines = { "1111", "22222" }, type = "V" } },
  })
  -- Same as native `:iput`: `]` stays on the last inserted character.
  eq_marks({ "[", "]" }, { { 2, 0 }, { 5, 9 } })
end

T["paste"]["change marks with multibyte last line"] = function()
  validate_steps({ "aaa", "bbb" }, {
    { { 0, 0 }, '"agcp', { "aaa", "// 你", "bbb" } },
  }, { reg = { a = { lines = { "你" }, type = "V" } } })
  eq_marks({ "[", "]" }, { { 2, 0 }, { 2, 3 } })

  validate_steps({ "abcdef" }, {
    { { 0, 2 }, '"agbp', { "abc/* 你 */def" } },
  }, { reg = { a = { lines = { "你" }, type = "v" } } })
  eq_marks({ "[", "]" }, { { 1, 3 }, { 1, 11 } })
end

T["paste"]["blank lines keep empty"] = function()
  child.fn.setreg("a", { "  s1", "", "  s2" }, "V")
  validate_steps({ "  aaa", "bbb" }, { { { 1, 0 }, '"agcP', { "  aaa", "// s1", "// ", "// s2", "bbb" } } })
end

T["paste"]["relative indentation"] = function()
  child.fn.setreg("a", { "    a", "      b", "   c" }, "V")
  validate_steps({ "  anchor", "bbb" }, { { { 0, 2 }, '"agcp', { "  anchor", "//   a", "//     b", "//  c", "bbb" } } })
end

T["paste"]["tab indentation"] = function()
  set_context({ bo = { tabstop = 4, shiftwidth = 0, expandtab = false } })
  child.fn.setreg("a", { "\ts1", "\t\ts2" }, "V")
  validate_steps({ "\taaa", "bbb" }, { { { 0, 1 }, '"agcp', { "\taaa", "\t// s1", "\t// \ts2", "bbb" } } })
end

T["paste"]["indent = false"] = function()
  child.lua_func(function()
    local cmt = require("celeste_comment")
    vim.keymap.set(
      "n",
      "gcq",
      cmt.H.make_operator(cmt.CMT.kLine, { motion = "0", action = cmt.ACTION.kForceAdd, paste = { indent = false } }),
      { expr = true }
    )
    vim.keymap.set(
      "n",
      "gbq",
      cmt.H.make_operator(cmt.CMT.kBlock, { motion = "0", action = cmt.ACTION.kForceAdd, paste = { indent = false } }),
      { expr = true }
    )
  end)
  child.fn.setreg("a", { "  X" }, "V")
  validate_steps({ "    aaa", "bbb" }, { { { 0, 4 }, '"agcq', { "    aaa", "  // X", "bbb" } } })

  -- linewise block paste also honors `indent = false`
  child.fn.setreg("a", { "  X" }, "V")
  validate_steps({ "    aaa", "bbb" }, { { { 0, 4 }, '"agbq', { "    aaa", "  /* X */", "bbb" } } })
end

T["paste"]["keep_cursor = false"] = function()
  set_context({ config = { keep_cursor = false } })
  child.fn.setreg("a", { "X" }, "V")
  validate_steps({ "  aaa", "bbb" }, { { { 0, 2 }, '"agcp', { "  aaa", "  // X", "bbb" }, { 1, 2 } } })
end

T["paste"]["undo"] = function()
  child.fn.setreg("a", { "X", "Y" }, "V")
  validate_steps({ "a", "b" }, {
    { '"agcp', { "a", "// X", "// Y", "b" } },
    { "u", { "a", "b" } },
  })
end

-- multiple cursor tests ──────────────────────────────────────────────────────

if vim.fn.has("nvim-0.13") == 1 then
  T["multicursor"] = new_set({
    hooks = {
      pre_case = function()
        set_context({ bo = { filetype = "markdown", tabstop = 2, shiftwidth = 0, expandtab = true } })
        child.lua_func(function()
          vim.treesitter.language.add("markdown")
          vim.treesitter.language.add("lua")
          vim.treesitter.language.add("c")
          vim.treesitter.start()
        end)
      end,
    },
  })

  T["multicursor"]["works"] = function()
    local lines = {
      "```lua",
      "  print('a')",
      "  print('bb')",
      "  print('ccc')",
      "```",
      "",
      "### heading",
      "```c",
      '  printf("a");',
      '  printf("bb");',
      '  printf("ccc");',
      "```",
    }
    set_lines(lines)
    child.lua_func(function() vim.treesitter.start() end)

    -- gcc / gbc
    validate_steps(nil, {
      { { { 1, 0 }, { 6, 0 }, { 8, 0 } }, { "q=", "w" }, nil, { { 1, 2 }, { 6, 4 }, { 8, 2 } } },
      {
        "gcc",
        {
          { from = 2, "  -- print('a')" },
          { from = 7, "<!-- ### heading -->" },
          { from = 9, '  // printf("a");' },
        },
        { { 1, 5 }, { 6, 9 }, { 8, 5 } },
      },
      {
        ".",
        {
          { from = 2, "  print('a')" },
          { from = 7, "### heading" },
          { from = 9, '  printf("a");' },
        },
        { { 1, 2 }, { 6, 4 }, { 8, 2 } },
      },
      {
        "gbc",
        {
          { from = 2, "  --[[ print('a') ]]" },
          { from = 7, "<!-- ### heading -->" },
          { from = 9, '  /* printf("a"); */' },
        },
        { { 1, 7 }, { 6, 9 }, { 8, 5 } },
      },
      {
        ".",
        {
          { from = 2, "  print('a')" },
          { from = 7, "### heading" },
          { from = 9, '  printf("a");' },
        },
        { { 1, 2 }, { 6, 4 }, { 8, 2 } },
      },
    }, {
      config = { keep_selection = "never", fallback_to_block = "if_line_cms_wrapped" },
    })

    -- visual gc
    validate_steps(lines, {
      { { { 1, 0 }, { 5, 0 }, { 8, 0 } }, { "q=", "v", "j", "4l" }, nil, { { 2, 4 }, { 6, 4 }, { 9, 4 } } },
      {
        "gc",
        {
          "```lua",
          "  -- print('a')",
          "  -- print('bb')",
          "  print('ccc')",
          "```",
          "<!-- ",
          "### heading -->",
          "```c",
          '  // printf("a");',
          '  // printf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 7 }, { 6, 4 }, { 9, 7 } },
      },
    })

    -- visual gb
    validate_steps(lines, {
      { { { 1, 0 }, { 5, 0 }, { 8, 0 } }, { "q=", "v", "j", "3l" }, nil, { { 2, 3 }, { 6, 3 }, { 9, 3 } } },
      {
        "gb",
        {
          "```lua",
          "--[[   print('a')",
          "  pr ]]int('bb')",
          "  print('ccc')",
          "```",
          "<!-- ",
          "###  -->heading",
          "```c",
          '/*   printf("a");',
          '  pr */intf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 3 }, { 6, 3 }, { 9, 3 } },
      },
    })

    -- gco
    validate_steps(lines, {
      {
        { { 1, 0 }, { 5, 0 }, { 8, 0 } },
        { "q=", "gco" },
        {
          "```lua",
          "  print('a')",
          "  -- ",
          "  print('bb')",
          "  print('ccc')",
          "```",
          "",
          "<!--  -->",
          "### heading",
          "```c",
          '  printf("a");',
          "  // ",
          '  printf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 5 }, { 7, 5 }, { 11, 5 } },
      },
    })
    eq(child.api.nvim_get_mode().mode, "i")
    feed("<esc>")

    -- gcO
    validate_steps(lines, {
      {
        { { 2, 0 }, { 6, 0 }, { 9, 0 } },
        { "q=", "gcO" },
        {
          "```lua",
          "  print('a')",
          "  -- ",
          "  print('bb')",
          "  print('ccc')",
          "```",
          "",
          "<!--  -->",
          "### heading",
          "```c",
          '  printf("a");',
          "  // ",
          '  printf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 5 }, { 7, 5 }, { 11, 5 } },
      },
    })
    eq(child.api.nvim_get_mode().mode, "i")
    feed("<esc>")

    -- gcA
    validate_steps(lines, {
      {
        { { 2, 0 }, { 6, 0 }, { 9, 0 } },
        { "q=", "gcA" },
        {
          "```lua",
          "  print('a')",
          "  print('bb') -- ",
          "  print('ccc')",
          "```",
          "",
          "### heading <!--  -->",
          "```c",
          '  printf("a");',
          '  printf("bb"); // ',
          '  printf("ccc");',
          "```",
        },
        { { 2, 17 }, { 6, 17 }, { 9, 19 } },
      },
    })
    eq(child.api.nvim_get_mode().mode, "i")
    feed("i")
    feed("<esc>")

    -- gcu
    validate_steps(lines, {
      { { 1, 0 }, "gbj" },
      { { 5, 0 }, "." },
      {
        { 8, 0 },
        "gcj",
        {
          "```lua",
          "  --[[ print('a')",
          "  print('bb') ]]",
          "  print('ccc')",
          "```",
          "<!-- ",
          "### heading -->",
          "```c",
          '  // printf("a");',
          '  // printf("bb");',
          '  printf("ccc");',
          "```",
        },
      },
      {
        { { 2, 4 }, { 6, 5 }, { 9, 7 } },
        "q=",
        nil,
        { { 2, 4 }, { 6, 5 }, { 9, 7 } },
      },
      {
        "gcu",
        {
          "```lua",
          "  print('a')",
          "  print('bb')",
          "  print('ccc')",
          "```",
          "",
          "### heading",
          "```c",
          '  printf("a");',
          '  printf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 4 }, { 6, 5 }, { 9, 4 } },
      },
    })

    -- line textobject (outer, inner)
    validate_steps(lines, {
      {
        { { 1, 0 }, { 5, 0 }, { 8, 0 } },
        { "q=", "gcj" },
        {
          "```lua",
          "  -- print('a')",
          "  -- print('bb')",
          "  print('ccc')",
          "```",
          "<!-- ",
          "### heading -->",
          "```c",
          '  // printf("a");',
          '  // printf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 1, 0 }, { 5, 4 }, { 8, 0 } },
      },
      { { "v", "agc" }, nil, nil, { { 1, 0, 2, 15 }, { 5, 0, 6, 14 }, { 8, 0, 9, 0 } } },
      { "<esc>" },
      { { "v", "ic" }, nil, nil, { { 2, 5, 2, 15 }, { 5, 5, 6, 10 }, { 9, 5, 9, 17 } } },
      { "<esc>" },
    })

    -- block textobject (outer, inner)
    validate_steps(lines, {
      {
        { { 1, 4 }, { 5, 0 }, { 8, 5 } },
        { "q=", "v", "j", "6l" },
        nil,
        { { 2, 10 }, { 6, 6 }, { 9, 11 } },
      },
      {
        "gb",
        {
          "```lua",
          "  pr--[[ int('a')",
          "  print('bb ]]')",
          "  print('ccc')",
          "```",
          "<!-- ",
          "### hea -->ding",
          "```c",
          '  pri/* ntf("a");',
          '  printf("bb */");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 10 }, { 6, 6 }, { 9, 11 } },
      },
      { { "v", "agb" }, nil, nil, { { 1, 4, 2, 13 }, { 5, 0, 6, 10 }, { 8, 5, 9, 14 } } },
      { "<esc>" },
      { { "v", "ic" }, nil, nil, { { 1, 9, 2, 10 }, { 5, 5, 6, 6 }, { 8, 8, 9, 11 } } },
      { "<esc>" },
    })

    -- auto textobject on end-of-line comments (lua + c in one session)
    validate_steps({
      "```lua",
      "local a = 1 -- aaa",
      "local bb = 2 -- bbb",
      "local ccc = 3 -- ccc",
      "```",
      "```c",
      "int x = 1; /* a // b */ // tail",
      "int x = 1; /* a // b */ // tail",
      "```",
    }, {
      {
        { { 1, 16 }, { 2, 17 }, { 3, 18 }, { 6, 28 }, { 7, 28 } },
        { "q=", "v", "ga" },
        nil,
        nil,
        {
          { 1, 12, 1, 17 },
          { 2, 13, 2, 18 },
          { 3, 14, 3, 19 },
          { 6, 24, 6, 30 },
          { 7, 24, 7, 30 },
        },
      },
      { "<esc>" },
      {
        { "v", "gia" },
        nil,
        nil,
        {
          { 1, 15, 1, 17 },
          { 2, 16, 2, 18 },
          { 3, 17, 3, 19 },
          { 6, 27, 6, 30 },
          { 7, 27, 7, 30 },
        },
      },
      { "<esc>" },
      {
        { "d", "ga" },
        {
          "```lua",
          "local a = 1 ",
          "local bb = 2 ",
          "local ccc = 3 ",
          "```",
          "```c",
          "int x = 1; /* a // b */ ",
          "int x = 1; /* a // b */ ",
          "```",
        },
      },
    })

    -- skip block comments on the same line, per cursor
    validate_steps({
      "```lua",
      "local x = 1 --[[ a ]] -- tail",
      "local x = 1 --[[ a ]] -- tail",
      "local x = 1 --[[ a ]] -- tail",
      "```",
    }, {
      {
        { { 1, 26 }, { 2, 26 }, { 3, 26 } },
        { "q=", "v", "ga" },
        nil,
        nil,
        { { 1, 22, 1, 28 }, { 2, 22, 2, 28 }, { 3, 22, 3, 28 } },
      },
      { "<esc>" },
      {
        { "v", "gia" },
        nil,
        nil,
        { { 1, 25, 1, 28 }, { 2, 25, 2, 28 }, { 3, 25, 3, 28 } },
      },
      { "<esc>" },
    })

    -- empty content: outer selects the marker, inner / gcu do nothing
    validate_steps({ "```lua", "x --", "xx --", "xxx --", "```" }, {
      {
        { { 1, 3 }, { 2, 4 }, { 3, 5 } },
        { "q=", "v", "ga" },
        nil,
        nil,
        { { 1, 2, 1, 3 }, { 2, 3, 2, 4 }, { 3, 4, 3, 5 } },
      },
      { "<esc>" },
      { { "d", "gia", "<esc>" }, { "```lua", "x --", "xx --", "xxx --", "```" } },
      { "gcu", { "```lua", "x --", "xx --", "xxx --", "```" } },
    })

    -- insert mode comment toggle
    validate_steps(lines, {
      {
        { { 2, 12 }, { 3, 3 }, { 6, 10 }, { 9, 13 }, { 10, 3 } },
        "a",
        nil,
        { { 2, 13 }, { 3, 4 }, { 6, 11 }, { 9, 14 }, { 10, 4 } },
      },
      {
        "<c-/>",
        {
          "```lua",
          "  print('a')",
          "  -- print('bb')",
          "  -- print('ccc')",
          "```",
          "",
          "<!-- ### heading -->",
          "```c",
          '  printf("a");',
          '  // printf("bb");',
          '  // printf("ccc");',
          "```",
        },
        { { 2, 16 }, { 3, 7 }, { 6, 16 }, { 9, 17 }, { 10, 7 } },
      },
      {
        "<c-/>",
        {
          "```lua",
          "  print('a')",
          "  print('bb')",
          "  print('ccc')",
          "```",
          "",
          "### heading",
          "```c",
          '  printf("a");',
          '  printf("bb");',
          '  printf("ccc");',
          "```",
        },
        { { 2, 13 }, { 3, 4 }, { 6, 11 }, { 9, 14 }, { 10, 4 } },
      },
      {
        { "<c-/>", "@" },
        {
          "```lua",
          "  print('a')",
          "  -- print('bb')@",
          "  -- pr@int('ccc')",
          "```",
          "",
          "<!-- ### heading@ -->",
          "```c",
          '  printf("a");',
          '  // printf("bb")@;',
          '  // pr@intf("ccc");',
          "```",
        },
        { { 2, 17 }, { 3, 8 }, { 6, 17 }, { 9, 18 }, { 10, 8 } },
      },
      {
        "<esc>",
        {
          "```lua",
          "  print('a')",
          "  -- print('bb')@",
          "  -- pr@int('ccc')",
          "```",
          "",
          "<!-- ### heading@ -->",
          "```c",
          '  printf("a");',
          '  // printf("bb")@;',
          '  // pr@intf("ccc");',
          "```",
        },
      },
    })
    eq(child.api.nvim_get_mode().mode, "n")

    -- paste and comment
    validate_steps({ "aaaaa", "b", "c", "d", "e", "f", "g" }, {
      {
        { { 0, 3 }, { 3, 2 }, { 6, 4 } },
        '"agcp',
        { "aaaaa", "<!-- X", "Y -->", "b", "c", "d", "<!-- X", "Y -->", "e", "f", "g", "<!-- X", "Y -->" },
        { { 2, 0 }, { 7, 0 }, { 12, 0 } },
      },
      {
        ".",
        {
          "aaaaa",
          "<!-- X",
          "Y -->",
          "<!-- X",
          "Y -->",
          "b",
          "c",
          "d",
          "<!-- X",
          "Y -->",
          "<!-- X",
          "Y -->",
          "e",
          "f",
          "g",
          "<!-- X",
          "Y -->",
          "<!-- X",
          "Y -->",
        },
      },
    }, { reg = { a = { lines = { "X", "Y" }, type = "V" } } })

    -- paste uses cursor-local register
    validate_steps({ "foo", "bar", "baz" }, {
      { { { 0, 0 }, { 1, 0 }, { 2, 0 } }, { "yiw", "gcp" }, { "foo", "// foo", "bar", "// bar", "baz", "// baz" } },
    }, { bo = { filetype = "c" } })

    -- charwise block paste uses each cursor's own anchor column
    validate_steps({ "foo", "bar", "baz" }, {
      { { { 0, 0 }, { 1, 0 }, { 2, 0 } }, { "yiw", "gbp" }, { "f/* foo */oo", "b/* bar */ar", "b/* baz */az" } },
    }, { bo = { filetype = "c" } })
  end

  T["multicursor"]["keep_selection works"] = function()
    set_context({ bo = { filetype = "lua" }, config = { keep_selection = "adjust" } })
    local lines = { "aaaaa", "bbbbb", "", "ccccc", "ddddd" }
    validate_steps(lines, {
      { { { 0, 1 }, { 3, 2 } }, { "q=", "v", "j", "l" }, nil, nil, { { 0, 1, 1, 2 }, { 3, 2, 4, 3 } } },
      { "gb", { "a--[[ aaaa", "bbb ]]bb", "", "cc--[[ ccc", "dddd ]]d" } },
      { "gv", nil, nil, { { 0, 6, 1, 2 }, { 3, 7, 4, 3 } } },
      { "<esc>" },
      { { "vac", "gb" }, { "aaaaa", "bbbbb", "", "ccccc", "ddddd" }, { { 1, 2 }, { 4, 3 } } },
      { "gv", nil, nil, { { 0, 1, 1, 2 }, { 3, 2, 4, 3 } } },
      { "gc", { "-- aaaaa", "-- bbbbb", "", "-- ccccc", "-- ddddd" }, { { 1, 5 }, { 4, 6 } } },
      { "gv", nil, nil, { { 0, 4, 1, 5 }, { 3, 5, 4, 6 } } },
      { "gc", lines, { { 1, 2 }, { 4, 3 } } },
      { "gv", nil, nil, { { 0, 1, 1, 2 }, { 3, 2, 4, 3 } } },
    })

    validate_steps(nil, {
      { "gb", { "a--[[ aaaa", "bbb ]]bb", "", "cc--[[ ccc", "dddd ]]d" } },
      { "gv", nil, nil, { { 0, 1, 1, 5 }, { 3, 2, 4, 6 } } },
      { "gb", lines, { { 1, 2 }, { 4, 3 } } },
      { "gv", nil, nil, { { 0, 1, 1, 2 }, { 3, 2, 4, 3 } } },
      { "gc", { "-- aaaaa", "-- bbbbb", "", "-- ccccc", "-- ddddd" }, { { 1, 5 }, { 4, 6 } } },
      { "gv", nil, nil, { { 0, 0, 1, 7 }, { 3, 5, 4, 6 } } },
      { "gc", lines, { { 1, 2 }, { 4, 3 } } },
      { "gv", nil, nil, { { 0, 0, 1, 4 }, { 3, 2, 4, 3 } } },
      { "d", { "" } },
    }, { config = { keep_selection = "adjust | expand_line | expand_block" } })

    validate_steps(lines, {
      { { { 0, 2 }, { 3, 3 } }, { "q=", "viw" }, nil, { { 0, 4 }, { 3, 4 } }, { { 0, 0, 0, 4 }, { 3, 0, 3, 4 } } },
      {
        "gb",
        { "--[[ aaaaa ]]", "bbbbb", "", "--[[ ccccc ]]", "ddddd" },
        { { 0, 12 }, { 3, 12 } },
        { { 0, 0, 0, 12 }, { 3, 0, 3, 12 } },
      },
      {
        "gb",
        lines,
        { { 0, 4 }, { 3, 4 } },
        { { 0, 0, 0, 4 }, { 3, 0, 3, 4 } },
      },
      {
        "gc",
        { "-- aaaaa", "bbbbb", "", "-- ccccc", "ddddd" },
        { { 0, 7 }, { 3, 7 } },
        { { 0, 3, 0, 7 }, { 3, 3, 3, 7 } },
      },
      {
        "gc",
        lines,
        { { 0, 4 }, { 3, 4 } },
        { { 0, 0, 0, 4 }, { 3, 0, 3, 4 } },
      },
    }, { config = { keep_selection = "adjust | expand_block | keep_visual" } })
  end
end

return T
