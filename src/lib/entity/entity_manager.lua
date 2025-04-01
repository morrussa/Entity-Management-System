local M = {}
local entityAssets = require("src.lib.entity.entity_assets_loader")
local lovepatch = require("src.lib.lovepatch")

--[[ 画布操作API ]]
function M.set_current_canvas(canvas_id)
    if type(canvas_id) ~= "number" or canvas_id < 1 then
        error("Invalid canvas id: " .. tostring(canvas_id))
    end
    M.current_canvas = canvas_id
    -- 初始化画布相关结构
    M.canvas_layers = M.canvas_layers or {}
    M.layer_chains = M.layer_chains or {}
    M.sorted_entities = M.sorted_entities or {}
    M.canvas_layers[canvas_id] = M.canvas_layers[canvas_id] or 0
    M.layer_chains[canvas_id] = M.layer_chains[canvas_id] or {head = nil, tail = nil}
    M.sorted_entities[canvas_id] = M.sorted_entities[canvas_id] or {}
end
function M.get_current_canvas()
    return M.current_canvas
end
-- 初始化默认画布（在函数定义之后调用）
M.current_canvas = 1
M.canvas_layers = {}  -- 显式初始化
M.layer_chains = {}   -- 显式初始化
M.sorted_entities = {}-- 显式初始化
M.animation_index = {}-- 显式初始化动画索引
M.set_current_canvas(M.current_canvas)  -- 现在可以安全调用
-- ECS核心结构
M.entities = {}
M.id_counter = 0
-- 移除ID池系统：删除对象池相关代码
-- local id_pool = {}       -- [已删除]
function M.get_id_counter()
    return M.id_counter
end
-- 索引系统（支持复合索引）
M.indices = {
    tag = {},
    canvas = {},
    layer = {},          -- 嵌套结构：[canvas][layer] = {ids}
    isDraw = {},
    composite = {
        ["canvas-layer"] = {},
        ["tag-canvas"] = {}
    }
}
-- 操作符扩展
M.valid_operators = {
    ["=="] = function(a, b) return a == b end,
    [">"] = function(a, b) return a > b end,
    ["<"] = function(a, b) return a < b end,
    [">="] = function(a, b) return a >= b end,
    ["<="] = function(a, b) return a <= b end,
    ["~="] = function(a, b) return a ~= b end,
    ["between"] = function(a, lower, upper) return a >= lower and a <= upper end
}
-- 索引更新函数
local function updateIndex(index, key, id, action)
    if not index then
        error("Index table is nil for key: " .. tostring(key))
    end
    if action == "add" then
        index[key] = index[key] or {}
        table.insert(index[key], id)
    elseif action == "remove" then
        local list = index[key]
        if list then
            for i = #list, 1, -1 do
                if list[i] == id then
                    table.remove(list, i)
                    break
                end
            end
        end
    end
end
-- 动画索引维护
-- local function updateAnimationIndex(entity, action)
--     if type(entity.resource) == "table" then
--         updateIndex(M.animation_index, true, entity.id, action)
--     end
-- end

local function updateAnimationIndex(entity, action)
    if type(entity.resource) == "table" and 
       type(entity.resource.update) == "function" then
        updateIndex(M.animation_index, true, entity.id, action)
    end
end

-- 复合索引维护
local function updateCompositeIndices(entity, action)
    -- canvas-layer 索引
    local cl_key = string.format("%d-%d", entity.canvas, entity.layer)
    updateIndex(M.indices.composite["canvas-layer"], cl_key, entity.id, action)
    -- tag-canvas 索引
    local tc_key = string.format("%s-%d", entity.tag, entity.canvas)
    updateIndex(M.indices.composite["tag-canvas"], tc_key, entity.id, action)
end
-- 移除ID池系统：直接使用自增ID
local function getNextID()
    M.id_counter = M.id_counter + 1
    return M.id_counter
end
--[[ 实体管理 ]]

