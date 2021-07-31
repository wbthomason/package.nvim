local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait
local log = require('packer.log')
local fmt = string.format

local spec = { {'wbthomason/packer.nvim'} }

a.describe("Packer testing git", function ()
    a.describe("get_rev()", function ()

        a.it("of existing plugin", function ()
            local packer = require("packer")
            local use = packer.use
            local _packer = packer.startup(function ()
                use(spec)
            end)
            _packer.__manage_all()
            log.info(fmt("spec = %s", vim.inspect(spec)))
            local res = await(spec.get_rev())
            log.info(fmt("res = %s", res))
            log.info(vim.inspect(res))
            assert.True(type(res) == "string")
            assert.True(res ~= "")
        end)

        a.it("of non-existing plugin", function ()
            local packer = require("packer")
            local use = packer.use
            spec = { {'wbthomason/packer.nvim'}, { "not-valid-plugin" } }
            local _packer = packer.startup(function ()
                use(spec)
            end)
            spec.install_path = "/not-valid-path"
            _packer.__manage_all()
            log.info(fmt("spec = %s", vim.inspect(spec)))

            local res = await(spec.get_rev())
            log.info(fmt("res = %s", res))
            log.info(vim.inspect(res))
            assert.are.equals("", res)
        end)
    end)
end)
