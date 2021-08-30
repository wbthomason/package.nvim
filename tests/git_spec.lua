local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait
local log = require('packer.log')
local fmt = string.format

local spec = {'wbthomason/packer.nvim'}

a.describe("Packer testing git", function ()
    a.describe("get_rev()", function ()

        a.it("of existing plugin", function ()
            local packer = require("packer")
            local use = packer.use
            local _packer = packer.startup(function ()
                use(spec)
            end)
            _packer.__manage_all()
            local res = await(spec.get_rev())
            assert.True(type(res) == "string")
            assert.True(res ~= "")
        end)

        a.it("of non-git plugin", function ()
            local packer = require("packer")
            local use = packer.use
            spec = { {'wbthomason/packer.nvim'}, { "not-valid-plugin" } }
            local _packer = packer.startup(function ()
                use(spec)
            end)
            spec.install_path = "/not-valid-path"
            spec[2].type = "local"
            _packer.__manage_all()
            assert.is_nil(spec[2].get_rev)
        end)
    end)

--    a.describe("revert()", function ()
--        a.it("of existing plugin", function ()
--            local packer = require("packer")
--            local use = packer.use
--            local _packer = packer.startup(function ()
--                use(spec)
--            end)
--            _packer.__manage_all()
--            spec = spec[1]
--            spec.commit = "2acfa72"
--            log.info(vim.inspect(spec))
--            await(spec.revert())
--            local commit = await(spec.get_rev())
--            assert.are.equals(spec.commit, commit)
--        end)
--    end)
end)
