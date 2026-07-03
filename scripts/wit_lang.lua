-- wit_lang: 国际化模块
-- 自动适应 DST 游戏语言, 也可在配置中强制切换
-- 所有玩家可见文本都集中在此

local LANG = GetModConfigData("LANGUAGE") or ""
if LANG == "" or LANG == "auto" then
	local lang_id = (Profile and Profile:GetLanguageID()) or LANGUAGE.ENGLISH
	if lang_id == LANGUAGE.CHINESE_S or lang_id == LANGUAGE.CHINESE_T or lang_id == LANGUAGE.CHINESE_S_RAIL then
		LANG = "zh"
	else
		LANG = "en"
	end
end

local TXT = {}

if LANG == "zh" then
	-- ======== 中文 ========
	TXT.TAB_CRAFTING = "制作"
	TXT.TAB_COOKING = "烹饪"
	TXT.TAB_CRAFT_FROM = "制作来源"
	TXT.TAB_CRAFT_USE = "制作用途"
	TXT.TAB_COOK_FROM = "烹饪来源"
	TXT.TAB_COOK_USE = "烹饪用途"
	TXT.TAB_INFO = "信息"
	TXT.PRIORITY = "P"
	TXT.CLOSE = "×"
	TXT.LOADING = "加载中..."
	TXT.NO_INFO = "无详细信息"
	TXT.AUTO_COOK_TIP = "自动放入"

	-- 物品信息
	TXT.DMG = "伤害"
	TXT.ABSORB = "吸收"
	TXT.DUR = "耐久"
	TXT.EFF = "效率"
	TXT.ACTION = "动作"
	TXT.HUNGER = "饱食"
	TXT.HEALTH = "生命"
	TXT.SANITY = "精神"
	TXT.FOODTYPE = "食物类型"
	TXT.TEMP = "温度"
	TXT.HEAL = "治疗"
	TXT.SLOT = "装备位"
	TXT.SPEED = "速度"
	TXT.USES = "次数"
	TXT.SPOIL = "保鲜"
	TXT.DAY = "天"
	TXT.BURN = "燃烧"
	TXT.SEC = "秒"
	TXT.FUEL = "燃料"
	TXT.MIN = "分"
	TXT.WATERPROOF = "防水"
	TXT.INSULATE = "保暖"
	TXT.STACK = "堆叠"
	TXT.TRADE = "交易"
	TXT.REPAIRABLE = "可修理"
	TXT.REPAIRABLE_BY = "可被 %s 修理"
	TXT.SEWABLE = "可缝补"
	TXT.INEDIBLE_PLAYER = "非玩家可食"
	TXT.EDIBLE_BY = "可被 %s 食用"

	-- 装备位（EQUIPSLOTS 枚举值）
	TXT.EQUIPSLOT_NAMES = {
		head = "头部",
		body = "身体",
		hands = "手部",
		beard = "胡须",
	}

	-- 标签条件
	TXT.TAG_NAMES = {
		meat = "肉度", monster = "怪物度", veggie = "蔬菜度", fruit = "水果度",
		egg = "蛋度", fish = "鱼度", sweetener = "甜味剂度", fat = "油脂度",
		dairy = "乳制品度", inedible = "不可食用度", seed = "种子度", magic = "魔法度",
		decoration = "装饰度", precook = "预处理度", dried = "干货度", frozen = "冰度",
		-- mod 自定义 tag（永不妥协等）
		insectoid = "虫类度", foliage = "叶绿度", rice = "米粮度",
	}

	-- 食物类型本地化（与官方图鉴翻译一致）
	TXT.FOODTYPE_NAMES = {
		GENERIC = "通用", MEAT = "肉", VEGGIE = "素食",
		ELEMENTAL = "元素", GEARS = "齿轮", HORRIBLE = "可怕",
		INSECT = "昆虫", SEEDS = "种子", BERRY = "浆果",
		RAW = "生的", BURNT = "烧焦", ROUGHAGE = "粗食",
		WOOD = "木质", GOODIES = "好东西", MONSTER = "怪物",
		LUNAR_SHARDS = "月亮碎片", CORPSE = "尸体",
	}

	-- 图标悬浮提示（中文）
	TXT.ICON_TOOLTIPS = {
		icon_hunger = "饥饿值回复",
		icon_health = "生命值回复",
		icon_sanity = "理智值回复",
		icon_damage = "攻击伤害",
		icon_armor = "护甲吸收率",
		icon_uses = "使用次数",
		icon_action = "工具动作",
		icon_clothing = "装备类型",
		icon_food = "食物类型",
		icon_heat = "升温效果",
		icon_cold = "降温效果",
		icon_spoil = "腐坏时间",
		icon_burnable = "燃烧时长",
		icon_fuel = "使用/燃料时长",
		icon_wrench = "可修理",
		icon_sewingkit = "可缝补",
		icon_wetness = "防水效果",
		icon_stack = "最大堆叠",
		cane = "移速加成",
		goldnugget = "交易价值",
	}

	-- 信息栏区块提示
	TXT.TIP_SPOIL = "腐烂时间"
	TXT.TIP_ATK_RANGE = "攻击范围"
	TXT.TIP_TOOL_EFF = "工具效率倍率"
	TXT.TIP_BURN = "作为燃料时燃烧时长"
	TXT.TIP_FUEL_USAGE = "装备磨损耐久"
	TXT.TIP_FUEL_TIME = "燃料时长"
	TXT.TIP_SEW = "可使用缝纫包修复"
	TXT.TIP_WATERPROOF = "防水效果百分比"
	TXT.TIP_INSULATE_SUMMER = "隔热时长（夏季）"
	TXT.TIP_INSULATE_WINTER = "保暖时长（冬季）"
	TXT.TIP_TRADE = "交易价值"
	TXT.TIP_REPAIR_MAT = "可使用该材料修复"
	TXT.TIP_TEMP_HEAT = "升温"
	TXT.TIP_TEMP_COOL = "降温"
	TXT.TIP_TEMP_DUR = "量 / 持续时间"
	TXT.TIP_SANITY_AURA = "附近时理智光环（/分钟）"
	TXT.TIP_SANITY_EQUIP = "装备时理智变化（/分钟）"
	TXT.FMT_EDIBLE_BY = "可被 %s 食用"
	TXT.FMT_INEDIBLE = "非玩家可食用"
	TXT.FMT_COND_ZERO = "＝０"
	TXT.EATER_BEEFALO = "皮弗娄牛"
	TXT.EATER_SHADOW = "暗影生物"
	TXT.NAV_BACK = "后退"
	TXT.NAV_FWD = "前进"
	TXT.FMT_MOD_SOURCE = "[来自] %s"
	TXT.FILLER_SLOT = "任意食材"
	TXT.FILLER_SLOT_TIP = "此格可放入任意食材（填充物）"
	TXT.TAB_SOURCES = "获取来源"
	TXT.SRC_DROP = "掉落"
	TXT.SRC_PICK = "采集"
	TXT.SRC_CHOP = "砍伐"
	TXT.SRC_DIG = "挖掘"
	TXT.SRC_HAMMER = "锤拆"
	TXT.SRC_MINE = "开采"
	TXT.SRC_TRADE = "交易"
	TXT.SRC_TRAP = "陷阱"
	TXT.SRC_DECONSTRUCT = "拆解"
	TXT.SRC_NO_SOURCE = "无已知来源"
	TXT.NOUNLOCK_STATION = "需在制作站旁制作"
	TXT.CFG_LANG_LABEL = "界面语言"
	TXT.CFG_LANG_HOVER = "选择 Mod 界面显示语言。切换后需重启游戏生效"
	TXT.CFG_LANG_AUTO = "自动"
	TXT.CFG_LANG_ZH = "中文"
	TXT.CFG_LANG_EN = "英文"
	TXT.CFG_KEY_R_LABEL = "来源查询键"
	TXT.CFG_KEY_R_HOVER = "悬浮物品后按下此键，查看该物品的制作/烹饪配方和获取来源"
	TXT.CFG_KEY_U_LABEL = "用途查询键"
	TXT.CFG_KEY_U_HOVER = "悬浮物品后按下此键，查看该物品的用途"
	TXT.CFG_NAV_BACK_LABEL = "导航后退键"
	TXT.CFG_NAV_BACK_HOVER = "在 WIT 弹窗中按下此键，回退到上一个浏览的物品"
	TXT.CFG_NAV_FORWARD_LABEL = "导航前进键"
	TXT.CFG_NAV_FORWARD_HOVER = "在 WIT 弹窗中按下此键，前进到下一个浏览的物品"
	TXT.CFG_POS_LABEL = "弹窗位置"
	TXT.CFG_POS_HOVER = "信息弹窗的水平显示位置"
	TXT.CFG_POS_AUTO = "自动（跟随合成栏）"
	TXT.CFG_POS_LEFT = "居左"
	TXT.CFG_POS_RIGHT = "居右"
	TXT.CFG_BTN_TOOLTIP = "打开 Mod 配置 - 调整语言、按键绑定等"
	TXT.CFG_HOVER_LABEL = "图标悬浮详情"
	TXT.CFG_HOVER_HOVER = "在弹窗内悬浮物品图标时，显示该物品的核心属性数值（图标+数字）"
	TXT.CFG_PAUSE_LABEL = "打开UI自动暂停"
	TXT.CFG_PAUSE_HOVER = "单人世界中打开本模组主界面时自动暂停世界；多人模式下不生效"
	TXT.CFG_DETAIL_LCLICK_LABEL = "菜单图标左键查询"
	TXT.CFG_DETAIL_LCLICK_HOVER = "在合成菜单详情面板中，左键产物图标时打开来源查询。关闭后仍可使用悬浮+R/U键查询"
	TXT.CFG_DETAIL_RCLICK_LABEL = "菜单图标右键查询"
	TXT.CFG_DETAIL_RCLICK_HOVER = "在合成菜单详情面板中，右键图标时打开用途查询。关闭后仍可使用悬浮+R/U键查询"
	TXT.CFG_ON = "开"
	TXT.CFG_OFF = "关"

