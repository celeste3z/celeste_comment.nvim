NVIM_EXEC ?= nvim

TEST_FILES := $(wildcard tests/test_*.lua)
TEST_TARGETS := $(TEST_FILES:tests/%.lua=test-%)

test: $(TEST_TARGETS)

test-%: tests/%.lua
	$(NVIM_EXEC) --headless --noplugin -u scripts/minimal_init.lua \
	  -c "lua require('mini.test').setup()" \
	  -c "lua MiniTest.run_file('tests/$*.lua')" \
	  +"qa!"

# Run a single test case by name pattern
# Usage: make test-one NAME="base | comment_string_unwrap"
test-one: tests/test_celeste_comment.lua
	$(NVIM_EXEC) --headless --noplugin -u scripts/minimal_init.lua \
	  -c "lua require('mini.test').setup()" \
	  -c "lua MiniTest.run_file('tests/test_celeste_comment.lua', {collect={filter_cases=function(c) return table.concat(c.desc,' | '):find('$(NAME)') end}})" \
	  +"qa!"

# Run a single test case at a specific line
# Usage: make test-at-line LINE=116
test-at-line: tests/test_celeste_comment.lua
	$(NVIM_EXEC) --headless --noplugin -u scripts/minimal_init.lua \
	  -c "lua require('mini.test').setup()" \
	  -c "lua MiniTest.run_at_location({file='tests/test_celeste_comment.lua', line=$(LINE)})" \
	  +"qa!"
