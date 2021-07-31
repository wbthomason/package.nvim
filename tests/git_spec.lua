local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait

local packer = require('packer')

local use = packer.use

local spec = {'wbthomason/packer.nvim'}

a.describe("Packer testing git", function ()
    before_each(function ()
        local _packer = packer.startup(function ()
            use(spec)
        end)
        _packer.__manage_all()
        spec.install_path = vim.loop.cwd()
    end)
    a.describe("get_rev()", function ()
        a.it("get_rev of existing package", function ()
            local res = await(spec.get_rev())
            assert.True(type(res) == "string")
            assert.True(res ~= "")
        end)
    end)
end)
