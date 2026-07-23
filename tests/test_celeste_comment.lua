---@diagnostic disable: inject-field, param-type-mismatch, need-check-nil, cast-local-type
local MiniTest = require("mini.test")
local expect = MiniTest.expect
local eq = expect.equality
local neq = expect.no_equality
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

local set_lines = function(lines, from, to)
  from, to = from or 0, to or -1
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local get_lines = function(from, to)
  from = (from or 1) - 1
  to = to or -1
  return child.api.nvim_buf_get_lines(0, from, to, false)
end

local set_cursor = function(line, col) child.api.nvim_win_set_cursor(0, { line, col or 0 }) end

local get_cursor = function() return child.api.nvim_win_get_cursor(0) end

local feed = function(...) child.type_keys(...) end

local set_config = function(opts)
  child.b.celeste_comment_config = vim.tbl_deep_extend("force", child.b.celeste_comment_config or {}, opts or {})
end

local selection = function(frow, fcol, trow, tcol)
  set_cursor(frow, fcol)
  feed("v")
  set_cursor(trow, tcol)
end

local make_pos = function(buf, row, col) return vim.pos(row, col, { buf = buf }) end
if vim.fn.has("nvim-0.12.2") == 1 then make_pos = function(buf, row, col) return vim.pos(buf, row, col) end end

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.bo.tabstop = 4
      child.bo.commentstring = "# %s"
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

              line_textobject = "gc",
              block_textobject = "gb",
              auto_textobject = "ga",
              uncomment_auto = "gcu",

              line_add_below = "gco",
              line_add_above = "gcO",
              line_add_eol = "gcA",
              line_invert = "gcI",
              line_force_add = "gC",
              line_force_remove = "gU",
              dot_repeat = ".",
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

local apply = function(line, edits)
  local lines = { line }
  H.apply_edits(lines, edits or {})
  return lines[1]
end

local make_line_info = function(opts)
  opts = opts or {}
  return {
    offset = opts.offset or 0,
    csi = opts.csi,
    ignore = opts.ignore or false,
    lcs_pos = opts.lcs_pos,
    rcs_pos = opts.rcs_pos,
    row = opts.row or 0,
  }
end

-- Base tests ──────────────────────────────────────────────────────────────────

T["base"] = new_set()

T["base"]["comment_string_unwrap"] = function()
  local u = H.comment_string_unwrap
  eq(u("//%s"), { { "//", "" } })
  eq(u("/*%s*/"), { { "/*", "*/" } })
  eq(u("// %s"), { { "// ", "" } })
  eq(u("<!-- %s -->"), { { "<!-- ", " -->" } })
  eq(u("# %s"), { { "# ", "" } })
  eq(u("hello"), { { "", "" } })
  eq(u("{-%s-}"), { { "{-", "-}" } })
  eq(u("=begin%s=end"), { { "=begin", "=end" } })
  eq(u({ "//%s", "///%s", "//!%s" }), { { "//", "" }, { "///", "" }, { "//!", "" } })
end

T["base"]["next_visible_column"] = function()
  local n = H.next_visible_column
  eq(n(0, string.byte(" "), 4), 1)
  eq(n(1, string.byte(" "), 4), 2)
  eq(n(0, string.byte("\t"), 4), 4)
  eq(n(3, string.byte("\t"), 4), 4)
  eq(n(4, string.byte("\t"), 4), 8)
end

T["base"]["find_insert_offset"] = function()
  local f = H.find_insert_offset
  eq(f("  code", 2, 0, 4), 0)
  eq(f("  code", 2, 1, 4), 1)
  eq(f("  code", 2, 2, 4), 2)
  eq(f("\tcode", 1, 0, 4), 0)
  eq(f("\tcode", 1, 1, 4), 0)
  eq(f("\tcode", 1, 4, 4), 1)
  eq(f("    code", 4, 2, 4), 2)
  eq(f(" \t code", 3, 3, 4), 1)
end

T["base"]["pattern_ci"] = function()
  local f = H.pattern_ci
  eq(f("rem"), "[rR][eE][mM]")
  eq(f("REM"), "[rR][eE][mM]")
  eq(f("/%*"), "/%*")
  eq(f(""), "")
  eq(("REM hello"):find("^%s*" .. f(vim.pesc("rem"))), 1)
  eq(("rem hello"):find("^%s*" .. f(vim.pesc("rem"))), 1)
  eq(("  ReM hello"):find("^%s*" .. f(vim.pesc("rem"))), 1)
  eq(("nope"):find("^%s*" .. f(vim.pesc("rem"))), nil)
  local i, c = ("  REM hello"):match("^(%s*)" .. f(vim.pesc("rem")) .. "(.*)")
  eq(i, "  ")
  eq(c, " hello")
end

T["base"]["skip_whitespace"] = function()
  local f = H.skip_whitespace
  -- forward
  eq(f("  abc", 3, 5, 1), 3)
  eq(f("  abc", 1, 2, 1), 3)
  eq(f("  abc", 1, 1, 1), 2)
  eq(f("\t\tabc", 1, 2, 1), 3)
  eq(f("abc", 1, 5, 1), 1)
  eq(f("", 1, 5, 1), 1)
  -- backward
  eq(f("abc  ", 5, 3, -1), 3)
  eq(f("abc  ", 5, 2, -1), 3)
  eq(f("abc\t\t", 5, 2, -1), 3)
  eq(f("abc", 3, 5, -1), 3)
  -- mix
  eq(f(" \t x", 1, 3, 1), 4)
  eq(f("x \t ", 4, 3, -1), 1)
end

T["base"]["shrink_region"] = function()
  local s = H.shrink_region
  -- single line, no padding
  eq(s({ "abc" }, { 0, 0, 0, 2 }), { 0, 0, 0, 2 })
  -- single line, leading spaces
  eq(s({ "  abc" }, { 0, 0, 0, 4 }), { 0, 2, 0, 4 })
  -- single line, leading+trailing spaces
  eq(s({ "  abc  " }, { 0, 0, 0, 6 }), { 0, 2, 0, 4 })
  -- all whitespace
  eq(s({ "   ", "  " }, { 0, 0, 1, 1 }), nil)
  -- multi-line, first line blank, last line blank
  eq(s({ "", "  a", "b  ", "" }, { 0, 0, 3, 1 }), { 1, 2, 2, 0 })
  -- only on first line
  eq(s({ "  x", "", "" }, { 0, 0, 2, 0 }), { 0, 2, 0, 2 })
  -- only on last line
  eq(s({ "", "", "y  " }, { 0, 0, 2, 3 }), { 2, 0, 2, 0 })
  -- selection has leading+trailing whitespace
  eq(s({ "  /* 1 */  " }, { 0, 0, 0, 10 }), { 0, 2, 0, 8 })
  -- selection already within content
  eq(s({ "  /* 1 */  " }, { 0, 2, 0, 8 }), { 0, 2, 0, 8 })
  -- selecting just subset of content
  eq(s({ "  /* 1 */  " }, { 0, 3, 0, 7 }), { 0, 3, 0, 7 })
  -- multi-line both lines with padding
  eq(s({ "  a  ", "  b  " }, { 0, 0, 1, 5 }), { 0, 2, 1, 2 })
  -- multi-line, selection mid-content on each line
  eq(s({ "  a  ", "  b  " }, { 0, 2, 1, 3 }), { 0, 2, 1, 2 })
  -- only first line selected
  eq(s({ "  a  " }, { 0, 0, 0, 4 }), { 0, 2, 0, 2 })
  -- blank first line, content on subsequent lines
  eq(s({ "", "a" }, { 0, 0, 1, 0 }), { 1, 0, 1, 0 })
  -- content with blank line between
  eq(s({ "a", "", "c" }, { 0, 0, 2, 0 }), { 0, 0, 2, 0 })
  -- single non-whitespace char
  eq(s({ "x" }, { 0, 0, 0, 0 }), { 0, 0, 0, 0 })
  -- tab character in whitespace
  eq(s({ "\tx" }, { 0, 0, 0, 1 }), { 0, 1, 0, 1 })
  -- multiple blank lines before content
  eq(s({ "", "", "  a  " }, { 0, 0, 2, 4 }), { 2, 2, 2, 2 })
  -- selection ends at whitespace after last content
  eq(s({ "a  ", "b" }, { 0, 0, 1, 0 }), { 0, 0, 1, 0 })
  -- empty lines array
  eq(s({}, { 0, 0, 0, 0 }), nil)
  -- rows reversed
  eq(s({ "a" }, { 1, 0, 0, 0 }), nil)
  -- single line, scol > ecol
  eq(s({ "a" }, { 0, 2, 0, 0 }), nil)
  -- multi-line, rows ok but single-line col reversed
  eq(s({ "a" }, { 0, 2, 0, 2 }), nil)
end

T["base"]["match_byte"] = function()
  local mb = H.match_byte
  -- forward exact match
  eq(mb("abc", 0, "abc", 0, 1, false), 3)
  eq(mb("abc", 0, "ab", 0, 1, false), 2)
  eq(mb("abc", 1, "bc", 0, 1, false), 2)
  -- forward partial match (fails partway)
  eq(mb("abc", 0, "abd", 0, 1, false), 2) -- "ab" matches, then "c" != "d"
  eq(mb("abc", 0, "x", 0, 1, false), 0)
  -- forward past end of sa
  eq(mb("ab", 0, "abc", 0, 1, false), 2) -- "ab" matches, can't read more
  eq(mb("ab", 2, "a", 0, 1, false), 0)
  -- forward offset in sb
  eq(mb("abc", 0, "xabc", 1, 1, false), 3) -- sb from pos 1 = "abc"
  eq(mb("abc", 1, "xbc", 1, 1, false), 2)
  -- forward ci
  eq(mb("ABC", 0, "abc", 0, 1, true), 3)
  eq(mb("aBc", 1, "bC", 0, 1, true), 2)
  eq(mb("abc", 0, "abD", 0, 1, true), 2) -- "ab" matches, "c" != "D"
  -- backward exact match
  eq(mb("abc", 2, "cb", 0, -1, false), 2)
  eq(mb("abc", 2, "cba", 0, -1, false), 3)
  eq(mb("a #", 2, "# ", 0, -1, false), 2)
  -- backward partial match (fails partway)
  eq(mb("a #", 2, "# ", 0, -1, false), 2) -- pos 2,1 in "a #" = "# "
  eq(mb("a #", 2, "# x", 0, -1, false), 2) -- "# " matches, sb longer than matched
  eq(mb("a b", 2, " #", 0, -1, false), 0) -- "b" != " "
  -- backward past start of sa
  eq(mb("ab", 0, "a", 0, -1, false), 1)
  eq(mb("ab", 0, "x", 0, -1, false), 0)
  -- backward ci
  eq(mb("ABC", 2, "cb", 0, -1, true), 2)
  eq(mb("aBc", 2, "cB", 0, -1, true), 2)
  -- forward empty sb
  eq(mb("abc", 1, "", 0, 1, false), 0)
  -- backward empty sb
  eq(mb("abc", 1, "", 0, -1, false), 0)
  -- mixed chars forward
  eq(mb("a1b2c", 1, "1b2", 0, 1, false), 3)
  eq(mb("/* comment */", 0, "/* ", 0, 1, false), 3)
  -- tab vs space (exact match, no whitespace skipping)
  eq(mb("#\ttext", 0, "#\t", 0, 1, false), 2)
  eq(mb("#\ttext", 1, " ", 0, 1, false), 0) -- tab != space
  eq(mb("# text", 1, " ", 0, 1, false), 1)
  eq(mb("# text", 1, "\t", 0, 1, false), 0) -- space != tab
  -- unicode (byte comparison)
  eq(mb("f", 0, "f", 0, 1, false), 1)
  eq(mb("ü", 0, "ü", 0, 1, false), 2)
end

