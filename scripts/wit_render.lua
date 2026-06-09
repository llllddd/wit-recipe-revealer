-- wit_render: 卡片渲染
-- 依赖: 全局 Image, Text, TextButton, ImageButton

-- ============================
-- 烹饪条件推导
-- ============================
function FormatCookCondition(recipe, _)
	-- 从 card_def 示例组合各食材的标签值累加
	-- 这只反映示例配方的标签值, 不是配方的实际 tag 需求阈值
	-- 例如 test() 要求 tags.meat 即 meat≥1, 但示例用了 meat 3 份, 显示为 3
	-- 此处仅作参考, 不作为精确条件判断
	if recipe.card_def and recipe.card_def.ingredients then
		local agg = {}
		for _, ci in ipairs(recipe.card_def.ingredients) do
			local tags = WIT.ingredient_tags[ci[1]]
			if tags then
				for tname, tval in pairs(tags) do
					agg[tname] = (agg[tname] or 0) + tval * ci[2]
				end
			end
		end
		local parts = {}
		for tname, tval in pairs(agg) do
			table.insert(parts, CN(tname) .. " " .. tval)
		end
		return parts
	end
	return {}
end

-- ============================
-- 渲染合成配方卡片
-- ============================
function RenderCardCrafting(r, card_y)
	local ings = r.ingredients or {}
	local ing_count = math.min(#ings, 5)
	local start_x = -140
	for ii = 1, ing_count do
		local ing = ings[ii]
		local hl = (ing.type == WIT_NAME)
		MakeSlot(WIT_CONTENT, ing.type, start_x + (ii - 1) * 58, card_y, ing.amount, hl)
	end
	MakeArrow(WIT_CONTENT, start_x + ing_count * 58 - 10, card_y)
	MakeSlot(WIT_CONTENT, r.product or r.name, start_x + ing_count * 58 + 32, card_y, nil, false)

	local state = GetRecipeBuildState(r.name)
	if state ~= nil then
		local can_craft = (state == "has_ingredients" or state == "buffered" or state == "freecrafting" or state == "prototype")
		local craft_btn = WIT_CONTENT:AddChild(ImageButton("images/crafting_menu.xml", "ingredient_craft.tex", "ingredient_craft.tex"))
		if craft_btn then
			craft_btn:SetPosition(start_x + ing_count * 58 + 32 + 32, card_y - 32)
			craft_btn:SetScale(0.35)
			if can_craft then
				craft_btn.image:SetTint(1, 1, 1, 1)
			else
				craft_btn.image:SetTint(0.5, 0.5, 0.5, 1)
			end
			craft_btn:SetOnClick(function() JumpToCraft(r) end)
		end
	end
end

-- ============================
-- 渲染烹饪卡片
-- ============================
function RenderCardCooking(r, card_y)
	-- 跳过没有 card_def 的配方 (无法正确渲染槽位)
	if not r.card_def or not r.card_def.ingredients then return end

	local pri = WIT_CONTENT:AddChild(Text(NEWFONT, 18))
	if pri then
		pri:SetString(WIT_TXT.PRIORITY .. (r.priority or 0))
		pri:SetPosition(130, card_y + 30)
		pri:SetColour(1, 0.88, 0.55, 1)
	end

	local conds = FormatCookCondition(r, WIT_NAME)
	if #conds > 0 then
		local ct = WIT_CONTENT:AddChild(Text(NEWFONT, 20))
		if ct then
			ct:SetString(table.concat(conds, "  "))
			ct:SetRegionSize(320, 30)
			ct:SetPosition(-44, card_y + 30)
			ct:SetHAlign(0)
			ct:SetColour(0.7, 0.65, 0.5, 1)
		end
	end

	-- 构建 4 槽显示列表, 确保 WIT_NAME 出现在其中
	local ings_list = {}
	if r.card_def and r.card_def.ingredients then
		-- 展开 card_def 为平坦 list
		for _, ci in ipairs(r.card_def.ingredients) do
			for _ = 1, ci[2] do
				table.insert(ings_list, ci[1])
			end
		end
		-- 如果 WIT_NAME 不在列表中, 找一个可替换的槽位替换进去
		-- 替换条件: 替换后 test() 仍然 pass
		local found_gname = false
		for _, v in ipairs(ings_list) do
			if v == WIT_NAME then found_gname = true; break end
		end
		if not found_gname and r.test then
			local cooking = GLOBAL.require("cooking")
			local best_slot = nil
			for try_slot = #ings_list, 1, -1 do
				-- 尝试替换此槽为 WIT_NAME, 跑 test()
				local sim_names, sim_tags = {}, {}
				for ii, ing in ipairs(ings_list) do
					local name = (ii == try_slot) and WIT_NAME or ing
					sim_names[name] = (sim_names[name] or 0) + 1
					local ing_data = (cooking.ingredients or {})[name]
					if ing_data then
						for kk, vv in pairs(ing_data.tags) do
							sim_tags[kk] = (sim_tags[kk] or 0) + vv
						end
					end
				end
				if r.test("cookpot", sim_names, sim_tags) then
					best_slot = try_slot
					break
				end
			end
			if best_slot then
				ings_list[best_slot] = WIT_NAME
			end
		end
		-- 第二步: 对剩余缺失槽位, 尝试用背包中的同标签食材替换
		-- 替换条件: 替换后 test() 仍然 pass, 且替换食材标签值 >= 被替换食材
		if r.test then
			local cooking = GLOBAL.require("cooking")
			local bp_items = GetPlayerIngredientList() or {}
			local bp_avail = {}
			for _, v in ipairs(bp_items) do
				local name = WIT_COOKING_ALIASES[v] or v
				bp_avail[name] = (bp_avail[name] or 0) + 1
			end
			-- 扣除已在 ings_list 中且背包有的食材
			for _, ing in ipairs(ings_list) do
				if bp_avail[ing] and bp_avail[ing] > 0 then
					bp_avail[ing] = bp_avail[ing] - 1
				end
			end
			-- 逐槽检查: 该槽食材背包缺失 → 尝试替换
			for slot_i = 1, #ings_list do
				local cur = ings_list[slot_i]
				if cur ~= nil and cur ~= WIT_NAME then
					-- 检查背包是否已有足够此食材
					local bp_check = {}
					for _, v in ipairs(bp_items) do
						local name = WIT_COOKING_ALIASES[v] or v
						bp_check[name] = (bp_check[name] or 0) + 1
					end
					local need_count = 0
					for _, v in ipairs(ings_list) do
						if v == cur then need_count = need_count + 1 end
					end
					if (bp_check[cur] or 0) < need_count then
						-- 背包缺此食材, 尝试从背包找替代
						local best_sub = nil
						for bp_name, bp_count in pairs(bp_avail) do
							if bp_count > 0 and bp_name ~= cur then
								-- 只用 test() 验证替换安全性
								local sim_names, sim_tags = {}, {}
								for ii, ing in ipairs(ings_list) do
									local name = (ii == slot_i) and bp_name or ing
									sim_names[name] = (sim_names[name] or 0) + 1
									local ing_data = (cooking.ingredients or {})[name]
									if ing_data then
										for kk, vv in pairs(ing_data.tags) do
											sim_tags[kk] = (sim_tags[kk] or 0) + vv
										end
									end
								end
								if r.test("cookpot", sim_names, sim_tags) then
									best_sub = bp_name
									break
								end
							end
						end
						if best_sub then
							ings_list[slot_i] = best_sub
							bp_avail[best_sub] = bp_avail[best_sub] - 1
						end
					end
				end
			end
		end
	end
	if #ings_list > 0 then
		local need_map = {}
		for _, ci in ipairs(r.card_def and r.card_def.ingredients or {}) do
			need_map[ci[1]] = (need_map[ci[1]] or 0) + ci[2]
		end
		while #ings_list < 4 do table.insert(ings_list, nil) end

		local slot_start_x = -140
		for ii = 1, 4 do
			local hl = (ings_list[ii] == WIT_NAME)
			local need_amt = ings_list[ii] and need_map[ings_list[ii]] or nil
			MakeSlot(WIT_CONTENT, ings_list[ii], slot_start_x + (ii - 1) * 58, card_y - 8, need_amt, hl, nil, nil, nil, false)
		end
		MakeArrow(WIT_CONTENT, slot_start_x + 4 * 58 - 10, card_y - 8)
		MakeSlot(WIT_CONTENT, r.name, slot_start_x + 4 * 58 + 32, card_y - 8, nil, false, nil, nil, nil, false)

		local can_cook = CanAutoCook(r)
		local craft_btn = WIT_CONTENT:AddChild(ImageButton("images/crafting_menu.xml", "ingredient_craft.tex", "ingredient_craft.tex"))
		if craft_btn then
			craft_btn:SetPosition(slot_start_x + 4 * 58 + 32 + 32, card_y - 8 - 32)
			craft_btn:SetScale(0.35)
			if can_cook then
				craft_btn.image:SetTint(1, 1, 1, 1)
			else
				craft_btn.image:SetTint(0.5, 0.5, 0.5, 1)
			end
			craft_btn:SetOnClick(function()
				if not CanAutoCook(r) then return end
				AutoFillCookPot(r)
			end)
		end
	end
end

-- ============================
-- 通用分页卡片渲染
-- ============================
function RenderCards(recipes, card_h, card_spacing, render_card_fn)
	if WIT_CONTENT == nil then return end
	WIT_CONTENT:KillAllChildren()

	local total = #recipes
	local pages = math.max(1, math.ceil(total / WIT_PAGE_SIZE))
	if WIT_PAGE > pages then WIT_PAGE = pages end
	if WIT_PAGE < 1 then WIT_PAGE = 1 end

	if WIT_PG_TEXT then WIT_PG_TEXT:SetString(WIT_PAGE .. " / " .. pages) end

	local start_i = (WIT_PAGE - 1) * WIT_PAGE_SIZE + 1
	local end_i = math.min(start_i + WIT_PAGE_SIZE - 1, total)

	for idx = start_i, end_i do
		local r = recipes[idx]
		local local_i = idx - start_i
		local card_y = -local_i * card_spacing + 25
		local card_bg = WIT_CONTENT:AddChild(Image("images/global.xml", "square.tex"))
		if card_bg then card_bg:SetSize(370, card_h); card_bg:SetTint(0.12, 0.10, 0.08, 0.6); card_bg:SetPosition(0, card_y) end
		render_card_fn(r, card_y)
	end
end
