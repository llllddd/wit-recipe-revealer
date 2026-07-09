-- wit_ui_input: 导航历史与 R/U 键分发
local function WIT_DebugPrintItem(label, item)
    if type(item) ~= "table" then
        print("[WIT]", label, tostring(item))
        return
    end

    local parts = {}
    for key, value in pairs(item) do
        table.insert(parts, tostring(key) .. "=" .. tostring(value))
    end
    print("[WIT]", label, "{" .. table.concat(parts, ", ") .. "}")
end
-- ============================
-- 导航历史：前进/后退
-- 在前进/后退历史栈之间切换弹窗条目。
local function _NavGo(target_stack, source_stack)
    if #target_stack == 0 or WIT_POPUP == nil then
        return
    end
    -- 当前条目压入来源栈
    if WIT_NAME ~= nil then
        table.insert(source_stack, { prefab = WIT_NAME, mode = WIT_MODE, cat = WIT_CUR_CAT })
    end
    local entry = table.remove(target_stack)
    if entry == nil then
        return
    end
    BuildIndexes()
    WIT_NAV_LOCK = true
    ClosePopup()
    WIT_NAV_LOCK = false
    CreatePopup(entry.prefab, entry.mode, entry.cat)
end

-- 导航到上一个 WIT 弹窗条目。
function WIT_NAV_BACK()
    _NavGo(WIT_BACK_STACK, WIT_FORWARD_STACK)
end

-- 导航到下一个 WIT 弹窗条目。
function WIT_NAV_FORWARD()
    _NavGo(WIT_FORWARD_STACK, WIT_BACK_STACK)
end

-- ============================
-- 键盘输入处理 (from wit_input.lua)
-- ============================
-- 注意：全局按键分发器在 modmain.lua 中注册，
-- 调用 WIT_DISPATCH_R / WIT_DISPATCH_U 进行转发。

-- 处理 R 键：以来源优先顺序打开当前目标。
function WIT_DISPATCH_R()
    local ok, e = pcall(function()
        if ThePlayer == nil then return end
        if TheFrontEnd and TheFrontEnd.textProcessorWidget then return end
        if ThePlayer.components.playercontroller ~= nil and ThePlayer.components.playercontroller.placer ~= nil then return end
        BuildIndexes()
        local item = GetHoverItem()
        -- 合成菜单详情面板悬浮材料/产物图标时按 R 键也可触发
        if item == nil and WIT_POPUP == nil and WIT_HOVERED_DETAIL_PREFAB then
            item = { prefab = WIT_HOVERED_DETAIL_PREFAB }
        end
        -- 图鉴面板按键也触发
        if item == nil then
            item = GetScrapbookSelectedItem()
        end
        -- 鼠标指向游戏世界实体时触发,图鉴打开时不读取被图鉴遮挡的世界实体
        if item == nil and GetActiveScrapbookScreen() == nil then
            item = GetWorldHoveredItem()
        end

        if item == nil then
            if WIT_POPUP ~= nil then ClosePopupAndResume() end
            return
        end
        WIT_DebugPrintItem("item_nme:", item)

        local name = item.prefab
        if type(name) ~= "string" then return end
        
        if WIT_POPUP ~= nil then
            -- 同一个物品由 R 打开的弹窗，再按 R 直接关闭
            -- 不受当前所处标签影响
            if WIT_NAME == name and WIT_MODE == "SOURCE" then
                ClosePopupAndResume()
                return
            end

            ClosePopup()
        end
        CreatePopup(name, "SOURCE")
    end)
    if not ok then print("[WIT] R:", e) end
end

-- 处理 U 键：以用途优先顺序打开当前目标。
function WIT_DISPATCH_U()
    local ok, e = pcall(function()
        if ThePlayer == nil then return end
        if TheFrontEnd and TheFrontEnd.textProcessorWidget then return end
        BuildIndexes()
        local item = GetHoverItem()
        -- 合成菜单详情面板悬浮材料/产物图标时按 U 键也可触发
        if item == nil and WIT_POPUP == nil and WIT_HOVERED_DETAIL_PREFAB then
            item = { prefab = WIT_HOVERED_DETAIL_PREFAB }
        end
        -- 图鉴面板按键也触发
        if item == nil then
            item = GetScrapbookSelectedItem()
        end
        -- 鼠标指向游戏世界实体时触发
        if item == nil and GetActiveScrapbookScreen() == nil then
            item = GetWorldHoveredItem()
        end
        if item == nil then
            if WIT_POPUP ~= nil then ClosePopupAndResume() end
            return
        end
        local name = item.prefab
        if type(name) ~= "string" then return end
        if WIT_POPUP ~= nil then
            -- 同一个物品由 U 打开的弹窗，再按 U 直接关闭
            -- 不受当前所处标签影响
            if WIT_NAME == name and WIT_MODE == "USE" then
                ClosePopupAndResume()
                return
            end
            ClosePopup()
        end
        CreatePopup(name, "USE")
    end)
    if not ok then print("[WIT] U:", e) end
end