T["base"]["match_line_comment"] = function()
  local csi = H.make_csi({ { "//", "" }, { "///", "" }, { "//!", "" } })
  -- check_only mode
  eq(H.match_line_comment("/// doc", 0, csi, { check_only = true }), true)
  eq(H.match_line_comment("//! note", 0, csi, { check_only = true }), true)
  eq(H.match_line_comment("// comment", 0, csi, { check_only = true }), true)
  eq(H.match_line_comment("not a comment", 0, csi, { check_only = true }), false)

  -- full mode: lcs_pos
  local r = H.match_line_comment("  /// doc", 1, csi)
  assert(r)
  eq(type(r), "table")
  eq(r.lcs_pos[1], 1)
  eq(r.lcs_pos[2], 2)
  eq(r.rcs_pos, nil)

  r = H.match_line_comment("  //! note", 1, csi)
  eq(type(r), "table")

  r = H.match_line_comment("  // comment", 1, csi)
  eq(type(r), "table")

  -- no match
  eq(H.match_line_comment("  foo", 0, csi), nil)
  eq(H.match_line_comment("  foo", 0, csi, { check_only = true }), false)

  -- single token (backward compat)
  local csi2 = H.make_csi({ { "//", "" } })
  eq(H.match_line_comment("// foo", 0, csi2, { check_only = true }), true)
  eq(H.match_line_comment("/// foo", 0, csi2, { check_only = true }), true)
  eq(H.match_line_comment("foo", 0, csi2, { check_only = true }), false)

  -- rcs-only comment string (%s # style)
  local csi3 = H.make_csi({ { "", " #" } })
  eq(H.match_line_comment("line #", 0, csi3, { check_only = true }), true)
  eq(H.match_line_comment("line # ", 0, csi3, { check_only = true }), true)
  eq(H.match_line_comment("line", 0, csi3, { check_only = true }), false)

  -- rcs-only full mode
  local r3 = H.match_line_comment("  a # b #", 1, csi3)
  assert(r3)
  eq(type(r3), "table")
  eq(r3.rcs_pos, { 1, 7, 8 })
  eq(r3.lcs_pos, nil)

  -- rcs-only: line with multiple ##, only last one matched
  r3 = H.match_line_comment("line ##", 1, csi3)
  assert(r3)
  eq(type(r3), "table")
  eq(r3.rcs_pos, { 1, 6, 6 })

  -- lcs+rcs with pad
  local csi4 = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local r4 = H.match_line_comment("  /* hello */", 1, csi4)
  assert(r4)
  eq(r4.lcs_pos[2], 2)
  eq(r4.rcs_pos, { 1, 10, 12 })

  -- lcs+rcs without pad
  local csi5 = H.make_csi({ { "/*", "*/" } }, { pad = false })
  local r5 = H.match_line_comment("  /*hello*/", 1, csi5)
  assert(r5)
  eq(r5 ~= nil, true)
  eq(r5.lcs_pos[2], 2)
  eq(r5.rcs_pos[2], 9)

  -- multi-word content after lcs with rcs
  local csi6 = H.make_csi({ { "// ", "" } })
  local r6 = H.match_line_comment("  // hello world", 1, csi6)
  assert(r6)
  eq(type(r6), "table")
  eq(r6.lcs_pos[2], 2)
  eq(r6.rcs_pos, nil)

  -- tab indentation
  r6 = H.match_line_comment("\t// indented", 1, csi6)
  assert(r6)
  eq(type(r6), "table")
  eq(r6.lcs_pos[2], 1)

  r6 = H.match_line_comment("// foo", 1, csi6)
  assert(r6)

  -- lcs+rcs: content with nested lcs pattern
  local csi7 = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local r7 = H.match_line_comment("  /* a /* b */", 1, csi7)
  assert(r7)
  eq(type(r7), "table")
  eq(r7.lcs_pos, { 1, 2, 4 })
  eq(r7.rcs_pos, { 1, 11, 13 })

  -- will_blank with check_will_blank
  local r8 = H.match_line_comment("  //", 1, csi, { check_will_blank = true })
  assert(r8)
  eq(r8.will_blank, true)
  r8 = H.match_line_comment("  /// doc", 1, csi, { check_will_blank = true })
  assert(r8)
  eq(r8.will_blank, false)
end

T["base"]["compute_cursor_state"] = function()
  local lines_d = { "x", "x", "x", "x", "x" }
  local range_d = { 0 }
  local csi_d = { orcs = "" }
  local function cr(row, col) return { cursor = make_pos(0, row, col) } end
  local f = function(cs, edits, lines, range, csi)
    H.compute_cursor_state(cs, edits, lines or lines_d, range or range_d, csi or csi_d)
  end
  local cs

  -- nil cursor_state
  f(nil, {})
  eq(cs, nil)

  -- empty edits
  cs = cr(0, 3)
  f(cs, {})
  eq(cs, cr(0, 3))

  -- insertion on same row, cursor after insert point
  cs = cr(0, 3)
  f(cs, { { range = { 0, 0, 0, 0 }, text = { "# " } } })
  eq(cs, cr(0, 5))

  -- insertion on same row, cursor at insert point
  cs = cr(0, 0)
  f(cs, { { range = { 0, 0, 0, 0 }, text = { "# " } } })
  eq(cs, cr(0, 2))

  -- insertion on same row, cursor before insert point
  cs = cr(0, 0)
  f(cs, { { range = { 0, 3, 0, 3 }, text = { "//" } } })
  eq(cs, cr(0, 0))

  -- insertion on different row
  cs = cr(1, 2)
  f(cs, { { range = { 0, 0, 0, 0 }, text = { "# " } } })
  eq(cs, cr(1, 2))

  -- deletion, cursor after deleted range
  cs = cr(0, 5)
  f(cs, { { range = { 0, 0, 0, 3 }, text = { "" } } })
  eq(cs, cr(0, 2))

  -- deletion, cursor within deleted range → clamped to start
  cs = cr(0, 2)
  f(cs, { { range = { 0, 0, 0, 3 }, text = { "" } } })
  eq(cs, cr(0, 0))

  -- deletion, cursor before deleted range
  cs = cr(0, 0)
  f(cs, { { range = { 0, 3, 0, 5 }, text = { "" } } })
  eq(cs, cr(0, 0))

  -- multi-line replacement on same row, cursor after end
  cs = cr(0, 6)
  f(cs, { { range = { 0, 3, 0, 5 }, text = { "longer", "b", "c" } } })
  eq(cs, cr(2, 10))

  -- multi-line replacement on same row, cursor inside replaced range
  cs = cr(0, 4)
  f(cs, { { range = { 0, 3, 0, 5 }, text = { "/*", "*/" } } })
  eq(cs, cr(1, 4))

  -- multi-line replacement before cursor row
  cs = cr(2, 2)
  f(cs, { { range = { 0, 0, 0, 0 }, text = { "a", "b" } } })
  eq(cs, cr(3, 2))

  -- multi-line replacement after cursor row
  cs = cr(0, 2)
  f(cs, { { range = { 3, 0, 3, 0 }, text = { "a", "b" } } })
  eq(cs, cr(0, 2))

  -- multiple edits: insert + delete on same row
  cs = cr(0, 5)
  f(cs, {
    { range = { 0, 3, 0, 3 }, text = { "//" } },
    { range = { 0, 0, 0, 2 }, text = { "" } },
  })
  eq(cs, cr(0, 5))

  -- multiple edits: delete + insert on same row (reversed order)
  cs = cr(0, 5)
  f(cs, {
    { range = { 0, 0, 0, 2 }, text = { "" } },
    { range = { 0, 3, 0, 3 }, text = { "//" } },
  })
  eq(cs, cr(0, 5))

  -- multiple edits: two inserts expanding cursor right
  cs = cr(0, 3)
  f(cs, {
    { range = { 0, 0, 0, 0 }, text = { "# " } },
    { range = { 0, 5, 0, 5 }, text = { " //" } },
  })
  eq(cs, cr(0, 5))

  -- multiple edits: two multi-line inserts before cursor, stacking rows
  cs = cr(4, 0)
  f(cs, {
    { range = { 0, 0, 0, 0 }, text = { "a", "b" } },
    { range = { 1, 0, 1, 0 }, text = { "c", "d" } },
  })
  eq(cs, cr(6, 0))

  -- multiple edits: insert on same row + multi-line before row
  cs = cr(2, 2)
  f(cs, {
    { range = { 1, 0, 1, 0 }, text = { "x", "y" } },
    { range = { 2, 0, 2, 0 }, text = { "# " } },
  })
  eq(cs, cr(3, 4))

  -- sentinel insert 1 line before cursor → nrow +1
  cs = cr(1, 0)
  f(cs, { { range = { 0, -1, 0, -1 }, text = { "/*" } } })
  eq(cs, cr(2, 0))

  -- sentinel insert 1 line on cursor row → nrow +1
  cs = cr(0, 0)
  f(cs, { { range = { 0, -1, 0, -1 }, text = { "/*" } } })
  eq(cs, cr(1, 0))

  -- sentinel insert 1 line after cursor → nrow unchanged
  cs = cr(0, 0)
  f(cs, { { range = { 2, -1, 2, -1 }, text = { "/*" } } })
  eq(cs, cr(0, 0))

  -- sentinel insert 2 lines before cursor → nrow +2
  cs = cr(1, 0)
  f(cs, { { range = { 0, -1, 0, -1 }, text = { "a", "b" } } })
  eq(cs, cr(3, 0))

  -- sentinel delete 1 line before cursor → nrow -1
  cs = cr(2, 0)
  f(cs, { { range = { 0, -1, 1, -1 }, text = {} } })
  eq(cs, cr(1, 0))

  -- sentinel delete 1 line on cursor row → nrow -1
  cs = cr(0, 0)
  f(cs, { { range = { 0, -1, 1, -1 }, text = {} } })
  eq(cs, cr(0, 0))

  -- sentinel delete 1 line after cursor → nrow unchanged
  cs = cr(0, 0)
  f(cs, { { range = { 2, -1, 3, -1 }, text = {} } })
  eq(cs, cr(0, 0))

  -- sentinel delete 2 lines before cursor → nrow -2
  cs = cr(3, 0)
  f(cs, { { range = { 0, -1, 2, -1 }, text = {} } })
  eq(cs, cr(1, 0))

  -- EOL + RHS insert: skip shift
  cs = cr(0, 7)
  f(cs, { { range = { 0, 7, 0, 7 }, text = { " */" } } }, { "  hello" }, { 0, 0, 0, 7 }, { orcs = " */" })
  eq(cs, cr(0, 7))

  -- EOL + LHS insert: normal shift
  cs = cr(0, 7)
  f(cs, { { range = { 0, 7, 0, 7 }, text = { "/* " } } }, { "  hello" }, { 0, 0, 0, 7 }, { orcs = " */" })
  eq(cs, cr(0, 10))

  -- EOL + RHS insert with orcs="" (LHS-only): normal shift
  cs = cr(0, 7)
  f(cs, { { range = { 0, 7, 0, 7 }, text = { "// " } } }, { "  hello" }, { 0, 0, 0, 7 }, { orcs = "" })
  eq(cs, cr(0, 10))

  -- non-EOL + RHS insert: no shift (cursor before insert point)
  cs = cr(0, 3)
  f(cs, { { range = { 0, 7, 0, 7 }, text = { " */" } } }, { "  hello" }, { 0, 0, 0, 7 }, { orcs = " */" })
  eq(cs, cr(0, 3))

  -- EOL + LHS+RHS: LHS shifts, RHS skips
  cs = cr(0, 7)
  f(cs, {
    { range = { 0, 2, 0, 2 }, text = { "/* " } },
    { range = { 0, 7, 0, 7 }, text = { " */" } },
  }, { "  hello" }, { 0, 0, 0, 7 }, { orcs = " */" })
  eq(cs, cr(0, 10))
end

T["base"]["make_csi"] = function()
  -- single pair, no pad
  local csi = H.make_csi({ { "//", "" } })
  eq(#csi.pairs, 1)
  eq(csi.pairs[1].traw[1], "//")
  eq(csi.pairs[1].tesc[1], vim.pesc("//"))
  eq(csi.pairs[1].tout[1], "//")
  eq(csi.tlcs, "//")
  eq(csi.olcs, "//")

  -- with pad
  csi = H.make_csi({ { "//", "" } }, { pad = true })
  eq(csi.olcs, "// ")

  -- multi pair sorted by length descending
  csi = H.make_csi({ { "//", "" }, { "///", "" }, { "//!", "" } })
  eq(#csi.pairs, 3)
  eq(csi.pairs[1].traw[1], "///")
  eq(csi.pairs[2].traw[1], "//!")
  eq(csi.pairs[3].traw[1], "//")
  eq(csi.pairs[3].tesc[1], vim.pesc("//"))

  -- block pair with pad
  csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  eq(csi.wrapped, true)
  eq(csi.olcs, "/* ")
  eq(csi.orcs, " */")

  -- block pair without pad
  csi = H.make_csi({ { "/*", "*/" } }, { pad = false })
  eq(csi.olcs, "/*")
  eq(csi.orcs, "*/")
  eq(csi.wrapped, true)

  -- case insensitive
  csi = H.make_csi({ { "@REM", "" } }, { ci = true })
  eq(#csi.pairs, 1)
  eq(csi.pairs[1].tesc[1], "@[rR][eE][mM]")

  -- rcs only
  csi = H.make_csi({ { "", " #" } })
  eq(#csi.pairs, 1)
  eq(csi.tlcs, "")
  eq(csi.trcs, "#")
  eq(csi.wrapped, false)

  -- raw strings preserved when no pad
  csi = H.make_csi({ { "/* ", " */" } })
  eq(csi.olcs, "/* ")
  eq(csi.orcs, " */")

  -- empty pair filtered out
  csi = H.make_csi({ { "//", "" }, { "", "" } })
  eq(#csi.pairs, 1)

  -- no valid pairs
  eq(H.make_csi({ { "", "" } }), nil)
end

T["base"]["block_comment_info"] = function()
  local function f(lines, lcs, rcs, scol, ecol, motion, relaxed)
    local cfg = relaxed and { block_relaxed_detect = true } or nil
    local range = { 0, scol, #lines - 1, ecol }
    return H.block_comment_info(lines, H.make_csi({ { lcs, rcs } }), motion, range, cfg)
  end

  -- Line mode: complete block
  local info = f({ "  /* hello */" }, "/* ", " */", 0, 11, "line")
  eq(info.lcs_pos[2], 2)
  eq(info.lcs_pos[3], 4)
  eq(info.rcs_pos[2], 10)
  eq(info.rcs_pos[3], 12)

  -- Line mode: no block
  eq(f({ "hello" }, "/* ", " */", 0, 4, "line"), nil)

  -- Line mode: has lcs but no trailing rcs
  eq(f({ "  /* hello" }, "/* ", " */", 0, 9, "line"), nil)

  -- Char mode: selected pair
  info = f({ "he/* llo */ld" }, "/* ", " */", 2, 10, "char")
  eq(info.lcs_pos[2], 2)
  eq(info.lcs_pos[3], 4)
  eq(info.rcs_pos[2], 8)
  eq(info.rcs_pos[3], 10)

  -- Char mode: no lcs
  eq(f({ "hello" }, "/* ", " */", 2, 4, "char"), nil)

  -- Char mode: lcs present but no rcs within bounds
  eq(f({ "/* a */ b()" }, "/* ", " */", 0, 2, "char"), nil)

  -- Block mode (same as line)
  info = f({ "  /* hello */" }, "/* ", " */", 0, 11, "block")
  eq(info.lcs_pos[2], 2)
  eq(info.lcs_pos[3], 4)
  eq(info.rcs_pos[2], 10)
  eq(info.rcs_pos[3], 12)

  -- Relaxed: leading blank line (line motion)
  info = f({ "", "  /* hello */" }, "/* ", " */", 0, 11, "line", true)
  eq(info.lcs_pos[1], 1)
  eq(info.lcs_pos[2], 2)
  eq(info.rcs_pos[1], 1)
  eq(info.rcs_pos[2], 10)

  -- Relaxed: trailing blank line (line motion)
  info = f({ "  /* hello */", "" }, "/* ", " */", 0, 11, "line", true)
  eq(info.lcs_pos[1], 0)
  eq(info.lcs_pos[2], 2)
  eq(info.rcs_pos[1], 0)
  eq(info.rcs_pos[2], 10)

  -- Relaxed: both sides blank (line motion)
  info = f({ "", "  /* hello */", "" }, "/* ", " */", 0, 11, "line", true)
  eq(info.lcs_pos[1], 1)
  eq(info.lcs_pos[2], 2)
  eq(info.rcs_pos[1], 1)
  eq(info.rcs_pos[2], 10)

  -- Relaxed: all blank lines (line motion)
  eq(f({ "", "" }, "/* ", " */", 0, 0, "line", true), nil)

  -- Relaxed: char mode, leading whitespace before lcs
  info = f({ "  /* 1 */  " }, "/* ", " */", 0, 10, "char", true)
  eq(info.lcs_pos[2], 2)
  eq(info.lcs_pos[3], 4)
  eq(info.rcs_pos[2], 6)
  eq(info.rcs_pos[3], 8)

  -- Relaxed: char mode, all whitespace
  eq(f({ "      " }, "/* ", " */", 0, 5, "char", true), nil)

  -- Relaxed: multi-line, blank first line (char mode)
  info = f({ "", "/* 1 */" }, "/* ", " */", 0, 6, "char", true)
  eq(info.lcs_pos[1], 1)
  eq(info.lcs_pos[2], 0)
  eq(info.lcs_pos[3], 2)
  eq(info.rcs_pos[1], 1)
  eq(info.rcs_pos[2], 4)
  eq(info.rcs_pos[3], 6)

  -- Non-relaxed should still fail when leading blank
  eq(f({ "", "  /* hello */" }, "/* ", " */", 0, 11, "line"), nil)

  -- Relaxed: multi-line block comment, linewise ec=0 (line motion)
  info = f({ "  --[[ xxx", "  yyy ]] " }, "--[[ ", " ]]", 0, 0, "line", true)
  eq(info.lcs_pos, { 0, 2, 6 })
  eq(info.rcs_pos, { 1, 5, 7 })

  -- Relaxed: block motion, multi-line (same as line)
  info = f({ "  --[[ xxx", "  yyy ]] " }, "--[[ ", " ]]", 0, 0, "block", true)
  eq(info.lcs_pos, { 0, 2, 6 })
  eq(info.rcs_pos, { 1, 5, 7 })

  -- Relaxed: three-line block comment (line motion)
  info = f({ "  --[[ xxx", "  yyy", "  zzz ]] " }, "--[[ ", " ]]", 0, 0, "line", true)
  eq(info.lcs_pos, { 0, 2, 6 })
  eq(info.rcs_pos, { 2, 5, 7 })

  -- Multi-pair: pair 1
  local csi_mb = H.make_csi({ { "{-", "-}" }, { "{#", "#}" } }, { pad = true })
  info = H.block_comment_info({ "{- hello -}" }, csi_mb, "line", { 0, 0, 0, 10 }, {})
  assert(info)
  eq(info.lcs_pos[2], 0)
  eq(info.rcs_pos[2], 8)
  eq(info.rcs_pos[3], 10)

  -- Multi-pair: pair 2
  info = H.block_comment_info({ "{# hello #}" }, csi_mb, "line", { 0, 0, 0, 10 }, {})
  assert(info)
  eq(info.lcs_pos[2], 0)
  eq(info.rcs_pos[2], 8)
end

T["base"]["match_block_comment"] = function()
  local csi = H.make_csi({ { "{-", "-}" }, { "{#", "#}" } }, { pad = true })

  -- single line, line motion, pair 1
  local info = H.match_block_comment({ "{- hello -}" }, { 0, 0, 0, 9 }, { 0, 0, 0, 9 }, csi, "line")
  assert(info)
  eq(info.lcs_pos[2], 0)
  eq(info.rcs_pos[2], 8)

  -- single line, line motion, pair 2
  info = H.match_block_comment({ "{# hello #}" }, { 0, 0, 0, 9 }, { 0, 0, 0, 9 }, csi, "line")
  assert(info)
  eq(info.lcs_pos[2], 0)
  eq(info.rcs_pos[2], 8)

  -- multi line: LCS on line 1, RCS on line 2
  info = H.match_block_comment({ "{- a", "b -}" }, { 0, 0, 1, 4 }, { 0, 0, 1, 4 }, csi, "line")
  assert(info)
  eq(info.lcs_pos[1], 0)
  eq(info.rcs_pos[1], 1)

  -- multi line (n=3): LCS on line 1, RCS on line 3
  info = H.match_block_comment({ "{- a", "b", "c -}" }, { 0, 0, 2, 4 }, { 0, 0, 2, 4 }, csi, "line")
  assert(info)
  eq(info.lcs_pos[1], 0)
  eq(info.rcs_pos[1], 2)

  -- with leading whitespace
  info = H.match_block_comment({ "  {- hello -}" }, { 0, 0, 0, 11 }, { 0, 0, 0, 11 }, csi, "line")
  assert(info)
  eq(info.lcs_pos[2], 2)
  eq(info.rcs_pos[2], 10)

  -- char motion
  local csi2 = H.make_csi({ { "/*", "*/" } }, { pad = true })
  info = H.match_block_comment({ "/* hello */" }, { 0, 0, 0, 10 }, { 0, 0, 0, 10 }, csi2, "char")
  assert(info)
  eq(info.lcs_pos[2], 0)

  -- no match
  eq(H.match_block_comment({ "hello" }, { 0, 0, 0, 4 }, { 0, 0, 0, 4 }, csi, "line"), nil)

  -- no match (only LCS, no RCS)
  eq(H.match_block_comment({ "{- hello" }, { 0, 0, 0, 7 }, { 0, 0, 0, 7 }, csi, "line"), nil)

  -- different markers (same prefix, different content)
  local csi3 = H.make_csi({ { "{-", "-}" }, { "{+", "+}" } }, { pad = true })
  info = H.match_block_comment({ "{+ hello +}" }, { 0, 0, 0, 9 }, { 0, 0, 0, 9 }, csi3, "line")
  assert(info)
  eq(info.lcs_pos[2], 0)
end

T["base"]["resolve"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  local function f(ft, cs, ctype, insert_space)
    local cfg = { insert_space = insert_space ~= false, hooks = {} }
    vim.bo[buf].filetype = ft
    vim.bo[buf].commentstring = cs
    local csi = H.resolve(make_pos(buf, 0, 0), ctype, cfg, { 1, 1, 1, 1 })
    assert(csi)
    return { csi.tlcs, csi.trcs }
  end
  eq(f("cpp", "// %s", 2), { "/*", "*/" })
  eq(f("cpp", "// %s", 1), { "//", "" })
  eq(f("lua", "-- %s", 2), { "--[[", "]]" })
  eq(f("lua", "-- %s", 1), { "--", "" })
  eq(f("html", "<!-- %s -->", 2), { "<!--", "-->" })
  eq(f("cpp", "// %s", 2, false), { "/*", "*/" })
  vim.api.nvim_buf_delete(buf, { force = true })
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
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "ab", "cd", "ef" })

  local edits = {
    { range = { 2, 1, 2, 1 }, text = { "X" } },
    { range = { 0, 0, 0, 0 }, text = { "Z" } },
    { range = { 1, 2, 1, 2 }, text = { "Y" } },
  }
  edits.need_sort = true
  edits.any_multi = true

  H.commit_edits(buf, nil, nil, edits, false)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "Zab")
  eq(lines[2], "cdY")
  eq(lines[3], "eXf")

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["edits"]["commit_edits"] = function()
  local buf = vim.api.nvim_create_buf(false, true)

  -- 1. any_multi + set_text: multi-element text, expand 1 line to 3
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
  H.commit_edits(buf, nil, nil, {
    { range = { 0, 0, 0, 5 }, text = { "/*", "hello", "*/" } },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "/*", "hello", "*/" })

  -- 2. any_multi + set_text: multi-line range replaced with fewer lines (delete 2 lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c", "d" })
  H.commit_edits(buf, nil, nil, {
    { range = { 1, 0, 3, 1 }, text = { "x" } },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "a", "x" })

  -- 3. any_multi + set_text: append beyond buffer (max <= range[1])
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa", "bb" })
  H.commit_edits(buf, nil, nil, {
    { range = { 2, 0, 2, 0 }, text = { "cc" } },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "aa", "bb", "cc" })

  -- 4. sentinel: insert 1 line at start
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa", "bb" })
  H.commit_edits(buf, nil, nil, {
    { range = { 0, -1, 0, -1 }, text = { "/*" } },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "/*", "aa", "bb" })

  -- 5. sentinel: insert 1 line in middle
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa", "bb" })
  H.commit_edits(buf, nil, nil, {
    { range = { 1, -1, 1, -1 }, text = { "/*" } },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "aa", "/*", "bb" })

  -- 6. sentinel: insert 2 lines at start
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa" })
  H.commit_edits(buf, nil, nil, {
    { range = { 0, -1, 0, -1 }, text = { "/*", "*/" } },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "/*", "*/", "aa" })

  -- 7. sentinel: delete 1 line
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa", "bb", "cc" })
  H.commit_edits(buf, nil, nil, {
    { range = { 1, -1, 2, -1 }, text = {} },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "aa", "cc" })

  -- 8. sentinel: delete 2 lines
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa", "bb", "cc" })
  H.commit_edits(buf, nil, nil, {
    { range = { 0, -1, 2, -1 }, text = {} },
    any_multi = true,
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "cc" })

  -- 9. sentinel + need_sort: insert both /* and */ around content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aa", "bb" })
  local edits = {
    { range = { 2, -1, 2, -1 }, text = { "*/" } },
    { range = { 0, -1, 0, -1 }, text = { "/*" } },
  }
  edits.need_sort = true
  edits.any_multi = true
  H.commit_edits(buf, nil, nil, edits, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "/*", "aa", "bb", "*/" })

  -- 10. non-any_multi: apply_edits path
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
  H.commit_edits(buf, { 0, 0, 0, 5 }, { "hello" }, {
    { range = { 0, 0, 0, 0 }, text = { "# " } },
  }, false)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "# hello" })

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["edits"]["make_comment_edits"] = function()
  local csi = H.make_csi({ { "# ", "" } })
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "hello", {})
  assert(edits)
  eq(apply("hello", edits), "# hello")
  eq(#edits, 1)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 0)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "# " })
end

T["edits"]["make_comment_edits_with_indent"] = function()
  local csi = H.make_csi({ { "# ", "" } })
  local edits = H.make_comment_edits(make_line_info({ offset = 2, csi = csi }), "  hello", {})
  assert(edits)
  eq(apply("  hello", edits), "  # hello")
  eq(#edits, 1)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 2)
  eq(edits[1].range[4], 2)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "# " })
end

T["edits"]["make_uncomment_edits"] = function()
  local info = make_line_info({ lcs_pos = { 0, 0, 1 } })
  local edits = H.make_uncomment_edits(info, "# hello")
  assert(edits)
  eq(apply("# hello", edits), "hello")
  eq(#edits, 1)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 2)
  eq(edits[1].text, { "" })
end

T["edits"]["make_comment_edits_with_rcs"] = function()
  local csi = H.make_csi({ { "<!-- ", " -->" } }, { pad = true })
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "hello", {})
  assert(edits)
  eq(apply("hello", edits), "<!-- hello -->")
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 0)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "<!-- " })
  eq(edits[2].range[1], 0)
  eq(edits[2].range[2], 5)
  eq(edits[2].range[4], 5)
  eq(#edits[2].text, 1)
  eq(edits[2].text, { " -->" })
end

T["edits"]["make_uncomment_edits_with_rcs"] = function()
  local info = make_line_info({ lcs_pos = { 0, 0, 4 }, rcs_pos = { 0, 10, 13 } })
  local edits = H.make_uncomment_edits(info, "<!-- hello -->")
  assert(edits)
  eq(apply("<!-- hello -->", edits), "hello")
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 5)
  eq(edits[1].text, { "" })
  eq(edits[2].range[1], 0)
  eq(edits[2].range[2], 10)
  eq(edits[2].range[4], 14)
  eq(edits[2].text, { "" })
