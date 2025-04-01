local peachy = require("src.lib.peachy")
local json = require("src.lib.peachy.lib.json")
local lovepatch = require("src.lib.lovepatch")

local entityAssets = {}
local animationCache = {}
local ninePatchCache = {}

--- 加载指定目录下的所有资源
---@param directory string 目标目录路径
---@return table 资源表
local function loadResources(directory)
    local files = love.filesystem.getDirectoryItems(directory)
    for _, filename in ipairs(files) do
        local path = directory .. "/" .. filename
        local info = love.filesystem.getInfo(path)
        
        if info and info.type == "file" then
            local extension = string.match(filename, "%.([^.]+)$")
            if extension then
                extension = extension:lower()
                
                -- 处理普通图片
                if extension == "png" or extension == "jpg" or extension == "jpeg" then
                    local key = filename:match("^(.+)%..+$")
                    -- 九宫格图片特殊处理
                    if string.find(directory:lower(), "nine_patch") then
                        ninePatchCache[key] = love.graphics.newImage(path)
                    else
                        entityAssets[key] = love.graphics.newImage(path)
                    end
                end
                
                -- 处理动画JSON文件
                if extension == "json" then
                    local jsonPath = path
                    local jsonData = json.decode(love.filesystem.read(jsonPath))
                    local frameTags = jsonData.meta and jsonData.meta.frameTags or {}
                    local defaultTag = frameTags[1] and frameTags[1].name or "default"
                    
                    local imagePath = directory .. "/sheet/" .. filename:sub(1, -6) .. ".png"
                    local animationKey = filename:sub(1, -6)
                    
                    animationCache[animationKey] = {
                        jsonPath = jsonPath,
                        imagePath = imagePath,
                        defaultTag = defaultTag
                    }
                end
            end
        end
    end
    return entityAssets
end

--- 获取资源（支持多种类型）
---@param name string|table 资源名称或参数表
---@param ... mixed 附加参数
---@return table|userdata 资源对象
function entityAssets:getResource(name, ...)
    -- 处理九宫格资源
    if type(name) == "table" and #name >= 3 and ninePatchCache[name[1]] then
        local img = ninePatchCache[name[1]]
        if #name == 3 then
            return lovepatch.loadSameEdge(img, name[2], name[3])
        elseif #name >= 5 then
            return lovepatch.loadDiffrntEdge(img, name[2], name[3], name[4], name[5])
        end
    end
    
    -- 处理普通字符串资源名
    if type(name) == "string" then
        -- 普通图片
        if entityAssets[name] then
            return entityAssets[name]
        end
        
        -- 动画资源
        if animationCache[name] then
            local cacheData = animationCache[name]
            local img = love.graphics.newImage(cacheData.imagePath)
            return peachy.new(cacheData.jsonPath, img, ... or cacheData.defaultTag)
        end
    end
    
    error("Resource not found: " .. tostring(name))
end

-- 自动加载资源
entityAssets = loadResources("assets/entity")
loadResources("assets/entity/nine_patch")  -- 专门加载九宫格资源

return entityAssets