else
	-- ======== 英文 ========
	TXT.TAB_CRAFTING = "Crafting"
	TXT.TAB_COOKING = "Cooking"
	TXT.TAB_CRAFT_FROM = "Craft From"
	TXT.TAB_CRAFT_USE = "Craft Use"
	TXT.TAB_COOK_FROM = "Cook From"
	TXT.TAB_COOK_USE = "Cook Use"
	TXT.TAB_INFO = "Info"
	TXT.PRIORITY = "P"
	TXT.CLOSE = "×"
	TXT.LOADING = "Loading..."
	TXT.NO_INFO = "No detailed info"
	TXT.AUTO_COOK_TIP = "Auto Cook"

	-- Item Info
	TXT.DMG = "Damage"
	TXT.ABSORB = "Absorb"
	TXT.DUR = "Durability"
	TXT.EFF = "Efficiency"
	TXT.ACTION = "Action"
	TXT.HUNGER = "Hunger"
	TXT.HEALTH = "Health"
	TXT.SANITY = "Sanity"
	TXT.FOODTYPE = "Food Type"
	TXT.TEMP = "Temp"
	TXT.HEAL = "Heal"
	TXT.SLOT = "Slot"
	TXT.SPEED = "Speed"
	TXT.USES = "Uses"
	TXT.SPOIL = "Spoilage"
	TXT.DAY = "d"
	TXT.BURN = "Burn"
	TXT.SEC = "s"
	TXT.FUEL = "Fuel"
	TXT.MIN = "min"
	TXT.WATERPROOF = "Waterproof"
	TXT.INSULATE = "Insulation"
	TXT.STACK = "Stack"
	TXT.TRADE = "Trade"
	TXT.REPAIRABLE = "Repairable"
	TXT.REPAIRABLE_BY = "Repaired by %s"
	TXT.SEWABLE = "Sewable"
	TXT.INEDIBLE_PLAYER = "Not edible by players"
	TXT.EDIBLE_BY = "Edible by %s"

	TXT.EQUIPSLOT_NAMES = {
		head = "Head",
		body = "Body",
		hands = "Hands",
		beard = "Beard",
	}

	TXT.TAG_NAMES = {
		meat = "Meat", monster = "Monster", veggie = "Vegetable", fruit = "Fruit",
		egg = "Egg", fish = "Fish", sweetener = "Sweetener", fat = "Fat",
		dairy = "Dairy", inedible = "Inedible", seed = "Seed", magic = "Magic",
		decoration = "Decoration", precook = "Precooked", dried = "Dried", frozen = "Frozen",
		-- mod custom tags
		insectoid = "Insectoid", foliage = "Foliage", rice = "Rice",
	}

	-- Food type translations (matching official scrapbook)
	TXT.FOODTYPE_NAMES = {
		GENERIC = "Generic", MEAT = "Meat", VEGGIE = "Vegetable",
		ELEMENTAL = "Elemental", GEARS = "Gears", HORRIBLE = "Horrible",
		INSECT = "Insect", SEEDS = "Seeds", BERRY = "Berry",
		RAW = "Raw", BURNT = "Burnt", ROUGHAGE = "Roughage",
		WOOD = "Wood", GOODIES = "Goodies", MONSTER = "Monster",
		LUNAR_SHARDS = "Lunar Shards", CORPSE = "Corpse",
	}

	-- Icon tooltips (English)
	TXT.ICON_TOOLTIPS = {
		icon_hunger = "Hunger Restored",
		icon_health = "Health Restored",
		icon_sanity = "Sanity Restored",
		icon_damage = "Attack Damage",
		icon_armor = "Armor Absorption",
		icon_uses = "Uses",
		icon_action = "Tool Action",
		icon_clothing = "Equipment Slot",
		icon_food = "Food Type",
		icon_heat = "Heating Effect",
		icon_cold = "Cooling Effect",
		icon_spoil = "Spoilage Time",
		icon_burnable = "Burn Duration",
		icon_fuel = "Use/Fuel Duration",
		icon_wrench = "Repairable",
		icon_sewingkit = "Sewable",
		icon_wetness = "Waterproofing",
		icon_stack = "Max Stack",
		cane = "Speed Bonus",
		goldnugget = "Trade Value",
	}

	-- Info block tooltips (English)
	TXT.TIP_SPOIL = "Spoilage Time"
	TXT.TIP_ATK_RANGE = "Attack Range"
	TXT.TIP_TOOL_EFF = "Tool Efficiency"
	TXT.TIP_BURN = "Burn Duration as Fuel"
	TXT.TIP_FUEL_USAGE = "Equipment Durability"
	TXT.TIP_FUEL_TIME = "Fuel Duration"
	TXT.TIP_SEW = "Repairable with Sewing Kit"
	TXT.TIP_WATERPROOF = "Waterproofing"
	TXT.TIP_INSULATE_SUMMER = "Insulation (Summer)"
	TXT.TIP_INSULATE_WINTER = "Insulation (Winter)"
	TXT.TIP_TRADE = "Trade Value"
	TXT.TIP_REPAIR_MAT = "Repairable with this material"
	TXT.TIP_TEMP_HEAT = "Heating"
	TXT.TIP_TEMP_COOL = "Cooling"
	TXT.TIP_TEMP_DUR = "Amount / Duration"
	TXT.TIP_SANITY_AURA = "Sanity Aura (/min) nearby"
	TXT.TIP_SANITY_EQUIP = "Sanity Change (/min) when equipped"
	TXT.FMT_EDIBLE_BY = "Edible by %s"
	TXT.FMT_INEDIBLE = "Not edible by players"
	TXT.FMT_COND_ZERO = "=0"
	TXT.FILLER_SLOT = "Any Ingredient"
	TXT.FILLER_SLOT_TIP = "Any ingredient can go here (filler)"
	TXT.TAB_SOURCES = "Sources"
	TXT.SRC_DROP = "Drop"
	TXT.SRC_PICK = "Pick"
	TXT.SRC_CHOP = "Chop"
	TXT.SRC_DIG = "Dig"
	TXT.SRC_HAMMER = "Hammer"
	TXT.SRC_MINE = "Mine"
	TXT.SRC_TRADE = "Trade"
	TXT.SRC_TRAP = "Trap"
	TXT.SRC_DECONSTRUCT = "Deconstruct"
	TXT.SRC_NO_SOURCE = "No known source"
	TXT.NOUNLOCK_STATION = "Must craft at station"
	TXT.EATER_BEEFALO = "Beefalo"
	TXT.EATER_SHADOW = "Shadow Creature"
	TXT.NAV_BACK = "Back"
	TXT.NAV_FWD = "Forward"
	TXT.FMT_MOD_SOURCE = "[From] %s"

	-- Mod Config UI (English)
	TXT.CFG_LANG_LABEL = "Language"
	TXT.CFG_LANG_HOVER = "Select UI language. Requires game restart to take effect"
	TXT.CFG_LANG_AUTO = "Auto"
	TXT.CFG_LANG_ZH = "Chinese"
	TXT.CFG_LANG_EN = "English"
	TXT.CFG_KEY_R_LABEL = "Source Key"
	TXT.CFG_KEY_R_HOVER = "Hover an item and press to see recipes, cooking, and drop sources."
	TXT.CFG_KEY_U_LABEL = "Usage Key"
	TXT.CFG_KEY_U_HOVER = "Hover an item and press to see uses."
	TXT.CFG_NAV_BACK_LABEL = "Back"
	TXT.CFG_NAV_BACK_HOVER = "Navigate back to the previously browsed item in the WIT popup"
	TXT.CFG_NAV_FORWARD_LABEL = "Forward"
	TXT.CFG_NAV_FORWARD_HOVER = "Navigate forward to the next browsed item in the WIT popup"
	TXT.CFG_POS_LABEL = "Popup Position"
	TXT.CFG_POS_HOVER = "Horizontal position of the info popup"
	TXT.CFG_POS_AUTO = "Auto (Follow crafting)"
	TXT.CFG_POS_LEFT = "Left"
	TXT.CFG_POS_RIGHT = "Right"
	TXT.CFG_BTN_TOOLTIP = "Open Mod Configuration - Language, key bindings, etc."
	TXT.CFG_HOVER_LABEL = "Icon Hover Info"
	TXT.CFG_HOVER_HOVER = "Show core item stats (icons+values) when hovering over item icons in the popup"
	TXT.CFG_PAUSE_LABEL = "Pause On Open"
	TXT.CFG_PAUSE_HOVER = "Automatically pauses the world when opening the main WIT popup in single-player sessions; does nothing in multiplayer"
	TXT.CFG_DETAIL_LCLICK_LABEL = "Detail Left-Click Query"
	TXT.CFG_DETAIL_LCLICK_HOVER = "When enabled, left-clicking the product icon in the crafting menu detail panel opens the source popup. R/U key lookup still works when disabled."
	TXT.CFG_DETAIL_RCLICK_LABEL = "Detail Right-Click Query"
	TXT.CFG_DETAIL_RCLICK_HOVER = "When enabled, right-clicking an icon in the crafting menu detail panel opens the usage popup. R/U key lookup still works when disabled."
	TXT.CFG_ON = "On"
	TXT.CFG_OFF = "Off"
