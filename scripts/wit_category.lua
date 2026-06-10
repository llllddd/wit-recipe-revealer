-- wit_category: 分类切换 + 配方获取
-- 依赖: 全局 WIT_CUR_CAT, WIT_PAGE, WIT_TAB_BTNS, WIT_NAME, WIT_MODE, WIT, SortRecipesByBuildable, SortCookingByAvailable, RenderCards, RenderCardCrafting, RenderCardCooking

function GetCurrentRecipes()
	if WIT_CUR_CAT == "CRAFTING" then
		local recipes = (WIT_MODE == "SOURCE") and (WIT.by_product[WIT_NAME] or {}) or (WIT.by_material[WIT_NAME] or {})
		return SortRecipesByBuildable(recipes)
	elseif WIT_CUR_CAT == "COOKING" then
		local recipes = {}
		if WIT_MODE == "SOURCE" then
			if WIT.cook_foods[WIT_NAME] then table.insert(recipes, WIT.cook_foods[WIT_NAME]) end
			table.sort(recipes, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
			recipes = SortCookingByAvailable(recipes)
		else
			-- USE 模式：排序由 SelectCategory 基于解析后的视图数据完成，此处只做优先级基线
			local src = WIT.cook_by_ingredient[WIT_NAME]
			if src then
				for _, r in ipairs(src) do table.insert(recipes, r) end
			end
			table.sort(recipes, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
		end
		return recipes
	end
	return {}
end

function SelectCategory(cat, reset_page)
	WIT_CUR_CAT = cat
	if reset_page then WIT_PAGE = 1 end

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

	local recipes = GetCurrentRecipes()
	-- U 模式烹饪：过滤 + 排序
	if cat == "COOKING" and WIT_MODE == "USE" then
		local ctx = WIT_COOK_CONTEXT
		local inv_counts = ctx and ctx.snapshot and ctx.snapshot.counts or {}

		local filtered = {}
		for _, r in ipairs(recipes) do
			local view = GetResolvedCookingCard(r, WIT_NAME)
			if view then
				r._cook_view = view
				table.insert(filtered, r)
			end
		end

		-- 三档排序：
		-- ① 能自动烹饪（有材料+有锅）→ 按优先级
		-- ② 材料齐全（有材料但没锅） → 按优先级
		-- ③ 缺材料 → 按界面显示的红底/空槽位数量（缺料程度）从小到大，同级按优先级
		table.sort(filtered, function(a, b)
			local va, vb = a._cook_view, b._cook_view

			-- 辅助函数：计算视图中有多少个槽位是缺失的（红底或空）
			local function GetMissingCount(view)
				if not view or not view.slots then return 4 end
				local missing = 0
				for i = 1, 4 do
					local s = view.slots[i]
					if s == nil then
						missing = missing + 1
					else
						-- UI渲染逻辑：只要该物品的总需求大于背包数量，其所有槽位都会变红
						-- 这里必须与UI表现绝对对齐，不再豁免 WIT_NAME
						local need_amt = view.need_map and view.need_map[s] or 1
						if (inv_counts[s] or 0) < need_amt then
							missing = missing + 1
						end
					end
				end
				return missing
			end

			local gap_a = GetMissingCount(va)
			local gap_b = GetMissingCount(vb)

			-- 判断三档
			local tier_a = 2
			if va and va.can_auto_cook then
				tier_a = 0
			elseif gap_a == 0 then
				tier_a = 1
			end

			local tier_b = 2
			if vb and vb.can_auto_cook then
				tier_b = 0
			elseif gap_b == 0 then
				tier_b = 1
			end

			if tier_a ~= tier_b then
				return tier_a < tier_b
			end

			-- 同一档内
			if tier_a == 2 then
				-- ③ 缺材料：按缺口从小到大
				if gap_a ~= gap_b then
					return gap_a < gap_b
				end
			end
			return (a.priority or 0) > (b.priority or 0)
		end)
		recipes = filtered
	end
	-- 每次切标签都清空并重建内容容器，防止 widget 堆积
	if WIT_POPUP and WIT_CONTENT then WIT_CONTENT:Kill(); WIT_CONTENT = nil end
	if WIT_POPUP then
		WIT_CONTENT = WIT_POPUP:AddChild(Widget("c"))
		if WIT_CONTENT then WIT_CONTENT:SetPosition(0, 16) end
	end
	if cat == "CRAFTING" then
		RenderCards(recipes, 85, 90, RenderCardCrafting)
	else
		RenderCards(recipes, 85, 90, RenderCardCooking)
	end
end
