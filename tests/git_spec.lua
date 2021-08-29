local a = require('plenary.async_lib.tests')
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
            local function reset()
                local jobs = require 'packer.jobs'
                local commit = "589af85c954eb530d0a711ff994029fa2c2f10c2"
                local reset_cmd = fmt("git" .. ' reset --soft %s --', commit)
                log.debug(reset_cmd)
                local dest = "./unimi-dl/"
                local opts = { capture_output = true, cwd = dest }
                return jobs.run(reset_cmd, opts)
            end

            --            await(reset())
            local packer = require("packer")
            local use = packer.use
            local _packer = packer.startup(function ()
                use(spec)
            end)
            _packer.__manage_all()
            spec.commit = "2acfa72"
            local r = await(spec.reset_commit())
            local commit = await(spec.get_rev())
            assert.are.equals(spec.commit, commit)

        end)
    end)
end)
