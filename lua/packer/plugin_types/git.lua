local util = require('packer.util')
local jobs = require('packer.jobs')
local a = require('packer.async')
local result = require('packer.result')
local await = a.wait
local async = a.sync
local fmt = string.format

local vim = vim

local git = {}

local config = nil
git.cfg = function(_config)
  config = _config.git
  config.base_dir = _config.package_root
  config.default_base_dir = util.join_paths(config.base_dir, _config.plugin_package)
  config.exec_cmd = config.cmd .. ' '
end

local handle_checkouts = function(plugin, dest, disp)
  local plugin_name = util.get_plugin_full_name(plugin)
  return async(function()
    if disp ~= nil then disp:task_update(plugin_name, 'fetching reference...') end
    local output = jobs.output_table()
    local callbacks = {
      stdout = jobs.logging_callback(output.err.stdout, output.data.stdout, nil, disp, plugin_name),
      stderr = jobs.logging_callback(output.err.stderr, output.data.stderr)
    }

    local opts = {capture_output = callbacks}

    local r = result.ok(true)

    if plugin.branch or plugin.tag then
      local branch_or_tag = plugin.branch and plugin.branch or plugin.tag
      if disp ~= nil then
        disp:task_update(plugin_name, fmt('checking out %s %s...',
                                          plugin.branch and 'branch' or 'tag', branch_or_tag))
      end
      r = r:and_then(await, jobs.run(config.exec_cmd
                                       .. fmt(config.subcommands.checkout, dest, branch_or_tag),
                                     opts)):map_err(
            function(err)
          return {
            msg = fmt('Error checking out %s %s for %s', plugin.branch and 'branch' or 'tag',
                      branch_or_tag, plugin_name),
            data = err,
            output = output
          }
        end)
    end

    if plugin.commit then
      if disp ~= nil then
        disp:task_update(plugin_name, fmt('checking out %s...', plugin.commit))
      end
      r = r:and_then(await, jobs.run(config.exec_cmd
                                       .. fmt(config.subcommands.checkout, dest, plugin.commit),
                                     opts)):map_err(
            function(err)
          return {
            msg = fmt('Error checking out commit %s for %s', plugin.commit, plugin_name),
            data = err,
            output = output
          }
        end)
    end

    return r:map_ok(function(ok) return {status = ok, output = output} end):map_err(
             function(err)
        if not err.msg then
          return {
            msg = fmt('Error updating %s: %s', plugin_name, table.concat(err, '\n')),
            data = err,
            output = output
          }
        end

        err.output = output
        return err
      end)
  end)
end