end

T["edits"]["make_comment_edits_blank_line"] = function()
  local csi = H.make_csi({ { "# ", "" } })
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "", {})
  assert(edits)
  eq(apply("", edits), "# ")
  eq(#edits, 1)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 0)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "# " })
end

T["edits"]["make_comment_edits_noindent"] = function()
  local csi = H.make_csi({ { "// ", "" } })
  local cfg = { line_comment_no_indent = true }
  local edits = H.make_comment_edits(make_line_info({ offset = 0, csi = csi }), "  code", cfg)
  assert(edits)
  eq(apply("  code", edits), "//   code")
  eq(#edits, 1)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 0)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "// " })
end

T["edits"]["make_block_comment_edits_two_lines"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "hello", "world" }
  local edits = H.make_block_comment_edits(lines, csi, { 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* hello")
  eq(lines[2], "world */")
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 0)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "/* " })
  eq(edits[2].range[1], 1)
  eq(edits[2].range[2], 5)
  eq(edits[2].range[4], 5)
  eq(#edits[2].text, 1)
  eq(edits[2].text, { " */" })
end

T["edits"]["make_block_comment_edits_empty_lines"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "  " }
  local edits = H.make_block_comment_edits(lines, csi, { 0, 0, 0, 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*    */")
  eq(#edits, 2)
  eq(edits[1].range, { 0, 0, 0, 0 })
  eq(edits[1].text, { "/* " })
  eq(edits[2].range, { 0, 2, 0, 2 })
  eq(edits[2].text, { " */" })

  lines = { "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 1, 0, 1 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*    */")
  eq(#edits, 2)
  eq(edits[1].range, { 0, 0, 0, 0 })
  eq(edits[1].text, { "/* " })
  eq(edits[2].range, { 0, 2, 0, 2 })
  eq(edits[2].text, { " */" })

  lines = { "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 2, 0, 2 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*    */")
  eq(#edits, 2)
  eq(edits[1].range, { 0, 0, 0, 0 })
  eq(edits[1].text, { "/* " })
  eq(edits[2].range, { 0, 2, 0, 2 })
  eq(edits[2].text, { " */" })

  -- insmode
  lines = { "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 0, 0, 0 }, { insmode = true })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/*  */  ")
  eq(#edits, 2)
  eq(edits[1].range, { 0, 0, 0, 0 })
  eq(edits[1].text, { "/* " })
  eq(edits[2].range, { 0, 0, 0, 0 })
  eq(edits[2].text, { " */" })

  lines = { "  ", "  " }
  edits = H.make_block_comment_edits(lines, csi, { 0, 0, 1, 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines, { "/*   ", "   */" })
  eq(#edits, 2)
  eq(edits[1].range, { 0, 0, 0, 0 })
  eq(edits[1].text, { "/* " })
  eq(edits[2].range, { 1, 2, 1, 2 })
  eq(edits[2].text, { " */" })
end

T["edits"]["make_block_comment_edits_single_line"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "hello" }
  local edits = H.make_block_comment_edits(lines, csi, { 0 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "/* hello */")
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 0)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "/* " })
  eq(edits[2].range[1], 0)
  eq(edits[2].range[2], 5)
  eq(edits[2].range[4], 5)
  eq(#edits[2].text, 1)
  eq(edits[2].text, { " */" })
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
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 3)
  eq(edits[1].text, { "" })
  eq(edits[2].range[1], 1)
  eq(edits[2].range[2], 5)
  eq(edits[2].range[4], 8)
  eq(edits[2].text, { "" })
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
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 0)
  eq(edits[1].range[4], 3)
  eq(edits[1].text, { "" })
  eq(edits[2].range[1], 0)
  eq(edits[2].range[2], 8)
  eq(edits[2].range[4], 11)
  eq(edits[2].text, { "" })
end

T["edits"]["make_block_partial_edits"] = function()
  local csi = H.make_csi({ { "/*", "*/" } }, { pad = true })
  local lines = { "hello world" }
  local edits = H.make_block_partial_edits(lines, csi, { 0, 3, 0, 7 })
  assert(edits)
  H.apply_edits(lines, edits)
  eq(lines[1], "hel/* lo wo */rld")
  eq(#edits, 2)
  eq(edits[1].range[1], 0)
  eq(edits[1].range[2], 3)
  eq(edits[1].range[4], 3)
  eq(#edits[1].text, 1)
  eq(edits[1].text, { "/* " })
  eq(edits[2].range[1], 0)
  eq(edits[2].range[2], 8)
  eq(edits[2].range[4], 8)
  eq(#edits[2].text, 1)
  eq(edits[2].text, { " */" })
end

T["edits"]["compute_line_edits_actions"] = function()
  local ACT = M.ACTION
  local csi = H.make_csi({ { "// ", "" } })
  local cfg = {}

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

-- line_comment_no_indent tests ───────────────────────────────────────────────

T["line_comment_no_indent"] = new_set()

T["line_comment_no_indent"]["gcc on tab-indented line"] = function()
  child.bo.commentstring = "#%s"
  child.b.celeste_comment_config = { line_comment_no_indent = true, insert_space = false }
  set_lines({ "\ta" })
  feed("gcc")
  eq(get_lines(), { "#\ta" })

  feed("gcc")
  eq(get_lines(), { "\ta" })
end

T["line_comment_no_indent"]["gcc on whitespace-only line adds comment at col 0"] = function()
  child.bo.commentstring = "#%s"
  child.b.celeste_comment_config = { line_comment_no_indent = true, insert_space = false }
  set_lines({ "  " })
  feed("gcc")
  eq(get_lines(), { "#  " })
end

T["line_comment_no_indent"]["gcc puts // at col 0"] = function()
  child.bo.commentstring = "#%s"
  child.b.celeste_comment_config = {}
  set_lines({ "  aa", "    bb" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "#   aa", "    bb" })
  feed("gcc")
  eq(get_lines(), { "  aa", "    bb" })
end

T["line_comment_no_indent"]["gc motion puts // at col 0"] = function()
  child.bo.commentstring = "--%s"
  child.b.celeste_comment_config = {}
  set_lines({ "  aa", "  bb", "  cc" })
  set_cursor(1, 0)
  feed("gc", "2j")
  eq(get_lines(), { "--   aa", "--   bb", "--   cc" })
  feed("gc", "2j")
  eq(get_lines(), { "  aa", "  bb", "  cc" })
end

T["line_comment_no_indent"]["recognition: indented comment not uncommented"] = function()
  child.bo.commentstring = "%%%s"
  child.b.celeste_comment_config = { insert_space = false }
  set_lines({ "  %% aa", "%%     bb" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "   aa", "%%     bb" })
  set_cursor(2, 5)
  feed("gcc")
  eq(get_lines(), { "   aa", "     bb" })
end

T["line_comment_no_indent"]["gcj motion"] = function()
  child.bo.commentstring = "##%s"
  child.b.celeste_comment_config = {}
  set_lines({ "##   aa", "##   bb" })
  set_cursor(1, 0)
  feed("gc", "j")
  eq(get_lines(), { "  aa", "  bb" })
  feed("gc", "j")
  eq(get_lines(), { "##   aa", "##   bb" })
end

T["line_comment_no_indent"]["gcgc textobject"] = function()
  child.bo.commentstring = "<!--%s-->"
  child.b.celeste_comment_config = { fallback_to_block = "never" }
  set_lines({ "<!-- hello -->", "<!-- world -->" })
  set_cursor(2, 3)
  feed("gcgc")
  eq(get_lines(), { "hello", "world" })

  child.b.celeste_comment_config = { insert_space = false, fallback_to_block = "if_line_cms_wrapped" }
  set_lines({ "<!-- hello -->", "<!-- world -->" })
  set_cursor(1, 4)
  feed("gcgc")
  eq(get_lines(), { " hello ", "<!-- world -->" })
end

T["line_comment_no_indent"]["indent_algo:vscode + noindent: sol with normalize"] = function()
  child.bo.commentstring = ";%s"
  child.b.celeste_comment_config = { insert_space = false }
  set_lines({ "  aa", "    bb" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { ";  aa", "    bb" })
  feed("gcc")
  eq(get_lines(), { "  aa", "    bb" })
end

-- ignore empty lines tests ──────────────────────────────────────────────────

T["ignore_empty_lines"] = new_set()

T["ignore_empty_lines"]["textobject treats blank as uncommented boundary"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  set_lines({ "bb", "# aa", "", "# bb", "# cc", "end" })
  set_cursor(3, 0)
  feed("gcgc")
  eq(get_lines(), { "bb", "# aa", "", "# bb", "# cc", "end" })
end

T["ignore_empty_lines"]["textobject cursor on comment skips blanks when false"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  set_lines({ "# a", "", "# b", "end" })
  set_cursor(1, 0)
  feed("dgc")
  eq(get_lines(), { "", "# b", "end" })
end

T["ignore_empty_lines"]["never: works with empty lines"] = function()
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  set_lines({ "", "  " })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "# ", "  " })
  set_cursor(2, 0)
  feed(".")
  eq(get_lines(), { "# ", "  # " })
  feed("gck")
  eq(get_lines(), { "", "  " })
  feed(".")
  eq(get_lines(), { "# ", "#   " })
end

T["ignore_empty_lines"]["always: works with empty lines"] = function()
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_lines({ "", "  " })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "# ", "  " })
  set_cursor(2, 0)
  feed(".")
  eq(get_lines(), { "# ", "#   " })
  feed("gck")
  eq(get_lines(), { "", "  " })
  feed(".")
  eq(get_lines(), { "# ", "#   " })
end

T["ignore_empty_lines"]["textobject includes blanks when ignore_empty_lines=always"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_lines({ "# aa", " ", "\t\t", "\t ", "# bb", "  \t", "#cc" })
  set_cursor(3, 2)
  feed("gcgc")
  eq(get_lines(), { "aa", " ", "\t\t", "\t ", "bb", "  \t", "cc" })
end

T["ignore_empty_lines"]["textobject trims blanks at edges"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_lines({ "", "# a", "", "# b", "", "# c", "" })
  set_cursor(3, 0)
  feed("dgc")
  eq(get_lines(), { "", "" })
end

T["ignore_empty_lines"]["mixed: works with empty lines"] = function()
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "  ", "    " })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "  # ", "    " })
  set_cursor(2, 0)
  feed(".")
  eq(get_lines(), { "  # ", "    # " })
  feed("gck")
  eq(get_lines(), { "  ", "    " })

  -- (3 / 2) * 2 = 2
  set_cursor(1, 0)
  set_lines({ "   " })
  feed("gcc")
  eq(get_lines(), { "  #  " })
  feed(".")
  eq(get_lines(), { "   " })
end

T["ignore_empty_lines"]["mixed: blank line not participate in indent calc but can be commented"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "    aa", "", "    bb" })
  set_cursor(1, 0)
  feed("gc", "2j")
  eq(get_lines(), { "    # aa", "    # ", "    # bb" })
  feed("gc", "2j")
  eq(get_lines(), { "    aa", "    ", "    bb" })
end

T["ignore_empty_lines"]["mixed: blank line should not be trimmed after uncomment"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "    # aa", "    # ", "    # bb" })
  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines(), { "    # aa", "    ", "    # bb" })
end

T["ignore_empty_lines"]["mixed: extobject select works"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "    # aa", "    # ", "    # bb" })
  set_cursor(2, 0)
  feed("v", "ga", "d")
  eq(get_lines(), { "" })
end

T["ignore_empty_lines"]["mixed: textobject not skip blanks"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "", "# a", "", "# b", "" })
  set_cursor(2, 2)
  feed("gcgc")
  eq(get_lines(), { "", "a", "", "# b", "" })
  eq(get_cursor(), { 2, 0 })
  feed("u")
  eq(get_lines(), { "", "# a", "", "# b", "" })
  set_cursor(3, 0)
  feed("gcgc")
  eq(get_lines(), { "", "# a", "", "# b", "" })
  eq(get_cursor(), { 3, 0 })

  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  feed("vga", "d")
  eq(get_lines(), { "", "" })

  feed("u")
  eq(get_lines(), { "", "# a", "", "# b", "" })
  feed("gcgc")
  eq(get_lines(), { "", "a", "", "b", "" })
end

T["ignore_empty_lines"]["mixed: gc2j respects indent from non-blank lines"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "    a", "", "    b" })
  set_cursor(1, 0)
  feed("gc", "2j")
  eq(get_lines(), { "    # a", "    # ", "    # b" })
end

T["ignore_empty_lines"]["works with set_text"] = function()
  child.lua_func(function()
    vim.b.celeste_comment_config = {
      ignore_empty_lines = "mixed",
      hooks = {
        pre_commit_edits = function(ctx) ctx.o_use_set_text = true end,
      },
    }
  end)
  child.tabstop = 2
  set_lines({
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
  })
  set_cursor(3, 6)
  feed("gci{")
  eq(get_lines(), {
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
  })
  eq(get_cursor(), { 3, 8 })
end

-- insert_space tests ──────────────────────────────────────────────────────────────

T["insert_space"] = new_set()

T["insert_space"]["insert_space=false linewise"] = function()
  child.b.celeste_comment_config = { insert_space = false }
  child.bo.filetype = "python"
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "#hello" })
  feed("gcc")
  eq(get_lines(), { "hello" })
end

T["insert_space"]["insert_space=false blockwise"] = function()
  child.b.celeste_comment_config = { insert_space = false }
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gbc")
  eq(get_lines(), { "/*hello*/" })
  feed("gbc")
  eq(get_lines(), { "hello" })
end

T["insert_space"]["insert_space=false does not strip inner space"] = function()
  child.b.celeste_comment_config = { insert_space = false }
  child.bo.filetype = "python"
  set_lines({ "#    hello" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "    hello" })
end

-- extra keymap (gco, gcO, gcA) ───────────────────────────────────────────────

T["extra"] = new_set()

T["extra"]["gco inserts comment below"] = function()
  set_lines({ "aa", "bb", "cc" })
  set_cursor(2, 0)
  feed("gco")
  eq(get_lines(), { "aa", "bb", "# ", "cc" })
  eq(get_cursor(), { 3, 2 })
  feed("<Esc>")
  set_cursor(4, 0)
  feed("gco")
  eq(get_lines(), { "aa", "bb", "# ", "cc", "# " })
  eq(get_cursor(), { 5, 2 })
end

T["extra"]["gcO inserts comment above"] = function()
  set_lines({ "aa", "bb", "cc" })
  set_cursor(1, 0)
  feed("gcO")
  eq(get_lines(), { "# ", "aa", "bb", "cc" })
  eq(get_cursor(), { 1, 2 })
  feed("<Esc>")
end

T["extra"]["gcA adds comment at end of line"] = function()
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gcA")
  eq(get_lines(), { "hello # " })
  eq(get_cursor(), { 1, 8 })
end

T["extra"]["gcA on empty line"] = function()
  set_lines({ "" })
  set_cursor(1, 0)
  feed("gcA")
  eq(get_lines(), { "# " })
  eq(get_cursor(), { 1, 2 })
end

T["extra"]["gco inserts --[[ ]] below"] = function()
  child.b.celeste_comment_config = { cms_confs = { wraptest = { "--[[%s]]" } } }
  child.bo.filetype = "wraptest"
  child.bo.commentstring = "# %s"
  set_lines({ "aa", "bb", "cc" })
  set_cursor(2, 0)
  feed("gco")
  eq(get_lines(), { "aa", "bb", "--[[  ]]", "cc" })
  eq(get_cursor(), { 3, 5 })
  feed("1")
  eq(get_lines(), { "aa", "bb", "--[[ 1 ]]", "cc" })
end

T["extra"]["gcO inserts --[[ ]] above"] = function()
  child.b.celeste_comment_config = { cms_confs = { wraptest = { "--[[%s]]" } } }
  child.bo.filetype = "wraptest"
  child.bo.commentstring = "# %s"
  set_lines({ "aa", "bb", "cc" })
  set_cursor(2, 0)
  feed("gcO")
  eq(get_lines(), { "aa", "--[[  ]]", "bb", "cc" })
  eq(get_cursor(), { 2, 5 })
  feed("1")
  eq(get_lines(), { "aa", "--[[ 1 ]]", "bb", "cc" })
  eq(get_cursor(), { 2, 6 })
end

T["extra"]["gcA appends --[[ ]] at eol"] = function()
  child.b.celeste_comment_config = { cms_confs = { wraptest = { "--[[%s]]" } } }
  child.bo.filetype = "wraptest"
  child.bo.commentstring = "# %s"
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gcA")
  eq(get_lines(), { "hello --[[  ]]" })
  eq(get_cursor(), { 1, 11 })
  feed("1")
  eq(get_lines(), { "hello --[[ 1 ]]" })
  eq(get_cursor(), { 1, 12 })
end

-- linewise tests ─────────────────────────────────────────────────────────────

T["linewise"] = new_set()

T["linewise"]["gcc toggles current line"] = function()
  set_lines({ "aa", " bb", "  cc" })
  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines(), { "aa", "#  bb", "  cc" })
  feed("gcc")
  eq(get_lines(), { "aa", " bb", "  cc" })
end

T["linewise"]["gc + motion works"] = function()
  set_lines({ "aa", "bb", "cc", "dd" })
  set_cursor(1, 0)
  feed("gc", "j")
  eq(get_lines(), { "# aa", "# bb", "cc", "dd" })
  feed("gc", "j")
  eq(get_lines(), { "aa", "bb", "cc", "dd" })
end

T["linewise"]["gcc with count"] = function()
  set_lines({ "a", "b", "c", "d" })
  set_cursor(2, 0)
  feed("2gcc")
  eq(get_lines(), { "a", "# b", "# c", "d" })
end

T["linewise"]["visual mode gc"] = function()
  set_lines({ "aa", "bb", "cc" })
  set_cursor(1, 0)
  feed("V", "j", "gc")
  eq(get_lines(), { "# aa", "# bb", "cc" })
end

T["linewise"]["works with folded lines"] = function()
  child.bo.filetype = "lua"
  child.wo.foldmethod = "manual"
  set_lines({ "  a", "  b", "  c", "  d", "  e", "  f" })
  set_cursor(1, 0)
  feed("zf3j")
  feed("2gcc")
  eq(get_lines(), { "--   a", "--   b", "--   c", "--   d", "--   e", "  f" })
  feed("gcgc")
  eq(get_lines(), { "  a", "  b", "  c", "  d", "  e", "  f" })
end

-- Case-insensitive tests ─────────────────────────────────────────────────────

T["case_insensitive"] = new_set()

T["case_insensitive"]["case_insensitive gcc on @REM variants"] = function()
  child.bo.filetype = "bat"
  child.b.celeste_comment_config = { case_insensitive = true }

  -- @REM (uppercase): comment then uncomment
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "@REM hello" })
  feed("gcc")
  eq(get_lines(), { "hello" })

  -- @rem (lowercase): comment produces @REM from config token
  set_lines({ "world" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "@REM world" })
  feed("gcc")
  eq(get_lines(), { "world" })

  -- @Rem (mixed case): uncomment, then comment uses config token @REM
  set_lines({ "@Rem foo" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "foo" })
  feed("gcc")
  eq(get_lines(), { "@REM foo" })

  -- without case_insensitive
  child.b.celeste_comment_config = { case_insensitive = false }
  set_lines({ "@rEm 123" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "@REM @rEm 123" })
end

