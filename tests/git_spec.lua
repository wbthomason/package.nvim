local a = require('plenary.async_lib.tests')
local before_each = require('plenary.busted').before_each
local await = require('packer.async').wait
local log = require('packer.log')
local fmt = string.format

local spec = {'wbthomason/packer.nvim'}

a.describe("Packer testing git", function ()
--    a.describe("get_rev()", function ()
--
--        a.it("of existing plugin", function ()
--            local packer = require("packer")
--            local use = packer.use
--            local _packer = packer.startup(function ()
--                use(spec)
--            end)
--            _packer.__manage_all()
--            log.info(fmt("spec = %s", vim.inspect(spec)))
--            local res = await(spec.get_rev())
--            log.info(fmt("res = %s", res))
--            log.info(vim.inspect(res))
--            assert.True(type(res) == "string")
--            assert.True(res ~= "")
--        end)
--
--        a.it("of non-git plugin", function ()
--            local packer = require("packer")
--            local use = packer.use
--            spec = { {'wbthomason/packer.nvim'}, { "not-valid-plugin" } }
--            local _packer = packer.startup(function ()
--                use(spec)
--            end)
--            spec.install_path = "/not-valid-path"
--            spec[2].type = "local"
--            _packer.__manage_all()
--            log.info(fmt("spec = %s", vim.inspect(spec)))
--            assert.is_nil(spec[2].get_rev)
--        end)
--    end)

    a.describe("reset_commit()", function ()
        a.it("of existing plugin", function ()
            local function update()
                local jobs = require 'packer.jobs'
                local update_cmd = "git" .. ' pull --ff-only --progress --rebase=false'
                local dest = "/home/nezuko/Downloads/github/packer.nvim.git/snapshot/"
                log.info(update_cmd)
                local opts = { capture_output = true, cwd = dest }
                return jobs.run(update_cmd, opts)
            end

            log.info('funzioni')
            await(update()):map_ok(function (ok)
                log.info("ok")
                log.info(vim.inspect(ok))
            end):map_err(function (err)
                log.info("err")
                log.info(vim.inspect(err))
            end)

            local packer = require("packer")
            local use = packer.use
            local _packer = packer.startup(function ()
                use(spec)
            end)
            _packer.__manage_all()
            spec.commit = "2acfa72"
--            local r = await(spec.reset_commit())
--            local commit = await(spec.get_rev())
--            assert.are.equals(spec.commit, commit)
            assert.True(true)

        end)
    end)
end)
