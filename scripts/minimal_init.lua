vim.cmd([[let &rtp = getcwd() .. "," .. &rtp]])
vim.cmd("set rtp+=" .. vim.fn.stdpath("data") .. "/site")
vim.cmd("set packpath+=" .. vim.fn.stdpath("data") .. "/site")

pcall(vim.cmd, "packadd mini.nvim")
pcall(vim.cmd, "packadd mini.test")

vim.o.termguicolors = true
vim.o.columns = 80
vim.o.lines = 24
vim.o.winborder = "rounded"
vim.cmd("colorscheme habamax")
