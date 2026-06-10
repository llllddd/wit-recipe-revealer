-- wit_render: 卡片渲染
-- 依赖: 全局 Image, Text, TextButton, ImageButton

-- ============================
-- 烹饪条件推导
-- ============================

-- 格式化条件数值：去除非必要的 ".0"（≥2.0 → ≥2，≥0.5 保留）
-- ">" 后加空格提高辨识度（DST 字体较窄，> 易和数字粘连）
-- "==" 改为 "=0"（表示禁止该食材，需换字体解决 = 看不清的问题）
local function FormatCondValue(v)
	if v == nil then return "" end
	-- 禁止项
	if v == "==" then return "=0" end
	local prefix = v:match("^([^%d.]+)")
	local num_str = v:match("([%d.]+)$")
	if num_str then
		local n = tonumber(num_str)
		if n ~= nil and n == math.floor(n) then
			num_str = tostring(math.floor(n))
		end
		-- > 后加空格，避免在 DST 窄字体中和数字粘连
		if prefix == ">" then
			return "> " .. num_str
		end
		return (prefix or "") .. num_str
	end
	return v
end

function FormatCookCondition(recipe, _)
	-- 从 wiki 提取的精确标签条件数据
	local CONDITIONS = {
		["baconeggs"] = {{"meat",">1.0"}, {"egg",">1.0"}, {"veggie","=="}},
		["bananajuice"] = {{"cave_banana","×2"}},
		["barnaclepita"] = {{"barnacle","+1"}, {"veggie","≥0.5"}},
		["barnaclesushi"] = {{"barnacle","+1"}, {"kelp","+1"}, {"egg",">0"}},
		["barnaclinguine"] = {{"barnacle","×2"}, {"veggie","≥2.0"}},
		["bananapop"] = {{"cave_banana","+1"}, {"ice","+1"}, {"twigs","+1"}},
		["barnaclestuffedfishhead"] = {{"barnacle","+1"}, {"fish","≥1.25"}},
		["batnosehat"] = {{"batnose","+1"}, {"kelp","+1"}, {"dairy","≥1.0"}},
		["beefalofeed"] = {{"inedible",">0"}, {"seed","≥1"}, {"forgetmelots","+1"}},
		["beefalotreat"] = {{"acorn","+1"}, {"inedible",">0"}, {"forgetmelots","+1"}},
		["bonestew"] = {{"meat","≥3.0"}},
		["bunnystew"] = {{"meat",">0"}, {"frozen","≥2"}},
		["butterflymuffin"] = {{"butterflywings","+1"}, {"veggie","≥0.5"}},
		["californiaroll"] = {{"seaweed","+2"}, {"fish","≥1.0"}},
		["dragonpie"] = {{"dragonfruit","+1"}},
		["figkabab"] = {{"fig","+1"}, {"meat","≥1.0"}, {"twigs","+1"}},
		["fishtacos"] = {{"corn","+1"}, {"fish","≥0.25"}},
		["fishsticks"] = {{"fish",">0"}, {"twigs","×1.0"}},
		["flowersalad"] = {{"cactus_flower","+1"}, {"veggie","≥2.0"}},
		["frogglebunwich"] = {{"froglegs","+1"}, {"veggie","≥0.5"}},
		["fruitmedley"] = {{"fruit","≥3.0"}},
		["guacamole"] = {{"cactus_flower","+1"}, {"veggie","≥0.5"}},
		["honeyham"] = {{"honey","+1"}, {"meat",">1.5"}},
		["honeynuggets"] = {{"honey","+1"}, {"meat",">0"}},
		["hotchili"] = {{"pepper","+1"}, {"meat","≥1.0"}},
		["icecream"] = {{"ice","+1"}, {"dairy","≥1.0"}, {"sweetener","≥1.0"}},
		["jammypreserves"] = {{"fruit",">0"}},
		["jellybean"] = {{"royal_jelly","+1"}},
		["justeggs"] = {{"egg","≥3.0"}},
		["kabobs"] = {{"meat",">0"}, {"twigs","+1"}},
		["koalefig_trunk"] = {{"trunk_summer","+1"}, {"fig","+1"}},
		["leafloaf"] = {{"plantmeat","×2"}},
		["leafymeatburger"] = {{"plantmeat","+1"}, {"onion","+1"}, {"veggie","≥2.0"}},
		["leafymeatsouffle"] = {{"plantmeat","×2"}, {"sweetener","≥2.0"}},
		["lobsterbisque"] = {{"wobster_sheller_land","+1"}, {"ice","+1"}},
		["lobsterdinner"] = {{"wobster_sheller_land","+1"}, {"butter","+1"}},
		["mandrakesoup"] = {{"mandrake","+1"}},
		["mashedpotatoes"] = {{"potato","×2"}, {"garlic","+1"}},
		["meatballs"] = {{"meat",">0"}},
		["meatysalad"] = {{"plantmeat","+1"}, {"veggie","≥3.0"}},
		["monsterlasagna"] = {{"monstermeat","×2"}},
		["pepperpopper"] = {{"pepper","+1"}, {"meat","≥1.0"}},
		["perogies"] = {{"egg",">0"}, {"meat",">0"}, {"veggie",">0"}},
		["potatotornado"] = {{"potato","+1"}, {"twigs","+1"}},
		["powcake"] = {{"twigs","+1"}, {"honey","+1"}, {"corn","+1"}},
		["pumpkincookie"] = {{"pumpkin","+1"}, {"sweetener","≥2.0"}},
		["ratatouille"] = {{"veggie","≥0.5"}},
		["salsa"] = {{"tomato","+1"}, {"onion","+1"}},
		["shroomcake"] = {{"moon_cap","+1"}, {"red_cap","+1"}, {"blue_cap","+1"}, {"green_cap","+1"}},
		["stuffedeggplant"] = {{"eggplant","+1"}, {"veggie",">1.0"}},
		["surfnturf"] = {{"meat","≥2.5"}, {"fish","≥1.5"}},
		["sweettea"] = {{"honey","+1"}, {"ice","+1"}},
		["taffy"] = {{"sweetener","≥3.0"}},
		["trailmix"] = {{"berries","+1"}, {"fruit","≥0.5"}},
		["turkeydinner"] = {{"drumstick","×2"}, {"meat",">1.0"}},
		["unagi"] = {{"eel","+1"}, {"cutlichen","+1"}},
		["vegstinger"] = {{"asparagus","+1"}, {"tomato","+1"}, {"veggie",">2.0"}, {"frozen","≥1.0"}},
		["waffles"] = {{"butter","+1"}, {"egg",">0"}, {"berries","+1"}},
		["watermelonicle"] = {{"watermelon","+1"}, {"ice","+1"}, {"twigs","+1"}},
		["frognewton"] = {{"fig","+1"}, {"froglegs","+1"}},
		["figatoni"] = {{"fig","+1"}, {"veggie","≥2.0"}},
		["frozenbananadaiquiri"] = {{"cave_banana","+1"}, {"frozen","≥1.0"}},
		["asparagussoup"] = {{"asparagus","+1"}, {"veggie","≥1.5"}},
		["ceviche"] = {{"ice","+1"}, {"fish","≥2.0"}},
		["seafoodgumbo"] = {{"fish",">2.0"}},
		["talleggs"] = {{"tallbirdegg","+1"}, {"veggie","≥1.0"}},
		["veggieomlet"] = {{"egg","≥1.0"}, {"veggie","≥1.0"}},
		["wetgoop"] = {{}},
		["dustmeringue"] = {{"refined_dust","+1"}},
		["shroombait"] = {{"moon_cap","≥2"}, {"monstermeat","+1"}},
		-- 沃利便携锅专属配方
		["voltgoatjelly"] = {{"sweetener","≥2"}},
		["glowberrymousse"] = {{"fruit","≥2"}},
		["frogfishbowl"] = {{"fish","≥1"}},
		["gazpacho"] = {{"frozen","≥2"}},
		["potatosouffle"] = {{"egg",">0"}},
		["monstertartare"] = {{"monster","≥2"}},
		["freshfruitcrepes"] = {{"fruit","≥1.5"}},
		["bonesoup"] = {{"inedible","<3"}},
		["moqueca"] = {{"fish",">0"}},
		["nightmarepie"] = {{"nightmarefuel","+1"}},
		["dragonchilisalad"] = {{"dragonfruit","+1"}},
	}

	local conds = CONDITIONS[recipe.name]
	if not conds and WIT_PROBED_CONDITIONS then
		conds = WIT_PROBED_CONDITIONS[recipe.name]
	end
	if conds then
		local parts = {}
		for _, c in ipairs(conds) do
			if c[1] ~= nil then
				table.insert(parts, CN(c[1]) .. " " .. FormatCondValue(c[2]))
			end
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

	-- 从求解器获取已求解的展示视图
	local view = GetResolvedCookingCard(r, WIT_NAME)
	if not view then
		-- 降级: 无求解器上下文时直接展开原始食材
		local raw = FlattenIngredients(r.card_def and r.card_def.ingredients)
		view = { slots = PadSlots(raw, 4), need_map = BuildNeedMap(r.card_def and r.card_def.ingredients), can_auto_cook = false }
	end

	local slot_start_x = -140
	for ii = 1, 4 do
		local hl = (view.slots[ii] == WIT_NAME)
		local need_amt = view.slots[ii] and view.need_map[view.slots[ii]] or nil
		MakeSlot(WIT_CONTENT, view.slots[ii], slot_start_x + (ii - 1) * 58, card_y - 8, need_amt, hl, nil, nil, nil, false)
	end
	MakeArrow(WIT_CONTENT, slot_start_x + 4 * 58 - 10, card_y - 8)
	MakeSlot(WIT_CONTENT, r.name, slot_start_x + 4 * 58 + 32, card_y - 8, nil, false, nil, nil, nil, false)

	local craft_btn = WIT_CONTENT:AddChild(ImageButton("images/crafting_menu.xml", "ingredient_craft.tex", "ingredient_craft.tex"))
	if craft_btn then
		craft_btn:SetPosition(slot_start_x + 4 * 58 + 32 + 32, card_y - 8 - 32)
		craft_btn:SetScale(0.35)
		if view.can_auto_cook then
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

-- ============================
-- 通用分页卡片渲染
-- ============================
function RenderCards(recipes, card_h, card_spacing, render_card_fn)
	if WIT_CONTENT == nil then return end
	WIT_CONTENT:KillAllChildren()

	local total = #recipes
	local pages = math.max(1, math.ceil(total / WIT_PAGE_SIZE))
	if WIT_PAGE > pages then WIT_PAGE = 1 end
	if WIT_PAGE < 1 then WIT_PAGE = pages end

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
