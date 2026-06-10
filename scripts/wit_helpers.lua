-- wit_helpers: 通用辅助函数
-- 依赖: 全局 WIT_POPUP, WIT_NAME, WIT_MODE, WIT_CUR_CAT, WIT_PAGE, WIT_AVAIL_CATS, WIT_CONTENT, WIT_TAB_BTNS, WIT_PG_TEXT, WIT_PG_PREV, WIT_PG_NEXT, WIT_OPEN_COOKPOT

function GetHoverItem()
	local hud_ent = TheInput:GetHUDEntityUnderMouse()
	if hud_ent == nil then return nil end
	return hud_ent.widget and hud_ent.widget.parent and hud_ent.widget.parent.item
end

function ClosePopup()
	if WIT_POPUP ~= nil then WIT_POPUP:Kill(); WIT_POPUP = nil end
	WIT_NAME = nil; WIT_MODE = nil; WIT_CUR_CAT = nil; WIT_PAGE = 1
	WIT_AVAIL_CATS = {}; WIT_CONTENT = nil; WIT_TAB_BTNS = {}
	WIT_PG_TEXT = nil; WIT_PG_PREV = nil; WIT_PG_NEXT = nil
	WIT_OPEN_COOKPOT = nil; WIT_COOK_CONTEXT = nil
end

-- ============================
-- 烹饪锅检测
-- ============================
function GetOpenCookPot()
	if ThePlayer == nil or ThePlayer.replica == nil then return nil end
	local containers = ThePlayer.replica.inventory:GetOpenContainers()
	if containers == nil then return nil end
	for ent, _ in pairs(containers) do
		if ent:HasTag("stewer") and ent.replica.container ~= nil then
			return ent
		end
	end
	return nil
end

-- ============================
-- 统计玩家库存中某食材数量
-- ============================
function CountPlayerItem(prefab)
	if ThePlayer == nil or ThePlayer.replica == nil then return 0 end
	local inv = ThePlayer.replica.inventory
	if inv == nil then return 0 end
	local count = 0
	local items = {}
	if inv.classified ~= nil and inv.classified.GetItems ~= nil then
		items = inv.classified:GetItems()
	end
	for _, item in pairs(items) do
		if item.prefab == prefab then
			local stack = item.replica.stackable
			count = count + (stack and stack:StackSize() or 1)
		end
	end
	local overflow = inv:GetOverflowContainer()
	if overflow ~= nil and overflow.classified ~= nil then
		local oitems = overflow.classified:GetItems()
		for _, item in pairs(oitems) do
			if item.prefab == prefab then
				local stack = item.replica.stackable
				count = count + (stack and stack:StackSize() or 1)
			end
		end
	end
	return count
end

-- ============================
-- 收集玩家背包食材列表 (最多 4 个相同物品)
-- ============================
function GetPlayerIngredientList()
	if ThePlayer == nil or ThePlayer.replica == nil then return nil end
	local inv = ThePlayer.replica.inventory
	if inv == nil then return nil end
	local list = {}
	local items = {}
	if inv.classified ~= nil and inv.classified.GetItems ~= nil then
		items = inv.classified:GetItems()
	end
	for _, item in pairs(items) do
		if item.replica.inventoryitem then
			local stackable = item.replica.stackable
			local cnt = stackable and stackable:StackSize() or 1
			for _ = 1, math.min(cnt, 4) do
				table.insert(list, item.prefab)
			end
		end
	end
	local overflow = inv:GetOverflowContainer()
	if overflow ~= nil and overflow.classified ~= nil and overflow.classified.GetItems ~= nil then
		local oitems = overflow.classified:GetItems()
		for _, item in pairs(oitems) do
			if item.replica.inventoryitem then
				local stackable = item.replica.stackable
				local cnt = stackable and stackable:StackSize() or 1
				for _ = 1, math.min(cnt, 4) do
					table.insert(list, item.prefab)
				end
			end
		end
	end
	return list
end

-- ============================
-- 在库存 + 背包中找食材槽位
-- ============================
function FindItemSlotInInventory(prefab)
	if ThePlayer == nil or ThePlayer.replica == nil then return nil, nil end
	local inv = ThePlayer.replica.inventory
	if inv == nil then return nil, nil end
	local classified = inv.classified
	if classified == nil then return nil, nil end
	local items = classified:GetItems()
	for slot, item in pairs(items) do
		if item.prefab == prefab then
			return slot, ThePlayer
		end
	end
	local overflow = inv:GetOverflowContainer()
	if overflow ~= nil and overflow.classified ~= nil then
		local oitems = overflow.classified:GetItems()
		for slot, item in pairs(oitems) do
			if item.prefab == prefab then
				return slot, overflow.inst
			end
		end
	end
	return nil, nil
end

-- ============================
-- 自动烹饪检测
-- ============================
function CanAutoCook(recipe)
	if recipe == nil then return false end
	local pot = WIT_OPEN_COOKPOT
	if pot == nil then return false end
	if recipe.card_def == nil or recipe.card_def.ingredients == nil then return false end
	if pot.replica.stewer ~= nil then
		if pot.replica.stewer:IsCooking() or pot.replica.stewer:IsDone() then return false end
	end
	local need = {}
	for _, ci in ipairs(recipe.card_def.ingredients) do
		need[ci[1]] = (need[ci[1]] or 0) + ci[2]
	end
	for prefab, count in pairs(need) do
		if CountPlayerItem(prefab) < count then return false end
	end
	return true
end

-- ============================
-- 自动填充烹饪锅
-- ============================
function AutoFillCookPot(recipe)
	if ThePlayer == nil or recipe == nil then return end
	local pot = WIT_OPEN_COOKPOT
	if pot == nil then return end
	local inv = ThePlayer.replica.inventory
	if inv == nil then return end
	local classified = inv.classified
	if classified == nil then return end
	for _, ci in ipairs(recipe.card_def.ingredients or {}) do
		for _ = 1, ci[2] do
			local slot, owner = FindItemSlotInInventory(ci[1])
			if slot ~= nil and owner ~= nil then
				classified:MoveItemFromAllOfSlot(slot, pot)
			end
		end
	end
end
