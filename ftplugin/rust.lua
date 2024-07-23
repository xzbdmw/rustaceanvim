---@type RustaceanConfig
local config = require('rustaceanvim.config.internal')
if not vim.g.did_rustaceanvim_initialize then
  require('rustaceanvim.config.check').check_for_lspconfig_conflict(vim.schedule_wrap(function(warn)
    vim.notify_once(warn, vim.log.levels.WARN)
  end))
  vim.lsp.commands['rust-analyzer.runSingle'] = function(command)
    local runnables = require('rustaceanvim.runnables')
    local cached_commands = require('rustaceanvim.cached_commands')
    ---@type RARunnable[]
    local ra_runnables = command.arguments
    local runnable = ra_runnables[1]
    local cargo_args = runnable.args.cargoArgs
    if #cargo_args > 0 and vim.startswith(cargo_args[1], 'test') then
      cached_commands.set_last_testable(1, ra_runnables)
    end
    cached_commands.set_last_runnable(1, ra_runnables)
    runnables.run_command(1, ra_runnables)
  end

  vim.lsp.commands['rust-analyzer.gotoLocation'] = function(command, ctx)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client then
      vim.lsp.util.jump_to_location(command.arguments[1], client.offset_encoding)
    end
  end

  vim.lsp.commands['rust-analyzer.showReferences'] = function(_)
    vim.lsp.buf.implementation()
  end

  vim.lsp.commands['rust-analyzer.debugSingle'] = function(command)
    local overrides = require('rustaceanvim.overrides')
    local args = command.arguments[1].args
    overrides.sanitize_command_for_debugging(args.cargoArgs)
    local cached_commands = require('rustaceanvim.cached_commands')
    cached_commands.set_last_debuggable(args)
    local rt_dap = require('rustaceanvim.dap')
    rt_dap.start(args)
  end

  local commands = require('rustaceanvim.commands')
  commands.create_rustc_command()
end

vim.g.did_rustaceanvim_initialize = true
local auto_attach = config.server.auto_attach
if type(auto_attach) == 'function' then
  local bufnr = vim.api.nvim_get_current_buf()
  auto_attach = auto_attach(bufnr)
end

if auto_attach then
  local bufnr = vim.api.nvim_get_current_buf()
  local timer = vim.loop.new_timer()
  local has_start = false

  vim.defer_fn(function()
    local is_active = timer:is_active()
    if is_active then
      vim.notify("Timer haven't been closed!", vim.log.levels.ERROR)
    end
  end, 2000)

  local timout = function(opts)
    local force = opts.force
    if not vim.api.nvim_buf_is_valid(bufnr) then
      if timer:is_active() then
        timer:close()
      end
      return
    end
    if not force and (has_start or not vim.b[bufnr].ts_parse_over) then
      return
    end
    if timer:is_active() then
      timer:close()
      -- haven't start
      has_start = true
      require('rustaceanvim.lsp').start(bufnr)
    end
  end

  vim.defer_fn(function()
    timout { force = false }
  end, 100)
  vim.defer_fn(function()
    timout { force = true }
  end, 1000)

  local col = vim.fn.screencol()
  local row = vim.fn.screenrow()
  timer:start(5, 2, function()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        if timer:is_active() then
          timer:close()
        end
        return
      end
      if has_start or not vim.b[bufnr].ts_parse_over then
        return
      end
      local new_col = vim.fn.screencol()
      local new_row = vim.fn.screenrow()
      if new_row ~= row and new_col ~= col then
        if timer:is_active() then
          timer:close()
          has_start = true
          require('rustaceanvim.lsp').start(bufnr)
        end
      end
    end)
  end)
end
