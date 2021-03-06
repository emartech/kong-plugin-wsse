local Object = require "classic"
local Logger = require "logger"
local utils = require "kong.tools.utils"

local KeyDb = Object:extend()

local function fix_consumer_reference(wsse_key)
    if wsse_key then
        wsse_key.consumer = {
            id = wsse_key.consumer_id
        }
        wsse_key.consumer_id = nil
    end
    return wsse_key
end

local function load_credential(username, strict_key_matching)
    local wsse_keys, err = kong.db.connector:query(string.format("SELECT * FROM wsse_keys WHERE key = '%s'", username))
    if err then
        return nil, err
    end

    if #wsse_keys == 0 and not strict_key_matching then
        wsse_keys, err = kong.db.connector:query(string.format("SELECT * FROM wsse_keys WHERE key_lower = '%s'", username:lower()))
        if err then
            return nil, err
        end
    end

    return fix_consumer_reference(wsse_keys[1])
end

function KeyDb:new(crypto, strict_key_matching)
    self.crypto = crypto
    self.strict_key_matching = strict_key_matching
end

function KeyDb:find_by_username(username)
    if username == nil then
        error({ msg = "Username is required." })
    end

    if string.find(username, "'") then
        error({ msg = "Username contains illegal characters." })
    end

    local cache_key = kong.db.wsse_keys:cache_key(username)
    local wsse_key, err = kong.cache:get(cache_key, nil, load_credential, username, self.strict_key_matching)

    if err then
        Logger.getInstance(ngx):logError(err)
        error({ msg = "WSSE key could not be loaded from DB." })
    end

    if wsse_key == nil then
        error({ msg = "WSSE key can not be found." })
    end

    local wsse_key_copy = utils.deep_copy(wsse_key)
    wsse_key_copy.secret = self.crypto:decrypt(wsse_key.secret)

    return wsse_key_copy
end

return KeyDb