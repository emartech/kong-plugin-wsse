local Logger = require "logger"
local KeyDb = require "kong.plugins.wsse.key_db"
local EasyCrypto = require "resty.easy-crypto"
local Crypt = require "kong.plugins.wsse.crypt"

Logger.getInstance = function()
    return {
        logError = function() end,
        logWarning = function() end
    }
end

describe("KeyDb", function()

    local original_kong

    local function get_easy_crypto()
        local ecrypto = EasyCrypto:new({
            saltSize = 12,
            ivSize = 16,
            iterationCount = 10000
        })
        return ecrypto
    end
    
    local function load_encryption_key_from_file(file_path)
        local file = assert(io.open(file_path, "r"))
        local encryption_key = file:read("*all")
        file:close()
        return encryption_key
    end


    setup(function()
        original_kong = _G.kong
    end)

    teardown(function()
        _G.kong = original_kong
    end)

    describe("#find_by_username", function()

        context("when kong does not queries the database", function()
            before_each(function()
                _G.kong = {
                    db = {
                        wsse_keys = {
                            cache_key = function() end
                        }
                    },
                    cache = {
                        get = function() end
                    }
                }
            end)

            it("should throw error when username is nil", function()
                local strict_key_matching = false;
                local username = nil;
                local expected_error = {
                    msg = "Username is required.",
                }

                assert.has.errors(function()
                    KeyDb(strict_key_matching):find_by_username(username)
                end, expected_error)
            end)

            it("should throw error when username is injected", function()
                local strict_key_matching = false;
                local username = "' or 1=1;--";
                local expected_error = {
                    msg = "Username contains illegal characters.",
                }

                assert.has.errors(function()
                    KeyDb(strict_key_matching):find_by_username(username)
                end, expected_error)
            end)

            it("should throw error when username is not found", function()
                local strict_key_matching = false;
                local username = "non_existing";
                local expected_error = {
                    msg = "WSSE key can not be found.",
                }

                assert.has.errors(function()
                    KeyDb(strict_key_matching):find_by_username(username)
                end, expected_error)
            end)
        end)

        context("when kong queries the database and throws an error", function()
            before_each(function()
                _G.kong = {
                    db = {
                        wsse_keys = {
                            cache_key = function() end
                        }
                    },
                    cache = {
                        get = function()
                            return nil, "error"
                        end
                    }
                }
            end)

            it("should throw error when database error happens", function()
                local strict_key_matching = false;
                local username = "username";
                local expected_error = {
                    msg = "WSSE key could not be loaded from DB.",
                }

                assert.has.errors(function()
                    KeyDb(strict_key_matching):find_by_username(username)
                end, expected_error)
            end)
        end)

        context("when kong queries the database and returns a result", function()
            local encrypted_secret = "encrypted_irrelevant";
            local crypt = {
                decrypt = function() 
                    return "decrypted_irrelevant"
                end
            }
            
            before_each(function()
                local counter = 0;
                local key = {
                    key = "username",
                    secret = "irrelevant",
                    encrypted_secret,
                    consumer_id = "consumer"
                }

                _G.kong = {
                    db = {
                        wsse_keys = {
                            cache_key = function() end
                        },
                        connector = {
                            query = function()
                                local result = counter == 0 and {} or {key}
                                counter = counter + 1
                                return result
                            end
                        }
                    },
                    cache = {
                        get = function(self, key, opts, cb, param1, param2)
                            return cb(param1, param2)
                        end
                    }
                }
            end)

            it("should return a wsse key", function()
                local strict_key_matching = false;
                local use_encrypted_key = "yes";
                local username = "USERNAME";
                local expected_key = {
                    key = "username",
                    secret = "decrypted_irrelevant",
                    encrypted_secret,
                    consumer = {
                        id = "consumer"
                    }
                }

                local key = KeyDb(crypt, strict_key_matching, use_encrypted_key):find_by_username(username);

                assert.are.same(expected_key, key)
            end)

            context("if flipper is off", function()
                it("should return a wsse key", function()
                    local strict_key_matching = false;
                    local use_encrypted_key = "no";
                    local username = "USERNAME";
                    local expected_key = {
                        key = "username",
                        secret = "irrelevant",
                        encrypted_secret,
                        consumer = {
                            id = "consumer"
                        }
                    }
    
                    local key = KeyDb(crypt, strict_key_matching, use_encrypted_key):find_by_username(username);
    
                    assert.are.same(expected_key, key)
                end)
            end)

            context("if flipper is in darklaunch mode", function()
                it("should return wsse key", function()
                    local strict_key_matching = false;
                    local use_encrypted_key = "darklaunch";
                    local username = "USERNAME";
                    local expected_key = {
                        key = "username",
                        secret = "irrelevant",
                        encrypted_secret,
                        consumer = {
                            id = "consumer"
                        }
                    }
    
                    local key = KeyDb(crypt, strict_key_matching, use_encrypted_key):find_by_username(username);
    
                    assert.are.same(expected_key, key)
                end)
            end)
        end)
    end)
end)