T["case_insensitive"]["case_insensitive textobject dgc on @REM/@rem"] = function()
  child.bo.filetype = "bat"
  child.b.celeste_comment_config = { case_insensitive = true }
  set_lines({ "code", "@REM hello", "@rem world", "end" })
  set_cursor(2, 0)
  feed("dgc")
  eq(get_lines(), { "code", "end" })
end

T["case_insensitive"]["case_insensitive gc on mixed case @REM lines"] = function()
  child.bo.filetype = "bat"
  child.b.celeste_comment_config = { case_insensitive = true }
  set_lines({ "@REM a", "@rem b", "@Rem c" })
  set_cursor(1, 0)
  feed("gc", "2j")
  eq(get_lines(), { "a", "b", "c" })
  feed("gc", "2j")
  -- Comment back: all get uppercase @REM from config token
  eq(get_lines(), { "@REM a", "@REM b", "@REM c" })
end

-- blockwise tests ────────────────────────────────────────────────────────────

T["blockwise"] = new_set()

T["blockwise"]["gbc on single line"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "hello world" })
  set_cursor(1, 0)
  feed("gbc")
  eq(get_lines(), { "/* hello world */" })
  feed("gbc")
  eq(get_lines(), { "hello world" })
end

T["blockwise"]["gbc on blank and whitespace lines"] = function()
  child.bo.filetype = "cpp"
  set_lines({ "" })
  set_cursor(1, 0)
  feed("gbc")
  eq(get_lines(), { "/*  */" })
  set_lines({ "   " })
  set_cursor(1, 0)
  feed("gbc")
  eq(get_lines(), { "/*     */" })
  set_lines({ "" })
  feed("\\<C-v>")
  feed("gb")
  eq(get_lines(), { "/*  */" })
  set_lines({ "" })
  feed("v")
  feed("gb")
  eq(get_lines(), { "/*  */" })
end

T["blockwise"]["gb + ap on paragraph"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "start", "line1", "line2", "line3", "end" })
  set_cursor(2, 0)
  feed("gb", "ap")
  eq(get_lines(), { "/* start", "line1", "line2", "line3", "end */" })
  feed("gb", "ap")
  eq(get_lines(), { "start", "line1", "line2", "line3", "end" })
end

T["blockwise"]["visual line gb"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "aa", "bb", "cc" })
  set_cursor(1, 0)
  feed("V", "j", "gb")
  eq(get_lines(), { "/* aa", "bb */", "cc" })
end

T["blockwise"]["visual block C-v + gb per line"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "aaaa", "bbbb", "cccc" })
  set_cursor(1, 0)
  feed("\\<C-v>", "2j", "$", "gb")
  eq(get_lines(), { "/* aaaa", "bbbb", "cccc */" })
end

T["blockwise"]["C-v mid-column gb per line"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "aaaabbbb", "aaaabbbb", "aaaabbbb" })
  set_cursor(1, 4)
  feed("\\<C-v>", "2j", "l", "l", "gb")
  eq(get_lines(), { "/* aaaabbbb", "aaaabbbb", "aaaabbbb */" })
  set_cursor(1, 4)
  feed("\\<C-v>", "2j", "l", "l", "gb")
  eq(get_lines(), { "aaaabbbb", "aaaabbbb", "aaaabbbb" })
end

T["blockwise"]["C-v with variable line lengths wraps first/last"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({
    "local a = vim.fn.doSomething()",
    "  local b = vim.fn.otherFunc(arg1)",
    "  return a + b",
  })
  set_cursor(1, 12)
  feed("\\<C-v>", "j", "j", "$", "gb")
  -- comment.nvim behavior: /* after indent on first line, */ at end of last line
  eq(get_lines(), {
    "/* local a = vim.fn.doSomething()",
    "  local b = vim.fn.otherFunc(arg1)",
    "  return a + b */",
  })
  -- Toggle back
  set_cursor(1, 12)
  feed("\\<C-v>", "j", "j", "$", "gb")
  eq(get_lines(), {
    "local a = vim.fn.doSomething()",
    "  local b = vim.fn.otherFunc(arg1)",
    "  return a + b",
  })
end

T["blockwise"]["C-v tab indent and mixed scenarios"] = function()
  -- Tab indent at tabstop=4
  child.bo.tabstop = 4
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"

  set_lines({ "\t\taaa", "\t\tbbb" })
  set_cursor(1, 0)
  feed("\\<C-v>", "j", "$", "gb")
  eq(get_lines(), { "\t\t/* aaa", "\t\tbbb */" })
  set_cursor(1, 0)
  feed("\\<C-v>", "j", "$", "gb")
  eq(get_lines(), { "\t\taaa", "\t\tbbb" })

  -- Mixed indent (spaces of different widths)
  set_lines({ "    aaa", "  bbb", "    ccc" })
  set_cursor(1, 0)
  feed("\\<C-v>", "j", "j", "$", "gb")
  eq(get_lines(), { "    /* aaa", "  bbb", "    ccc */" })
  set_cursor(1, 0)
  feed("\\<C-v>", "j", "j", "$", "gb")
  eq(get_lines(), { "    aaa", "  bbb", "    ccc" })

  -- Different tab widths, consistent tab indentation
  set_lines({ "\taaa", "\t\tbbb", "\tccc" })
  set_cursor(1, 0)
  feed("\\<C-v>", "j", "j", "$", "gb")
  eq(get_lines(), { "\t/* aaa", "\t\tbbb", "\tccc */" })
  set_cursor(1, 0)
  feed("\\<C-v>", "j", "j", "$", "gb")
  eq(get_lines(), { "\taaa", "\t\tbbb", "\tccc" })
end

T["blockwise"]["v multi-line mid-column gb wraps first/last"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "  start", "  middle text", "  more lines", "  end line" })
  set_cursor(2, 2)
  feed("v", "j", "j", "$", "gb")
  local result = get_lines()
  eq(result[2], "  /* middle text")
  eq(result[1], "  start")
  eq(result[3], "  more lines")
  eq(result[4], "  end line */")
end

T["blockwise"]["v single-line mid-column gb wraps selection"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "hello world" })
  set_cursor(1, 2)
  feed("v", "6l", "gb")
  eq(get_lines(), { "he/* llo wor */ld" })
  -- Select from /* to */ via textobject (i( or similar not reliable)
  -- Use gbgb (textobject_blockwise + toggle) instead
  child.api.nvim_win_set_cursor(0, { 1, 4 })
  feed("gbgb")
  eq(get_lines(), { "hello world" })
end

T["blockwise"]["v multi-line both mid-column gb wraps first/last"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "aa", "bbbbbbbb", "cccccccc", "dd" })
  -- Start at line2 col2, end at line3 col5
  set_cursor(2, 2)
  feed("v", "j", "3l", "gb")
  local result = get_lines()
  eq(result[2], "bb/* bbbbbb")
  eq(result[3], "cccccc */cc")
  eq(result[1], "aa")
  eq(result[4], "dd")
  -- Toggle back via gbgb (textobject selects exact pair boundaries)
  child.api.nvim_win_set_cursor(0, { 2, 4 })
  feed("gbgb")
  eq(get_lines(), { "aa", "bbbbbbbb", "cccccccc", "dd" })
end

T["blockwise"]["gbgb toggles block comment via textobject"] = function()
  child.bo.filetype = "lua"
  child.bo.commentstring = "-- %s"
  set_lines({ "  --[[ line 1", "  line 2", "  line 3 ]]" })
  set_cursor(1, 0)
  feed("gb", "ap")
  eq(get_lines(), { "  line 1", "  line 2", "  line 3" })
end

