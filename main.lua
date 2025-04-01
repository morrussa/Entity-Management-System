local entity_m = require("src.lib.entity.entity_manager")

local cam2x = 0
local osagechanx,osagechany = 100,400
local osagechanid = 0
local boxid = 0
local timer = 0
function love.load()
    entity_m.set_current_canvas(1)--set current canvas to 1
    entity_m.addEntity(320,240,{"action_bar_frame2", 10, 10}, 100,50,0,"action_bar_frame")--a nine patch entity
    boxid = tag2id("action_bar_frame")

    entity_m.set_current_canvas(2)
    entity_m.addEntity(-32,32,{"test","Loop"},1,1,0,"osagechan")
    osagechanid = tag2id("osagechan")
end

function love.draw()
    entity_m.draw_c(1)--draw canvas 1
    entity_m.draw_c(2)
end

function love.update(dt)
    timer = timer + 1
    local scalex = math.sin(timer/60)*50 + 50
    entity_m.update(dt)
    entity_m.updateEntity(boxid,{scaleX = scalex})
    entity_m.updateEntity(osagechanid,{x = osagechanx,y = osagechany})
end

function love.keypressed(key)
    if key == "left" then
        cam2x = cam2x + 1
    elseif key == "right" then
        cam2x = cam2x - 1
    elseif key == "s" then
        osagechany = osagechany +5
    elseif key == "w" then
        osagechany = osagechany -5
    elseif key == "a" then
        osagechanx = osagechanx -5
    elseif key == "d" then
        osagechanx = osagechanx +5
    end
        
end

-- 提取表的第一位数据
function firstnum(table)
    if type(table) ~= "table" then
        error("Expected a table, got " .. type(table))
    end
    if #table == 0 then
        return nil -- 如果表为空，返回 nil
    end
    return table[1] -- 返回表的第一位数据
end

-- 通过tag找到ID，由于整个过程非常繁琐所以诞生的工具函数。
function tag2id(tag)
    local returnid = firstnum(entity_m.queryEntities({{property = "tag", operator = "==", value = tag}}))
    return returnid
end