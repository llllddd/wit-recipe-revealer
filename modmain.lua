-- [JEI] What Is This - modmain
-- 入口文件: 全局常量 + 事件注册 + 模块加载

GLOBAL.setmetatable(env, { __index = function(_, k) return GLOBAL.rawget(GLOBAL, k) end })

-- 模块依赖
GLOBAL.Widget = require("widgets/widget")
GLOBAL.Image = require("widgets/image")
GLOBAL.Text = require("widgets/text")
GLOBAL.TextButton = require("widgets/textbutton")
GLOBAL.ImageButton = require("widgets/imagebutton")

Widget = GLOBAL.Widget
Image = GLOBAL.Image
Text = GLOBAL.Text
TextButton = GLOBAL.TextButton
ImageButton = GLOBAL.ImageButton

-- ============================
-- 全局常量 (WIT_ 前缀避免全局污染)
-- 注意：WIT_KEYS 在 wit_core.lua 中定义（支持运行时重绑定）
-- WIT_COOKING_ALIASES / WIT_INGREDIENT_PREFAB_MAP → wit_core.lua
-- WIT_PAGE_SIZE → wit_ui.lua

-- ============================
-- 数据层状态
-- ============================
WIT = {}
WIT.by_product = {}
WIT.by_material = {}
WIT.cook_foods = {}
WIT.cook_by_ingredient = {}
WIT.ingredient_tags = {}
WIT_data_built = false

-- ============================
-- UI 层状态
-- ============================
WIT_POPUP = nil
WIT_NAME = nil
WIT_MODE = nil
WIT_CUR_CAT = nil
WIT_PAGE = 1
WIT_AVAIL_CATS = {}
WIT_CONTENT = nil
WIT_TAB_BTNS = {}
WIT_PG_TEXT = nil
WIT_PG_PREV = nil
WIT_PG_NEXT = nil
WIT_OPEN_COOKPOT = nil
WIT_HOVER_INFO = true  -- 可在配置中关闭，wit_ui.lua 读取

-- ============================
-- 纯客户端实体拦截
-- ============================
WIT_SPAWNING_ITEM = false
AddGlobalClassPostConstruct("entityscript", "EntityScript", function(self)
    local oldRegisterComponentActions = self.RegisterComponentActions
    if oldRegisterComponentActions ~= nil then
        self.RegisterComponentActions = function(self, name)
            if not WIT_SPAWNING_ITEM then
                return oldRegisterComponentActions(self, name)
            end
        end
    end
end)

-- ============================
-- 加载子模块 (顺序: 国际化 → 数据层 → 表现层)
-- ============================
modimport("scripts/wit_lang")
modimport("scripts/wit_core")
modimport("scripts/wit_ui")

-- 读取悬浮详情配置（wit_ui 加载后才能覆盖默认值）
WIT_HOVER_INFO = GetModConfigData("SHOW_HOVER_INFO")

-- 注册全局按键分发器（两个模块加载完后 WIT_DISPATCH_R/U 才可用）
TheInput:AddKeyHandler(function(key, down)
    if not down then return end
    -- 重绑定模式：捕获按键后更新UI
    if WIT_REBINDING then
        CompleteRebinding(key)
        return
    end
    if key == WIT_KEYS.R then
        WIT_DISPATCH_R()
    elseif key == WIT_KEYS.U then
        WIT_DISPATCH_U()
    end
end)

-- ============================
-- 初始化事件
-- ============================
AddPlayerPostInit(function(inst)
    local function wit_refresh()
        WIT_OPEN_COOKPOT = GetOpenCookPot()
        BuildCookContext()
        if WIT_POPUP ~= nil and WIT_CONTENT ~= nil and WIT_CUR_CAT ~= nil then
            SelectCategory(WIT_CUR_CAT, false)
        end
    end
    inst:ListenForEvent("refreshcrafting", wit_refresh)
    inst:ListenForEvent("refreshinventory", wit_refresh)
    inst:ListenForEvent("opencontainer", wit_refresh)
    inst:ListenForEvent("closecontainer", wit_refresh)
    inst:DoTaskInTime(0, wit_refresh)
end)

-- 合成菜单联动
AddClassPostConstruct("widgets/redux/craftingmenu_hud", function(self)
    local orig_open = self.Open
    self.Open = function(s, ...)
        local ret = orig_open(s, ...)
        if WIT_POPUP ~= nil then
            WIT_POPUP:MoveTo(WIT_POPUP:GetPosition(), Vector3(881, 35, 0), 0.25)
        end
        return ret
    end
    local orig_close = self.Close
    self.Close = function(s, ...)
        local ret = orig_close(s, ...)
        if WIT_POPUP ~= nil then
            WIT_POPUP:MoveTo(WIT_POPUP:GetPosition(), Vector3(405, 35, 0), 0.25)
        end
        return ret
    end
end)