T["blockwise"]["block_nesting=false: nested /* */ is uncommented"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b */ c */" })
  set_cursor(1, 5)
  feed("gbc")
  eq(get_lines(), { "a /* b */ c" })
end

T["blockwise"]["gbc then gbgb on inline block comment restores original"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  local input = "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),"
  set_lines({ input })
  set_cursor(1, 30)
  feed("gbc")
  eq(get_lines()[1], "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */")
  set_cursor(1, 30)
  feed("gbgb")
  eq(get_lines()[1], input)
end

T["blockwise"]["v selects partial inner /* */ adds comment layer"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  local line = "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */"
  set_lines({ line })
  set_cursor(1, 10)
  feed("v", "19l", "gb")
  eq(get_lines()[1], "        /*/*  /* key */ EncodeAsS */tring(k), /* timestamp */ EncodeAsUint64(k + 1), */")
end

T["blockwise"]["v selects /* key */ Enco without rcs adds layer, not remove"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  local line = "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),"
  set_lines({ line })
  -- Select /* key */ Enco (no matching */ in selection)
  set_cursor(1, 8)
  feed("v", "10l", "gb")
  eq(get_lines()[1], "        /* /* key */ E */ncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),")
end

T["blockwise"]["v selects /* key */ with trailing space wraps not remove"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  local line = "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),"
  set_lines({ line })
  set_cursor(1, 8)
  feed("v", "9l", "gb")
  eq(get_lines()[1], "        /* /* key */  */EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1),")
end

T["blockwise"]["v selects exact /* timestamp */ removes inner pair"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  local line = "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */"
  set_lines({ line })
  -- Select exactly /* timestamp */ (17 chars)
  set_cursor(1, 36)
  feed("v", "16l", "gb")
  eq(get_lines()[1], "        /* /* key */ EncodeAsString(/* k), /* timestamp  */*/ EncodeAsUint64(k + 1), */")
end

T["blockwise"]["v selects /* timestamp */ with trailing space tolerates whitespace"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  local line = "        /* /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k + 1), */"
  set_lines({ line })
  -- Select /* timestamp */  with trailing space
  set_cursor(1, 36)
  feed("v", "17l", "gb")
  eq(get_lines()[1], "        /* /* key */ EncodeAsString(/* k), /* timestamp * *// EncodeAsUint64(k + 1), */")
end

T["blockwise"]["gbgb outermost content on nested line removes outer"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b */ c */" })
  set_cursor(1, 4)
  feed("gbgb")
  eq(get_lines(), { "a /* b */ c" })
end

T["blockwise"]["gbgb inside innermost nested removes only inner"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b */ c */" })
  set_cursor(1, 11)
  feed("gbgb")
  eq(get_lines(), { "/* a b c */" })
end

T["blockwise"]["gbgb outermost content targets outermost pair"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b */ c */" })
  set_cursor(1, 4)
  feed("gbgb")
  eq(get_lines(), { "a /* b */ c" })
end

T["blockwise"]["gbgb between two block comments returns"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a */ str() /* b */" })
  set_cursor(1, 9)
  feed("gbgb")
  eq(get_lines(), { "/* a */ str() /* b */" })
end

T["blockwise"]["gbgb three-level nested various cursor positions"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b /* c */ d */ e */" })
  -- Cursor in innermost (c) → removes innermost pair
  set_cursor(1, 16)
  feed("gbgb")
  eq(get_lines(), { "/* a /* b c d */ e */" })
  -- Reset
  set_lines({ "/* a /* b /* c */ d */ e */" })
  -- Cursor in intermediate (b) → also removes innermost pair (gb count=1)
  set_cursor(1, 10)
  feed("gbgb")
  eq(get_lines(), { "/* a /* b c d */ e */" })
  -- Reset
  set_lines({ "/* a /* b /* c */ d */ e */" })
  -- Cursor in outermost (a) → only outermost pair found, removes it
  set_cursor(1, 4)
  feed("gbgb")
  eq(get_lines(), { "a /* b /* c */ d */ e" })
end

T["blockwise"]["d2gb deletes middle pair in 3-level nested"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b /* c */ d */ e */" })
  set_cursor(1, 11)
  feed("d", "2", "gb")
  eq(get_lines(), { "/* a  e */" })
end

T["blockwise"]["d3gb deletes outermost pair"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a /* b /* c */ d */ e */" })
  set_cursor(1, 11)
  feed("d", "3", "gb")
  eq(get_lines(), { "" })
end

T["blockwise"]["gbap multi-line nested with block_nesting=false"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "/* a", "  /* b */", "c */" })
  set_cursor(1, 1)
  feed("gb", "ap")
  eq(get_lines(), { "a", "  /* b */", "c" })
end

T["blockwise"]["gbgb on python docstring"] = function()
  child.bo.filetype = "python"
  set_lines({ '"""', "hello", '"""' })
  set_cursor(2, 0)
  feed("gbgb")
  eq(get_lines(), { "", "hello", "" })
end

T["blockwise"]["empty selection and use set_text"] = function()
  child.lua_func(function()
    vim.b.celeste_comment_config = { hooks = { pre_commit_edits = function(ctx) ctx.o_use_set_text = true end } }
  end)
  child.bo.filetype = "cpp"
  set_lines({ "begin", "", "", "", "", "", "end" })
  set_cursor(2, 1)
  -- case1:
  feed("v")
  feed("gb")
  eq(get_lines(), { "begin", "/*  */", "", "", "", "", "end" })
  feed("u")
  eq(get_lines(), { "begin", "", "", "", "", "", "end" })

  -- case2:
  set_cursor(2, 1)
  feed("\\<C-v>")
  feed("gb")
  eq(get_lines(), { "begin", "/*  */", "", "", "", "", "end" })
  feed("u")

  -- case3:
  set_cursor(2, 1)
  feed("v", "3j")
  feed("gb")
  eq(get_lines(), { "begin", "/* ", "", "", " */", "", "end" })
  feed("u")
  eq(get_lines(), { "begin", "", "", "", "", "", "end" })

  -- case4:
  set_cursor(2, 1)
  feed("\\<C-v>")
  feed("3j")
  feed("gb")
  eq(get_lines(), { "begin", "/* ", "", "", " */", "", "end" })
  feed("u")
  eq(get_lines(), { "begin", "", "", "", "", "", "end" })
end

T["blockwise"]["multi block cms works"] = function()
  child.bo.filetype = "unknown"
  child.b.celeste_comment_block_commentstring = { "{-%s-}", "{+%s+}" }

  -- gbc add (first pair)
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gbc")
  eq(get_lines(), { "{- hello -}" })

  -- gbc toggle (remove)
  feed("gbc")
  eq(get_lines(), { "hello" })

  -- gb2j multi-line block comment
  set_lines({ "a", "b", "c" })
  set_cursor(1, 0)
  feed("gb", "2j")
  eq(get_lines(), { "{- a", "b", "c -}" })

  -- gbgb textobject toggle on multi-line block
  set_cursor(1, 3)
  feed("gbgb")
  eq(get_lines(), { "a", "b", "c" })

  set_lines({ "{+ a", "b", "c +}" })
  set_cursor(1, 0)
  feed("gbgb")
  eq(get_lines(), { "a", "b", "c" })

  -- gbc using first pair (always the default for adding)
  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gbc")
  eq(get_lines(), { "{- hello -}" })

  -- gbgb toggle on first pair
  set_cursor(1, 3)
  feed("gbgb")
  eq(get_lines(), { "hello" })

  -- gbc toggle on second pair marker detects and removes it
  set_lines({ "{+ hello +}" })
  set_cursor(1, 3)
  feed("gbc")
  eq(get_lines(), { "hello" })

  -- charwise v4lgb inline block comment
  set_lines({ "before hello after" })
  set_cursor(1, 7)
  feed("v", "4l", "gb")
  eq(get_lines(), { "before {- hello -} after" })

  -- gbgb toggle inline block comment
  set_cursor(1, 8)
  feed("gbgb")
  eq(get_lines(), { "before hello after" })

  -- dgb delete multi-line inline block comment
  set_lines({ "x {- a", "b -} y" })
  set_cursor(1, 3)
  feed("dgb")
  eq(get_lines(), { "x  y" })

  -- charwise across two lines
  set_lines({ "a b ", "c d e" })
  set_cursor(1, 2)
  feed("v", "j", "2l", "gb")
  eq(get_lines(), { "a {- b ", "c d e -}" })

  -- two inline blocks, cursor in first
  set_lines({ "{- a -}  {+ b +}" })
  set_cursor(1, 2)
  feed("gbgb")
  eq(get_lines(), { "a  {+ b +}" })

  -- two inline blocks, cursor in second
  set_lines({ "{- a -}  {+ b +}" })
  set_cursor(1, 12)
  feed("gbgb")
  eq(get_lines(), { "{- a -}  b" })

  -- nested different markers, cursor in inner
  set_lines({ "{- a {+ b +} c -}" })
  set_cursor(1, 8)
  feed("gbgb")
  eq(get_lines(), { "{- a b c -}" })

  -- nested, cursor in outer
  set_cursor(1, 3)
  feed("gbgb")
  eq(get_lines(), { "a b c" })

  -- multi-line dgb
  set_lines({ "  {- a", "  b -}  c" })
  set_cursor(1, 5)
  feed("dgb")
  eq(get_lines(), { "    c" })
end

T["blockwise"]["overlapping markers with /*/{}"] = function()
  child.bo.filetype = "unknown"
  -- overlapping markers: {/* (len3) vs /* (len2), */} (len3) vs */ (len2)
  child.b.celeste_comment_block_commentstring = { "{/*%s*/}", "/*%s*/" }

  -- gbgb selects the full {/* ... */} (not the inner /* ... */)
  set_lines({ "x = {/* aaa */}" })
  set_cursor(1, 7)
  feed("gbgb")
  eq(get_lines(), { "x = aaa" })

  -- two inline blocks, cursor in the first ({/* */})
  set_lines({ "{/* aaa */}  /* bbb */" })
  set_cursor(1, 4)
  feed("gbgb")
  eq(get_lines(), { "aaa  /* bbb */" })

  -- two inline blocks, cursor in the second (/* */)
  set_lines({ "{/* aaa */}  /* bbb */" })
  set_cursor(1, 15)
  feed("gbgb")
  eq(get_lines(), { "{/* aaa */}  bbb" })
end

T["blockwise"]["overlapping markers with {{/{{{"] = function()
  child.bo.filetype = "unknown"
  child.b.celeste_comment_block_commentstring = { "{{%s}}", "{{{%s}}}" }

  -- gbgb on {{{ a }}} → selects the outer pair (longer opener wins)
  set_lines({ "{{{ a }}}" })
  set_cursor(1, 3)
  feed("gbgb")
  eq(get_lines(), { "a" })

  -- gbgb on {{ a }} → only the shorter pair matches
  set_lines({ "{{ a }}" })
  set_cursor(1, 2)
  feed("gbgb")
  eq(get_lines(), { "a" })

  -- two inline blocks, cursor in the first ({{{}}})
  set_lines({ "{{{ a }}}  {{ b }}" })
  set_cursor(1, 3)
  feed("gbgb")
  eq(get_lines(), { "a  {{ b }}" })

  -- two inline blocks, cursor in the second ({{}})
  set_lines({ "{{{ a }}}  {{ b }}" })
  set_cursor(1, 12)
  feed("gbgb")
  eq(get_lines(), { "{{{ a }}}  b" })
end

-- block_relaxed_detect tests ──────────────────────────────────────────────────

T["block_relaxed_detect"] = new_set({
  hooks = {
    pre_case = function() child.b.celeste_comment_config = { block_relaxed_detect = true } end,
  },
})

T["block_relaxed_detect"]["works"] = function()
  child.bo.filetype = "cpp"
  set_lines({
    "   \t\t\t   \t\t\t    ",
    "             ",
    "\t\t               \t",
    "              /*\t\t\t\t    z",
    "       \t\t   b   ",
    "    h    ",
    "a",
    "\t*/    ",
    "                         \t\t\t",
  })
  selection(1, 0, 4, 13)
  feed("gb")
  eq(get_lines(), {
    "/*    \t\t\t   \t\t\t    ",
    "             ",
    "\t\t               \t",
    "               *//*\t\t\t\t    z",
    "       \t\t   b   ",
    "    h    ",
    "a",
    "\t*/    ",
    "                         \t\t\t",
  })
  eq(get_cursor(), { 4, 13 })
  feed("u")

  selection(1, 6, 5, 0)
  feed("gb")
  eq(get_lines(), {
    "   \t\t\t/*    \t\t\t    ",
    "             ",
    "\t\t               \t",
    "              /*\t\t\t\t    z",
    "  */      \t\t   b   ",
    "    h    ",
    "a",
    "\t*/    ",
    "                         \t\t\t",
  })
  eq(get_cursor(), { 5, 0 })
  feed("u")

  selection(2, 3, 9, 7)
  feed("gb")
  eq(get_lines(), {
    "   \t\t\t   \t\t\t    ",
    "             ",
    "\t\t               \t",
    "              \t\t\t\t    z",
    "       \t\t   b   ",
    "    h    ",
    "a",
    "\t    ",
    "                         \t\t\t",
  })
  eq(get_cursor(), { 9, 7 })
end

T["block_relaxed_detect"]["bugfix for gbip"] = function()
  child.bo.filetype = "lua"
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.b.celeste_comment_config = { block_relaxed_detect = true }
  set_lines({
    "function test()",
    "",
    '  map("n", ".", "xxx", {})',
    '  map("n", ".", "yyy", {})',
    "",
    "end",
  })
  set_cursor(3, 3)
  feed("gbip")
  eq(get_cursor(), { 3, 8 })
  eq(get_lines(), {
    "function test()",
    "",
    '  --[[ map("n", ".", "xxx", {})',
    '  map("n", ".", "yyy", {}) ]]',
    "",
    "end",
  })

  feed(".")
  eq(get_cursor(), { 3, 3 })
  eq(get_lines(), {
    "function test()",
    "",
    '  map("n", ".", "xxx", {})',
    '  map("n", ".", "yyy", {})',
    "",
    "end",
  })
end

-- textobject tests ───────────────────────────────────────────────────────────

T["textobject"] = new_set()

T["textobject"]["block_match_pairs"] = function()
  local mp = H.textobject_block_match_pairs
  local c = function(lcs, rcs) return H.make_csi({ { lcs, rcs } }) end
  -- Single pair → 1 result
  local r = mp({ "/* a */" }, 1, c("/* ", " */"), make_pos(0, 0, 3))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 6)

  -- No pair
  eq(#mp({ "hello" }, 1, c("/* ", " */"), make_pos(0, 0, 1)), 0)

  -- Cursor between two blocks → no pair
  eq(#mp({ "/* a */ code /* b */" }, 1, c("/* ", " */"), make_pos(0, 0, 10)), 0)

  -- Orphan rcs
  eq(#mp({ "hello */ world" }, 1, c("/* ", " */"), make_pos(0, 0, 1)), 0)

  -- Three levels, cursor at innermost → 3 pairs, innermost first
  r = mp({ "/* a /* b /* c */ d */ e */" }, 1, c("/* ", " */"), make_pos(0, 0, 11))
  eq(#r, 3)
  eq(r[1][2], 10)
  eq(r[1][4], 16) -- innermost: /* c */
  eq(r[2][2], 5)
  eq(r[2][4], 21) -- middle: /* b /* c */ d */
  eq(r[3][2], 0)
  eq(r[3][4], 26) -- outermost: /* a /* b /* c */ d */ e */

  -- Three levels, cursor at outermost → 1 pair (outermost only)
  r = mp({ "/* a /* b /* c */ d */ e */" }, 1, c("/* ", " */"), make_pos(0, 0, 0))
  eq(#r, 1)
  eq(r[1][2], 0)
  eq(r[1][4], 26)

  -- Three levels, cursor in middle → 2 pairs (middle + outer)
  r = mp({ "/* a /* b /* c */ d */ e */" }, 1, c("/* ", " */"), make_pos(0, 0, 7))
  eq(#r, 2)
  eq(r[1][2], 5)
  eq(r[1][4], 21) -- middle
  eq(r[2][2], 0)
  eq(r[2][4], 26) -- outermost

  -- Cross-line nested
  r = mp({ "/* a", "/* b */", "c */" }, 1, c("/* ", " */"), make_pos(0, 1, 3))
  eq(#r, 2)
  eq(r[1][1], 2)
  eq(r[1][2], 0)
  eq(r[1][3], 2)
  eq(r[1][4], 6) -- innermost: /* b */
  eq(r[2][1], 1)
  eq(r[2][2], 0)
  eq(r[2][3], 3)
  eq(r[2][4], 3) -- outermost

  -- Lua --[[ ]] style
  r = mp({ "--[[ a ", "  b ]] " }, 1, c("--[[ ", " ]]"), make_pos(0, 1, 3))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 2)
  eq(r[1][4], 5)
end

T["textobject"]["block_match_pairs multi block cms"] = function()
  local mp = H.textobject_block_match_pairs
  local csi = H.make_csi({ { "{-", "-}" }, { "{#", "#}" } })
  local pos = H.make_pos

  -- single line, pair 1
  local r = mp({ "{- hello -}" }, 1, csi, pos(0, 0, 3))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 10)

  -- single line, pair 2
  r = mp({ "{# hello #}" }, 1, csi, pos(0, 0, 3))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 10)

  -- multi line, pair 1 spans two lines
  r = mp({ "{- a", "b -}" }, 1, csi, pos(0, 1, 1))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 2)
  eq(r[1][4], 3)

  -- two inline blocks on one line, cursor in first
  r = mp({ "{- a -} code {# b #}" }, 1, csi, pos(0, 0, 2))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 6)

  -- two inline blocks on one line, cursor in second
  r = mp({ "{- a -} code {# b #}" }, 1, csi, pos(0, 0, 14))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 13)
  eq(r[1][3], 1)
  eq(r[1][4], 19)

  -- nested both markers, cursor in outer pair
  r = mp({ "{- a {# b #} c -}" }, 1, csi, pos(0, 0, 2))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 16)

  -- nested both markers, cursor in inner pair
  r = mp({ "{- a {# b #} c -}" }, 1, csi, pos(0, 0, 8))
  eq(#r, 2)
  eq(r[1][1], 1)
  eq(r[1][2], 5)
  eq(r[1][3], 1)
  eq(r[1][4], 11)
  eq(r[2][1], 1)
  eq(r[2][2], 0)
  eq(r[2][3], 1)
  eq(r[2][4], 16)

  -- cursor between two blocks, no match
  r = mp({ "{- a -}  {# b #}" }, 1, csi, pos(0, 0, 7))
  eq(r, {})

  -- no match
  r = mp({ "hello" }, 1, csi, pos(0, 0, 1))
  eq(r, {})
end

T["textobject"]["block_match_pairs overlapping markers"] = function()
  local mp = H.textobject_block_match_pairs
  local pos = H.make_pos
  local csi = H.make_csi({ { "{/*", "*/}" }, { "/*", "*/" } })

  -- Single line, cursor inside → both match, outer first
  local r = mp({ "{/* aaa */}" }, 1, csi, pos(0, 0, 5))
  eq(#r, 2)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 10)
  eq(r[2][1], 1)
  eq(r[2][2], 1)
  eq(r[2][3], 1)
  eq(r[2][4], 9)

  -- Standalone /* */ → only the inner pair matches
  r = mp({ "/* bbb */" }, 1, csi, pos(0, 0, 5))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 8)

  -- Two blocks inline, cursor in the second
  r = mp({ "{/* aaa */}  /* bbb */" }, 1, csi, pos(0, 0, 15))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 13)
  eq(r[1][3], 1)
  eq(r[1][4], 21)

  -- Two blocks inline, cursor in the first → outer first
  r = mp({ "{/* aaa */}  /* bbb */" }, 1, csi, pos(0, 0, 5))
  eq(#r, 2)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 1)
  eq(r[1][4], 10)
  eq(r[2][1], 1)
  eq(r[2][2], 1)
  eq(r[2][3], 1)
  eq(r[2][4], 9)

  -- Multi-line {/*  */}, cursor on first line → outer first
  r = mp({ "{/* aaa", "bbb */}" }, 1, csi, pos(0, 0, 5))
  eq(#r, 2)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 2)
  eq(r[1][4], 6)
  eq(r[2][1], 1)
  eq(r[2][2], 1)
  eq(r[2][3], 2)
  eq(r[2][4], 5)

  -- Multi-line standalone /* */ → only inner pair matches
  r = mp({ "/* bbb", "ccc */" }, 1, csi, pos(0, 1, 3))
  eq(#r, 1)
  eq(r[1][1], 1)
  eq(r[1][2], 0)
  eq(r[1][3], 2)
  eq(r[1][4], 5)
end

T["textobject"]["line textobject works"] = function()
  set_lines({ "aa", "#bb", "# cc", "dd", "#ee", "#ff" })
  set_cursor(2, 2)
  feed("d", "gc")
  eq(get_lines(), { "aa", "dd", "#ee", "#ff" })

  set_cursor(4, 0)
  feed(".")
  eq(get_lines(), { "aa", "dd" })

  set_cursor(1, 0)
  feed(".")
  eq(get_lines(), { "aa", "dd" })
end

T["textobject"]["block textobject works"] = function()
  child.b.celeste_comment_block_commentstring = "--[[%s]]"
  set_lines({ "aaa", "--[[bbb]] ccc --[[ddd  ]] eeee", "ffff --[[ggg   ", "", "hh", "ii ]] jjj" })
  set_cursor(2, 14)
  feed("d", "gb")
  eq(get_lines(), { "aaa", "--[[bbb]] ccc  eeee", "ffff --[[ggg   ", "", "hh", "ii ]] jjj" })

  set_cursor(3, 6)
  feed(".")
  eq(get_lines(), { "aaa", "--[[bbb]] ccc  eeee", "ffff  jjj" })

  set_cursor(2, 9)
  feed(".")
  eq(get_lines(), { "aaa", "--[[bbb]] ccc  eeee", "ffff  jjj" }) -- do nothing
end

-- Referenced from: https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L797
T["textobject"]["respect tree-sitter injections"] = function()
  child.lua_func(function()
    vim.bo.filetype = "vim"
    vim.treesitter.start()
  end)
  set_lines({
    '"set background=dark',
    '"set termguicolors',
    "lua << EOF",
    "-- print(1)",
    "-- print(2)",
    "EOF",
  })
  set_cursor(1, 0)
  feed("dgc")
  eq(get_lines(), {
    "lua << EOF",
    "-- print(1)",
    "-- print(2)",
    "EOF",
  })

  set_cursor(2, 0)
  feed(".")
  eq(get_lines(), {
    "lua << EOF",
    "EOF",
  })
end

T["textobject"]["auto_linewise_detect"] = function()
  set_lines({ "aaa", "# bbb", "# ccc", "# ddd", "eee" })
  set_cursor(2, 3)
  feed("v", "ga")
  eq(get_cursor(), { 4, 3 })
  feed("gc")
  eq(get_cursor(), { 4, 1 })
  eq(get_lines(), { "aaa", "bbb", "ccc", "ddd", "eee" })
  feed("u")
  eq(get_lines(), { "aaa", "# bbb", "# ccc", "# ddd", "eee" })
  feed("dga")
  eq(get_lines(), { "aaa", "eee" })
end

T["textobject"]["auto_linewise_detect with ignore_empty_lines=always"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  set_lines({ " \t", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" })
  set_cursor(4, 0)
  feed("vgad")
  eq(get_cursor(), { 4, 0 })
  eq(get_lines(), { " \t", "# aaa", "\t \t ", "", "   ", "#bbb", "\t\t\t" })
  feed("u")
  eq(get_lines(), { " \t", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" })

  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_cursor(5, 1)
  feed("vgad")
  eq(get_cursor(), { 5, 1 })
  eq(get_lines(), { " \t", "# aaa", "\t \t ", " ", "  ", "#bbb", "\t\t\t" })
  feed("u")
  eq(get_lines(), { " \t", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" })

  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_cursor(5, 2)
  feed("vgad")
  eq(get_lines(), { " \t", "\t\t\t" })
  eq(get_cursor(), { 2, 0 })
  feed("u")
  eq(get_lines(), { " \t", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" })
  set_cursor(1, 1)
  feed("vgad")
  eq(get_lines(), { " ", "# aaa", "\t \t ", " ", "   ", "#bbb", "\t\t\t" })
  eq(get_cursor(), { 1, 0 })
end

T["textobject"]["auto_blockwise_detect"] = function()
  child.bo.filetype = "cpp"
  set_lines({ "start", "/* comment", "\t\t", " \t", "block */", "end" })
  set_cursor(3, 2)
  feed("v", "ga")
  eq(get_cursor(), { 5, 7 })
  feed("gb")
  eq(get_cursor(), { 5, 4 })
  eq(get_lines(), { "start", "comment", "\t\t", " \t", "block", "end" })
  feed("u")
  eq(get_lines(), { "start", "/* comment", "\t\t", " \t", "block */", "end" })
  feed("dga")
  eq(get_lines(), { "start", "", "end" })
end

T["textobject"]["nested linewise and blockwise comment auto detect"] = function()
  child.bo.filetype = "cpp"
  child.bo.tabstop = 2
  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_lines({
    "  aaa",
    "  /* bbb",
    "  \t\t\t\t\t\t\t\t",
    "  // cc",
    "  // dd",
    "\t\t\t\t\t\t\t\t\t",
    "  // ee",
    "",
    "   */",
  })
  set_cursor(6, 6)
  feed("vga")
  eq(get_cursor(), { 7, 7 })
  feed("d")
  eq(get_lines(), {
    "  aaa",
    "  /* bbb",
    "  \t\t\t\t\t\t\t\t",
    "",
    "   */",
  })

  feed("u")
  set_cursor(6, 6)
  feed("gcu")
  eq(get_lines(), {
    "  aaa",
    "  /* bbb",
    "  \t\t\t\t\t\t\t\t",
    "  cc",
    "  dd",
    "\t\t\t\t\t\t\t\t\t",
    "  ee",
    "",
    "   */",
  })
  eq(get_cursor(), { 6, 6 })
  feed("gcu")
  eq(get_lines(), {
    "  aaa",
    "  bbb",
    "  \t\t\t\t\t\t\t\t",
    "  cc",
    "  dd",
    "\t\t\t\t\t\t\t\t\t",
    "  ee",
    "",
    "  ",
  })
  eq(get_cursor(), { 6, 6 })
end

T["textobject"]["auto_uncomment_do_nothing"] = function()
  set_lines({ "aaa", "bbb", "ccc" })
  set_cursor(2, 1)
  feed("gcu")
  eq(get_lines(), { "aaa", "bbb", "ccc" })
  eq(get_cursor(), { 2, 1 })

  set_lines({ "aaa", "", "ccc" })
  set_cursor(2, 0)
  feed("gcu")
  eq(get_lines(), { "aaa", "", "ccc" })
  eq(get_cursor(), { 2, 0 })

  child.bo.filetype = "unknown"
  child.bo.commentstring = ""
  child.b.celeste_comment_block_commentstring = "--%s--"
  set_lines({ "--1-- 2 -- 3 --" })

  set_cursor(1, 5)
  feed("gcu")
  eq(get_cursor(), { 1, 5 })
  eq(get_lines(), { "--1-- 2 -- 3 --" })

  set_cursor(1, 6)
  feed("gcu")
  eq(get_cursor(), { 1, 6 })
  eq(get_lines(), { "--1-- 2 -- 3 --" })

  set_cursor(1, 7)
  feed("gcu")
  eq(get_cursor(), { 1, 7 })
  eq(get_lines(), { "--1-- 2 -- 3 --" })

  set_cursor(1, 8)
  feed("gcu")
  eq(get_cursor(), { 1, 8 })
  eq(get_lines(), { "--1-- 2 3" })

  set_cursor(1, 4)
  feed("gcu")
  eq(get_cursor(), { 1, 1 })
  eq(get_lines(), { "1 2 3" })

  child.bo.filetype = "unknown"
  child.bo.commentstring = ""
  set_lines({ "aaa", "# bbb", "ccc" })
  set_cursor(2, 1)
  feed("gcu")
  eq(get_lines(), { "aaa", "# bbb", "ccc" })
  eq(get_cursor(), { 2, 1 })
end

T["textobject"]["gcu respect ignore_empty_lines"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_lines({ "aaa", "# bbb", "# ccc", " ", "# eee" })
  set_cursor(2, 1)
  feed("gcu")
  eq(get_lines(), { "aaa", "bbb", "ccc", " ", "eee" })
  eq(get_cursor(), { 2, 0 })

  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  feed("u")
  set_cursor(2, 1)
  feed("gcu")
  eq(get_lines(), { "aaa", "bbb", "ccc", " ", "# eee" })
  eq(get_cursor(), { 2, 0 })

  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  feed("u")
  set_cursor(2, 1)
  feed("gcu")
  eq(get_lines(), { "aaa", "bbb", "ccc", " ", "# eee" })
  eq(get_cursor(), { 2, 0 })
end

T["textobject"]["gcu special case1"] = function()
  child.bo.filetype = "lua"
  child.lua_func(
    function()
      vim.b.celeste_comment_config = {
        cms_confs = { lua = { { "--%s", "---%s", "--[[%s]]" }, "--[[%s]]" } },
      }
    end
  )
  set_lines({
    "--[[aaa]]",
    "---@param xx",
    "-- test",
  })
  set_cursor(3, 4)
  feed("gcu")
  eq(get_cursor(), { 3, 1 })
  eq(get_lines(), {
    "aaa",
    "@param xx",
    "test",
  })
end

T["textobject"]["gcu special case2 : block lcs startswith line lcs"] = function()
  child.bo.filetype = "lua"
  child.bo.tabstop = 2
  child.lua_func(
    function()
      vim.b.celeste_comment_config = {
        cms_confs = { lua = { { "--%s" }, "--[[%s]]" } },
      }
    end
  )
  set_lines({
    "  hello",
    "  world",
  })
  set_cursor(1, 2)
  feed("gbj")
  eq(get_cursor(), { 1, 7 })
  eq(get_lines(), {
    "  --[[ hello",
    "  world ]]",
  })
  feed("gcu")
  eq(get_cursor(), { 1, 2 })
  eq(get_lines(), {
    "  hello",
    "  world",
  })
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
  child.lua_func(function()
    vim.bo.filetype = "cpp"
    vim.bo.tabstop = 2
    vim.bo.expandtab = true
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
    vim.b.celeste_comment_config = { textobj_treesitter_detect = true }
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
  eq(ts_comment_at_cursor({ 2, 13 }), vim.NIL)
  eq(ts_comment_at_cursor({ 4, 1 }), vim.NIL)
  eq(ts_comment_at_cursor({ 4, 2 }), { 3, 2, 5, 4 })
  eq(ts_comment_at_cursor({ 6, 4 }), { 3, 2, 5, 4 })
  eq(ts_comment_at_cursor({ 6, 5 }), vim.NIL)
  eq(ts_comment_at_cursor({ 8, 2 }), { 7, 2, 7, 16 })

  set_cursor(2, 13)
  feed("gbgb")
  eq(get_cursor(), { 2, 13 })
  eq(get_lines(2, 2), { '  printf("/* hello, world */");' })

  set_cursor(4, 2)
  feed(".")
  eq(get_lines(), {
    "int func() {",
    '  printf("/* hello, world */");',
    "",
    "  this is a test ...........",
    "     really a test ............",
    "    ",
    "",
    "  // hello world!",
    "}",
  })

  set_cursor(8, 2)
  feed("gcgc")
  eq(get_cursor(), { 8, 2 })
  eq(get_lines(8, 8), { "  hello world!" })
end

T["textobject treesitter"]["works in markdown"] = function()
  child.lua_func(function()
    vim.bo.filetype = "markdown"
    vim.bo.tabstop = 2
    vim.bo.expandtab = true
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("markdown")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
    vim.b.celeste_comment_config = { textobj_treesitter_detect = true }
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
  eq(ts_comment_at_cursor({ 1, 0 }), vim.NIL)
  eq(ts_comment_at_cursor({ 9, 0 }), { 8, 0, 8, 11 })
  eq(ts_comment_at_cursor({ 3, 7 }), vim.NIL)
  eq(ts_comment_at_cursor({ 3, 8 }), vim.NIL)
  eq(ts_comment_at_cursor({ 4, 0 }), { 3, 0, 5, 2 })
  eq(ts_comment_at_cursor({ 7, 1 }), { 6, 1, 6, 6 })

  set_cursor(9, 0)
  feed("gcu")
  eq(get_cursor(), { 9, 0 })
  eq(get_lines(9, 9), { "aaa" })

  set_cursor(7, 4)
  feed("gcu")
  eq(get_cursor(), { 7, 1 })
  eq(get_lines(7, 7), { " 123" })
  set_cursor(5, 3)
  feed("gcu")
  eq(get_cursor(), { 5, 3 })
  eq(get_lines(4, 6), {
    "hello",
    "   world",
    "",
  })
  set_cursor(3, 8)
  feed("gcu")
  eq(get_cursor(), { 3, 8 })
  eq(get_lines(3, 3), { 'printf("/*hello world*/!");' })
end

T["textobject treesitter"]["fallback to text match impl while no query"] = function()
  child.bo.filetype = "cpp"
  child.bo.tabstop = 2
  child.bo.expandtab = true
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
  set_cursor(2, 10)
  feed("gcu")
  eq(get_cursor(), { 2, 10 })
  eq(get_lines(2, 2), { '  printf("hello, world");' })
end

T["textobject treesitter"]["fallback to text match impl while disable textobj_treesitter_detect"] = function()
  child.lua_func(function()
    vim.bo.filetype = "cpp"
    vim.bo.tabstop = 2
    vim.bo.expandtab = true
    vim.cmd("packadd nvim-treesitter-textobjects")
    vim.treesitter.language.add("cpp")
    vim.treesitter.start()
  end)
  child.b.celeste_comment_config = { textobj_treesitter_detect = true }
  set_lines({ "// hello /* world */" })
  set_cursor(1, 9)
  feed("gbgb")
  eq(get_cursor(), { 1, 9 })
  eq(get_lines(), { "// hello /* world */" })

  child.b.celeste_comment_config = { textobj_treesitter_detect = false }
  feed("gbgb")
  eq(get_lines(), { "// hello world" })
end

-- keep cursor tests ──────────────────────────────────────────────────────────

T["keep_cursor"] = new_set()

T["keep_cursor"]["gcc comment/uncomment restore cursor"] = function()
  set_lines({ "aaa", "  bbbb", "ccc" })
  set_cursor(2, 2)
  feed("gcc")
  eq(get_cursor(), { 2, 4 })
  eq(get_lines(), { "aaa", "#   bbbb", "ccc" })
  feed("gcc")
  eq(get_lines(), { "aaa", "  bbbb", "ccc" })
  eq(get_cursor(), { 2, 2 })
end

T["keep_cursor"]["gcc uncomment special, match vscode's NeverGroupAtTypeEdge"] = function()
  child.bo.filetype = "lua"
  set_lines({ "  -- print('here')" })
  set_cursor(1, 2)
  feed("gcc")
  eq(get_lines(), { "  print('here')" })
  eq(get_cursor(), { 1, 2 })

  set_lines({ "  -- print('here')" })
  set_cursor(1, 3)
  feed("gcc")
  eq(get_lines(), { "  print('here')" })
  eq(get_cursor(), { 1, 2 })

  set_lines({ "  -- print('here')" })
  set_cursor(1, 3)
  feed("gcc")
  eq(get_lines(), { "  print('here')" })
  eq(get_cursor(), { 1, 2 })

  set_lines({ "  -- print('here')" })
  set_cursor(1, 4)
  feed("gcc")
  eq(get_lines(), { "  print('here')" })
  eq(get_cursor(), { 1, 2 })
end

T["keep_cursor"]["gcc keep_cursor=false not restore cursor"] = function()
  child.b.celeste_comment_config = { keep_cursor = false }
  set_lines({ "aaa", "bbbb", "ccc" })
  set_cursor(2, 2)
  feed("gcc")
  eq(get_cursor(), { 2, 0 })
  eq(get_lines(), { "aaa", "# bbbb", "ccc" })
  feed("gcc")
  eq(get_lines(), { "aaa", "bbbb", "ccc" })
  eq(get_cursor(), { 2, 0 })
end

T["keep_cursor"]["visual-line mode gc restore cursor"] = function()
  set_lines({ "aaaaa", "bbbb", "ccc" })
  set_cursor(1, 2)
  feed("V", "j")
  eq(get_cursor(), { 2, 2 })
  feed("gc")
  eq(get_cursor(), { 2, 4 })
  eq(get_lines(), { "# aaaaa", "# bbbb", "ccc" })
end

T["keep_cursor"]["visual mode gb restore cursor"] = function()
  child.bo.filetype = "cpp"
  set_lines({ "aaaaa", "bbbb", "ccc" })
  set_cursor(1, 2)
  feed("v", "j", "l")
  eq(get_cursor(), { 2, 3 })
  feed("gb")
  eq(get_cursor(), { 2, 3 })
  eq(get_lines(), { "aa/* aaa", "bbbb */", "ccc" })
end

T["keep_cursor"]["C-v mode gb restore cursor"] = function()
  child.bo.filetype = "cpp"
  --
  set_lines({ "aaaaaa", "bbbbbbb", "cccccccc" })
  set_cursor(1, 3)
  feed("\\<C-v>", "2j")
  eq(get_cursor(), { 3, 3 })
  feed("gb")
  eq(get_cursor(), { 3, 3 })
  eq(get_lines(), { "/* aaaaaa", "bbbbbbb", "cccccccc */" })
end

T["keep_cursor"]["gcc cursor before offset no shift"] = function()
  set_lines({ "  hello" })
  set_cursor(1, 1)
  feed("gcc")
  eq(get_cursor(), { 1, 3 })
  eq(get_lines(), { "#   hello" })
end

T["keep_cursor"]["gbc comment/uncomment restore cursor"] = function()
  child.bo.filetype = "cpp"
  set_lines({ "hello" })
  set_cursor(1, 2)
  feed("gbc")
  eq(get_cursor(), { 1, 5 })
  eq(get_lines(), { "/* hello */" })
  feed("gbc")
  eq(get_cursor(), { 1, 2 })
  eq(get_lines(), { "hello" })
end

T["keep_cursor"]["gbgb uncomment restore cursor"] = function()
  child.bo.filetype = "cpp"
  set_lines({ "/* hello */" })
  set_cursor(1, 7)
  feed("gbgb")
  eq(get_cursor(), { 1, 4 })
  eq(get_lines(), { "hello" })
end

T["keep_cursor"]["gc2j restore cursor"] = function()
  set_lines({ "aaaa", "bbbb", "cccc" })
  set_cursor(1, 2)
  feed("gc", "2j")
  eq(get_cursor(), { 1, 4 })
  eq(get_lines(), { "# aaaa", "# bbbb", "# cccc" })
end

T["keep_cursor"]["gbiw restore cursor"] = function()
  child.b.celeste_comment_block_commentstring = "!@#%s#@!"
  set_lines({ "aaaa bbb cccc" })
  set_cursor(1, 6)
  feed("gbiw")
  eq(get_lines(), { "aaaa !@# bbb #@! cccc" })
  eq(get_cursor(), { 1, 10 })
end

T["keep_cursor"]["dot-repeat works"] = function()
  child.bo.tabstop = 2
  child.b.celeste_comment_block_commentstring = "!@#%s#@!"
  set_lines({
    "  hello",
    "  world",
  })
  set_cursor(1, 4)
  feed("gcc")
  eq(get_cursor(), { 1, 6 })
  eq(get_lines(), {
    "  # hello",
    "  world",
  })
  feed(".")
  eq(get_cursor(), { 1, 4 })
  eq(get_lines(), {
    "  hello",
    "  world",
  })
  set_cursor(2, 5)
  feed(".")
  eq(get_cursor(), { 2, 7 })
  eq(get_lines(), {
    "  hello",
    "  # world",
  })
  feed(".")
  eq(get_cursor(), { 2, 5 })
  eq(get_lines(), {
    "  hello",
    "  world",
  })

  set_cursor(1, 5)
  feed("gbip")
  eq(get_cursor(), { 1, 9 })
  eq(get_lines(), {
    "  !@# hello",
    "  world #@!",
  })
  feed(".")
  eq(get_cursor(), { 1, 5 })
  eq(get_lines(), {
    "  hello",
    "  world",
  })
end

-- PreCommitEdits tests ───────────────────────────────────────────────────────

T["pre_commit_edits"] = new_set()

T["pre_commit_edits"]["multi_line edit with pre_commit_edits restores cursor"] = function()
  child.bo.filetype = "cpp"
  child.lua_func(function()
    vim.b.celeste_comment_config = {
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
  end)
  set_lines({ "  aaa", "  bbb", "  ccc" })
  set_cursor(1, 2)
  feed("gb", "2j")
  eq(get_cursor(), { 2, 2 })
end

T["pre_commit_edits"]["multi_line edit keep_cursor=false does not restore cursor"] = function()
  child.bo.filetype = "cpp"
  child.lua_func(function()
    vim.b.celeste_comment_config = {
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
  end)
  set_lines({ "aaa", "bbb", "ccc" })
  set_cursor(1, 0)
  feed("gb", "j")
  eq(get_cursor(), { 1, 0 })
end

T["pre_commit_edits"]["pre_commit_edits above/below lines"] = function()
  child.bo.filetype = "cpp"
  child.lua_func(function()
    vim.b.celeste_comment_config = {
      hooks = {
        pre_commit_edits = function(ctx)
          if ctx.ctype ~= 2 then return end
          local lines = ctx.lines
          local l1, ln = lines[1], lines[#lines]
          local e = ctx.edits
          e[1] = { range = { e[1].range[1], 0, e[1].range[1], #l1 }, text = { (l1:match("^(%s*)") or "") .. "/*", l1 } }
          e[2] = { range = { e[2].range[1], 0, e[2].range[1], #ln }, text = { ln, (ln:match("^(%s*)") or "") .. "*/" } }
          e.any_multi = true
          ctx.o_use_set_text = true
        end,
      },
    }
  end)
  set_lines({ "  void f() {", "    int a;", "  }" })
  set_cursor(1, 0)
  feed("3gbc")
  eq(get_lines(), { "  /*", "  void f() {", "    int a;", "  }", "  */" })
end

T["pre_commit_edits"]["pre_commit_edits edge: last line selection"] = function()
  child.bo.filetype = "cpp"
  child.lua_func(function()
    vim.b.celeste_comment_config = {
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
  end)
  set_lines({ "line1", "line2" })
  set_cursor(2, 0)
  feed("gbc")
  eq(get_lines(), { "line1", "/*", "line2", "*/" })
end

T["pre_commit_edits"]["out of range fallback to set lines"] = function()
  child.lua_func(function()
    vim.b.celeste_comment_config = {
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
  end)
  set_lines({ "aaa", "bbb" })
  set_cursor(1, 0)
  feed("gcj")
  eq(get_lines(), { "# aaa", "# bbb", "ccc" })
end

-- treesitter tests ───────────────────────────────────────────────────────────

T["treesitter"] = new_set()

T["treesitter"]["gcc/gbc respects injected languages in vim heredoc"] = function()
  set_lines({
    "set background=dark",
    "lua << EOF",
    "  print(1)",
    "  vim.cmd('set bg=light')",
    "EOF",
    "set nocursorline",
  })
  child.bo.tabstop = 2
  child.bo.filetype = "vim"
  child.treesitter.start()

  set_cursor(3, 2)
  feed("gcc")
  eq(get_lines(3, 3), { "  -- print(1)" })
  eq(get_cursor(), { 3, 5 })

  set_cursor(2, 0)
  feed(".")
  eq(get_lines(2, 2), { '" lua << EOF' })
  feed(".")

  set_cursor(6, 0)
  feed(".")
  eq(get_lines(6, 6), { '" set nocursorline' })
  feed(".")

  set_cursor(3, 5)
  feed(".")
  eq(get_lines(3, 3), { "  print(1)" })
  eq(get_cursor(), { 3, 2 })

  feed("gbc")
  eq(get_lines(3, 3), { "  --[[ print(1) ]]" })
  eq(get_cursor(), { 3, 7 })
  feed(".")
  eq(get_lines(3, 3), { "  print(1)" })
  eq(get_cursor(), { 3, 2 })

  set_cursor(1, 4)
  feed(".")
  eq(get_lines(1, 1), { "set background=dark" }) -- do nothing, vim does not have block comment string
end

T["treesitter"]["gco/gcO/gcA respect injected languages"] = function()
  set_lines({
    "set bg=dark",
    "lua << EOF",
    "  print(1)",
    "EOF",
    "set nocursorline",
  })
  child.bo.filetype = "vim"
  child.treesitter.start()

  set_cursor(3, 2)
  feed("gco")
  eq(get_cursor(), { 4, 5 })
  eq(get_lines(4, 4), { "  -- " })
  feed("<Esc>", "u")

  set_cursor(3, 2)
  feed("gcA")
  eq(get_cursor(), { 3, 14 })
  eq(get_lines(3, 3), { "  print(1) -- " })
  feed("<Esc>", "u")

  set_cursor(3, 2)
  feed("gcO")
  eq(get_cursor(), { 3, 3 })
  eq(get_lines(3, 3), { "-- " })
  feed("<Esc>", "u")

  set_cursor(1, 0)
  feed("gcO")
  eq(get_cursor(), { 1, 2 })
  eq(get_lines(1, 1), { '" ' })
  feed("<Esc>", "u")

  set_cursor(5, 0)
  feed("gco")
  eq(get_cursor(), { 6, 2 })
  eq(get_lines(6, 6), { '" ' })
  feed("<Esc>", "u")

  set_cursor(5, 0)
  feed("gcA")
  eq(get_cursor(), { 5, 19 })
  eq(get_lines(5, 5), { 'set nocursorline " ' })
  feed("<Esc>", "u")
end

T["treesitter"]["handles mismatch between parser name and filetype"] = function()
  child.lua_func(function()
    vim.bo.filetype = "celeste_test_filetype"
    vim.bo.commentstring = ""
    vim.treesitter.language.add("c")
    vim.treesitter.language.register("c", { "celeste_test_filetype" })
    vim.b.celeste_comment_config = { cms_confs = false }
  end)
  eq(child.lua_get([[ vim.treesitter.language.get_filetypes("c") ]]), { "c", "celeste_test_filetype" })

  set_lines({ "hello" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "hello" })

  child.lua_func(function() vim.treesitter.start() end)

  feed(".")
  eq(get_lines(), { "// hello" })
  eq(get_cursor(), { 1, 3 })
  eq(child.bo.commentstring, "")
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L592
T["treesitter"]["respects tree-sitter commentstring metadata : nvim-like builtin resolver"] = function()
  child.lua_func(function()
    vim.treesitter.query.set(
      "vim",
      "highlights",
      [[
        ((list) @_list (#set! @_list bo.commentstring "!! %s"))
      ]]
    )
    vim.bo.tabstop = 2
    vim.bo.filetype = "vim"
    vim.treesitter.start()
    vim.b.celeste_comment_config = { cms_confs = false }
  end)

  set_lines({
    "set background=dark",
    "let mylist = [",
    [[  \"a",]],
    [[  \"b",]],
    [[  \"c",]],
    "  \\]",
  })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), {
    '" set background=dark',
    "let mylist = [",
    [[  \"a",]],
    [[  \"b",]],
    [[  \"c",]],
    "  \\]",
  })
  eq(get_cursor(), { 1, 2 })

  -- should work with dot-repeat
  set_cursor(4, 0)
  feed(".")
  eq(get_lines(), {
    '" set background=dark',
    "let mylist = [",
    [[  \"a",]],
    [[  !! \"b",]],
    [[  \"c",]],
    "  \\]",
  })
  eq(get_cursor(), { 4, 0 })
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L630
T["treesitter"]["only applies the innermost tree-sitter commentstring metadata : nvim-like builtin resolver"] = function()
  child.lua_func(function()
    vim.treesitter.query.set(
      "vim",
      "highlights",
      [[
          ((list) @_list (#gsub! @_list "(.*)" "%1") (#set! bo.commentstring "!! %s"))
          ((script_file) @_src (#set! @_src bo.commentstring "## %s"))
      ]]
    )
    vim.bo.tabstop = 2
    vim.bo.filetype = "vim"
    vim.treesitter.start()
    vim.b.celeste_comment_config = { cms_confs = false }
  end)

  set_lines({
    "set background=dark",
    "let mylist = [",
    [[  \"a",]],
    [[  \"b",]],
    [[  \"c",]],
    "  \\]",
  })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), {
    "## set background=dark",
    "let mylist = [",
    [[  \"a",]],
    [[  \"b",]],
    [[  \"c",]],
    "  \\]",
  })
  eq(get_cursor(), { 1, 3 })

  -- should work with dot-repeat
  set_cursor(4, 0)
  feed(".")
  eq(get_lines(), {
    "## set background=dark",
    "let mylist = [",
    [[  \"a",]],
    [[  !! \"b",]],
    [[  \"c",]],
    "  \\]",
  })
  eq(get_cursor(), { 4, 0 })
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L673
T["treesitter"]["respects injected tree-sitter commentstring metadata : nvim-like builtin resolver"] = function()
  child.lua_func(function()
    vim.treesitter.query.set(
      "lua",
      "highlights",
      [[
        ((string) @string (#set! @string bo.commentstring "; %s"))
      ]]
    )
    vim.bo.tabstop = 2
    vim.bo.filetype = "vim"
    vim.treesitter.start()
    vim.b.celeste_comment_config = { cms_confs = false }
  end)
  set_lines({
    "set background=dark",
    "lua << EOF",
    "print[[",
    "Inside string",
    "]]",
    "EOF",
  })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), {
    '" set background=dark',
    "lua << EOF",
    "print[[",
    "Inside string",
    "]]",
    "EOF",
  })
  eq(get_cursor(), { 1, 2 })

  -- Should work with dot-repeat
  set_cursor(4, 0)
  feed(".")
  eq(get_lines(), {
    '" set background=dark',
    "lua << EOF",
    "print[[",
    "; Inside string",
    "]]",
    "EOF",
  })
  eq(get_cursor(), { 4, 2 })

  set_cursor(3, 0)
  feed(".")
  eq(get_lines(), {
    '" set background=dark',
    "lua << EOF",
    "-- print[[",
    "; Inside string",
    "]]",
    "EOF",
  })
  eq(get_cursor(), { 3, 3 })
end

-- Referenced from https://github.com/neovim/neovim/blob/master/test/functional/lua/comment_spec.lua#L725
T["treesitter"]["works across combined injections"] = function()
  child.lua_func(function()
    vim.bo.filetype = "lua"
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

  set_lines({
    'vim.cmd([[" some text]])',
    "local a = 123",
    'vim.cmd([[" some more text]])',
  })
  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines(), {
    'vim.cmd([[" some text]])',
    "-- local a = 123",
    'vim.cmd([[" some more text]])',
  })
  eq(get_cursor(), { 2, 3 })
end

-- markdown injected language tests ───────────────────────────────────────────

T["markdown"] = new_set()

T["markdown"]["gcc toggle line works"] = function()
  child.bo.filetype = "markdown"
  child.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
  set_lines({
    "aaa",
    "```bash",
    "echo here",
    "```",
    "bbb",
  })
  child.lua_func(function() vim.treesitter.language.add("bash") end)
  child.treesitter.start()
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(1, 1), { "<!-- aaa -->" })
  feed("gcc")
  eq(get_lines(1, 1), { "aaa" })
  set_cursor(3, 0)
  feed("gcc")
  eq(get_lines(3, 3), { "# echo here" })
  feed("gcc")
  eq(get_lines(3, 3), { "echo here" })
end

T["markdown"]["gcc works"] = function()
  child.bo.filetype = "markdown"
  child.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
  set_lines({
    "aaa",
    "```lua",
    "print('hello')",
    "```",
    "bbb",
  })
  child.treesitter.start()
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(1, 1), { "<!-- aaa -->" })
  feed("gcc")
  eq(get_lines(1, 1), { "aaa" })
  set_cursor(3, 0)
  feed("gcc")
  eq(get_lines(3, 3), { "-- print('hello')" })
  feed("gcc")
  eq(get_lines(3, 3), { "print('hello')" })
end

T["markdown"]["gcc on code block lua line uses --"] = function()
  child.bo.filetype = "markdown"
  child.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
  child.bo.commentstring = "<!-- %s -->"
  set_lines({
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
  })
  child.lua([[
    vim.treesitter.language.add("lua")
    vim.treesitter.start()
  ]])

  -- Inside lua code block → "-- "
  set_cursor(6, 0)
  feed("gcc")
  eq(get_lines()[6], "-- local x = 1")

  set_cursor(7, 0)
  feed("gcc")
  eq(get_lines()[7], "-- function foo()")

  -- Outside code block → commentstring fallback
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines()[1], "<!-- # Title -->")

  set_cursor(12, 0)
  feed("gcc")
  eq(get_lines()[12], "<!-- More text. -->")
end

T["markdown"]["gcc on code fence marker uses markdown comment"] = function()
  child.bo.filetype = "markdown"
  child.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
  child.bo.commentstring = "<!-- %s -->"
  set_lines({
    "",
    "```lua",
    "local x = 1",
    "```",
    "",
  })
  child.lua([[
    vim.treesitter.language.add("lua")
    vim.treesitter.start()
  ]])

  -- Code fence marker line → resolve_language_tree returns markdown root
  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines()[2], "<!-- ```lua -->")

  -- Closing fence
  set_cursor(4, 0)
  feed("gcc")
  eq(get_lines()[4], "<!-- ``` -->")
end

T["markdown"]["gco respects injected language in code block"] = function()
  child.bo.filetype = "markdown"
  child.bo.commentstring = "<!-- %s -->"
  set_lines({
    "",
    "```lua",
    "local x = 1",
    "```",
    "",
  })
  child.lua([[
    vim.treesitter.language.add("lua")
    vim.treesitter.start()
  ]])

  -- gco inside code block → new line with "-- "
  set_cursor(3, 0)
  feed("gco")
  feed("<Esc>")
  local result = get_lines()
  eq(result[4], "-- ")
end

T["markdown"]["visual mode works"] = function()
  child.bo.tabstop = 2
  child.bo.filetype = "markdown"
  child.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
  set_lines({
    "## head",
    "aaa",
    "```lua",
    "  local x = 1",
    "  local y = 2",
    "```",
    "bbb",
  })
  selection(1, 0, 4, 12)
  feed("gc")
  eq(get_lines(), {
    "<!-- ## head",
    "aaa",
    "```lua",
    "  local x = 1 -->",
    "  local y = 2",
    "```",
    "bbb",
  })
  eq(get_cursor(), { 4, 12 })
  feed("gcu")
  eq(get_lines(), {
    "## head",
    "aaa",
    "```lua",
    "  local x = 1",
    "  local y = 2",
    "```",
    "bbb",
  })
  eq(get_cursor(), { 4, 12 })

  selection(3, 0, 4, 0)
  feed("gc")
  eq(get_lines(), {
    "## head",
    "aaa",
    "<!-- ```lua",
    "  local x = 1 -->",
    "  local y = 2",
    "```",
    "bbb",
  })
  eq(get_cursor(), { 4, 0 })
  feed("gcu")
  eq(get_lines(), {
    "## head",
    "aaa",
    "```lua",
    "  local x = 1",
    "  local y = 2",
    "```",
    "bbb",
  })

  selection(4, 0, 5, 12)
  feed("gc")
  eq(get_lines(), {
    "## head",
    "aaa",
    "```lua",
    "--   local x = 1",
    "--   local y = 2",
    "```",
    "bbb",
  })
  eq(get_cursor(), { 5, 15 })
  feed("gcu")
  eq(get_lines(), {
    "## head",
    "aaa",
    "```lua",
    "  local x = 1",
    "  local y = 2",
    "```",
    "bbb",
  })
  eq(get_cursor(), { 5, 12 })
end

-- disable tests ───────────────────────────────────────────────────────────────

T["disable"] = new_set()

T["disable"]["vim.g disables mappings"] = function()
  child.g.celeste_comment_disable = true
  set_lines({ "aa" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "aa" })
end

T["disable"]["vim.b disables for buffer"] = function()
  child.b.celeste_comment_disable = true
  set_lines({ "aa" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "aa" })
end

-- Referenced from vscode ─────────────────────────────────────────────────────

T["referenced_from_vscode"] = new_set({
  hooks = {
    pre_case = function()
      child.b.celeste_comment_config = {
        ignore_empty_lines = "never",
        insert_space = true,
        case_insensitive = true,
        fallback_to_block = "if_line_cms_wrapped",
      }
      child.bo.commentstring = "!@#%s"
      child.bo.filetype = "vscode-comment-test"
      child.bo.tabstop = 4
    end,
  },
})

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L56
T["referenced_from_vscode"]["comment single line"] = function()
  set_lines({ "some text", "\tsome more text" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "!@# some text", "\tsome more text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L71
T["referenced_from_vscode"]["case insensitive"] = function()
  child.bo.commentstring = "rem%s"
  set_lines({ "REM some text" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "some text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L89
T["referenced_from_vscode"]["comment with token column fixed"] = function()
  set_config({ line_comment_no_indent = true })
  set_lines({ "some text", "\tsome more text" })
  set_cursor(2, 3)
  feed("gcc")
  eq(get_lines(), { "some text", "!@# \tsome more text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L198
T["referenced_from_vscode"]["normalize_insertion_point"] = function()
  local orig_ts = vim.bo.tabstop
  local function run(mixed, tabstop, expected, cfg)
    vim.bo.tabstop = tabstop
    local lines = {}
    for i = 1, #mixed, 2 do
      lines[#lines + 1] = mixed[i]
    end
    local csi = H.make_csi({ { "# ", "" } })
    local info = H.line_comment_info(lines, csi, cfg or {}, { 0 }, 1)
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
T["referenced_from_vscode"]["detect indentation"] = function()
  set_lines({ "\tsome text", "\tsome more text" })
  set_cursor(2, 2)
  feed("gck")
  eq(get_lines(), { "\t!@# some text", "\t!@# some more text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L309
T["referenced_from_vscode"]["detect indentation"] = function()
  set_lines({ "\tsome text", "    some more text" })
  set_cursor(1, 2)
  feed("gcj")
  eq(get_lines(), { "\t!@# some text", "    !@# some more text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L324
T["referenced_from_vscode"]["ignores whitespace lines"] = function()
  set_config({ ignore_empty_lines = "always" })
  set_lines({
    "\tsome text",
    "\t   ",
    "",
    "\tsome more text",
  })
  set_cursor(4, 2)
  feed("gc3k")
  eq(get_lines(), {
    "\t!@# some text",
    "\t   ",
    "",
    "\t!@# some more text",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L343
T["referenced_from_vscode"]["remove its own"] = function()
  set_config({ ignore_empty_lines = "always" })
  set_lines({ "\t!@# some text", "\t   ", "\t\t!@# some more text" })
  set_cursor(3, 4)
  feed("gc2k")
  eq(get_lines(), { "\tsome text", "\t   ", "\t\tsome more text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L360
T["referenced_from_vscode"]["works in only whitespace"] = function()
  set_lines({ "\t    ", "\t", "\t\tsome more text" })
  set_cursor(1, 0)
  feed("2gcc")
  eq(get_lines(), { "\t!@#     ", "\t!@# ", "\t\tsome more text" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L377
T["referenced_from_vscode"]["whitespace before comment token"] = function()
  set_lines({ "\t !@#first", "\tsecond line" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "\t first", "\tsecond line" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L392
T["referenced_from_vscode"]["line comment before caret"] = function()
  set_lines({ "first!@#", "\tsecond line" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "!@# first!@#", "\tsecond line" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L407
T["referenced_from_vscode"]["comment signle line"] = function()
  set_lines({ "first!@#", "\tsecond line" })
  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines(), { "first!@#", "\t!@# second line" })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L443
T["referenced_from_vscode"]["multiple lines"] = function()
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  set_cursor(1, 0)
  feed("gcj")
  eq(get_lines(), {
    "!@# first",
    "!@# \tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L464
T["referenced_from_vscode"]["multiple modes on multiple lines"] = function()
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(4, 4, 3, 1)
  feed("gc")
  eq(get_lines(), {
    "first",
    "\tsecond line",
    "!@# third line",
    "!@# fourth line",
    "fifth",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L485
T["referenced_from_vscode"]["toggle signle line"] = function()
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(1, 1, 1, 1)
  feed("gc")
  eq(get_lines(), {
    "!@# first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(1, 4, 1, 4)
  feed("gc")
  eq(get_lines(), {
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L525
T["referenced_from_vscode"]["toggle multiple lines"] = function()
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(2, 4, 1, 1)
  feed("gc")
  eq(get_lines(), {
    "!@# first",
    "!@# \tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(2, 7, 1, 4)
  feed("gc")
  eq(get_lines(), {
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L565
T["referenced_from_vscode"]["cursor is at the beginning of the line"] = function()
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(1, 1, 1, 1)
  feed("gc")
  eq(get_lines(), {
    "!@# first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  eq(get_cursor(), { 1, 5 })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L586
T["referenced_from_vscode"]["comment hotkeys throws the cursor before the comment"] = function()
  set_lines({
    "first",
    "",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines(), {
    "first",
    "!@# ",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  eq(get_cursor(), { 2, 3 })

  set_lines({
    "first",
    "\t",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  set_cursor(2, 2)
  feed("gcc")
  eq(get_lines(), {
    "first",
    "\t!@# ",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L630
T["referenced_from_vscode"]["Add line comment fault when blank lines involved"] = function()
  set_config({ ignore_empty_lines = "always" })
  set_lines({
    '    if displayName == "":',
    "        displayName = groupName",
    '    description = getAttr(attributes, "description")',
    '    mailAddress = getAttr(attributes, "mail")',
    "",
    '    print "||Group name|%s|" % displayName',
    '    print "||Description|%s|" % description',
    '    print "||Email address|[mailto:%s]|" % mailAddress`',
  })
  selection(1, 1, 8, 56)
  feed("gc")
  eq(get_lines(), {
    '    !@# if displayName == "":',
    "    !@#     displayName = groupName",
    '    !@# description = getAttr(attributes, "description")',
    '    !@# mailAddress = getAttr(attributes, "mail")',
    "",
    '    !@# print "||Group name|%s|" % displayName',
    '    !@# print "||Description|%s|" % description',
    '    !@# print "||Email address|[mailto:%s]|" % mailAddress`',
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L657
T["referenced_from_vscode"]["toggle comments shouldn't move cursor"] = function()
  set_lines({
    "    A line",
    "    Another line",
  })
  set_cursor(2, 7)
  feed("gck")
  eq(get_lines(), {
    "    !@# A line",
    "    !@# Another line",
  })
  eq(get_cursor(), { 2, 11 })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L672
T["referenced_from_vscode"]["insertSpace false"] = function()
  set_config({ insert_space = false })
  set_lines({
    "some text",
  })
  set_cursor(1, 1)
  feed("gcc")
  eq(get_lines(), {
    "!@#some text",
  })
  eq(get_cursor(), { 1, 4 })
end

-- NOTE: might differ with vscode, when insertSpace false, we respect the origin commentstring format
-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L690
T["referenced_from_vscode"]["insertSpace false does not remove space"] = function()
  set_config({ insert_space = false })
  set_lines({
    "!@#    some text",
  })
  set_cursor(1, 1)
  feed("gcc")
  eq(get_lines(), {
    "    some text",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L718
T["referenced_from_vscode"]["does not ignore whitespace lines"] = function()
  set_config({ ignore_empty_lines = "never" })
  set_lines({
    "\tsome text",
    "\t   ",
    "",
    "\tsome more text",
  })
  selection(4, 2, 1, 1)
  feed("gc")
  eq(get_lines(), {
    "!@# \tsome text",
    "!@# \t   ",
    "!@# ",
    "!@# \tsome more text",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L718
T["referenced_from_vscode"]["ignore_empty_lines removes its own"] = function()
  set_config({ ignore_empty_lines = "never" })
  set_lines({
    "\t!@# some text",
    "\t   ",
    "\t\t!@# some more text",
  })
  selection(3, 2, 1, 1)
  feed("gc")
  eq(get_lines(), {
    "\tsome text",
    "\t   ",
    "\t\tsome more text",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L754
T["referenced_from_vscode"]["ignore_empty_lines works in only whitespace"] = function()
  set_config({ ignore_empty_lines = "never" })
  set_lines({
    "\t    ",
    "\t",
    "\t\tsome more text",
  })
  set_cursor(1, 0)
  feed("gcj")
  eq(get_lines(), {
    "\t!@#     ",
    "\t!@# ",
    "\t\tsome more text",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L771
T["referenced_from_vscode"]["ignore_empty_lines comments signle line"] = function()
  set_config({ ignore_empty_lines = "never" })
  set_lines({
    "some text",
    "\tsome more text",
  })
  selection(1, 1, 1, 1)
  feed("gcc")
  eq(get_lines(), {
    "!@# some text",
    "\tsome more text",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L786
T["referenced_from_vscode"]["ignore_empty_lines comments signle line"] = function()
  set_config({ ignore_empty_lines = "never" })
  set_lines({
    "\tsome text",
    "\tsome more text",
  })
  selection(2, 2, 1, 1)
  feed("gcc")
  eq(get_lines(), {
    "\t!@# some text",
    "\t!@# some more text",
  })
end

T["referenced_from_vscode"]["commenting code in JSX files"] = function()
  child.lua_func(function()
    vim.treesitter.language.add("javascript")
    vim.bo.filetype = "javascript"
    vim.treesitter.start()
  end)

  set_lines({
    "import React from 'react';",
    "const Loader = () => (",
    "  <div>",
    "    Loading...",
    "  </div>",
    ");",
    "export default Loader;",
  })
  set_cursor(1, 0)
  feed("gc6j")
  eq(get_lines(), {
    "// import React from 'react';",
    "// const Loader = () => (",
    "//   <div>",
    "//     Loading...",
    "//   </div>",
    "// );",
    "// export default Loader;",
  })
  eq(get_cursor(), { 1, 3 })
  feed("gcgc")
  eq(get_lines(), {
    "import React from 'react';",
    "const Loader = () => (",
    "  <div>",
    "    Loading...",
    "  </div>",
    ");",
    "export default Loader;",
  })
  eq(get_cursor(), { 1, 0 })

  set_cursor(4, 0)
  feed("gcc")
  eq(get_lines(), {
    "import React from 'react';",
    "const Loader = () => (",
    "  <div>",
    "    {/* Loading... */}",
    "  </div>",
    ");",
    "export default Loader;",
  })
end

-- Referenced from:
-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L811
-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L832
-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L853
T["referenced_from_vscode"]["fallback to block comment command"] = function()
  child.bo.commentstring = ""
  child.b.celeste_comment_block_commentstring = "(%s)"
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  set_cursor(1, 3)
  feed("gcc")
  eq(get_lines(), {
    "( first )",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  eq(get_cursor(), { 1, 5 })

  feed("gcc")
  eq(get_lines(), {
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
end

-- https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L874
T["referenced_from_vscode"]["always expand selection to line boundaries"] = function()
  child.bo.commentstring = ""
  child.b.celeste_comment_block_commentstring = "(%s)"
  set_lines({
    "first",
    "\tsecond line",
    "third line",
    "fourth line",
    "fifth",
  })
  selection(3, 2, 1, 3)
  feed("gc")
  eq(get_lines(), {
    "( first",
    "\tsecond line",
    "third line )",
    "fourth line",
    "fifth",
  })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L924
T["referenced_from_vscode"]["fallback to block : no selection => uses indentation"] = function()
  child.bo.commentstring = ""
  child.b.celeste_comment_block_commentstring = "<!@#%s#@!>"
  set_lines({
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  })
  set_cursor(1, 3)
  feed("gcc")
  eq(get_lines(), {
    "\t\t<!@# first\t     #@!>",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  })
  eq(get_cursor(), { 1, 8 })

  feed("gcc")
  eq(get_lines(), {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  })
  eq(get_cursor(), { 1, 3 })
end

-- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L964
T["referenced_from_vscode"]["fallback to block : can remove"] = function()
  child.bo.commentstring = ""
  child.b.celeste_comment_block_commentstring = "<!@#%s#@!>"
  set_lines({
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  })
  set_cursor(5, 1)
  feed("gcc")
  eq(get_lines(), {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\tfifth\t\t",
  })

  set_lines({
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  })
  set_cursor(5, 3)
  feed("gcc")
  eq(get_lines(), {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\tfifth\t\t",
  })

  set_lines({
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\t<!@#fifth#@!>\t\t",
  })
  set_cursor(5, 4)
  feed("gcc")
  eq(get_lines(), {
    "\t\tfirst\t    ",
    "\t\tsecond line",
    "\tthird line",
    "fourth line",
    "\t\tfifth\t\t",
  })
end

--- Referenced from https://github.com/microsoft/vscode/blob/main/src/vs/editor/contrib/comment/test/browser/lineCommentCommand.test.ts#L1080
T["referenced_from_vscode"]["fallback to block : Remove comment not work consistently in HTML"] = function()
  child.bo.commentstring = ""
  child.b.celeste_comment_block_commentstring = "<!@#%s#@!>"
  set_lines({
    "     asd qwe",
    "     asd qwe",
    "",
  })
  feed("gcj")
  eq(get_lines(), {
    "     <!@# asd qwe",
    "     asd qwe #@!>",
    "",
  })

  set_lines({
    "     <!@#asd qwe",
    "     asd qwe#@!>",
    "",
  })
  feed("gcj")
  eq(get_lines(), {
    "     asd qwe",
    "     asd qwe",
    "",
  })
end

-- Regression tests ───────────────────────────────────────────────────────────

T["inline_multi_block"] = new_set()

T["inline_multi_block"]["gbc on line with inline block wraps whole line"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," })
  set_cursor(1, 30)
  feed("gbc")
  eq(get_lines(), { "        /* /* value */ EncodeAsString(k * 2), /* is_delete */ false, */" })
end

T["inline_multi_block"]["block_is_partial checks exact position"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "  /* a */ b(), /* c */ d()," })
  set_cursor(1, 2)
  feed("v", "6l", "gb")
  eq(get_lines(), { "  a b(), /* c */ d()," })
end

T["inline_multi_block"]["dgb multi-line mid-column deletes precisely"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "x /* a", "b */ y" })
  set_cursor(1, 3)
  feed("dgb")
  eq(get_lines(), { "x  y" })
end

T["inline_multi_block"]["gbgb toggles inline block comment"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "  /* value */ code" })
  set_cursor(1, 4)
  feed("gbgb")
  eq(get_lines(), { "  value code" })
end

T["inline_multi_block"]["gbiw toggles specific word only"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "  /* val */ str(), /* del */ true," })
  set_cursor(1, 13)
  feed("gbiw")
  eq(get_lines(), { "  /* val */ /* str */(), /* del */ true," })
end

T["inline_multi_block"]["vib selects multi-line block precisely"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  child.lua([[
    vim.keymap.set("x", "ib", '<Cmd>lua require("celeste_comment").H.textobject_blockwise()<CR>')
  ]])
  set_lines({ "pre /* comment starts", "middle line", "ends here */ post" })
  set_cursor(2, 5)
  feed("v", "i", "b", "<Esc>")

  local from = child.api.nvim_buf_get_mark(0, "<")
  local to = child.api.nvim_buf_get_mark(0, ">")

  eq(from[1], 1)
  eq(from[2], 4)
  eq(to[1], 3)
  eq(to[2], 11)
end

T["inline_multi_block"]["gbgb outside inline block does nothing"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," })
  -- Cursor on EncodeAsString, outside any /* */ block
  set_cursor(1, 23)
  feed("gbgb")
  -- No change: should NOT affect /* value */
  eq(get_lines(), { "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," })
end

T["inline_multi_block"]["gbgb inside inline block works"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," })
  -- Cursor on 'value' inside /* value */
  set_cursor(1, 12)
  feed("gbgb")
  -- /* value */ should be uncommented, is_delete unaffected
  eq(get_lines(), { "        value EncodeAsString(k * 2), /* is_delete */ false," })
end

T["inline_multi_block"]["gbgb on second inline block works"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," })
  -- Cursor on 'is_delete' inside /* is_delete */
  set_cursor(1, 48)
  feed("gbgb")
  eq(get_lines(), { "        /* value */ EncodeAsString(k * 2), is_delete false," })
end

T["inline_multi_block"]["gbgb on marker chars works"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "        /* value */ EncodeAsString(k * 2), /* is_delete */ false," })
  -- Cursor on '/' in /* value */
  set_cursor(1, 8)
  feed("gbgb")
  eq(get_lines(), { "        value EncodeAsString(k * 2), /* is_delete */ false," })
end

T["inline_multi_block"]["gbgb on empty line below inline block does nothing"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({ "        /* use_contiguous_buffer */ true);", "", "    /* is_delete */ true," })
  set_cursor(2, 0)
  feed("gbgb")
  eq(get_lines(), { "        /* use_contiguous_buffer */ true);", "", "    /* is_delete */ true," })
end

T["inline_multi_block"]["gbgb beyond block_textobj_nlines does nothing"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  child.b.celeste_comment_config = { block_textobj_nlines = 1 }
  local lines = {}
  for i = 1, 5 do
    lines[i] = ""
  end
  lines[1] = "/* far */ code"
  lines[5] = "content"
  set_lines(lines)
  set_cursor(5, 0)
  feed("gbgb")
  eq(get_lines()[1], "/* far */ code")
end

T["inline_multi_block"]["gbgb on first inline block in multi-line works"] = function()
  child.bo.filetype = "cpp"
  child.bo.commentstring = "// %s"
  set_lines({
    "input_descs.emplace_back(",
    "        /* key */ EncodeAsString(k), /* timestamp */ EncodeAsUint64(k),",
    "        /* value */ EncodeAsString(k), /* is_delete */ false,",
    "        /* use_contiguous_buffer */ false);",
  })
  set_cursor(2, 14)
  feed("gbgb")
  eq(get_lines(), {
    "input_descs.emplace_back(",
    "        key EncodeAsString(k), /* timestamp */ EncodeAsUint64(k),",
    "        /* value */ EncodeAsString(k), /* is_delete */ false,",
    "        /* use_contiguous_buffer */ false);",
  })
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
  child.bo.filetype = "rust"
  child.b.celeste_comment_config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } }
  set_lines({ "/// doc comment" })
  set_cursor(1, 0)
  feed("gcc")
  -- removes "/// " leaving "doc comment"
  eq(get_lines(), { "doc comment" })
end

T["multi_line_comment_string"]["gcc_removes_correct_token"] = function()
  child.bo.filetype = "rust"
  child.b.celeste_comment_config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } }
  set_lines({ "//! inner doc" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "inner doc" })
end

T["multi_line_comment_string"]["gcc_adds_primary_token"] = function()
  child.bo.filetype = "rust"
  child.b.celeste_comment_config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } }
  set_lines({ "normal code" })
  set_cursor(1, 0)
  feed("gcc")
  -- primary is "//"
  eq(get_lines(), { "// normal code" })
end

T["multi_line_comment_string"]["gcgc_selects_mixed_tokens"] = function()
  child.bo.filetype = "rust"
  child.b.celeste_comment_config = { cms_confs = { rust = { { "//%s", "///%s", "//!%s" }, "" } } }
  set_lines({ "/// doc", "// normal", "//! inner", "end" })
  set_cursor(2, 0)
  feed("dgc")
  eq(get_lines(), { "end" })
end

-- fallback_to_block tests ─────────────────────────────────────────────────────

T["fallback_to_block"] = new_set()

T["fallback_to_block"]["never: works"] = function()
  child.bo.filetype = "test"
  child.b.celeste_comment_config = {
    fallback_to_block = "never",
    cms_confs = { test = { nil, "/*%s*/" } },
  }
  set_lines({ "aaa", "bbb" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "aaa", "bbb" })

  child.b.celeste_comment_config = {
    fallback_to_block = "never",
    cms_confs = { test = { "<!--%s-->", "/*%s*/" } },
  }
  feed(".")
  eq(get_lines(), { "<!-- aaa -->", "bbb" })
  feed("u")

  feed("gc", "2j")
  eq(get_lines(), { "<!-- aaa -->", "<!-- bbb -->" })
  eq(get_cursor(), { 1, 5 })
  feed(".")
  eq(get_lines(), { "aaa", "bbb" })
end

T["fallback_to_block"]["if_line_cms_wrapped: works1"] = function()
  child.bo.filetype = "test"
  child.b.celeste_comment_config = {
    fallback_to_block = "if_line_cms_wrapped",
    cms_confs = { test = { nil, "/*%s*/" } },
  }
  set_lines({ "hello" })
  set_cursor(1, 3)
  feed("gcc")
  eq(get_lines(), { "/* hello */" })
  eq(get_cursor(), { 1, 6 })
  feed(".")
  eq(get_lines(), { "hello" })

  set_lines({ "    aaa", "    /* bbb */", "    /*ccc*/" })
  set_cursor(2, 4)
  feed("gc", "gc")
  eq(get_lines(), { "    aaa", "    bbb", "    /*ccc*/" })
  eq(get_cursor(), { 2, 4 })
  set_cursor(3, 6)
  feed(".")
  eq(get_lines(), { "    aaa", "    bbb", "    ccc" })

  set_lines({ "aaa", "bbb", "ccc" })
  set_cursor(1, 0)
  feed("gcj")
  eq(get_lines(), { "/* aaa", "bbb */", "ccc" })
  feed("gcgc")
  eq(get_lines(), { "aaa", "bbb", "ccc" })

  set_lines({ "/* aaa", "bbb */", "ccc" })
  set_cursor(1, 0)
  feed("gcj")
  eq(get_lines(), { "aaa", "bbb", "ccc" })

  -- always expand selection to line boundaries when fallback_to_block
  set_lines({ "hello world", "foo bar baz" })
  selection(1, 6, 2, 4)
  feed("gc")
  eq(get_lines(), { "/* hello world", "foo bar baz */" })
  -- round-trip: gcgc uncomments
  feed("gcgc")
  eq(get_lines(), { "hello world", "foo bar baz" })

  feed("u")
  set_cursor(1, 8)
  feed("gcu")
  eq(get_lines(), { "hello world", "foo bar baz" })
end

T["fallback_to_block"]["if_line_cms_wrapped: works2"] = function()
  child.bo.filetype = "test"
  child.b.celeste_comment_config = {
    fallback_to_block = "if_line_cms_wrapped",
    cms_confs = { test = { "#%s", "/*%s*/" } },
  }

  set_lines({ "a" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "# a" })
  eq(get_cursor(), { 1, 2 })
  feed(".")
  eq(get_lines(), { "a" })

  child.b.celeste_comment_config = {
    fallback_to_block = "if_line_cms_wrapped",
    cms_confs = { test = { "!@#%s#@!", "/*%s*/" } },
  }
  set_lines({ "a" })
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(), { "!@# a #@!" })
  eq(get_cursor(), { 1, 4 })

  set_lines({ "aaa", "bbb", "ccc" })
  set_cursor(1, 0)
  feed("gcj")
  eq(get_lines(), { "!@# aaa", "bbb #@!", "ccc" })
  eq(get_cursor(), { 1, 4 })
  feed("gc", "gc")
  eq(get_lines(), { "aaa", "bbb", "ccc" })
  eq(get_cursor(), { 1, 0 })
  feed("u")

  set_cursor(1, 6)
  feed("gcj")
  eq(get_lines(), { "aaa", "bbb", "ccc" })
  eq(get_cursor(), { 1, 2 })

  -- always expand selection to linewise
  set_lines({ "hello world", "foo bar baz" })
  selection(1, 6, 2, 4)
  feed("gc")
  eq(get_lines(), { "!@# hello world", "foo bar baz #@!" })
  -- round-trip: gcgc uncomments
  feed("gcgc")
  eq(get_lines(), { "hello world", "foo bar baz" })

  feed("u")
  set_cursor(1, 8)
  feed("gcu")
  eq(get_lines(), { "hello world", "foo bar baz" })
end

-- Toggle current line comment at insert mode ─────────────────────────────────

T["toggle_line_comment_at_insert_mode"] = new_set({
  parametrize = { { "never" }, { "if_line_cms_wrapped" } },
})

local function ins_f(col, etcol, start_line, end_line, expected_after_at)
  set_lines({ start_line })
  set_cursor(1, col)
  feed("<c-/>")
  eq(get_lines(), { end_line })
  eq(get_cursor(), { 1, etcol })
  feed("@")
  eq(get_lines(), { expected_after_at })
  eq(get_cursor(), { 1, etcol + 1 })
  feed("<c-h>")
  eq(get_cursor(), { 1, etcol })
end

T["toggle_line_comment_at_insert_mode"]["works for lcs only cms"] = function(fallback)
  child.b.celeste_comment_config = { fallback_to_block = fallback }
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.bo.filetype = "unknown"
  child.bo.commentstring = "// %s"
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
  child.b.celeste_comment_config = { fallback_to_block = fallback }
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.bo.filetype = "unknown"
  child.bo.commentstring = "/* %s */"
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
  child.b.celeste_comment_config = { fallback_to_block = fallback }
  child.bo.tabstop = 2
  child.bo.expandtab = true
  child.bo.filetype = "unknown"
  child.bo.commentstring = "%s --"
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
  child.bo.commentstring = "// %s"
  set_lines({ "hello", "// world" })
  set_cursor(1, 0)
  feed("gC", "j")
  eq(get_lines(), { "// hello", "// // world" })
  eq(get_cursor(), { 1, 3 })

  feed(".")
  eq(get_lines(), { "// // hello", "// // // world" })
  eq(get_cursor(), { 1, 6 })

  feed("V", "j", "gC")
  eq(get_lines(), { "// // // hello", "// // // // world" })
  eq(get_cursor(), { 2, 9 })
end

T["force_comment"]["force remove works"] = function()
  child.bo.commentstring = "// %s"
  set_lines({ "hello", "// world" })
  set_cursor(2, 3)
  feed("gU", "k")
  eq(get_lines(), { "hello", "world" })
  eq(get_cursor(), { 2, 0 })

  feed(".")
  eq(get_lines(), { "hello", "world" })
  eq(get_cursor(), { 2, 0 })

  set_lines({ "// hello", "  // ", "  ", "    // world" })
  set_cursor(1, 2)
  feed("V", "3j", "gU")
  eq(get_lines(), { "hello", "  ", "  ", "    world" })
  eq(get_cursor(), { 4, 2 })
end

T["force_comment"]["respect ignore_empty_lines"] = function()
  child.bo.tabstop = 2
  child.bo.commentstring = "// %s"

  -- ForceAdd + always: blank lines skipped
  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  set_lines({ "hello", "  ", "// world" })
  set_cursor(1, 0)
  feed("V", "2j", "gC")
  eq(get_lines(), { "// hello", "  ", "// // world" })

  -- ForceRemove + always: blank lines skipped, commented lines uncommented
  set_lines({ "// hello", "  ", "// world" })
  set_cursor(1, 0)
  feed("V", "2j", "gU")
  eq(get_lines(), { "hello", "  ", "world" })

  -- ForceAdd + never: blank lines participate in alignment, rounding to tabstop
  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  set_lines({ "   hello", " " })
  set_cursor(1, 0)
  feed("V", "j", "gC")
  eq(get_lines(), { "//    hello", "//  " })

  -- ForceAdd + mixed: blank lines excluded from alignment, min col from content
  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "   hello", " " })
  set_cursor(1, 0)
  feed("V", "j", "gC")
  eq(get_lines(), { "  //  hello", "  // " })
end

-- invert tests ────────────────────────────────────────────────────────────────

T["invert"] = new_set()

T["invert"]["works"] = function()
  child.bo.filetype = "cpp"
  set_lines({ "// a" })
  set_cursor(1, 3)
  feed("gcI_")
  eq(get_lines(), { "a" })
  eq(get_cursor(), { 1, 0 })
  feed("gcI_")
  eq(get_lines(), { "// a" })
  eq(get_cursor(), { 1, 3 })

  set_lines({ "//a", "b", "//c", "d", "//d" })
  set_cursor(1, 2)
  feed("gcI", "4j")
  eq(get_lines(), { "a", "// b", "c", "// d", "d" })
  eq(get_cursor(), { 1, 0 })
  feed("gcI", "4j")
  eq(get_lines(), { "// a", "b", "// c", "d", "// d" })
  eq(get_cursor(), { 1, 3 })
end

T["invert"]["works with special cms"] = function()
  child.bo.filetype = "unknown"
  child.b.celeste_comment_config = { fallback_to_block = "never" }
  child.bo.commentstring = "<!--%s-->"
  set_lines({ "a", "<!--b-->", " c" })
  set_cursor(3, 1)
  feed("gcI", "2k")
  eq(get_lines(), { "<!-- a -->", "b", "<!--  c -->" })
  eq(get_cursor(), { 3, 6 })

  child.bo.commentstring = "%s !@#"
  set_lines({ "aaaa", "bbbb!@#", "ccc" })
  selection(1, 0, 3, 2)
  feed("gcI")
  eq(get_lines(), { "aaaa !@#", "bbbb", "ccc !@#" })
  eq(get_cursor(), { 3, 2 })
end

T["invert"]["respect ignore_empty_lines"] = function()
  child.b.celeste_comment_config = { ignore_empty_lines = "never" }
  set_lines({ "    # a", "", "    # b" })
  set_cursor(1, 6)
  feed("gcI", "2j")
  eq(get_lines(), { "    a", "# ", "    b" })

  child.b.celeste_comment_config = { ignore_empty_lines = "mixed" }
  set_lines({ "    # a", "", "    # b" })
  set_cursor(1, 6)
  feed("gcI", "2j")
  eq(get_lines(), { "    a", "    # ", "    b" })
  eq(get_cursor(), { 1, 4 })
  feed("gcI", "2j")
  eq(get_lines(), { "    # a", "    ", "    # b" })
  eq(get_cursor(), { 1, 6 })

  child.b.celeste_comment_config = { ignore_empty_lines = "always" }
  feed("gcI", "2j")
  eq(get_lines(), { "    a", "    ", "    b" })
  eq(get_cursor(), { 1, 4 })
  feed("gcI", "2j")
  eq(get_lines(), { "    # a", "    ", "    # b" })
  eq(get_cursor(), { 1, 6 })
end

-- Vue files test ─────────────────────────────────────────────────────────────

T["vue"] = new_set({
  hooks = {
    pre_case = function()
      child.lua_func(function()
        vim.treesitter.language.add("vue")
        vim.treesitter.language.add("html")
        vim.treesitter.language.add("css")
        vim.treesitter.language.add("javascript")
        vim.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
      end)
    end,
  },
})

T["vue"]["works"] = function()
  child.bo.filetype = "vue"
  child.bo.tabstop = 2
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

  set_cursor(2, 0)
  feed("gcc")
  eq(get_lines(2, 2), { "  template comment" })
  set_cursor(3, 0)
  feed(".")
  eq(get_lines(3, 3), { "  <!-- <div>{{ msg }}</div> -->" })

  set_cursor(7, 0)
  feed(".")
  eq(get_lines(7, 7), { "script single-line comment" })
  set_cursor(8, 0)
  feed("gbc")
  eq(get_lines(8, 8), { "script multi-line comment" })

  set_cursor(13, 0)
  feed(".")
  eq(get_lines(13, 13), { "style comment" })
  set_cursor(14, 0)
  feed("gcc")
  eq(get_lines(14, 14), { "/* div { color: red; } */" })
end

-- JSX/TSX files test ─────────────────────────────────────────────────────────

T["jsx/tsx"] = new_set({
  hooks = {
    pre_case = function()
      child.lua_func(function()
        vim.treesitter.language.add("tsx")
        vim.treesitter.language.add("javascript")
        vim.treesitter.language.add("markdown")
        vim.bo.tabstop = 2
        vim.b.celeste_comment_config = { fallback_to_block = "if_line_cms_wrapped" }
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
  child.bo.filetype = "tsx"
  child.lua_func(function() vim.treesitter.start() end)

  local function fl(l, exp_lines, cmd)
    set_cursor(l, 0)
    feed(cmd or "gcc")
    eq(get_lines(l, l), exp_lines)
    feed(".")
    eq(get_lines(), lines)
  end

  local function fs(range, exp_lines, cmd)
    selection(unpack(range))
    feed(cmd or "gc")
    eq(get_lines(range[1], range[3]), exp_lines)
    feed(cmd and cmd .. cmd or "gcgc")
    eq(get_lines(), lines)
  end

  fl(1, { "// export default function App() {" })
  fl(2, { "  // return (" })
  fl(3, { '    // <div className="app">' })
  fl(4, { "      {/* <h1>Hello</h1> */}" })
  fl(5, { "      {/* <Foo bar={1} /> */}" })
  fl(6, { "    {/* </div> */}" })
  fl(7, { "  // );" })
  fl(8, { "// }" })

  fl(1, { "/* export default function App() { */" }, "gbc")
  fl(2, { "  /* return ( */" }, "gbc")
  fl(3, { '    /* <div className="app"> */' }, "gbc")
  fl(4, { "      {/* <h1>Hello</h1> */}" }, "gbc")
  fl(5, { "      {/* <Foo bar={1} /> */}" }, "gbc")
  fl(6, { "    {/* </div> */}" }, "gbc")
  fl(7, { "  /* ); */" }, "gbc")
  fl(8, { "/* } */" }, "gbc")

  fs({ 3, 0, 6, 0 }, {
    '    // <div className="app">',
    "    //   <h1>Hello</h1>",
    "    //   <Foo bar={1} />",
    "    // </div>",
  })

  fs({ 4, 0, 5, 0 }, {
    "      {/* <h1>Hello</h1>",
    "      <Foo bar={1} /> */}",
  })

  fs({ 3, 0, 6, 9 }, {
    '/*     <div className="app">',
    "      <h1>Hello</h1>",
    "      <Foo bar={1} />",
    "    </div> */",
  }, "gb")

  fs({ 4, 0, 5, 20 }, {
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
  child.bo.filetype = "markdown"
  child.lua_func(function() vim.treesitter.start() end)
  set_cursor(1, 0)
  feed("gcc")
  eq(get_lines(1, 1), { "<!-- ```tsx -->" })
  feed(".")
  eq(get_lines(1, 1), { "```tsx" })
  set_cursor(4, 0)
  feed(".")
  eq(get_lines(4, 4), { '    // <div className="app">' })
  feed(".")
  eq(get_lines(4, 4), { '    <div className="app">' })
  set_cursor(5, 0)
  feed(".")
  eq(get_lines(5, 5), { "      {/* <h1>Hello</h1> */}" })
  feed(".")
end

return T
