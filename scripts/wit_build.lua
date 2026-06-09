-- wit_build: 索引构建
-- 依赖: WIT, WIT.ingredient_tags (全局)

-- 为无 card_def 的配方提供硬编码示例组合 (来源: wiki Cookbook 卡 + test()验证)
local FALLBACK_CARD_DEF = {
	["asparagussoup"] = {ingredients = {{"asparagus",1}, {"carrot",2}, {"corn",1}} },
	["baconeggs"] = {ingredients = {{"monstermeat",1}, {"smallmeat",1}, {"egg",2}} },
	["bananajuice"] = {ingredients = {{"cave_banana",2}, {"berries",2}} },
	["barnaclepita"] = {ingredients = {{"barnacle",1}, {"carrot",1}, {"berries",2}} },
	["barnaclinguine"] = {ingredients = {{"barnacle",2}, {"carrot",1}, {"corn",1}} },
	["beefalotreat"] = {ingredients = {{"twigs",1}, {"forgetmelots",1}, {"acorn",1}, {"twigs",1}} },
	["bonestew"] = {ingredients = {{"meat",3}, {"berries",1}} },
	["bunnystew"] = {ingredients = {{"smallmeat",1}, {"ice",2}, {"berries",1}} },
	["ceviche"] = {ingredients = {{"fishmeat",2}, {"ice",2}} },
	["batnosehat"] = {ingredients = {{"batnose",1}, {"kelp",1}, {"butter",1}, {"berries",1}} },
	["dustmeringue"] = {ingredients = {{"refined_dust",1}, {"berries",3}} },
	["figatoni"] = {ingredients = {{"fig",1}, {"carrot",1}, {"corn",1}, {"berries",1}} },
	["flowersalad"] = {ingredients = {{"cactus_flower",1}, {"carrot",2}, {"corn",1}} },
	["frognewton"] = {ingredients = {{"fig",1}, {"froglegs",1}, {"berries",2}} },
	["frozenbananadaiquiri"] = {ingredients = {{"cave_banana",1}, {"ice",1}, {"berries",2}} },
	["fruitmedley"] = {ingredients = {{"dragonfruit",3}, {"berries",1}} },
	["icecream"] = {ingredients = {{"ice",1}, {"butter",1}, {"honey",1}, {"berries",1}} },
	["jammypreserves"] = {ingredients = {{"berries",4}} },
	["jellybean"] = {ingredients = {{"royal_jelly",1}, {"berries",3}} },
	["justeggs"] = {ingredients = {{"egg",3}, {"berries",1}} },
	["koalefig_trunk"] = {ingredients = {{"trunk_summer",1}, {"fig",1}, {"berries",2}} },
	["leafloaf"] = {ingredients = {{"plantmeat",2}, {"berries",2}} },
	["leafymeatburger"] = {ingredients = {{"plantmeat",1}, {"onion",1}, {"carrot",1}, {"corn",1}} },
	["leafymeatsouffle"] = {ingredients = {{"plantmeat",2}, {"honey",2}} },
	["lobsterbisque"] = {ingredients = {{"wobster_sheller_land",1}, {"ice",1}, {"berries",2}} },
	["lobsterdinner"] = {ingredients = {{"wobster_sheller_land",1}, {"butter",1}, {"smallmeat",1}, {"berries",1}} },
	["mandrakesoup"] = {ingredients = {{"mandrake",1}, {"berries",3}} },
	["mashedpotatoes"] = {ingredients = {{"potato",2}, {"garlic",1}, {"berries",1}} },
	["meatballs"] = {ingredients = {{"monstermeat",1}, {"red_cap",3}} },
	["meatysalad"] = {ingredients = {{"plantmeat",1}, {"carrot",1}, {"corn",1}, {"asparagus",1}} },
	["monsterlasagna"] = {ingredients = {{"monstermeat",2}, {"berries",2}} },
	["perogies"] = {ingredients = {{"smallmeat",1}, {"egg",1}, {"carrot",1}, {"berries",1}} },
	["potatotornado"] = {ingredients = {{"potato",1}, {"twigs",1}, {"berries",2}} },
	["ratatouille"] = {ingredients = {{"carrot",1}, {"berries",3}} },
	["salsa"] = {ingredients = {{"tomato",1}, {"onion",1}, {"berries",2}} },
	["seafoodgumbo"] = {ingredients = {{"fishmeat",2}, {"fishmeat_small",1}, {"ice",1}} },
	["shroombait"] = {ingredients = {{"moon_cap",2}, {"monstermeat",1}, {"berries",1}} },
	["shroomcake"] = {ingredients = {{"moon_cap",1}, {"red_cap",1}, {"blue_cap",1}, {"green_cap",1}} },
	["surfnturf"] = {ingredients = {{"meat",2}, {"fishmeat",2}} },
	["talleggs"] = {ingredients = {{"tallbirdegg",1}, {"carrot",1}, {"berries",2}} },
	["unagi"] = {ingredients = {{"eel",1}, {"cutlichen",1}, {"berries",2}} },
	["veggieomlet"] = {ingredients = {{"egg",2}, {"carrot",1}, {"corn",1}} },
	["vegstinger"] = {ingredients = {{"tomato",1}, {"asparagus",1}, {"carrot",1}, {"ice",1}} },
	["waffles"] = {ingredients = {{"butter",1}, {"egg",1}, {"berries",2}} },
	["watermelonicle"] = {ingredients = {{"watermelon",1}, {"ice",1}, {"twigs",1}, {"berries",1}} },
	["wetgoop"] = {ingredients = {{"twigs",4}} },
}