function M.addEntity(x, y, resourceName, scaleX, scaleY, angle, tag, isDraw, layer)
    local animTag, isNinePatch = nil, false
    local ninePatchArgs = {}

    -- 参数类型检测
    if type(resourceName) == "table" then
        -- 九宫格资源检测（参数数量>=3且第一个元素是字符串）
        if #resourceName >= 3 and type(resourceName[1]) == "string" then
            isNinePatch = true
            ninePatchArgs = resourceName
            resourceName = resourceName[1]
        -- 动画资源检测
        elseif #resourceName >= 1 and type(resourceName[1]) == "string" then
            animTag = resourceName[2]
            resourceName = resourceName[1]
        end
    end

    -- 获取资源
    local resource
    if isNinePatch then
        resource = entityAssets:getResource(ninePatchArgs)
    else
        resource = entityAssets:getResource(resourceName, animTag)
    end

    -- 创建实体
    local id = getNextID()
    local canvas = M.current_canvas
    local current_max = M.canvas_layers[canvas] or 0
    layer = layer or (current_max + 1)
    M.canvas_layers[canvas] = math.max(current_max, layer)

    local entity = {
        id = id,
        x = x,
        y = y,
        resource = resource,
        scaleX = isNinePatch and (scaleX or resource.width) or (scaleX or 1),
        scaleY = isNinePatch and (scaleY or resource.height) or (scaleY or 1),
        angle = angle or 0,
        tag = tag or "",
        isDraw = isDraw ~= false,
        canvas = canvas,
        layer = layer,
        prev_layer = nil,
        next_layer = nil,
        alpha = 1.0,
        isNinePatch = isNinePatch  -- 新增标识字段
    }
    M.entities[id] = entity
    -- 维护索引（保持原有逻辑）
    updateIndex(M.indices.tag, entity.tag, id, "add")
    updateIndex(M.indices.canvas, entity.canvas, id, "add")
    M.indices.layer[entity.canvas] = M.indices.layer[entity.canvas] or {}
    updateIndex(M.indices.layer[entity.canvas], entity.layer, id, "add")
    updateIndex(M.indices.isDraw, entity.isDraw, id, "add")
    updateCompositeIndices(entity, "add")
    updateAnimationIndex(entity, "add")
    -- 维护层级链表（保持原有逻辑）
    local chain = M.layer_chains[canvas]
    if chain.tail then
        local prev_entity = M.entities[chain.tail]
        prev_entity.next_layer = id
        entity.prev_layer = chain.tail
    end
    chain.tail = id
    if not chain.head then chain.head = id end
    -- 维护预排序列表（保持原有逻辑）
    local sorted = M.sorted_entities[canvas]
    sorted[layer] = sorted[layer] or {}
    table.insert(sorted[layer], id)
    return id
