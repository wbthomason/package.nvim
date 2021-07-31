local a = require('plenary.async_lib.tests')
local with = require('plenary.context_manager').with
local open = require('plenary.context_manager').open
local path = require('plenary.path')
local strings = require('plenary.strings')
local describe = require('plenary.busted').describe
local it = require('plenary.busted').it
local await = require('packer.async').wait
local async = require('packer.async').sync
local packer = require("packer")
local log = require "packer.log"
local use = packer.use
local fmt = string.format

local config = {
    snapshot_path = vim.fn.stdpath("cache") .. "/" .. "packer",
    display = {
        non_interactive = true,
        open_cmd = '65vnew \\[packer\\]',
        }
}

local spec = {'wbthomason/packer.nvim'}

a.describe('Packer testing ', function ()
    local snapshot_name = "test"
    local test_path = config.snapshot_path .. "/" .. snapshot_name
    local snapshot = require 'packer.snapshot'
    local p = path:new(test_path)

    before_each(function ()
        local _packer = packer.startup(function ()
            use(spec)
        end)
        _packer.__manage_all()
    end)

    a.describe('packer.snapshot()', function ()
        a.it(fmt("create snapshot with installed plugins'%s'", test_path), function ()
            await(snapshot(test_path, {spec}))
            assert.True(p:exists())
        end)

        after_each(function ()
            p:rm()
        end)
    end)

    a.describe('packer.rollback()', function ()
        a.it(fmt("restore plugin to previous state"), function ()
            local rev = 'c8c0600'
            with(open(test_path, 'w+'), function (file)
                file:write(fmt("%s %s", "packer.nvim", rev))
            end)

            packer.rollback(snapshot_name)
            p:rm()
            assert.False(p:exists())
            await(snapshot(test_path, {spec}))
--
--            local res = with(open(test_path), function (file)
--                return strings.strcharpart(file:read(), 11)
--            end)

            assert.equal(rev, res)
        end)
    end)
end)
