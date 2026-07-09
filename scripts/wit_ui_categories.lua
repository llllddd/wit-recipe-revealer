-- wit_ui_categories: 页签数据选择与内容刷新

-- ============================
-- 分类切换 + 配方获取 (from wit_category.lua)
-- ============================

-- 判断配方列表中是否包含拆解配方。
function WIT_HasDeconRecipe(recipes)
    for _, r in ipairs(recipes or {}) do if r.is_deconstruction_recipe then return true end end
    return false
end

-- 判断是否有普通制作来源配方。
function WIT_HasCraftFrom(name)
    if WIT.by_product[name] == nil then return false end
    for _, r in ipairs(WIT.by_product[name]) do
        if not r.is_deconstruction_recipe then return true end
    end
    return false
end

-- 判断是否可作为制作材料或可被拆解。
function WIT_HasCraftUse(name)
    if WIT.by_material[name] then
        for _, r in ipairs(WIT.by_material[name]) do
            if not r.is_deconstruction_recipe then return true end
        end
    end
    return WIT.by_product[name] and WIT_HasDeconRecipe(WIT.by_product[name]) or false
end

-- 判断是否可由拆解配方产出。
function WIT_HasCraftDeconSource(name)
    if WIT.by_material[name] == nil then return false end
    for _, r in ipairs(WIT.by_material[name]) do
        if r.is_deconstruction_recipe then return true end
    end
    return false
end

-- 判断是否存在实体掉落/采集来源。
function WIT_HasLootSources(name)
    for _, loots in pairs(WIT.entity_loot or {}) do
        for _, l in ipairs(loots) do
            if l.prefab == name then return true end
        end
    end
    return false
end

-- 判断是否可以由烹饪产出。
function WIT_HasCookFrom(name)
    return WIT.cook_foods[name] ~= nil
end

-- 判断是否可以作为烹饪材料使用。
function WIT_HasCookUse(name)
    return WIT.cook_by_ingredient[name] ~= nil and #WIT.cook_by_ingredient[name] > 0
end

-- 判断指定 prefab 在来源或用途模式下是否有可展示数据。
function HasData(name, mode)
    if mode == "SOURCE" then
        return WIT_HasCraftFrom(name) or WIT_HasCraftDeconSource(name) or WIT_HasCookFrom(name) or WIT_HasLootSources(name)
    elseif mode == "USE" then
        return WIT_HasCraftUse(name) or WIT_HasCookUse(name)
    end
    return WIT_HasCraftFrom(name) or WIT_HasCraftUse(name) or WIT_HasCraftDeconSource(name)
        or WIT_HasCookFrom(name)
        or WIT_HasCookUse(name)
        or WIT_HasLootSources(name)
end

