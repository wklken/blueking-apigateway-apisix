--
-- TencentBlueKing is pleased to support the open source community by making
-- 蓝鲸智云 - API 网关(BlueKing - APIGateway) available.
-- Copyright (C) 2017 THL A29 Limited, a Tencent company. All rights reserved.
-- Licensed under the MIT License (the "License"); you may not use this file except
-- in compliance with the License. You may obtain a copy of the License at
--
--     http://opensource.org/licenses/MIT
--
-- Unless required by applicable law or agreed to in writing, software distributed under
-- the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
-- either express or implied. See the License for the specific language governing permissions and
-- limitations under the License.
--
-- We undertake not to change the open source license (MIT license) applicable
-- to the current version of the project delivered to anyone in the future.
--

local plugin = require("apisix.plugins.bk-permission")
local bk_apigateway_core_component = require("apisix.plugins.bk-components.bk-apigateway-core")
local cache_fallback = require("apisix.plugins.bk-cache-fallback.init")


describe(
    "bk-permission", function()
        local ctx
        local conf

        before_each(
            function()
                -- stub(bk_apigateway_core_component, "query_permission", function ()
                --     return {}, nil
                -- end)

                ctx = {
                    var = {
                        bk_gateway_name = "bk-gateway",
                        bk_resource_name = "bk-resource",
                        bk_app_code = "bk-app-code",

                        bk_resource_auth = {
                            resource_perm_required = true,
                        },
                    },
                    conf_id = 123,
                    conf_type = "hello",
                }
                conf = {}

                plugin.init()

                stub(cache_fallback, "get_with_fallback", function ()
                    return {}, nil
                end)
            end
        )

        after_each(
            function()
                -- bk_apigateway_core_component.query_permission:revert()
                cache_fallback.get_with_fallback:revert()
            end
        )

        it(
            "should check schema", function()
                assert.is_equal(plugin.priority, 17640)
                assert.is_equal(plugin.name, "bk-permission")

                assert.is_true(plugin.check_schema(conf))
            end
        )

        it(
            "init", function()
                -- assert.is_nil(plugin._get_cache())
                local cache = plugin._get_cache()
                assert.is_not_nil(cache)


                assert.equal(5120, cache.lrucache_max_items)
                assert.equal(60, cache.lrucache_ttl)
                assert.equal(30, cache.lrucache_short_ttl)
                assert.equal(3600, cache.fallback_cache_ttl)

            end
        )

        it(
            "query_permission", function()
                local permission = {
                    ["hello"] = "world"
                }
                stub(bk_apigateway_core_component, "query_permission", function ()
                    return permission, nil
                end)

                local data, err = plugin._query_permission("bk-gateway", "bk-resource", "bk-app-code")
                assert.is_nil(err)
                assert.is_equal(permission, data)

                assert.stub(bk_apigateway_core_component.query_permission).was_called(1)

                bk_apigateway_core_component.query_permission:revert()
            end
        )

        it(
            "no resource_perm_required", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {}, nil
                end)
                ctx.var.bk_resource_auth.resource_perm_required = false
                plugin.init()
                local code = plugin.access(conf, ctx)
                assert.is_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(0)
                -- ctx.var.bk_resource_auth.resource_perm_required = true
            end
        )

        -- the main logical

        it(
            "get_with_fallback fail", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return nil,"this is an error"
                end)

                plugin.init()
                local code = plugin.access(conf, ctx)
                assert.is_not_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)

                assert.is_equal(500, code)
            end
        )

        -- 2. get_with_fallback success, data is empty
        it(
            "get_with_fallback success, no data", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {}, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_not_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)

                assert.is_equal(403, code)
            end
        )

        it(
            "get_with_fallback success, has data, no hit", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {["hello"] = 1}, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_not_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)

                assert.is_equal(403, code)
            end
        )

        it(
            "hit gateway_permission, expired", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {["bk-gateway:-:bk-app-code"] = 1}, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_not_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)

                assert.is_equal(403, code)
            end
        )

        it(
            "hit gateway_permission, not expired", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {["bk-gateway:-:bk-app-code"] = 1782070327}, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)
            end
        )

        it(
            "hit resource_permission, expired", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {["bk-gateway:bk-resource:bk-app-code"] = 1}, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_not_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)

                assert.is_equal(403, code)
            end
        )

        it(
            "hit resource_permission, not expired", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {["bk-gateway:bk-resource:bk-app-code"] = 1782070327}, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)
            end
        )

        it(
            "hit both, gateway permission effect", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {
                        ["bk-gateway:-:bk-app-code"] = 1782070327,
                        ["bk-gateway:bk-resource:bk-app-code"] = 1
                    }, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)
            end
        )
        it(
            "hit both, resource permission effect", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {
                        ["bk-gateway:-:bk-app-code"] = 1,
                        ["bk-gateway:bk-resource:bk-app-code"] = 1782070327
                    }, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)
            end
        )
        it(
            "hit both, both permission effect", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {
                        ["bk-gateway:-:bk-app-code"] = 1782070327,
                        ["bk-gateway:bk-resource:bk-app-code"] = 1782070327
                    }, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_nil(code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)
            end
        )
        it(
            "hit both, both expired", function()
                stub(cache_fallback, "get_with_fallback", function ()
                    return {
                        ["bk-gateway:-:bk-app-code"] = 1,
                        ["bk-gateway:bk-resource:bk-app-code"] = 1
                    }, nil
                end)

                local code = plugin.access(conf, ctx)
                assert.is_equals(403, code)
                assert.stub(cache_fallback.get_with_fallback).was_called(1)
            end
        )

    end
)