end
function M.rm_entity(id)
    local entity = M.entities[id]
    if not entity then return false end
    -- 移除索引
    updateIndex(M.indices.tag, entity.tag, id, "remove")
    updateIndex(M.indices.canvas, entity.canvas, id, "remove")
    updateIndex(M.indices.layer[entity.canvas], entity.layer, id, "remove")
    updateIndex(M.indices.isDraw, entity.isDraw, id, "remove")
    updateCompositeIndices(entity, "remove")
    updateAnimationIndex(entity, "remove")
    -- 维护层级链表
    local canvas_id = entity.canvas
    local chain = M.layer_chains[canvas_id]
    if chain then
        local prev = entity.prev_layer
        local next = entity.next_layer
        if prev then
            M.entities[prev].next_layer = next
        else
            chain.head = next
        end
        if next then
            M.entities[next].prev_layer = prev
        else
            chain.tail = prev
        end
    end
    -- 维护预排序列表
    local sorted = M.sorted_entities[canvas_id]
    if sorted and sorted[entity.layer] then
        for i = #sorted[entity.layer], 1, -1 do
            if sorted[entity.layer][i] == id then
                table.remove(sorted[entity.layer], i)
                break
            end
        end
    end
    -- 调整层高
    if entity.layer == M.canvas_layers[canvas_id] then
        local new_max = 0
        local current = M.layer_chains[canvas_id] and M.layer_chains[canvas_id].head
        while current do
            new_max = math.max(new_max, M.entities[current].layer)
            current = M.entities[current].next_layer
        end
        M.canvas_layers[canvas_id] = new_max
    end
    -- 移除ID池系统：直接废弃ID
    -- id_pool[#id_pool+1] = id  -- [已删除]
    M.entities[id] = nil
    return true
end
--[[ 渲染系统 ]]

function M.draw_c(canvas_id, offset_x, offset_y)
    offset_x = offset_x or 0
    offset_y = offset_y or 0

    local sorted = M.sorted_entities[canvas_id] or {}
    for layer, entities in pairs(sorted) do
        for _, id in ipairs(entities) do
            local entity = M.entities[id]
            if entity and entity.isDraw then
                local r, g, b, a = love.graphics.getColor()
                love.graphics.setColor(r, g, b, entity.alpha)

                if entity.isNinePatch then
                    -- 九宫格绘制
                    lovepatch.draw(
                        entity.resource,
                        entity.x + offset_x,
                        entity.y + offset_y,
                        entity.scaleX,
                        entity.scaleY
                    )
                elseif type(entity.resource) == "table" then
                    -- 动画绘制
                    entity.resource:draw(
                        entity.x + offset_x,
                        entity.y + offset_y,
                        entity.angle,
                        entity.scaleX,
                        entity.scaleY
                    )
                elseif entity.resource then
                    -- 普通图片绘制
                    local iw, ih = entity.resource:getDimensions()
                    love.graphics.draw(
                        entity.resource,
                        entity.x + offset_x,
                        entity.y + offset_y,
                        entity.angle,
                        entity.scaleX,
                        entity.scaleY,
                        iw/2, ih/2
                    )
                else
                    -- 默认矩形
                    love.graphics.rectangle(
                        "fill",
                        (entity.x + offset_x) - 10,
                        (entity.y + offset_y) - 10,
                        20, 20
                    )
                end

                love.graphics.setColor(r, g, b, a)
            end
        end
    end
end

--[[ 动画系统 ]]
function M.update(dt)
    local anim_entities = M.animation_index[true] or {}
    for _, id in ipairs(anim_entities) do
        local entity = M.entities[id]
        if entity and type(entity.resource) == "table" then
            entity.resource:update(dt)
        end
    end
end
--[[ 辅助函数 ]]
table.intersection = function(a, b)
    local set = {}
    for _, v in ipairs(a) do set[v] = true end
    local res = {}
    for _, v in ipairs(b) do
        if set[v] then table.insert(res, v) end
    end
    return res
end
------------------------------------------------------------------------------------------------------
--查询实体ID
function M.queryEntities(conditions, logic)
    logic = logic or "AND"
    local candidates = {}
    local has_index = false
    -- 索引预筛选
    for _, cond in ipairs(conditions) do
        local prop, op, val = cond.property, cond.operator, cond.value
        if prop and op and val then
            -- 复合索引处理
            if prop == "canvas-layer" then
                local key = string.format("%d-%d", val[1], val[2])
                local ids = M.indices.composite["canvas-layer"][key] or {}
                candidates = #candidates == 0 and ids or table.intersection(candidates, ids)
                has_index = true
            elseif prop == "tag-canvas" then
                local key = string.format("%s-%d", val[1], val[2])
                local ids = M.indices.composite["tag-canvas"][key] or {}
                candidates = #candidates == 0 and ids or table.intersection(candidates, ids)
                has_index = true
            -- 基础索引处理
            elseif M.indices[prop] then
                if op == "==" then
                    local ids = M.indices[prop][val] or {}
                    candidates = #candidates == 0 and ids or table.intersection(candidates, ids)
                    has_index = true
                elseif op == "between" then
                    local matched = {}
                    for key in pairs(M.indices[prop]) do
                        if key >= val[1] and key <= val[2] then
                            for _, eid in ipairs(M.indices[prop][key]) do
                                matched[eid] = true
                            end
                        end
                    end
                    local new_candidates = {}
                    for eid in pairs(matched) do
                        table.insert(new_candidates, eid)
                    end
                    candidates = #candidates == 0 and new_candidates or table.intersection(candidates, new_candidates)
                    has_index = true
                end
            end
        end
    end
    -- 全表扫描后备
    if not has_index or #candidates == 0 then
        candidates = {}
        for eid, _ in pairs(M.entities) do
            table.insert(candidates, eid)
        end
    end
    -- 最终验证
    local result = {}
    for _, eid in ipairs(candidates) do
        local entity = M.entities[eid]
        if entity then
            local isMatch = true
            for _, cond in ipairs(conditions) do
                local prop, op, val = cond.property, cond.operator, cond.value
                local entity_val = entity[prop]
                if not entity_val or not M.valid_operators[op](entity_val, unpack(type(val) == "table" and val or {val})) then
                    isMatch = false
                    break
                end
            end
            if isMatch then
                table.insert(result, eid)
            end
        end
    end
    return result
end
--修改实体ID的信息
function M.updateEntity(id, newProperties)
    local entity = M.entities[id]
    if not entity then
        error("Entity with id " .. tostring(id) .. " not found")
    end

    -- 保存旧属性用于索引更新
    local oldValues = {
        tag = entity.tag,
        layer = entity.layer,
        canvas = entity.canvas,
        isDraw = entity.isDraw,
        isNinePatch = entity.isNinePatch
    }

    -- 移除旧索引
    updateIndex(M.indices.tag, oldValues.tag, id, "remove")
    updateIndex(M.indices.canvas, oldValues.canvas, id, "remove")
    updateIndex(M.indices.layer[oldValues.canvas], oldValues.layer, id, "remove")
    updateIndex(M.indices.isDraw, oldValues.isDraw, id, "remove")
    updateCompositeIndices(entity, "remove")
    updateAnimationIndex(entity, "remove")

    -- 更新属性
    for key, value in pairs(newProperties) do
        if key == "resource" then
            -- 资源更新逻辑
            local animTag
            local resourceName
            local isNewNinePatch = false

            if type(value) == "table" then
                -- 九宫格资源检测（参数数量>=3且第一个元素是字符串）
                if #value >= 3 and type(value[1]) == "string" then
                    isNewNinePatch = true
                    entity.resource = entityAssets:getResource(value)
                    entity.isNinePatch = true
                -- 动画资源更新
                else
                    resourceName = value[1]
                    animTag = value[2]
                    
                    -- 仅更新动画标签的情况
                    if resourceName == nil and animTag then
                        if type(entity.resource) ~= "table" or not entity.resource.setTag then
                            error("Cannot set animation tag on non-animation resource")
                        end
                        if not entity.resource:hasTag(animTag) then
                            error("Animation tag '"..animTag.."' does not exist in current resource")
                        end
                        entity.resource:setTag(animTag)
                        entity.resource:play()
                    else
                        -- 完整动画资源更新
                        local resource = entityAssets:getResource(resourceName or entity.resource, animTag)
                        if not resource then
                            error("Resource '" .. tostring(resourceName) .. "' not found")
                        end
                        entity.resource = resource
                        entity.isNinePatch = false
                    end
                end
            else
                -- 普通资源更新
                local resource = entityAssets:getResource(value)
                if not resource then
                    error("Resource '" .. tostring(value) .. "' not found")
                end
                entity.resource = resource
                entity.isNinePatch = false
            end

        elseif key == "layer" then
            -- 图层验证
            if type(value) ~= "number" or value < 1 then
                error("Invalid layer value: " .. tostring(value))
            end
            entity.layer = value

        elseif key == "canvas" then
            -- 画布验证
            if type(value) ~= "number" or value < 1 then
                error("Invalid canvas value: " .. tostring(value))
            end
            entity.canvas = value

        elseif key == "alpha" then
            -- Alpha通道限制在0-1之间
            entity.alpha = math.min(1.0, math.max(0.0, value or 1.0))

        elseif key == "scaleX" or key == "scaleY" then
            -- 九宫格使用绝对尺寸，其他使用相对比例
            if entity.isNinePatch then
                entity[key] = value or (key == "scaleX" and entity.resource.width or entity.resource.height)
            else
                entity[key] = value or 1
            end

        else
            -- 其他属性直接赋值
            entity[key] = value
        end
    end

    -- 更新索引
    updateIndex(M.indices.tag, entity.tag, id, "add")
    updateIndex(M.indices.canvas, entity.canvas, id, "add")
    updateIndex(M.indices.layer[entity.canvas], entity.layer, id, "add")
    updateIndex(M.indices.isDraw, entity.isDraw, id, "add")
    updateCompositeIndices(entity, "add")
    updateAnimationIndex(entity, "add")

    -- 处理画布/图层变更
    if oldValues.canvas ~= entity.canvas or oldValues.layer ~= entity.layer then
        -- 从旧链表移除
        local oldChain = M.layer_chains[oldValues.canvas]
        if oldChain then
            local prev = entity.prev_layer
            local next = entity.next_layer
            
            if prev then
                M.entities[prev].next_layer = next
            else
                oldChain.head = next
            end
            
            if next then
                M.entities[next].prev_layer = prev
            else
                oldChain.tail = prev
            end
        end

        -- 插入到新链表
        local newChain = M.layer_chains[entity.canvas] or {head = nil, tail = nil}
        M.layer_chains[entity.canvas] = newChain
        
        if newChain.tail then
            local prev_entity = M.entities[newChain.tail]
            prev_entity.next_layer = id
            entity.prev_layer = newChain.tail
        end
        
        newChain.tail = id
        if not newChain.head then
            newChain.head = id
        end

        -- 更新预排序列表
        local oldSorted = M.sorted_entities[oldValues.canvas]
        if oldSorted and oldSorted[oldValues.layer] then
            for i = #oldSorted[oldValues.layer], 1, -1 do
                if oldSorted[oldValues.layer][i] == id then
                    table.remove(oldSorted[oldValues.layer], i)
                    break
                end
            end
        end

        local newSorted = M.sorted_entities[entity.canvas] or {}
        M.sorted_entities[entity.canvas] = newSorted
        newSorted[entity.layer] = newSorted[entity.layer] or {}
        table.insert(newSorted[entity.layer], id)
    end
end
------------------------------------------------------------------------------------------------------
--删除所有实体
function M.clearAllEntities()
    -- 收集所有实体ID（避免遍历时修改表的问题）
    local all_ids = {}
    for id, _ in pairs(M.entities) do
        table.insert(all_ids, id)
    end
    -- 批量删除实体
    for _, id in ipairs(all_ids) do
        M.rm_entity(id)
    end
    -- 重置画布层级信息（可选）
    for canvas_id, _ in pairs(M.canvas_layers) do
        M.canvas_layers[canvas_id] = 0
        M.layer_chains[canvas_id] = { head = nil, tail = nil }
        M.sorted_entities[canvas_id] = {}
    end
    -- 重置ID计数器（根据需求选择是否保留）
    M.id_counter = 0
    -- 移除ID池系统：删除相关代码
    -- id_pool = {}  -- [已删除]
end

--[[ 新增方法：获取动画当前帧 ]]
function M.get_entity_frame(id)
    local entity = M.entities[id]
    if not entity then
        error("Entity with id "..tostring(id).." not found")
    end
    if type(entity.resource) == "table" and entity.resource.getFrame then
        return entity.resource:getFrame()
    end
    return nil  -- 非动画实体返回nil
end

return M