-- 根据当前页签和当前 prefab 收集要渲染的配方列表。
function GetCurrentRecipes()
    if WIT_CUR_CAT == "CRAFT_FROM" then
        local recipes = {}
        local src = WIT.by_product[WIT_NAME]
        if src then
            for _, r in ipairs(src) do
                if not r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        local decon = WIT.by_material[WIT_NAME]
        if decon then
            for _, r in ipairs(decon) do
                if r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        return SortRecipesByBuildable(recipes)
    elseif WIT_CUR_CAT == "CRAFT_USE" then
        local recipes = {}
        local src = WIT.by_material[WIT_NAME]
        if src then
            for _, r in ipairs(src) do
                if not r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        local decon = WIT.by_product[WIT_NAME]
        if decon then
            for _, r in ipairs(decon) do
                if r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        return SortRecipesByBuildable(recipes)
    elseif WIT_CUR_CAT == "COOK_FROM" then
        local recipes = {}
        if WIT.cook_foods[WIT_NAME] then table.insert(recipes, WIT.cook_foods[WIT_NAME]) end
        table.sort(recipes, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
        return SortCookingByAvailable(recipes)
    elseif WIT_CUR_CAT == "COOK_USE" then
        local recipes = {}
        local src = WIT.cook_by_ingredient[WIT_NAME]
        if src then
            for _, r in ipairs(src) do table.insert(recipes, r) end
        end
        table.sort(recipes, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
        return recipes
    end
    return {}
end

-- 切换页签、刷新分页状态并重建内容区。
function SelectCategory(cat, reset_page)
    WIT_CUR_CAT = cat
    if reset_page then WIT_PAGE = 1 end
    WIT_expanded_sources = {}  -- 切页签/翻页时重置展开

    for c, t in pairs(WIT_TAB_BTNS) do
        if t then
            if c == cat then
                t:SetTextColour(0.95, 0.85, 0.55, 1)
                t:SetTextFocusColour(0.95, 0.85, 0.55, 1)
            else
                t:SetTextColour(0.45, 0.42, 0.36, 1)
                t:SetTextFocusColour(0.7, 0.65, 0.55, 1)
            end
        end
    end

    -- INFO 页签隐藏翻页控件
    if WIT_PG_PREV then
        if cat == "INFO" then
            WIT_PG_PREV:Hide(); WIT_PG_NEXT:Hide(); WIT_PG_TEXT:Hide()
        else
            WIT_PG_PREV:Show(); WIT_PG_NEXT:Show(); WIT_PG_TEXT:Show()
        end
    end

    local recipes = GetCurrentRecipes()
    -- 烹饪用途：过滤 + 排序（带 pcall 保护）
    if cat == "COOK_USE" then
        local ctx = WIT_COOK_CONTEXT
        local inv_counts = ctx and ctx.snapshot and ctx.snapshot.counts or {}
        local filtered = {}
        local ok_resolve = pcall(function()
            for _, r in ipairs(recipes) do
                local view = GetResolvedCookingCard(r, WIT_NAME)
                if view then
                    r._cook_view = view
                    table.insert(filtered, r)
                end
            end
        end)
        if not ok_resolve then
            for _, r in ipairs(recipes) do
                if r.card_def and r.card_def.ingredients then
                    local raw = FlattenIngredients(r.card_def.ingredients)
                    r._cook_view = { slots = PadSlots(raw, 4), need_map = BuildNeedMap(r.card_def.ingredients), can_auto_cook = false }
                    table.insert(filtered, r)
                end
            end
        end
        table.sort(filtered, function(a, b)
            local va, vb = a._cook_view, b._cook_view
            -- 计算烹饪卡片当前还缺多少个食材槽。
            local function GetMissingCount(view)
                if not view or not view.slots then return 4 end
                local missing = 0
                for i = 1, 4 do
                    local s = view.slots[i]
                    if s == nil then
                        missing = missing + 1
                    else
                        local need_amt = view.need_map and view.need_map[s] or 1
                        if (inv_counts[s] or 0) < need_amt then missing = missing + 1 end
                    end
                end
                return missing
            end
            local gap_a, gap_b = GetMissingCount(va), GetMissingCount(vb)
            local tier_a = va and va.can_auto_cook and 0 or (gap_a == 0 and 1 or 2)
            local tier_b = vb and vb.can_auto_cook and 0 or (gap_b == 0 and 1 or 2)
            if tier_a ~= tier_b then return tier_a < tier_b end
            if tier_a == 2 and gap_a ~= gap_b then return gap_a < gap_b end
            return (a.priority or 0) > (b.priority or 0)
        end)
        recipes = filtered
    end
    -- 每次切标签都清空并重建内容容器
    if WIT_POPUP and WIT_CONTENT then WIT_CONTENT:Kill(); WIT_CONTENT = nil end
    if WIT_POPUP then
        WIT_CONTENT = WIT_POPUP:AddChild(Widget("c"))
        if WIT_CONTENT then WIT_CONTENT:SetPosition(0, 20) end
    end
    if cat == "CRAFT_FROM" or cat == "CRAFT_USE" then
        RenderCards(recipes, 85, 90, RenderCardCrafting)
    elseif cat == "COOK_FROM" or cat == "COOK_USE" then
        RenderCards(recipes, 85, 90, RenderCardCooking)
    elseif cat == "SOURCES" then
        RenderSources()
    elseif cat == "INFO" then
        RenderItemInfo()
    end
end
