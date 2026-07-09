-- wit_ui_sort: 配方排序与跳转到原版制作菜单

-- ============================
-- 排序 + 跳转 (from wit_sort.lua)
-- ============================

-- 查找配方所属的分类标签
-- 在原版制作过滤器中查找指定配方所属分类。
local function _FindRecipeFilter(recipe_name)
    if not CRAFTING_FILTERS then return nil end
    for fname, filter in pairs(CRAFTING_FILTERS) do
        if type(filter) == "table" and type(filter.recipes) == "table" then
            for _, rname in ipairs(filter.recipes) do
                if rname == recipe_name then return fname end
            end
        end
    end
    return nil
end

-- 查询原版制作菜单里某个配方当前可制作状态。
function GetRecipeBuildState(recipe_name)
    if ThePlayer == nil or ThePlayer.HUD == nil then return "unknown" end
    local cm = ThePlayer.HUD.controls and ThePlayer.HUD.controls.craftingmenu and ThePlayer.HUD.controls.craftingmenu.craftingmenu
    if cm == nil or cm.crafting_hud == nil then return "unknown" end
    local rd = cm.crafting_hud.valid_recipes[recipe_name]
    if rd and rd.meta then return rd.meta.build_state end
    return "unknown"
end

-- 按可制作、可原型、不可制作的优先级排序合成配方。
function SortRecipesByBuildable(recipes)
    local buildable, partial, unbuildable = {}, {}, {}
    for _, r in ipairs(recipes) do
        local s = GetRecipeBuildState(r.name)
        if s == "buffered" or s == "has_ingredients" or s == "freecrafting" then
            table.insert(buildable, r)
        elseif s == "prototype" then
            table.insert(partial, r)
        else
            table.insert(unbuildable, r)
        end
    end
    -- 组内按背包材料匹配数排序
    local bp_items = GetPlayerIngredientList() or {}
    -- 统计烹饪配方卡片中当前物品出现的次数。
    local function match_count(r)
        if r and r.ingredients then
            local avail = {}
            for _, v in ipairs(bp_items) do
                local name = WIT_COOKING_ALIASES[v] or v
                avail[name] = (avail[name] or 0) + 1
            end
            local cnt = 0
            for _, ing in ipairs(r.ingredients) do
                if avail[ing.type] and avail[ing.type] > 0 then
                    cnt = cnt + 1
                    avail[ing.type] = avail[ing.type] - 1
                end
            end
            return cnt
        end
        return 0
    end
    table.sort(buildable, function(a, b) return match_count(a) > match_count(b) end)
    table.sort(partial, function(a, b) return match_count(a) > match_count(b) end)
    table.sort(unbuildable, function(a, b) return match_count(a) > match_count(b) end)
    local out = {}
    for _, r in ipairs(buildable) do table.insert(out, r) end
    for _, r in ipairs(partial) do table.insert(out, r) end
    for _, r in ipairs(unbuildable) do table.insert(out, r) end
    return out
end

-- 按当前库存能否满足食材需求排序烹饪配方。
function SortCookingByAvailable(recipes)
    if #recipes == 0 then return recipes end
    local prefablist = GetPlayerIngredientList()
    if prefablist == nil or #prefablist == 0 then
        table.sort(recipes, function(a, b)
            -- 潮湿黏糊（兜底失败品）始终排最末
            if a.name == "wetgoop" then return false end
            if b.name == "wetgoop" then return true end
            return (a.priority or 0) > (b.priority or 0)
        end)
        return recipes
    end
    local cooking = GLOBAL.require("cooking")
    local prefabs, tags = {}, {}
    for _, v in ipairs(prefablist) do
        local name = WIT_COOKING_ALIASES[v] or v
        prefabs[name] = (prefabs[name] or 0) + 1
        local data = (cooking.ingredients or {})[name]
        if data ~= nil then
            for kk, vv in pairs(data.tags) do
                tags[kk] = (tags[kk] or 0) + vv
            end
        end
    end
    local ingdata = { tags = tags, names = prefabs }
    local matched, unmatched = {}, {}
    for _, r in ipairs(recipes) do
        local match_count = 0
        if r.card_def and r.card_def.ingredients then
            for _, ci in ipairs(r.card_def.ingredients) do
                local name = WIT_COOKING_ALIASES[ci[1]] or ci[1]
                local has_item = prefabs[name] or 0
                for _ = 1, ci[2] do
                    if has_item > 0 then
                        match_count = match_count + 1
                        has_item = has_item - 1
                    end
                end
            end
        end
        if r.test and r.test("cookpot", ingdata.names, ingdata.tags) then
            r._cook_match = match_count; r._cook_pass = true
            table.insert(matched, r)
        else
            r._cook_match = match_count; r._cook_pass = false
            table.insert(unmatched, r)
        end
    end
    table.sort(matched, function(a, b)
        if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
        return (a._cook_match or 0) > (b._cook_match or 0)
    end)
    table.sort(unmatched, function(a, b)
        if (a._cook_match or 0) ~= (b._cook_match or 0) then return (a._cook_match or 0) > (b._cook_match or 0) end
        return (a.priority or 0) > (b.priority or 0)
    end)
    local out = {}
    for _, r in ipairs(matched) do table.insert(out, r) end
    for _, r in ipairs(unmatched) do table.insert(out, r) end
    return out
end

-- 打开原版制作菜单并跳转到指定配方详情。
function JumpToCraft(recipe)
    ClosePopup()
    if ThePlayer == nil or ThePlayer.HUD == nil then return end

    local hud = ThePlayer.HUD
    local menu = hud.controls and hud.controls.craftingmenu
    if menu and menu.Open then
        -- Redux crafting menu (controls.craftingmenu IS CraftingMenuHUD)
        menu:Open(false)
        -- Get last used skin for this recipe
        local skin = Profile and Profile:GetLastUsedSkinForItem(recipe.name)
        menu:PopulateRecipeDetailPanel(recipe.name, skin)
        -- Scroll the grid to this recipe + switch to its own filter tab
        local w = menu.craftingmenu  -- CraftingMenuWidget
        local recipe_data = menu.valid_recipes and menu.valid_recipes[recipe.name]
        if recipe_data and w and w.recipe_grid then
            local filter = _FindRecipeFilter(recipe.name) or CRAFTING_FILTERS.EVERYTHING.name
            if w.SelectFilter then
                w:SelectFilter(filter)
            end
            local idx = w.recipe_grid:FindDataIndex(recipe_data)
            if idx then
                w.recipe_grid:ScrollToDataIndex(idx)
            end
        end
        return
    end

    -- Fallback: classic crafting menu
    hud:OpenCrafting()
    local cm = hud.controls and hud.controls.craftingmenu and hud.controls.craftingmenu.craftingmenu
    if cm == nil then return end
    cm:SelectFilter(CRAFTING_FILTERS.EVERYTHING.name)
    local rd = cm.crafting_hud.valid_recipes[recipe.name]
    if rd == nil then rd = { recipe = recipe, meta = { build_state = "prototype", can_build = false } } end
    cm:PopulateRecipeDetailPanel(rd, nil)
end
