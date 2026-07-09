-- wit_core_cooking: 烹饪卡片求解与自动填锅
--
-- 这里只处理“给定焦点物品，如何展示/替换/搬运四格食材”。
-- 配方索引由 wit_core_indexes.lua 构建，库存遍历 helper 来自 wit_core_base.lua。

-- ============================
-- 烹饪卡片求解器 (from wit_cook_card_resolver.lua)
-- ============================

function TryInjectFocusIngredient(recipe, slots, focus_name)
    local found = false
    for _, v in ipairs(slots) do
        if v == focus_name then found = true; break end
    end
    if found or not recipe.test then return slots end

    for try_slot = #slots, 1, -1 do
        local override = {}
        for ii = 1, #slots do override[ii] = (ii == try_slot) and focus_name or slots[ii] end
        local sim_names, sim_tags = BuildSimInput(slots, override)
        if recipe.test("cookpot", sim_names, sim_tags) then
            slots[try_slot] = focus_name
            break
        end
    end
    return slots
end

function SubstituteMissingIngredients(recipe, slots, snapshot)
    if not recipe.test or not snapshot then return slots end
    local cooking = WIT_CORE.GetCooking()
    local bp_avail = {}
    for name, count in pairs(snapshot.counts) do
        if cooking and cooking.ingredients and cooking.ingredients[name] then
            bp_avail[name] = count
        end
    end
    for _, ing in ipairs(slots) do
        if bp_avail[ing] and bp_avail[ing] > 0 then bp_avail[ing] = bp_avail[ing] - 1 end
    end
    local focus_count = 0
    if WIT_NAME then
        for _, v in ipairs(slots) do
            if v == WIT_NAME then focus_count = focus_count + 1 end
        end
    end
    for slot_i = 1, #slots do
        local cur = slots[slot_i]
        if cur ~= nil then
            local need_count = 0
            for _, v in ipairs(slots) do if v == cur then need_count = need_count + 1 end end
            if (snapshot.counts[cur] or 0) < need_count then
                if cur == WIT_NAME and focus_count <= 1 then
                    -- 保留最后一个焦点食材
                else
                    local best_sub = nil
                    for bp_name, bp_count in pairs(bp_avail) do
                        if bp_count > 0 and bp_name ~= cur then
                            local override = {}
                            for ii = 1, #slots do override[ii] = (ii == slot_i) and bp_name or slots[ii] end
                            local sim_names, sim_tags = BuildSimInput(slots, override)
                            if recipe.test("cookpot", sim_names, sim_tags) then
                                best_sub = bp_name; break
                            end
                        end
                    end
                    if best_sub then
                        slots[slot_i] = best_sub
                        bp_avail[best_sub] = bp_avail[best_sub] - 1
                        if cur == WIT_NAME then focus_count = focus_count - 1 end
                    end
                end
            end
        end
    end
    return slots
end

-- ============================
-- 自动烹饪判定 (统一版，消除 2 份重复)
-- ============================

function CanAutoCook(view)
    if view == nil or view.need_map == nil then return false end
    local pot = WIT_OPEN_COOKPOT
    if pot == nil then return false end
    if pot.replica.stewer ~= nil then
        if pot.replica.stewer:IsCooking() or pot.replica.stewer:IsDone() then return false end
    end
    -- view.need_map uses resolved names (like meat_cooked)
    -- We need to check against actual inventory counts
    local snapshot = CollectIngredientSnapshot()
    for prefab, count in pairs(view.need_map) do
        if (snapshot.counts[prefab] or 0) < count then return false end
    end
    return true
end

function AutoFillCookPot(view)
    if ThePlayer == nil or view == nil or view.slots == nil then return end
    local pot = WIT_OPEN_COOKPOT
    if pot == nil then return end
    local classified = ThePlayer.replica.inventory and ThePlayer.replica.inventory.classified
    if classified == nil then return end

    -- 为所有需要搬运的食材统一查找库存引用（已包含 alias 回退）
    for _, prefab in ipairs(view.slots) do
        if prefab ~= nil then
            local ref = FindInventoryRefByPrefab(prefab)
            if ref and ref.slot ~= nil then
                classified:MoveItemFromAllOfSlot(ref.slot, pot)
            end
        end
    end
end

-- ============================
-- 库存快照 + 烹饪上下文管理
-- ============================

function CollectIngredientSnapshot()
    local bp_items = GetPlayerIngredientList() or {}
    local snapshot = { list = bp_items, counts = {}, tags = {} }
    for _, v in ipairs(bp_items) do
        local name = WIT_COOKING_ALIASES[v] or v
        snapshot.counts[name] = (snapshot.counts[name] or 0) + 1
        WIT_CORE.AccumulateIngredient(v, 1, {}, snapshot.tags)
    end
    return snapshot
end

function CanAutoCookFromSnapshot(need_map, counts)
    if need_map == nil or counts == nil then return false end
    local pot = WIT_OPEN_COOKPOT
    if pot == nil then return false end
    if pot.replica.stewer ~= nil then
        if pot.replica.stewer:IsCooking() or pot.replica.stewer:IsDone() then return false end
    end
    for prefab, count in pairs(need_map) do
        if (counts[prefab] or 0) < count then return false end
    end
    return true
end

function ResolveCookingCard(recipe, focus_name, snapshot)
    if not recipe.card_def or not recipe.card_def.ingredients then return nil end
    local slots = FlattenIngredients(recipe.card_def.ingredients)
    slots = TryInjectFocusIngredient(recipe, slots, focus_name)
    local raw_need_map = {}
    for _, s in ipairs(slots) do
        if s ~= nil then raw_need_map[s] = (raw_need_map[s] or 0) + 1 end
    end
    slots = SubstituteMissingIngredients(recipe, slots, snapshot)
    slots = PadSlots(slots, 4)
    if focus_name then
        local found = false
        for _, s in ipairs(slots) do
            if s == focus_name then found = true; break end
        end
        if not found then return nil end
    end
    local need_map = {}
    for _, s in ipairs(slots) do
        if s ~= nil then need_map[s] = (need_map[s] or 0) + 1 end
    end
    return {
        slots = slots,
        need_map = need_map,
        raw_need_map = raw_need_map,
        can_auto_cook = CanAutoCookFromSnapshot(need_map, snapshot.counts),
    }
end

function BuildCookContext()
    local snapshot = CollectIngredientSnapshot()
    if WIT_COOK_CONTEXT and (not snapshot or not snapshot.list or #snapshot.list == 0) then return end
    WIT_COOK_REV = (WIT_COOK_REV or 0) + 1
    WIT_COOK_CONTEXT = {
        revision = WIT_COOK_REV,
        snapshot = snapshot,
        resolved = {},
    }
end

function GetResolvedCookingCard(recipe, focus_name)
    local ctx = WIT_COOK_CONTEXT
    if ctx == nil then return nil end
    local key = recipe.name .. "|" .. focus_name
    if ctx.resolved[key] == nil then
        ctx.resolved[key] = ResolveCookingCard(recipe, focus_name, ctx.snapshot)
    end
    return ctx.resolved[key]
end

-- ============================
-- 烹饪锅状态检测 (from wit_helpers.lua)
-- ============================

function GetOpenCookPot()
    if ThePlayer == nil or ThePlayer.replica == nil or ThePlayer.replica.inventory == nil then return nil end
    local containers = ThePlayer.replica.inventory:GetOpenContainers()
    if containers == nil then return nil end
    for ent, _ in pairs(containers) do
        if ent:HasTag("stewer") and ent.replica.container ~= nil then
            return ent
        end
    end
    return nil
end
