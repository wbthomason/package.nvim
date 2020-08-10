-- TODO: Allow to review/rollback updates
-- TODO: Fetch/manage LuaRocks dependencies
-- TODO: Performance analysis/tuning
-- TODO: Merge start plugins?
-- WIP:
-- TODO: Allow separate packages
local a = require('packer.async')
local clean = require('packer.clean')
local compile = require('packer.compile')
local display = require('packer.display')
local handlers = require('packer.handlers')
local install = require('packer.install')
local log = require('packer.log')
local plugin_types = require('packer.plugin_types')
local plugin_utils = require('packer.plugin_utils')
local update = require('packer.update')
local util = require('packer.util')

local async = a.sync
local await = a.wait

-- Config
local packer = {}
local config_defaults = {
  ensure_dependencies = true,
  package_root = util.is_windows and '~\\AppData\\Local\\nvim-data\\site\\pack'
    or '~/.local/share/nvim/site/pack',
  compile_path = util.is_windows and (vim.fn.stdpath('config') .. '\\plugin\\packer_compiled.vim')
    or (vim.fn.stdpath('config') .. '/plugin/packer_compiled.vim'),
  plugin_package = 'packer',
  max_jobs = nil,
  auto_clean = true,
  disable_commands = false,
  git = {
    cmd = 'git',
    subcommands = {
      update = '-C %s pull --ff-only --progress --rebase=false',
      install = 'clone %s %s --depth %i --no-single-branch --progress',
      fetch = '-C %s fetch --depth 999999 --progress',
      checkout = '-C %s checkout %s --',
      update_branch = '-C %s merge --ff-only @{u}',
      current_branch = '-C %s branch --show-current',
      diff = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt = '%%h %%s (%%cr)',
      get_rev = '-C %s rev-parse --short HEAD',
      get_msg = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      submodules = '-C %s submodule update --init --recursive --progress'
    },
    depth = 1
  },
  display = {
    open_fn = nil,
    open_cmd = '65vnew [packer]',
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    header_sym = '━',
    header_lines = 2,
    title = 'packer.nvim'
  }
}

local config = vim.tbl_extend('force', {}, config_defaults)

local plugins = nil

--- Initialize packer
-- Forwards user configuration to sub-modules, resets the set of managed plugins, and ensures that
-- the necessary package directories exist
packer.init = function(user_config)
  user_config = user_config or {}
  config = util.deep_extend('force', config, user_config)

  packer.reset()

  config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
  local _
  config.package_root, _ = string.gsub(config.package_root, '/$', '', 1)
  config.pack_dir = util.join_paths(config.package_root, config.plugin_package)
  config.opt_dir = util.join_paths(config.pack_dir, 'opt')
  config.start_dir = util.join_paths(config.pack_dir, 'start')

  for _, mod in ipairs({
    clean, compile, display, handlers, install, plugin_types, plugin_utils, update
  }) do mod.cfg(config) end

  plugin_utils.ensure_dirs()
end

packer.reset = function() plugins = {} end

