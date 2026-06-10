-- wit_cook_card_resolver: 烹饪卡片求解器
-- 将候选食材推导、背包扫描、test() 验证从渲染层分离
-- 依赖: 全局 WIT_NAME, WIT_COOKING_ALIASES, WIT_OPEN_COOKPOT

-- ============================
-- 库存快照：单次扫描产出 {list, counts, tags}
-- ============================
function CollectIngredientSnapshot()
	local bp_items = GetPlayerIngredientList() or {}
	local snapshot = { list = bp_items, counts = {}, tags = {} }
	local cooking = GLOBAL.require("cooking")
	for _, v in ipairs(bp_items) do
		local name = WIT_COOKING_ALIASES[v] or v
		snapshot.counts[name] = (snapshot.counts[name] or 0) + 1
		local ing_data = (cooking.ingredients or {})[name]
		if ing_data then
			for kk, vv in pairs(ing_data.tags) do
				snapshot.tags[kk] = (snapshot.tags[kk] or 0) + vv
			end
		end
	end
	return snapshot
end

-- ============================
-- 基础工具函数
-- ============================
function FlattenIngredients(ingredients)
	local list = {}
	if not ingredients then return list end
	for _, ci in ipairs(ingredients) do
		for _ = 1, ci[2] do
			table.insert(list, ci[1])
		end
	end
	return list
end

function BuildNeedMap(ingredients)
	local map = {}
	if not ingredients then return map end
	for _, ci in ipairs(ingredients) do
		map[ci[1]] = (map[ci[1]] or 0) + ci[2]
	end
	return map
end

function PadSlots(slots, count)
	while #slots < count do
		table.insert(slots, nil)
	end
	return slots
end

-- ============================
-- 模拟 test() 输入构建
-- ============================
function BuildSimInput(slot_list, slot_override)
	local sim_names, sim_tags = {}, {}
	local cooking = GLOBAL.require("cooking")
	for ii, ing in ipairs(slot_list) do
		local name = slot_override[ii] or ing
		sim_names[name] = (sim_names[name] or 0) + 1
		local ing_data = (cooking.ingredients or {})[name]
		if ing_data then
			for kk, vv in pairs(ing_data.tags) do
				sim_tags[kk] = (sim_tags[kk] or 0) + vv
			end
		end
	end
	return sim_names, sim_tags
end

-- ============================
-- 步骤 1：将 WIT_NAME 注入槽位
-- ============================
function TryInjectFocusIngredient(recipe, slots, focus_name)
	local found = false
	for _, v in ipairs(slots) do
		if v == focus_name then found = true; break end
	end
	if found or not recipe.test then return slots end

	for try_slot = #slots, 1, -1 do
		local override = {}
		for ii = 1, #slots do
			override[ii] = (ii == try_slot) and focus_name or slots[ii]
		end
		local sim_names, sim_tags = BuildSimInput(slots, override)
		if recipe.test("cookpot", sim_names, sim_tags) then
			slots[try_slot] = focus_name
			break
		end
	end
	return slots
end

-- ============================
-- 步骤 2：对背包缺失食材做替换
-- ============================
function SubstituteMissingIngredients(recipe, slots, snapshot)
	if not recipe.test or not snapshot then return slots end

	local cooking = GLOBAL.require("cooking")
	-- 可用食材池：只取烹饪系统注册过的食材，排除背包里的非食材物品（武器、头盔等）
	local bp_avail = {}
	for name, count in pairs(snapshot.counts) do
		if cooking and cooking.ingredients and cooking.ingredients[name] then
			bp_avail[name] = count
		end
	end
	for _, ing in ipairs(slots) do
		if bp_avail[ing] and bp_avail[ing] > 0 then
			bp_avail[ing] = bp_avail[ing] - 1
		end
	end

	-- 统计焦点食材在当前槽位中的数量
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
			for _, v in ipairs(slots) do
				if v == cur then need_count = need_count + 1 end
			end
			if (snapshot.counts[cur] or 0) < need_count then
				-- 允许替换焦点食材，但必须保证至少保留一个焦点食材不被替换
				if cur == WIT_NAME and focus_count <= 1 then
					-- skip
				else
					local best_sub = nil
					for bp_name, bp_count in pairs(bp_avail) do
						if bp_count > 0 and bp_name ~= cur then
							local override = {}
							for ii = 1, #slots do
								override[ii] = (ii == slot_i) and bp_name or slots[ii]
							end
							local sim_names, sim_tags = BuildSimInput(slots, override)
							if recipe.test("cookpot", sim_names, sim_tags) then
								best_sub = bp_name
								break
							end
						end
					end
					if best_sub then
						slots[slot_i] = best_sub
						bp_avail[best_sub] = bp_avail[best_sub] - 1
						if cur == WIT_NAME then
							focus_count = focus_count - 1
						end
					end
				end
			end
		end
	end
	return slots
end

-- ============================
-- 基于快照的自动烹饪判定
-- ============================
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

-- ============================
-- 核心求解器：配方 + 快照 → 展示视图
-- ============================
function ResolveCookingCard(recipe, focus_name, snapshot)
	if not recipe.card_def or not recipe.card_def.ingredients then return nil end

	local slots = FlattenIngredients(recipe.card_def.ingredients)
	slots = TryInjectFocusIngredient(recipe, slots, focus_name)
	-- 注入后、背包替代前的原始需求（用于排序缺口计算，排除替代干扰）
	local raw_need_map = {}
	for _, s in ipairs(slots) do
		if s ~= nil then
			raw_need_map[s] = (raw_need_map[s] or 0) + 1
		end
	end
	slots = SubstituteMissingIngredients(recipe, slots, snapshot)
	slots = PadSlots(slots, 4)

	-- 焦点食材不在任何槽位 → 该料理不适用此食材，跳过
	if focus_name then
		local found = false
		for _, s in ipairs(slots) do
			if s == focus_name then found = true; break end
		end
		if not found then return nil end
	end

	-- 基于注入+替换后的实际槽位重建需求映射
	local need_map = {}
	for _, s in ipairs(slots) do
		if s ~= nil then
			need_map[s] = (need_map[s] or 0) + 1
		end
	end

	return {
		slots = slots,
		need_map = need_map,
		raw_need_map = raw_need_map,
		can_auto_cook = CanAutoCookFromSnapshot(need_map, snapshot.counts),
	}
end

-- ============================
-- 上下文管理：快照构建 + 结果缓存
-- ============================
function BuildCookContext()
	local snapshot = CollectIngredientSnapshot()
	-- 首次构建：总是创建上下文（即使空背包也保持结构完整）
	-- 后续刷新：只在有有效数据时替换，避免空数据覆盖已有上下文
	if WIT_COOK_CONTEXT and (not snapshot or not snapshot.list or #snapshot.list == 0) then
		return
	end
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