end

function CN(tag)
	if type(tag) ~= "string" then
		return tostring(tag)
	end
	-- 支持 "a/b/c" 形式的条件展示，逐段本地化后再拼回去。
	if tag:find("/", 1, true) then
		local parts = {}
		for part in tag:gmatch("[^/]+") do
			table.insert(parts, CN(part))
		end
		return table.concat(parts, "/")
	end
	-- 1. 具体食材/物品名：中文模式用 STRINGS.NAMES，英文模式跳过避免返回中文
	if LANG == "zh" then
		if STRINGS and STRINGS.NAMES then
			local name = STRINGS.NAMES[string.upper(tag)]
			if name then return name end
		end
		-- 2. 动作名（砍树、挖矿等）
		if STRINGS and STRINGS.ACTIONS then
			local act = STRINGS.ACTIONS[string.upper(tag)]
			if act and type(act) == "string" then return act end
			if act and type(act) == "table" and act.GENERIC then return act.GENERIC end
		end
	end
	-- 3. 烹饪标签名（蛋度、肉度等）优先级最低：仅当不是 prefab 时使用
	local t = TXT.TAG_NAMES[tag]
	if t then return t end
	-- 4. 纯回退：英文模式下至少首字母大写
	if LANG == "en" then
		return tag:sub(1,1):upper() .. tag:sub(2)
	end
	return tag
end

WIT_TXT = TXT
