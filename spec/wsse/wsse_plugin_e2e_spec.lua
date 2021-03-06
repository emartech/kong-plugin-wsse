local kong_helpers = require "spec.helpers"
local test_helpers = require "kong_client.spec.test_helpers"
local Wsse = require "kong.plugins.wsse.wsse_lib"
local uuid = require "kong.tools.utils".uuid
local EasyCrypto = require "resty.easy-crypto"

describe("WSSE #plugin #handler #e2e", function()

    local kong_sdk, send_request, send_admin_request
    local service, consumer

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

    local crypto = get_easy_crypto()
    local encryption_key = load_encryption_key_from_file("/secret.txt")

    setup(function()
        kong_helpers.start_kong({ plugins = "wsse" })

        kong_sdk = test_helpers.create_kong_client()
        send_request = test_helpers.create_request_sender(kong_helpers.proxy_client())
        send_admin_request = test_helpers.create_request_sender(kong_helpers.admin_client())
    end)

    teardown(function()
        kong_helpers.stop_kong()
    end)

    before_each(function()
        kong_helpers.db:truncate()

        service = kong_sdk.services:create({
            name = "testservice",
            url = "http://mockbin:8080/request"
        })

        kong_sdk.routes:create_for_service(service.id, "/")

        consumer = kong_sdk.consumers:create({
            username = "TestUser"
        })
    end)

    context("when no anonymous consumer was configured", function()

        before_each(function()
            kong_sdk.plugins:create({
                service = { id = service.id },
                name = "wsse",
                config = {
                    encryption_key_path = "/secret.txt"
                }
            })
        end)

        it("should reject request with HTTP 401 if X-WSSE header is not present", function()
            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com"
                }
            })

            assert.are.equals(401, response.status)
            assert.are.equals("WSSE authentication header is missing.", response.body.message)
        end)

        it("should reject request with HTTP 401 if X-WSSE header is malformed", function()
            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = "some wsse header string"
                }
            })

            assert.are.equals(401, response.status)
            assert.are.equals("The Username field is missing from WSSE authentication header.", response.body.message)
        end)

        it("should proxy the request to the upstream on successful auth", function()
            local header = Wsse.generate_header("test", "test", uuid())

            send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/wsse_key",
                body = {
                    key = 'test',
                    secret = "test",
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = header
                }
            })

            assert.are.equals(200, response.status)
        end)

        it("should reject the request with HTTP 401 when WSSE key could not be found", function()
            send_admin_request({
                method = "PUT",
                path = "/consumers/" .. consumer.id .. "/wsse_key",
                body = {
                    key = 'test001'
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = 'UsernameToken Username="test003", PasswordDigest="ODM3MmJiN2U2OTA2ZDhjMDlkYWExY2ZlNDYxODBjYTFmYTU0Y2I0Mg==", Nonce="4603fcf8f0fb2ea03a41ff007ea70d25", Created="2018-02-27T09:46:22Z"'
                }
            })

            assert.are.equals(401, response.status)
            assert.are.equals("Credentials are invalid.", response.body.message)
        end)

        context("when timeframe validation fails", function()
            it("should proxy the request to the upstream if strict validation was disabled", function ()
                local header = Wsse.generate_header("test2", "test2", uuid(), "2017-02-27T09:46:22Z")

                send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/wsse_key",
                    body = {
                        key = "test2",
                        secret = "test2",
                        strict_timeframe_validation = false
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com",
                        ["X-WSSE"] = header
                    }
                })

                assert.are.equals(200, response.status)
            end)

            it("should reject the request with HTTP 401 when strict validation is on", function ()
                local header = Wsse.generate_header("test2", "test2", uuid(), "2017-02-27T09:46:22Z")

                send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/wsse_key",
                    body = {
                        key = 'test2',
                        secret = "test2",
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com",
                        ["X-WSSE"] = header
                    }
                })

                assert.are.equals(401, response.status)
                assert.are.equals("Timeframe is invalid.", response.body.message)
            end)
        end)

    end)

    context("With anonymous user enabled", function()

        before_each(function()
            local anonymous_consumer = kong_sdk.consumers:create({
                username = "anonymous"
            })

            kong_sdk.plugins:create({
                service = { id = service.id },
                name = "wsse",
                config = {
                    anonymous = anonymous_consumer.id,
                    encryption_key_path = "/secret.txt"
                }
            })
        end)

        it("should proxy request with anonymous user if X-WSSE header is not present", function()
            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com"
                }
            })

            assert.are.equals(200, response.status)
            assert.are.equals("anonymous", response.body.headers["x-consumer-username"])
        end)

        it("should proxy the request to the upstream when header is present two times", function()
            local header = Wsse.generate_header("test1", "test1", uuid())
            local other_header = Wsse.generate_header("test1", "test1", uuid())

            send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/wsse_key",
                body = {
                    key = 'test1',
                    secret = "test1",
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = {header, other_header},
                }
            })

            assert.are.equals(200, response.status)
            assert.are.equals("TestUser", response.body.headers["x-consumer-username"])
        end)

        it("should proxy the request with anonymous user if X-WSSE header is malformed", function()
            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = "some wsse header string"
                }
            })

            assert.are.equals(200, response.status)
            assert.are.equals("anonymous", response.body.headers["x-consumer-username"])
        end)

        it("should proxy the request to the upstream on successful auth", function()
            local header = Wsse.generate_header("test", "test", uuid())

            send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/wsse_key",
                body = {
                    key = 'test',
                    secret = "test",
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = header
                }
            })

            assert.are.equals(200, response.status)
            assert.are.equals("TestUser", response.body.headers["x-consumer-username"])
        end)

        it("should proxy the request with anonymous user when WSSE key could not be found", function()
            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = 'UsernameToken Username="non-existing", PasswordDigest="ODM3MmJiN2U2OTA2ZDhjMDlkYWExY2ZlNDYxODBjYTFmYTU0Y2I0Mg==", Nonce="4603fcf8f0fb2ea03a41ff007ea70d25", Created="2018-02-27T09:46:22Z"'
                }
            })

            assert.are.equals(200, response.status)
            assert.are.equals("anonymous", response.body.headers["x-consumer-username"])
        end)

        context("when timeframe is invalid", function()
            it("should proxy the request to the upstream if strict validation was disabled", function ()
                local header = Wsse.generate_header("test2", "test2", uuid(), "2017-02-27T09:46:22Z")

                send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/wsse_key",
                    body = {
                        key = 'test2',
                        secret = "test2",
                        strict_timeframe_validation = false
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com",
                        ["X-WSSE"] = header
                    }
                })

                assert.are.equals(200, response.status)
                assert.are.equals("TestUser", response.body.headers["x-consumer-username"])
            end)

            it("should proxy the request with anonymous when strict validation is on", function ()
                local header = Wsse.generate_header("test2", "test2", uuid(), "2017-02-27T09:46:22Z")

                send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/wsse_key",
                    body = {
                        key = 'test2',
                        secret = 'test2'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com",
                        ["X-WSSE"] = header
                    }
                })

                assert.are.equals(200, response.status)
                assert.are.equals("anonymous", response.body.headers["x-consumer-username"])
            end)
        end)
    end)

    context('when strict key matching is disabled', function()

        before_each(function()
            kong_sdk.plugins:create({
                service = { id = service.id },
                name = "wsse",
                config = {
                    strict_key_matching = false,
                    encryption_key_path = "/secret.txt"
                }
            })
        end)

        it('should respond with 200 when wsse key casing is different', function()
            local header = Wsse.generate_header("testci", "test", uuid())

            send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/wsse_key",
                body = {
                    key = 'TeStCi',
                    secret = "test",
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            local response = send_request({
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com",
                    ["X-WSSE"] = header
                }
            })

            assert.are.equals(200, response.status)
        end)

    end)

    context('when given status code for failed authentications', function()

        before_each(function()
            kong_sdk.plugins:create({
                service = { id = service.id },
                name = "wsse",
                config = {
                    status_code = 400,
                    encryption_key_path = "/secret.txt"
                }
            })
        end)

        it("should reject request with given HTTP status", function()
            local response = send_request({
                method = "GET",
                path = "/request"
            })

            assert.are.equals(400, response.status)
        end)
    end)

    context("when message template is not default", function()

        before_each(function()
            kong_sdk.plugins:create({
                service = { id = service.id },
                name = "wsse",
                config = {
                    message_template = '{"custom-message": "%s"}',
                    encryption_key_path = "/secret.txt"
                }
            })
        end)

        it("should return response message in the given format", function()
            local response = send_request({
                method = "GET",
                path = "/request"
            })

            assert.are.equals(401, response.status)
            assert.is_nil(response.body.message)
            assert.are.equals("WSSE authentication header is missing.", response.body['custom-message'])
        end)
    end)

    it("should not modify the cache by reference", function()
        local plugin = kong_sdk.plugins:create({
            service = { id = service.id },
            name = "wsse",
            config = {
                encryption_key_path = "/secret.txt"
            }
        })

        send_admin_request({
            method = "POST",
            path = "/consumers/" .. consumer.id .. "/wsse_key",
            body = {
                key = 'my-key',
                secret = "secret",
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })

        local header = Wsse.generate_header("my-key", "secret", uuid())

        local first_response = send_request({
            method = "GET",
            path = "/request",
            headers = {
                ["Host"] = "test1.com",
                ["X-WSSE"] = header
            }
        })
        local second_response = send_request({
            method = "GET",
            path = "/request",
            headers = {
                ["Host"] = "test1.com",
                ["X-WSSE"] = header
            }
        })

        assert.are.equals(200, first_response.status)
        assert.are.equals(200, second_response.status)
    end)

end)