git.setup = function(plugin)
  local plugin_name = util.get_plugin_full_name(plugin)
  local install_to = plugin.install_path
  local install_cmd = config.exec_cmd
                        .. fmt(config.subcommands.install, plugin.url, install_to,
                               plugin.commit and 999999 or config.depth)
  local submodule_cmd = config.exec_cmd .. fmt(config.subcommands.submodules, install_to)
  local rev_cmd = config.exec_cmd .. fmt(config.subcommands.get_rev, install_to)
  local update_cmd = config.exec_cmd
  if plugin.commit or plugin.tag then
    update_cmd = update_cmd .. fmt(config.subcommands.fetch, install_to)
  else
    update_cmd = update_cmd .. fmt(config.subcommands.update, install_to)
  end

  local branch_cmd = config.exec_cmd .. fmt(config.subcommands.current_branch, install_to)
  local commit_cmd =
    vim.split(config.exec_cmd .. fmt(config.subcommands.get_msg, install_to), '%s+')
  for i, arg in ipairs(commit_cmd) do
    commit_cmd[i] = string.gsub(arg, 'FMT', config.subcommands.diff_fmt)
  end

  local messages_cmd = vim.split(config.exec_cmd .. fmt(config.subcommands.diff, install_to), '%s+')
  for i, arg in ipairs(messages_cmd) do
    messages_cmd[i] = string.gsub(arg, 'FMT', config.subcommands.diff_fmt)
  end

  if plugin.branch or plugin.tag then
    install_cmd = fmt('%s --branch %s', install_cmd, plugin.branch and plugin.branch or plugin.tag)
  end

  local needs_checkout = plugin.tag ~= nil or plugin.commit ~= nil or plugin.branch ~= nil

  plugin.installer = function(disp)
    local output = jobs.output_table()
    local callbacks = {
      stdout = jobs.logging_callback(output.err.stdout, output.data.stdout),
      stderr = jobs.logging_callback(output.err.stderr, output.data.stderr, nil, disp, plugin_name)
    }

    local installer_opts = {capture_output = callbacks, timeout = config.clone_timeout}

    return async(function()
      disp:task_update(plugin_name, 'cloning...')
      local r = await(jobs.run(install_cmd, installer_opts))
      r = r:and_then(await, jobs.run(submodule_cmd, installer_opts))

      if plugin.commit then
        disp:task_update(plugin_name, fmt('checking out %s...', plugin.commit))
        r = r:and_then(await,
                       jobs.run(config.exec_cmd
                                  .. fmt(config.subcommands.checkout, install_to, plugin.commit),
                                installer_opts)):map_err(
              function(err)
            return {
              msg = fmt('Error checking out commit %s for %s', plugin.commit, plugin_name),
              data = {err, output}
            }
          end)
      end

      r = r:and_then(await, jobs.run(commit_cmd, installer_opts)):map_ok(
            function(_) plugin.messages = output.data.stdout end):map_err(
            function(err)
          plugin.output = {err = output.data.stderr}
          if not err.msg then
            return {
              msg = fmt('Error installing %s: %s', plugin_name,
                        table.concat(output.data.stderr, '\n')),
              data = {err, output}
            }
          end
        end)

      return r
    end)
  end

  plugin.updater = function(disp)
    return async(function()
      local update_info = {err = {}, revs = {}, output = {}, messages = {}}

      local function exit_ok(r)
        if #update_info.err > 0 or r.exit_code ~= 0 then return result.err(r) end
        return result.ok(r)
      end

      local rev_onread = jobs.logging_callback(update_info.err, update_info.revs)
      local rev_callbacks = {stdout = rev_onread, stderr = rev_onread}

      disp:task_update(plugin_name, 'checking current commit...')
      local r
      r =
        await(jobs.run(rev_cmd, {success_test = exit_ok, capture_output = rev_callbacks})):map_err(
          function(err)
            plugin.output = {err = vim.list_extend(update_info.err, update_info.revs), data = {}}

            return {
              msg = fmt('Error getting current commit for %s: %s', plugin_name,
                        table.concat(update_info.revs, '\n')),
              data = err
            }
          end)

      local current_branch
      disp:task_update(plugin_name, 'checking current branch...')
      r = r:and_then(await, jobs.run(branch_cmd, {success_test = exit_ok, capture_output = true}))
            :map_ok(function(ok) current_branch = ok.output.data.stdout[1] end):map_err(
              function(err)
            plugin.output = {err = vim.list_extend(update_info.err, update_info.revs), data = {}}

            return {
              msg = fmt('Error checking current branch for %s: %s', plugin_name,
                        table.concat(update_info.revs, '\n')),
              data = err
            }
          end)

      if not needs_checkout then
        local origin_branch = ''
        disp:task_update(plugin_name, 'checking origin branch...')
        local origin_refs_path = util.join_paths(install_to, '.git', 'refs', 'remotes', 'origin', 'HEAD')
        local origin_refs_file = vim.loop.fs_open(origin_refs_path, 'r', 438)
        if origin_refs_file ~= nil then
          local origin_refs_stat = vim.loop.fs_fstat(origin_refs_file)
          -- NOTE: This should check for errors
          local origin_refs = vim.split(vim.loop.fs_read(origin_refs_file, origin_refs_stat.size, 0), '\n')
          vim.loop.fs_close(origin_refs_file)
          if #origin_refs > 0 then
            origin_branch = string.match(origin_refs[1], [[^ref: refs/remotes/origin/(.*)]])
          end
        end

        if current_branch ~= origin_branch then
          needs_checkout = true
          plugin.branch = origin_branch
        end
      end

      if needs_checkout then
        r = r:and_then(await, handle_checkouts(plugin, install_to, disp))
        local function merge_output(res)
          if res.output ~= nil then
            vim.list_extend(update_info.err, res.output.err.stderr)
            vim.list_extend(update_info.err, res.output.err.stdout)
            vim.list_extend(update_info.output, res.output.data.stdout)
            vim.list_extend(update_info.output, res.output.data.stderr)
          end
        end

        r:map_ok(merge_output)
        r:map_err(function(err)
          merge_output(err)
          plugin.output = {err = vim.list_extend(update_info.err, update_info.output), data = {}}
          return {msg = err.msg .. ' ' .. table.concat(update_info.output, '\n'), data = err.data}
        end)
      end

      local update_callbacks = {
        stdout = jobs.logging_callback(update_info.err, update_info.output),
        stderr = jobs.logging_callback(update_info.err, update_info.output, nil, disp, plugin_name)
      }

      disp:task_update(plugin_name, 'pulling updates...')
      r = r:and_then(await, jobs.run(update_cmd,
                                     {success_test = exit_ok, capture_output = update_callbacks}))
            :and_then(await, jobs.run(submodule_cmd,
                                      {success_test = exit_ok, capture_output = update_callbacks}))
            :map_err(function(err)
          plugin.output = {err = vim.list_extend(update_info.err, update_info.output), data = {}}

          return {
            msg = fmt('Error pulling updates for %s: %s', plugin_name,
                      table.concat(update_info.output, '\n')),
            data = err
          }
        end)

      disp:task_update(plugin_name, 'checking updated commit...')
      r = r:and_then(await,
                     jobs.run(rev_cmd, {success_test = exit_ok, capture_output = rev_callbacks}))
            :map_err(function(err)
          plugin.output = {err = vim.list_extend(update_info.err, update_info.revs), data = {}}
          return {
            msg = fmt('Error checking updated commit for %s: %s', plugin_name,
                      table.concat(update_info.revs, '\n')),
            data = err
          }
        end)

      if r.ok then
        if update_info.revs[1] ~= update_info.revs[2] then
          local messages_onread = jobs.logging_callback(update_info.err, update_info.messages)
          local messages_callbacks = {stdout = messages_onread, stderr = messages_onread}

          disp:task_update(plugin_name, 'getting commit messages...')
          r = r:and_then(await, jobs.run(messages_cmd, {
            success_test = exit_ok,
            capture_output = messages_callbacks
          }))

          plugin.output = {err = update_info.err, data = update_info.output}
          if r.ok then
            plugin.messages = update_info.messages
            plugin.revs = update_info.revs
          end
        else
          plugin.revs = update_info.revs
          plugin.messages = update_info.messages
        end
      else
        plugin.output.err = vim.list_extend(plugin.output.err, update_info.messages)
      end

      r.info = update_info
      return r
    end)
  end

  plugin.revert_last = function()
    local r = result.ok(true)
    async(function()
      local revert_cmd = config.exec_cmd .. fmt(config.subcommands.revert, install_to)
      r = r:and_then(await, jobs.run(revert_cmd, {capture_output = true}))
      if needs_checkout then r = r:and_then(await, handle_checkouts(plugin, install_to, nil)) end
      return r
    end)()
    return r
  end
end

return git
