local before_each = require('plenary.busted').before_each
local path        = require('plenary.path')
local a           = require('plenary.async_lib.tests')
local mocked_plugin_utils = require('packer.plugin_utils')
local log = require('packer.log')

local await       = require('packer.async').wait
local fmt         = string.format
local packer      = require('packer')

local config = {
    snapshot_path = vim.fn.stdpath("cache") .. "/" .. "packer",
    display = {
        non_interactive = true,
        open_cmd = '65vnew \\[packer\\]',
    },
    start_dir = "../../"
}

--[[ For testing purposes the spec file is made up so that when running `packer`
it could manage it as if it was in `~/.local/share/nvim/site/pack/packer/start/` --]]
local install_path = vim.fn.getcwd()

mocked_plugin_utils.list_installed_plugins = function ()
    return {[install_path] = true}, {}
end

local old_require = _G.require

_G.require = function (modname)
    if modname == 'plugin_utils' then
        return mocked_plugin_utils
    end

    return old_require(modname)
end

local spec = {'wbthomason/packer.nvim'}

local cache_path = path:new(config.snapshot_path)
vim.fn.mkdir(tostring(cache_path), "p")

a.describe('Packer testing ', function ()
    local snapshot_name = "test"
    local test_path = path:new(config.snapshot_path .. "/" .. snapshot_name)
    local snapshot = require 'packer.snapshot'

    before_each(function ()
        packer.reset()
        packer.init(config)
        packer.use(spec)
        packer.__manage_all()
    end)

    a.describe('packer.snapshot()', function ()
        a.it(fmt("create snapshot in '%s'", test_path), function ()
            spec.install_path = install_path
            await(snapshot(tostring(test_path), {spec}))
            assert.True(test_path:exists())
        end)

        it("checking if snapshot content corresponds to plugins'", function ()
            ---@type string
            local line = test_path:read()
            local start, i_end, captured = string.find(line, " ")

            log.debug(fmt("start = %s", start))
            log.debug(fmt("end = %s", i_end))
            log.debug(fmt("captured = %s", captured))

            local name = string.sub(line, 1, start-1)
            local commit = string.sub(line, start + 1, line:len()-1)
            log.debug(fmt("name = %s", name))
            log.debug(fmt("commit = %s", commit))
            log.debug(fmt("line = %s", vim.inspect(line)))

            assert.are.equals("packer.nvim", name)
            local expected_rev = await(spec.get_rev())
            assert.are.equals(expected_rev, commit)
        end)
    end)
end)
