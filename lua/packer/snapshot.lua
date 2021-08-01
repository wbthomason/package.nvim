local a = require 'packer.async'
local async = a.sync
local await = a.wait
local fmt = string.format
local log = require 'packer.log'
local plugin_utils = require 'packer.plugin_utils'

local function cfg(_config)
  config = _config
end

---Makes a snapshot of all plugins to the path specified by `filename`
---If there is already a snapshot it will be overwritten
---Snapshotting work only with `git` plugins, other plugins will be ignored.
---@param filename string
---@param plugins Plugin[]
---@return function
local function do_snapshot(_, filename, plugins)
  if type(plugins) ~= "table" then
    plugins = { plugins }
  end
  return async(function()
    local snapshot_content = ''
    local opt, start = plugin_utils.list_installed_plugins()
    local installed = {}

    for key, _ in pairs(opt) do installed[key] = key end
    for key, _ in pairs(start) do installed[key] = key end

    log.debug(vim.inspect(plugins))
    log.debug(fmt("installed= %s", vim.inspect(installed)))
    for _, plugin in pairs(plugins) do
      log.debug(vim.inspect(plugin))
      if installed[plugin.install_path] ~= nil then -- this plugin is installed
        log.debug(fmt("Snapshotting '%s'", plugin.short_name))
        if plugin.type == plugin_utils.git_plugin_type then
          local r = await(plugin.get_rev())

          log.debug(vim.inspect(r))
          if r == nil then
            log.warning(fmt('Snapshotting %s failed', plugin.short_name))
          else
            snapshot_content = snapshot_content .. plugin.short_name .. ' ' .. r.ok .. '\n'
          end
        end
      end
    end

    local file, err = io.open(filename, 'w+')
    if err then
      log.err(err)
    else
      file:write(snapshot_content)
    end

    if file ~= nil then
      file:close()
    end
    log.debug "Snapshot completed"
  end)
end

local snapshot = setmetatable({ cfg = cfg }, { __call = do_snapshot })

return snapshot

-- vim:sw=2 ts=2 et