--- The main logic for adding a plugin (and any dependencies) to the managed set
-- Can be invoked with (1) a single plugin spec as a string, (2) a single plugin spec table, or (3)
-- a list of plugin specs
local manage = nil
manage = function(plugin)
  if type(plugin) == 'string' then
    plugin = {plugin}
  elseif type(plugin) == 'table' and #plugin > 1 then
    for _, spec in ipairs(plugin) do manage(spec) end
    return
  end

  local path = vim.fn.expand(plugin[1])
  local name_segments = vim.split(path, '/')
  local name = name_segments[#name_segments]
  if plugins[name] then
    log.warning('Plugin ' .. name .. ' is used twice!')
    return
  end

  -- Handle aliases
  plugin.short_name = plugin.as or name
  plugin.name = path
  plugin.path = path

  -- Some config keys modify a plugin type
  if plugin.opt then plugin.manual_opt = true end

  for _, key in ipairs(compile.opt_keys) do
    if plugin[key] then
      plugin.opt = true
      break
    end
  end

  -- TODO: This needs to change for supporting multiple packages
  plugin.install_path = util.join_paths(plugin.opt and config.opt_dir or config.start_dir,
                                        plugin.short_name)

  if not plugin.type then plugin_utils.guess_type(plugin) end
  if plugin.type ~= 'custom' then plugin_types[plugin.type].setup(plugin) end
  for k, v in pairs(plugin) do if handlers[k] then handlers[k](plugins, plugin, v) end end
  plugins[name] = plugin

  if plugin.requires and config.ensure_dependencies then
    if type(plugin.requires) == 'string' then plugin.requires = {plugin.requires} end
    for _, req in ipairs(plugin.requires) do
      if type(req) == 'string' then req = {req} end
      local req_name_segments = vim.split(req[1], '/')
      local req_name = req_name_segments[#req_name_segments]
      if not plugins[req_name] then manage(req) end
    end
  end
end

--- Add a new keyword handler
packer.set_handler = function(name, func) handlers[name] = func end

--- Add a plugin to the managed set
packer.use = manage

--- Clean operation:
-- Finds plugins present in the `packer` package but not in the managed set
packer.clean = function(results) async(function() await(clean(plugins, results)) end)() end

local function args_or_all(...) return util.nonempty_or({...}, vim.tbl_keys(plugins)) end

--- Install operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Installs missing plugins, then updates helptags and rplugins
packer.install = function(...)
  local install_plugins
  if ... then
    install_plugins = {...}
  else
    install_plugins = plugin_utils.find_missing_plugins(plugins)
  end

  if #install_plugins == 0 then
    log.info('All configured plugins are installed')
    return
  end

  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    local tasks, display_win = install(plugins, install_plugins, results)
    if next(tasks) then
      table.insert(tasks, 1, function() return not display.status.running end)
      table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
      display_win:update_headline_message('installing ' .. #tasks - 2 .. ' / ' .. #tasks - 2
                                            .. ' plugins')
      a.interruptible_wait_pool(unpack(tasks))
      local install_paths = {}
      for plugin_name, r in pairs(results.installs) do
        if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
      end

      await(a.main)
      plugin_utils.update_helptags(install_paths)
      plugin_utils.update_rplugins()
      local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
      display_win:final_results(results, delta)
    else
      log.info('Nothing to install!')
    end
  end)()
end

--- Update operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Fixes plugin types, installs missing plugins, then updates installed plugins and updates helptags
-- and rplugins
packer.update = function(...)
  local update_plugins = args_or_all(...)
  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    local missing_plugins, installed_plugins = util.partition(
                                                 plugin_utils.find_missing_plugins(plugins),
                                                 update_plugins)

    update.fix_plugin_types(plugins, missing_plugins, results)
    local _
    _, missing_plugins = util.partition(vim.tbl_keys(results.moves), missing_plugins)
    local tasks, display_win = install(plugins, missing_plugins, results)
    local update_tasks
    update_tasks, display_win = update(plugins, installed_plugins, display_win, results)
    vim.list_extend(tasks, update_tasks)
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message('updating ' .. #tasks - 2 .. ' / ' .. #tasks - 2
                                          .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    local install_paths = {}
    for plugin_name, r in pairs(results.installs) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    for plugin_name, r in pairs(results.updates) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    await(a.main)
    plugin_utils.update_helptags(install_paths)
    plugin_utils.update_rplugins()
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

--- Sync operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Runs (in sequence):
--  - Update plugin types
--  - Clean stale plugins
--  - Install missing plugins and update installed plugins
--  - Update helptags and rplugins
packer.sync = function(...)
  local sync_plugins = args_or_all(...)
  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    local missing_plugins, installed_plugins = util.partition(
                                                 plugin_utils.find_missing_plugins(plugins),
                                                 sync_plugins)

    update.fix_plugin_types(plugins, missing_plugins, results)
    local _
    _, missing_plugins = util.partition(vim.tbl_keys(results.moves), missing_plugins)
    if config.auto_clean then
      await(clean(plugins, results))
      _, installed_plugins = util.partition(vim.tbl_keys(results.removals), installed_plugins)
    end

    local tasks, display_win = install(plugins, missing_plugins, results)
    local update_tasks
    update_tasks, display_win = update(plugins, installed_plugins, display_win, results)
    vim.list_extend(tasks, update_tasks)
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message(
      'syncing ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    local install_paths = {}
    for plugin_name, r in pairs(results.installs) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    for plugin_name, r in pairs(results.updates) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    await(a.main)
    plugin_utils.update_helptags(install_paths)
    plugin_utils.update_rplugins()
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

--- Update the compiled lazy-loader code
-- Takes an optional argument of a path to which to output the resulting compiled code
packer.compile = function(output_path)
  output_path = output_path or config.compile_path
  local compiled_loader = compile(plugins)
  output_path = vim.fn.expand(output_path)
  vim.fn.mkdir(vim.fn.fnamemodify(output_path, ":h"), 'p')
  local output_file = io.open(output_path, 'w')
  output_file:write(compiled_loader)
  output_file:close()
  log.info('Finished compiling lazy-loaders!')
end

packer.config = config

--- Convenience function for simple setup
-- Can be invoked as follows:
--  spec can be a function:
--  packer.startup(function() use 'tjdevries/colorbuddy.vim' end)
--
--  spec can be a table with a function as its first element and config overrides as another
--  element:
--  packer.startup({function() use 'tjdevries/colorbuddy.vim' end, config = { ... }})
--
--  spec can be a table with a table of plugin specifications as its first element and config
--  overrides as another element:
--  packer.startup({{'tjdevries/colorbuddy.vim'}, config = { ... }})
packer.startup = function(spec)
  local user_func = nil
  local user_config = nil
  local user_plugins = nil
  if type(spec) == 'function' then
    user_func = spec
  elseif type(spec) == 'table' then
    if type(spec[1]) == 'function' then
      user_func = spec[1]
    elseif type(spec[1]) == 'table' then
      user_plugins = spec[1]
    else
      log.error(
        'You must provide a function or table of specifications as the first element of the argument to startup!')
      return
    end

    -- NOTE: It might be more convenient for users to allow arbitrary config keys to be specified
    -- and to merge them, but I feel that only avoids a single layer of nesting and adds more
    -- complication here, so I'm not sure if the benefit justifies the cost
    user_config = spec.config
  end

  packer.init(user_config)
  packer.reset()

  if user_func then
    setfenv(user_func, vim.tbl_extend('force', getfenv(), {use = packer.use}))
    local status, err = pcall(user_func, packer.use)
    if not status then
      log.error('Failure running setup function: ' .. vim.inspect(err))
      error(err)
    end
  else
    packer.use(user_plugins)
  end

  if not config.disable_commands then
    vim.cmd [[command! PackerInstall  lua require('packer').install()]]
    vim.cmd [[command! PackerUpdate   lua require('packer').update()]]
    vim.cmd [[command! PackerSync     lua require('packer').sync()]]
    vim.cmd [[command! PackerClean    lua require('packer').clean()]]
    vim.cmd [[command! PackerCompile  lua require('packer').compile()]]
  end

  return packer
end

return packer
