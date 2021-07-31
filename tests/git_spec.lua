local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait
local log = require('packer.log')
local fmt = string.format
local packer = require('packer')

local use = packer.use

local spec = {'wbthomason/packer.nvim'}

a.describe("Packer testing git", function ()
    a.describe("get_rev()", function ()
        before_each(function ()
            local _packer = packer.startup(function ()
                use(spec)
            end)
            _packer.__manage_all()
        end)
        a.it("of existing plugin", function ()
            spec.install_path = vim.loop.cwd()
            local res = await(spec.get_rev())
            log.info(fmt("res = %s", res))
            assert.True(type(res) == "string")
            assert.True(res ~= "")
        end)

        a.it("of non-existing plugin", function ()
            spec.install_path = ""
            local res = await(spec.get_rev())
            log.info(vim.inspect(res))
            assert.are.equals("", res)
        end)
    end)
end)
