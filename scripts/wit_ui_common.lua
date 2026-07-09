-- wit_ui_common: UI 状态、悬浮目标、弹窗关闭与暂停控制

-- ============================
-- 通用辅助函数
-- ============================

-- 每页最多展示的卡片数量。
WIT_PAGE_SIZE = 3

local WIT_UI_PAUSED_WORLD = false

-- 导航跳转期间锁住历史写入；modmain 已初始化，这里兜底兼容热加载。
WIT_NAV_LOCK = WIT_NAV_LOCK or false

-- 获取鼠标当前悬浮的库存/图鉴物品。
function GetHoverItem()
    local hud_ent = TheInput:GetHUDEntityUnderMouse()
    if hud_ent == nil then return nil end

    -- 普通库存格通常把 item 放在父控件上；官方图鉴的滚动格则把
    -- 当前条目放在更上层 cell 的 data 中。因此向上遍历控件树，
    -- 同时兼容两种结构。
    local widget = hud_ent.widget
    local depth = 0
    while widget ~= nil and depth < 8 do
        if widget.item ~= nil then
            return widget.item
        end
        if type(widget.data) == "table" and type(widget.data.prefab) == "string" then
            return { prefab = widget.data.prefab }
        end
        widget = widget.parent
        depth = depth + 1
    end
    return nil
end

-- 查找当前前端栈里打开的图鉴界面实例。
function GetActiveScrapbookScreen()
    if TheFrontEnd == nil or TheFrontEnd.GetActiveScreen == nil then return nil end
    local screen = TheFrontEnd:GetActiveScreen()
    if screen ~= nil and screen.name == "ScrapbookScreen" then
        return screen
    end
    return nil
end

-- 当鼠标位于图鉴详情页而不是右侧列表项上时，使用当前已经打开的条目。
-- 从图鉴详情页读取当前选中的 prefab。
function GetScrapbookSelectedItem()
    local screen = GetActiveScrapbookScreen()
    if screen == nil then return nil end

    local entry = screen.details and screen.details.entry
    if type(entry) ~= "string" then return nil end

    local data = screen.GetData and screen:GetData(entry) or nil
    local prefab = data and data.prefab or entry
    if type(prefab) ~= "string" or prefab == "" then return nil end

    return { prefab = prefab }
end

-- 获取鼠标当前指向的游戏世界实体
-- 获取鼠标当前指向的世界实体实际获取的是name。
function GetWorldHoveredItem()
    if TheInput == nil
        or TheInput.GetWorldEntityUnderMouse == nil then
        return nil
    end

    local inst = TheInput:GetWorldEntityUnderMouse()

    if inst == nil then
        return nil
    end

    local prefab = inst.prefab

    if type(prefab) ~= "string" or prefab == "" then
        return nil
    end

    return {
        prefab = prefab,
        inst = inst,
    }
end

-- 判断打开 WIT 弹窗时是否应该自动暂停单人本地世界。
local function _ShouldPauseWorldForPopup()
    -- DST API：GetModConfigData 读取 Mod 配置，AUTO_PAUSE_UI 控制是否自动暂停。
    if not GetModConfigData("AUTO_PAUSE_UI") then
        return false
    end
    if TheNet == nil or not TheNet.GetServerIsClientHosted or not TheNet:GetServerIsClientHosted() then
        return false
    end
    if AllPlayers == nil or #AllPlayers ~= 1 then
        return false
    end
    return true
end

-- 在允许的本地单人场景中为弹窗暂停世界。
function WIT_PauseWorldForPopup()
    if WIT_UI_PAUSED_WORLD or not _ShouldPauseWorldForPopup() then
        return
    end
    if TheNet ~= nil and TheNet:IsServerPaused(true) then
        return
    end
    SetServerPaused(true)
    WIT_UI_PAUSED_WORLD = true
end

-- 关闭弹窗时恢复由 WIT 暂停的世界。
function WIT_ResumeWorldForPopup()
    if not WIT_UI_PAUSED_WORLD then
        return
    end
    WIT_UI_PAUSED_WORLD = false
    if TheNet ~= nil and TheNet:IsServerPaused(true) then
        SetServerPaused(false)
    end
end

-- 关闭当前 WIT 弹窗并清理 UI 状态。
function ClosePopup()
    -- 保存当前条目供导航历史使用（CreatePopup 会用此值入栈）
    WIT_PrevHistory = (not WIT_NAV_LOCK and WIT_NAME ~= nil) and { prefab = WIT_NAME, mode = WIT_MODE, cat = WIT_CUR_CAT } or nil
    if WIT_POPUP ~= nil then WIT_POPUP:Kill(); WIT_POPUP = nil end
    WIT_expanded_sources = {}  -- 关UI时重置展开
    WIT_NAME = nil; WIT_MODE = nil; WIT_CUR_CAT = nil; WIT_PAGE = 1
    WIT_AVAIL_CATS = {}; WIT_CONTENT = nil; WIT_TAB_BTNS = {}
    WIT_PG_TEXT = nil; WIT_PG_PREV = nil; WIT_PG_NEXT = nil
    WIT_OPEN_COOKPOT = nil; WIT_COOK_CONTEXT = nil
end

-- 关闭弹窗、恢复世界暂停状态并清空导航历史。
function ClosePopupAndResume()
    WIT_ResumeWorldForPopup()
    WIT_BACK_STACK = {}; WIT_FORWARD_STACK = {}; WIT_PrevHistory = nil
    ClosePopup()
end
