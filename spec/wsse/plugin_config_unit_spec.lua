local PluginConfig = require "kong.plugins.wsse.plugin_config"

describe("PluginConfig", function()
    describe("#merge_onto_defaults", function()
        it("should return an empty table for an empty schema and empty config", function()
            local schema = {
                fields = {}
            }
            local config = {}
            local merged_config = PluginConfig(schema):merge_onto_defaults(config)
            local expected_config = {}

            assert.are.same(expected_config, merged_config)
        end)

        it("should return merged copy of schema defaults and config", function()
            local schema = {
                fields = {
                    {
                        config = {
                            type = "record",
                            fields = {
                                { my_config = { type = "string" } },
                                { with_default = { type = "string", default = "some other value" } }
                            }
                        }
                    }
                }
            }
            local config = {
                my_config = "some value"
            }
            local merged_config = PluginConfig(schema):merge_onto_defaults(config)
            local expected_config = {
                my_config = "some value",
                with_default = "some other value"
            }

            assert.are.same(expected_config, merged_config)
        end)

        it("should handle the plugin's schema correctly", function()
            local schema = require "kong.plugins.wsse.schema"
            local config = {}
            local merged_config = PluginConfig(schema):merge_onto_defaults(config)
            local expected_config = {
                timeframe_validation_threshold_in_minutes = 5,
                strict_key_matching = true,
                message_template = '{"message": "%s"}',
                status_code = 401,
                use_encrypted_secret = 'no'
            }

            assert.are.same(expected_config, merged_config)
        end)
    end)
end)