function BuildIndexes()
	if WIT_data_built then return end
	WIT_data_built = true
	for rname, recipe in pairs(AllRecipes) do
		local prod = recipe.product or rname
		WIT.by_product[prod] = WIT.by_product[prod] or {}
		table.insert(WIT.by_product[prod], recipe)
		for _, ing in ipairs(recipe.ingredients or {}) do
			if type(ing.type) == "string" then
				WIT.by_material[ing.type] = WIT.by_material[ing.type] or {}
				table.insert(WIT.by_material[ing.type], recipe)
			end
		end
	end
	local cooking = GLOBAL.require("cooking")
	if cooking ~= nil then
		for _, recipes in pairs(cooking.cookbook_recipes or {}) do
			for fname, frecipe in pairs(recipes) do
				WIT.cook_foods[fname] = frecipe
			end
		end
		for iname, idata in pairs(cooking.ingredients or {}) do
			WIT.ingredient_tags[iname] = idata.tags
		end

		local cooker_types = {"cookpot", "portablecookpot"}
		for _, cooker_type in ipairs(cooker_types) do
			for fname, frecipe in pairs(cooking.recipes[cooker_type] or {}) do
				if frecipe.test and not frecipe.card_def and FALLBACK_CARD_DEF[fname] then
					frecipe.card_def = FALLBACK_CARD_DEF[fname]
				end
				if not WIT.cook_foods[fname] then
					WIT.cook_foods[fname] = frecipe
				end
				if frecipe.test and frecipe.card_def and frecipe.card_def.ingredients then
					for iname, _ in pairs(cooking.ingredients or {}) do
						local item_tags = WIT.ingredient_tags[iname]
						if item_tags then
							local can_participate = false
							for slot_idx = 1, #frecipe.card_def.ingredients do
								local names, tags = {}, {}
								for j, ci in ipairs(frecipe.card_def.ingredients) do
									local name = ci[1]
									for _ = 1, ci[2] do
										if j == slot_idx then
											name = iname
										end
										names[name] = (names[name] or 0) + 1
										local ing_data = (cooking.ingredients or {})[name]
										if ing_data then
											for kk, vv in pairs(ing_data.tags) do
												tags[kk] = (tags[kk] or 0) + vv
											end
										end
									end
								end
								if frecipe.test("cookpot", names, tags) then
									can_participate = true
									break
								end
							end
							if can_participate then
								if not WIT.cook_by_ingredient[iname] then WIT.cook_by_ingredient[iname] = {} end
								local exists = false
								for _, r in ipairs(WIT.cook_by_ingredient[iname]) do
									if r.name == fname then exists = true; break end
								end
								if not exists then table.insert(WIT.cook_by_ingredient[iname], frecipe) end
							end
						end
					end
				end
			end
		end
	end
end