local before_each = require('plenary.busted').before_each
local path        = require('plenary.path')
local a           = require('plenary.async_lib.tests')
local mocked_plugin_utils = require('packer.plugin_utils')

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
        spec.install_path = install_path
    end)

    a.describe('packer.snapshot()', function ()
        a.it(fmt("create snapshot with installed plugins'%s'", test_path), function ()
            await(snapshot(tostring(test_path), {spec}))
            assert.True(test_path:exists())
--            local rev = 'c8c0600'
--            local line = with(open(test_path), function (read)
--                    return read:read()
--                end)
--            assert.equals(rev, line)
--            print(vim.inspect(line))
        end)
    end)

--    a.describe('packer.rollback()', function ()
--        a.it(fmt("restore plugin to previous state"), function ()
--            local rev = 'c8c0600'
--            with(open(test_path, 'w+'), function (file)
--                file:write(fmt("%s %s", "packer.nvim", rev))
--            end)
--
--            packer.rollback(snapshot_name)
--            p:rm()
--            assert.False(p:exists())
--            await(snapshot(test_path, {spec}))
--
--            local res = with(open(test_path), function (file)
--                return strings.strcharpart(file:read(), 11)
--            end)
--
--            assert.equal(rev, res)
--        end)
--    end)
end)
