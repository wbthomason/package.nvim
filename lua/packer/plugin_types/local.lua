local a = require('packer.async')
local log = require('packer.log')
local util = require('packer.util')
local Display = require('packer.display').Display

local uv = vim.loop

local M = {}










local symlink_fn
if util.is_windows then
   symlink_fn = function(path, new_path, flags, callback)
      flags = flags or {}
      flags.junction = true
      return uv.fs_symlink(path, new_path, flags, callback)
   end
else
   symlink_fn = uv.fs_symlink
end

local symlink = a.wrap(symlink_fn, 4)
local unlink = a.wrap(uv.fs_unlink, 2)

M.installer = a.sync(function(plugin, disp)
   local from = uv.fs_realpath(util.strip_trailing_sep(plugin.url))
   local to = util.strip_trailing_sep(plugin.install_path)

   disp:task_update(plugin.full_name, 'making symlink...')
   local err, success = symlink(from, to, { dir = true })
   if not success then
      plugin.err = { err }
      return plugin.err
   end
end, 2)

M.updater = a.sync(function(plugin, disp)
   local from = uv.fs_realpath(util.strip_trailing_sep(plugin.url))
   local to = util.strip_trailing_sep(plugin.install_path)
   disp:task_update(plugin.full_name, 'checking symlink...')
   local resolved_path = uv.fs_realpath(to)
   if resolved_path ~= from then
      disp:task_update(plugin.full_name, 'updating symlink...')
      local err, success = unlink(to)
      if success then
         err = symlink(from, to, { dir = true })
      end
      if err then
         return err
      end
   end
end, 1)

M.revert_last = function(_)
   log.warn("Can't revert a local plugin!")
end

M.diff = function(_, _, _)
   log.warn("Can't diff a local plugin!")
end

return M