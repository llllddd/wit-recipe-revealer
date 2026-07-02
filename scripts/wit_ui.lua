-- wit_ui: 表现层 - 所有与 UI 渲染/交互相关的逻辑
--
-- 职责范围:
--   - 弹窗创建 + 分页 + 分类切换
--   - 物品图标槽位 + 箭头 + 卡片渲染
--   - 物品百科信息页 (Visual UI, 图鉴风格)
--   - 排序 + 跳转制作
--   - 键盘输入处理 + 弹窗关闭
--
-- 不包含任何游戏数据逻辑（数据层在 wit_core.lua）。
-- 所有函数在此文件中定义为全局，modmain.lua 直接加载。

-- ============================
-- 弹窗状态 (从 modmain.lua 移过来的 UI 专用变量)
-- ============================
--  (WIT_POPUP, WIT_NAME, WIT_MODE, WIT_CUR_CAT, WIT_PAGE,
--  WIT_AVAIL_CATS, WIT_CONTENT, WIT_TAB_BTNS, WIT_PG_TEXT,
--  WIT_PG_PREV, WIT_PG_NEXT 在 modmain.lua 中声明)

-- UIAnim 动画控件（官方图鉴详情页用于实体 3D 模型渲染）
local UIAnim = GLOBAL.require("widgets/uianim")

-- ============================
-- 图标图集解析（提取为全局，供悬浮面板和 RenderItemInfo 共用）
-- ============================

-- 图鉴数据缓存：完整 entry（含 tex/build/bank/anim/type）
local _scrapbook_entry_map = nil
local function _GetScrapbookEntry(prefab)
    if _scrapbook_entry_map == nil then
        _scrapbook_entry_map = {}
        local ok, data = pcall(GLOBAL.require, "screens/redux/scrapbookdata")
        if ok and type(data) == "table" then
            for _, entry in pairs(data) do
                if type(entry) == "table" and entry.prefab then
                    _scrapbook_entry_map[entry.prefab] = entry
                end
            end
        end
    end
    return _scrapbook_entry_map[prefab]
end

-- 图鉴 tex 名查询（兼容遗留调用）
local function _GetScrapbookTex(prefab)
    local entry = _GetScrapbookEntry(prefab)
    return entry and entry.tex or nil
end

-- 图标图集解析（用于物品/战利品图集查找）
function ResolveEntityIconAtlas(name)
    local entry = _GetScrapbookEntry(name)
    if entry and entry.tex then
        local a = GLOBAL.GetScrapbookIconAtlas and GLOBAL.GetScrapbookIconAtlas(entry.tex)
        if a then return a, entry.tex end
        local ia = GLOBAL.GetInventoryItemAtlas(entry.tex)
        if ia then return ia, entry.tex end
    end
    return nil, nil
end

-- 创建实体来源图标控件
-- 实体 → UIAnim() 动态渲染 3D 模型（无框，与图鉴详情页一致）
-- 物品 → Image 库存图集（纯图标无框）
-- 返回带有 SetTooltip/OnMouseButton 支持的 widget
function CreateEntityIconWidget(parent, prefab, size, pos_x, pos_y)
    local entry = _GetScrapbookEntry(prefab)
    if entry == nil then return nil end

    -- ImageButton 作为交互基础（tooltip + click）
    local btn = parent:AddChild(ImageButton("images/hud.xml", "inv_slot.tex"))
    if not btn then return nil end
    btn:SetPosition(pos_x, pos_y)
    btn:ForceImageSize(size, size)
    btn.image:SetTint(0, 0, 0, 0)  -- 透明背景

    -- 物品/食物 → 库存图集 Image（纯图标无框）
    if entry.type == "item" or entry.type == "food" then
        if entry.tex then
            local atlas = GLOBAL.GetInventoryItemAtlas(entry.tex)
            if atlas then
                btn.image:SetTint(1, 1, 1, 1)
                btn:SetTextures(atlas, entry.tex)
            end
        end
        return btn
    end

    -- 实体 → UIAnim（3D 模型动态渲染，完全无框）
    if entry.build and entry.bank then
        local anim = btn:AddChild(UIAnim())
        if anim then
            -- 默认兜底比例（巨兽 1.25x）
            anim:SetScale(entry.type == "giant" and 0.1 or 0.08)
            anim:SetPosition(0, 0)
            pcall(function()
                local s = anim:GetAnimState()
                if s == nil then return end
                s:SetBuild(entry.build)
                s:SetBank(entry.bank)
                if entry.anim and #entry.anim > 0 then
                    s:SetPercent(entry.anim, 0.5)
                end
                -- 官方图鉴通用隐藏（防多余符号/错误渲染，如晾肉架的红色残留）
                s:Hide("snow")
                s:Hide("mouseover")
                if entry.hide then
                    for _, h in ipairs(entry.hide) do s:Hide(h) end
                end
                if entry.hidesymbol then
                    for _, h in ipairs(entry.hidesymbol) do s:HideSymbol(h) end
                end
                -- 用 VisualBB 计算等比缩放，使所有实体视觉大小统一
                local x1, y1, x2, y2 = s:GetVisualBB()
                if x1 and x2 and y1 and y2 then
                    local aw = x2 - x1
                    local ay = y2 - y1
                    if aw > 0 and ay > 0 then
                        local TARGET = size
                        local SCALE = math.min(TARGET * 1.4 / aw, TARGET * 1.4 / ay)
                        if entry.type == "giant" then SCALE = SCALE * 1.25 end
                        SCALE = math.max(0.04, math.min(0.6, SCALE))
                        anim:SetScale(SCALE)
                    end
                end
            end)
            anim:SetClickable(false)
        end
        return btn
    end

    -- 兜底：图鉴图集（极少数无 build/bank 的实体）
    if entry.tex then
        local atlas = GLOBAL.GetScrapbookIconAtlas and GLOBAL.GetScrapbookIconAtlas(entry.tex)
        if not atlas then atlas = GLOBAL.GetInventoryItemAtlas(entry.tex) end
        if atlas then
            btn.image:SetTint(1, 1, 1, 1)
            btn:SetTextures(atlas, entry.tex)
        end
    end
    return btn
end

function ResolveIconAtlas(icon)
    local function try_one(name)
        if GLOBAL.GetScrapbookIconAtlas then
            local a = GLOBAL.GetScrapbookIconAtlas(name)
            if a then return a end
        end
        local atlases = {"images/scrapbook_icons1.xml", "images/scrapbook_icons2.xml", "images/scrapbook_icons3.xml"}
        for _, a in ipairs(atlases) do
            if GLOBAL.TheSim:AtlasContains(a, name) then return a end
        end
        local ia = GLOBAL.GetInventoryItemAtlas(name)
        if ia then return ia end
        return nil
    end
    local atlas = try_one(icon)
    if atlas then return atlas end
    local base = icon:match("^(.+)%.tex$")
    if base then
        atlas = try_one(base)
        if atlas then return atlas end
    end
    return nil
end

-- ============================
-- 通用辅助函数
-- ============================

WIT_PAGE_SIZE = 3
local WIT_UI_PAUSED_WORLD = false
local WIT_NAV_LOCK = false  -- 前进/后退导航时闭锁 ClosePopup 的历史记录

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

local function GetActiveScrapbookScreen()
    if TheFrontEnd == nil or TheFrontEnd.GetActiveScreen == nil then return nil end
    local screen = TheFrontEnd:GetActiveScreen()
    if screen ~= nil and screen.name == "ScrapbookScreen" then
        return screen
    end
    return nil
end

-- 当鼠标位于图鉴详情页而不是右侧列表项上时，使用当前已经打开的条目。
local function GetScrapbookSelectedItem()
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
local function GetWorldHoveredItem()
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

local function _ShouldPauseWorldForPopup()
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

local function _PauseWorldForPopup()
    if WIT_UI_PAUSED_WORLD or not _ShouldPauseWorldForPopup() then
        return
    end
    if TheNet ~= nil and TheNet:IsServerPaused(true) then
        return
    end
    SetServerPaused(true)
    WIT_UI_PAUSED_WORLD = true
end

local function _ResumeWorldForPopup()
    if not WIT_UI_PAUSED_WORLD then
        return
    end
    WIT_UI_PAUSED_WORLD = false
    if TheNet ~= nil and TheNet:IsServerPaused(true) then
        SetServerPaused(false)
    end
end

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

function ClosePopupAndResume()
    _ResumeWorldForPopup()
    WIT_BACK_STACK = {}; WIT_FORWARD_STACK = {}; WIT_PrevHistory = nil
    ClosePopup()
end

-- ============================
-- 排序 + 跳转 (from wit_sort.lua)
-- ============================

-- 查找配方所属的分类标签
local function _FindRecipeFilter(recipe_name)
    if not CRAFTING_FILTERS then return nil end
    for fname, filter in pairs(CRAFTING_FILTERS) do
        if type(filter) == "table" and type(filter.recipes) == "table" then
            for _, rname in ipairs(filter.recipes) do
                if rname == recipe_name then return fname end
            end
        end
    end
    return nil
end

function GetRecipeBuildState(recipe_name)
    if ThePlayer == nil or ThePlayer.HUD == nil then return "unknown" end
    local cm = ThePlayer.HUD.controls and ThePlayer.HUD.controls.craftingmenu and ThePlayer.HUD.controls.craftingmenu.craftingmenu
    if cm == nil or cm.crafting_hud == nil then return "unknown" end
    local rd = cm.crafting_hud.valid_recipes[recipe_name]
    if rd and rd.meta then return rd.meta.build_state end
    return "unknown"
end

function SortRecipesByBuildable(recipes)
    local buildable, partial, unbuildable = {}, {}, {}
    for _, r in ipairs(recipes) do
        local s = GetRecipeBuildState(r.name)
        if s == "buffered" or s == "has_ingredients" or s == "freecrafting" then
            table.insert(buildable, r)
        elseif s == "prototype" then
            table.insert(partial, r)
        else
            table.insert(unbuildable, r)
        end
    end
    -- 组内按背包材料匹配数排序
    local bp_items = GetPlayerIngredientList() or {}
    local function match_count(r)
        if r and r.ingredients then
            local avail = {}
            for _, v in ipairs(bp_items) do
                local name = WIT_COOKING_ALIASES[v] or v
                avail[name] = (avail[name] or 0) + 1
            end
            local cnt = 0
            for _, ing in ipairs(r.ingredients) do
                if avail[ing.type] and avail[ing.type] > 0 then
                    cnt = cnt + 1
                    avail[ing.type] = avail[ing.type] - 1
                end
            end
            return cnt
        end
        return 0
    end
    table.sort(buildable, function(a, b) return match_count(a) > match_count(b) end)
    table.sort(partial, function(a, b) return match_count(a) > match_count(b) end)
    table.sort(unbuildable, function(a, b) return match_count(a) > match_count(b) end)
    local out = {}
    for _, r in ipairs(buildable) do table.insert(out, r) end
    for _, r in ipairs(partial) do table.insert(out, r) end
    for _, r in ipairs(unbuildable) do table.insert(out, r) end
    return out
end

function SortCookingByAvailable(recipes)
    if #recipes == 0 then return recipes end
    local prefablist = GetPlayerIngredientList()
    if prefablist == nil or #prefablist == 0 then
        table.sort(recipes, function(a, b)
            -- 潮湿黏糊（兜底失败品）始终排最末
            if a.name == "wetgoop" then return false end
            if b.name == "wetgoop" then return true end
            return (a.priority or 0) > (b.priority or 0)
        end)
        return recipes
    end
    local cooking = GLOBAL.require("cooking")
    local prefabs, tags = {}, {}
    for _, v in ipairs(prefablist) do
        local name = WIT_COOKING_ALIASES[v] or v
        prefabs[name] = (prefabs[name] or 0) + 1
        local data = (cooking.ingredients or {})[name]
        if data ~= nil then
            for kk, vv in pairs(data.tags) do
                tags[kk] = (tags[kk] or 0) + vv
            end
        end
    end
    local ingdata = { tags = tags, names = prefabs }
    local matched, unmatched = {}, {}
    for _, r in ipairs(recipes) do
        local match_count = 0
        if r.card_def and r.card_def.ingredients then
            for _, ci in ipairs(r.card_def.ingredients) do
                local name = WIT_COOKING_ALIASES[ci[1]] or ci[1]
                local has_item = prefabs[name] or 0
                for _ = 1, ci[2] do
                    if has_item > 0 then
                        match_count = match_count + 1
                        has_item = has_item - 1
                    end
                end
            end
        end
        if r.test and r.test("cookpot", ingdata.names, ingdata.tags) then
            r._cook_match = match_count; r._cook_pass = true
            table.insert(matched, r)
        else
            r._cook_match = match_count; r._cook_pass = false
            table.insert(unmatched, r)
        end
    end
    table.sort(matched, function(a, b)
        if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
        return (a._cook_match or 0) > (b._cook_match or 0)
    end)
    table.sort(unmatched, function(a, b)
        if (a._cook_match or 0) ~= (b._cook_match or 0) then return (a._cook_match or 0) > (b._cook_match or 0) end
        return (a.priority or 0) > (b.priority or 0)
    end)
    local out = {}
    for _, r in ipairs(matched) do table.insert(out, r) end
    for _, r in ipairs(unmatched) do table.insert(out, r) end
    return out
end

function JumpToCraft(recipe)
    ClosePopup()
    if ThePlayer == nil or ThePlayer.HUD == nil then return end

    local hud = ThePlayer.HUD
    local menu = hud.controls and hud.controls.craftingmenu
    if menu and menu.Open then
        -- Redux crafting menu (controls.craftingmenu IS CraftingMenuHUD)
        menu:Open(false)
        -- Get last used skin for this recipe
        local skin = Profile and Profile:GetLastUsedSkinForItem(recipe.name)
        menu:PopulateRecipeDetailPanel(recipe.name, skin)
        -- Scroll the grid to this recipe + switch to its own filter tab
        local w = menu.craftingmenu  -- CraftingMenuWidget
        local recipe_data = menu.valid_recipes and menu.valid_recipes[recipe.name]
        if recipe_data and w and w.recipe_grid then
            local filter = _FindRecipeFilter(recipe.name) or CRAFTING_FILTERS.EVERYTHING.name
            if w.SelectFilter then
                w:SelectFilter(filter)
            end
            local idx = w.recipe_grid:FindDataIndex(recipe_data)
            if idx then
                w.recipe_grid:ScrollToDataIndex(idx)
            end
        end
        return
    end

    -- Fallback: classic crafting menu
    hud:OpenCrafting()
    local cm = hud.controls and hud.controls.craftingmenu and hud.controls.craftingmenu.craftingmenu
    if cm == nil then return end
    cm:SelectFilter(CRAFTING_FILTERS.EVERYTHING.name)
    local rd = cm.crafting_hud.valid_recipes[recipe.name]
    if rd == nil then rd = { recipe = recipe, meta = { build_state = "prototype", can_build = false } } end
    cm:PopulateRecipeDetailPanel(rd, nil)
end

-- ============================
-- 物品图标 + 箭头 (from wit_slot.lua)
-- ============================

function MakeSlot(parent, prefab, x, y, need_amount, highlight, slot_size, icon_size, _, show_count)
    if parent == nil then return end
    slot_size = slot_size or 54
    icon_size = icon_size or 54
    if show_count == nil then show_count = true end

    local disp_prefab = prefab
    if prefab and WIT_INGREDIENT_PREFAB_MAP then
        disp_prefab = WIT_INGREDIENT_PREFAB_MAP[prefab] or prefab
    end

    local has_enough = true
    local on_hand = 0
    if need_amount ~= nil and ThePlayer ~= nil and ThePlayer.replica ~= nil then
        local inv = ThePlayer.replica.inventory
        if inv ~= nil then
            local ok, cnt = inv:Has(disp_prefab, need_amount, true)
            has_enough = ok
            on_hand = cnt or 0
        end
    end

    local bg_tex = (need_amount ~= nil and not has_enough) and "resource_needed.tex" or "inv_slot.tex"
    local slot = parent:AddChild(ImageButton("images/hud.xml", bg_tex))
    if slot == nil then return end
    slot:SetScale(slot_size / 64, slot_size / 64)
    slot:SetPosition(x, y)
    if highlight then slot.image:SetTint(1.2, 1.0, 0.6, 1) end

    if disp_prefab then
        local dispname = CN(disp_prefab) or disp_prefab
        slot:SetTooltip(dispname)
    elseif WIT_TXT and WIT_TXT.FILLER_SLOT then
        slot:SetTooltip(WIT_TXT.FILLER_SLOT_TIP or WIT_TXT.FILLER_SLOT)
        slot.image:SetTint(0.5, 0.5, 0.5, 0.4)
    end

    if disp_prefab then
        local img_name = disp_prefab .. ".tex"
        local atlas = GetInventoryItemAtlas(img_name)
        -- 无库存图标时的回退链（优先用图鉴 tex 名）
        if atlas == nil then
            local entry = _GetScrapbookEntry(disp_prefab)
            local tex_name = entry and entry.tex or img_name
            if GLOBAL.GetScrapbookIconAtlas then
                atlas = GLOBAL.GetScrapbookIconAtlas(tex_name)
            end
            if atlas == nil then
                local ia = GLOBAL.GetInventoryItemAtlas(tex_name)
                if ia then atlas = ia; img_name = tex_name end
            end
        end
        if atlas then
            local icon = slot.image:AddChild(Image(atlas, img_name))
            if icon then icon:SetSize(icon_size, icon_size) end
        else
            -- 无任何图标时显示名称首字母
            local dispname = CN(disp_prefab) or disp_prefab
            local fb = slot.image:AddChild(Text(NEWFONT, icon_size * 0.4))
            if fb then
                fb:SetString(dispname:sub(1, 1):upper())
                fb:SetPosition(0, 0)
                fb:SetColour(0.75, 0.7, 0.55, 1)
                fb:SetHAlign(ANCHOR_MIDDLE)
                fb:SetVAlign(ANCHOR_MIDDLE)
                slot.image:SetTint(0.3, 0.28, 0.22, 0.6)
            end
        end
    end

    if need_amount ~= nil and show_count then
        local t = slot.image:AddChild(Text(NUMBERFONT, 26))
        if t then
            if on_hand > 999 then
                t:SetString(string.format("999+/%d", need_amount))
            else
                t:SetString(string.format("%d/%d", on_hand, need_amount))
            end
            t:SetPosition(5, -31)
            t:SetColour(not has_enough and 1 or 1, not has_enough and 0.6 or 1, not has_enough and 0.6 or 1, 1)
        end
    end

    if disp_prefab ~= nil and ThePlayer ~= nil then
        slot:SetOnClick(function()
            BuildIndexes()
            ClosePopup()
            CreatePopup(disp_prefab, "SOURCE")
        end)
        local orig_oc = slot.OnControl
        slot.OnControl = function(btn, control, down)
            if down and control == CONTROL_SECONDARY then
                BuildIndexes()
                ClosePopup()
                CreatePopup(disp_prefab, "USE")
                return true
            end
            return orig_oc(btn, control, down)
        end
    end

    -- 悬浮信息面板（配置 SHOW_HOVER_INFO 控制）
    if WIT_HOVER_INFO and disp_prefab ~= nil then
        local hover_panel = nil

        local function _BuildHoverPanel(panel)
            local info = GetItemInfo and GetItemInfo(disp_prefab)
            if not info or next(info) == nil then return end

            -- 收集核心数据对（最多 4 个）
            local parts = {}

            if info.edible then
                local hg = info.edible.hunger or 0
                local hl = info.edible.health or 0
                local sn = info.edible.sanity or 0
                if hg ~= 0 then table.insert(parts, { icon = "icon_hunger.tex", text = (hg > 0 and "+" or "") .. tostring(hg) }) end
                if hl ~= 0 then table.insert(parts, { icon = "icon_health.tex", text = (hl > 0 and "+" or "") .. tostring(hl) }) end
                if sn ~= 0 then table.insert(parts, { icon = "icon_sanity.tex", text = (sn > 0 and "+" or "") .. tostring(sn) }) end
            end

            if info.weapon and #parts < 4 then
                local txt = tostring(info.weapon.damage)
                if info.weapon.attackrange and info.weapon.attackrange > 1 then
                    txt = txt .. "/" .. tostring(info.weapon.attackrange)
                end
                table.insert(parts, { icon = "icon_damage.tex", text = txt })
            end

            if info.armor and #parts < 4 then
                local pct = math.floor((info.armor.absorb_percent or 0) * 100) .. "%"
                table.insert(parts, { icon = "icon_armor.tex", text = pct })
                if info.armor.maxcondition and #parts < 4 then
                    table.insert(parts, { icon = "icon_uses.tex", text = tostring(info.armor.maxcondition) })
                end
            end

            if info.tools and #info.tools > 0 and #parts < 4 then
                local t = info.tools[1]
                local txt = (t.action and GLOBAL.STRINGS.ACTIONS and GLOBAL.STRINGS.ACTIONS[t.action.id] and type(GLOBAL.STRINGS.ACTIONS[t.action.id]) == "string" and GLOBAL.STRINGS.ACTIONS[t.action.id]) or tostring(t.action and t.action.id or "?")
                local eff = t.efficiency or 1
                if eff ~= 1 then txt = txt .. "×" .. tostring(eff) end
                table.insert(parts, { icon = "icon_action.tex", text = txt })
            end

            if info.finiteuses and #parts < 4 then
                table.insert(parts, { icon = "icon_uses.tex", text = tostring(info.finiteuses.maxuses) })
            end

            if info.fueled and #parts < 4 then
                local ft = info.fueled.maxfuel or 0
                local txt
                if ft >= 480 then txt = tostring(math.floor(ft / 480)) .. "d" else txt = tostring(math.floor(ft)) .. "s" end
                table.insert(parts, { icon = "icon_fuel.tex", text = txt })
            end

            if #parts == 0 then return end

            -- 渲染：单行水平排列
            local icon_h = 24
            local text_size = 18
            local pad = 6
            local gap = 2          -- 图标与同组文字间距
            local pair_gap = 6     -- 不同数据对之间的间距
            local child_list = {}  -- {widget, width, spacing_after}

            for _, part in ipairs(parts) do
                local atlas = ResolveIconAtlas(part.icon)
                if atlas then
                    local img = panel:AddChild(GLOBAL.Image(atlas, part.icon))
                    img:ScaleToSize(icon_h, icon_h)
                    table.insert(child_list, { img, icon_h, gap })
                end
                local txt = panel:AddChild(GLOBAL.Text(NUMBERFONT, text_size))
                txt:SetString(part.text)
                txt:SetColour(0.9, 0.85, 0.7, 1)
                local tw, _ = txt:GetRegionSize()
                table.insert(child_list, { txt, tw, pair_gap })
            end

            -- 计算总宽度并去掉末尾多余间距
            local total_w = pad * 2
            for _, entry in ipairs(child_list) do total_w = total_w + entry[2] + entry[3] end
            if #child_list > 0 then total_w = total_w - child_list[#child_list][3] end

            -- 定位子元素
            local cx = -total_w / 2 + pad
            for _, entry in ipairs(child_list) do
                entry[1]:SetPosition(cx + entry[2] / 2, 0)
                cx = cx + entry[2] + entry[3]
            end

            -- 半透明背景
            local bg = panel:AddChild(GLOBAL.Image("images/global.xml", "square.tex"))
            bg:SetSize(total_w, icon_h + pad)
            bg:SetTint(0.08, 0.06, 0.04, 0.88)
            bg:MoveToBack()
        end

        local old_gain = slot.OnGainFocus
        slot.OnGainFocus = function(btn)
            if hover_panel == nil and WIT_CONTENT ~= nil then
                hover_panel = WIT_CONTENT:AddChild(GLOBAL.Widget("hp"))
                if hover_panel then
                    local panel_h = 30
                    hover_panel:SetPosition(x, y - slot_size / 2 - 3 - panel_h / 2)
                    hover_panel:MoveToFront()
                    _BuildHoverPanel(hover_panel)
                end
            end
            if old_gain then return old_gain(btn) end
        end

        local old_lose = slot.OnLoseFocus
        slot.OnLoseFocus = function(btn)
            if hover_panel then
                hover_panel:Kill()
                hover_panel = nil
            end
            if old_lose then return old_lose(btn) end
        end
    end

    return slot
end

function MakeArrow(parent, x, y)
    if parent == nil then return end
    local t = parent:AddChild(Text(UIFONT, 40))
    if t then t:SetString("→"); t:SetPosition(x, y); t:SetColour(0.6, 0.55, 0.4, 1) end
end

-- ============================
-- 来源渲染 (SOURCES tab)
-- ============================

function RenderSources()
    if WIT_CONTENT == nil then return end
    WIT_CONTENT:KillAllChildren()

    -- 扫描 WIT.entity_loot，找出包含当前物品的实体
    local matched = {}
    for ename, loots in pairs(WIT.entity_loot or {}) do
        for _, l in ipairs(loots) do
            if l.prefab == WIT_NAME then
                table.insert(matched, { source = ename, loots = loots })
                break
            end
        end
    end

    if #matched == 0 then
        local t = WIT_CONTENT:AddChild(Text(NEWFONT, 24))
        if t then t:SetString(WIT_TXT.SRC_NO_SOURCE); t:SetPosition(0, 10); t:SetColour(0.6, 0.55, 0.4, 1) end
        return
    end

    -- 排序函数：目标物品优先，然后按概率降序
    local function _SortLoots(loots, target)
        local sorted = {}
        local target_item = nil
        for _, l in ipairs(loots) do
            if l.prefab == target then target_item = l else table.insert(sorted, l) end
        end
        table.sort(sorted, function(a, b)
            local ca, cb = a.chance or 1, b.chance or 1
            if ca ~= cb then return ca > cb end
            return (a.prefab or "") < (b.prefab or "")
        end)
        local result = {}
        if target_item then table.insert(result, target_item) end
        for _, v in ipairs(sorted) do table.insert(result, v) end
        return result
    end

    local type_icons = {
        drop   = { tex = "icon_damage.tex", tip = WIT_TXT.SRC_DROP },
        pick   = { tex = "icon_action.tex", tip = WIT_TXT.SRC_PICK },
        chop   = { tex = "icon_uses.tex",   tip = WIT_TXT.SRC_CHOP },
        dig    = { tex = "icon_uses.tex",   tip = WIT_TXT.SRC_DIG },
        hammer = { tex = "icon_uses.tex",   tip = WIT_TXT.SRC_HAMMER },
        mine   = { tex = "icon_uses.tex",   tip = WIT_TXT.SRC_MINE },
        trade  = { tex = "icon_action.tex", tip = WIT_TXT.SRC_TRADE },
        trap   = { tex = "icon_damage.tex", tip = WIT_TXT.SRC_TRAP },
    }

    -- 分页
    local PER_PAGE = 2
    local total = #matched
    local pages = math.max(1, math.ceil(total / PER_PAGE))
    if WIT_PAGE > pages then WIT_PAGE = 1 end
    if WIT_PAGE < 1 then WIT_PAGE = pages end
    if WIT_PG_TEXT then WIT_PG_TEXT:SetString(WIT_PAGE .. " / " .. pages) end

    local start_i = (WIT_PAGE - 1) * PER_PAGE + 1
    local end_i = math.min(start_i + PER_PAGE - 1, total)

    -- 布局常量（与其它页签卡片统一）
    local CARD_H = 130
    local CARD_W = 370
    local SRC_SIZE = 86
    local LOOT_SIZE = 52
    local ITEMS_PER_ROW = 4

    local start_y = 2  -- 与其它页签首张卡片顶部对齐
    for idx = start_i, end_i do
        local entry = matched[idx]
        local sorted = _SortLoots(entry.loots, WIT_NAME)
        local local_i = idx - start_i
        local card_y = -local_i * 140 + start_y

        -- 卡片背景（与其它页签一致）
        local card_bg = WIT_CONTENT:AddChild(Image("images/global.xml", "square.tex"))
        if card_bg then card_bg:SetSize(CARD_W, CARD_H); card_bg:SetTint(0.12, 0.10, 0.08, 0.6); card_bg:SetPosition(0, card_y) end

        -- 来源实体图标（UIAnim 动态渲染，无框）
        local src_widget = CreateEntityIconWidget(WIT_CONTENT, entry.source, SRC_SIZE, -129, card_y - 43)
        if src_widget then
            local en = CN(entry.source) or entry.source
            local clean_name = en:match("^[%u%l]") and en:gsub("_", " "):gsub("(%a)([%w]*)", function(a,b) return a:upper()..b end) or en
            src_widget:SetTooltip(clean_name)
            src_widget.OnMouseButton = function(_, button, down)
                if button == 0 and not down then
                    BuildIndexes(); ClosePopup(); CreatePopup(entry.source, "SOURCE")
                    return true
                end
            end
        else
            -- 彻底无数据时文字回退
            local dispname = CN(entry.source) or entry.source
            local clean_name = dispname:match("^[%u%l]") and dispname:gsub("_", " "):gsub("(%a)([%w]*)", function(a,b) return a:upper()..b end) or dispname
            local ib = WIT_CONTENT:AddChild(ImageButton("images/hud.xml", "inv_slot.tex"))
            if ib then
                ib:SetScale(SRC_SIZE / 64, SRC_SIZE / 64)
                ib:SetPosition(-125, card_y - 45)
                ib.image:SetTint(0.2, 0.18, 0.15, 0.5)
                ib:SetTooltip(clean_name)
                ib.OnMouseButton = function(_, button, down)
                    if button == 0 and not down then
                        BuildIndexes(); ClosePopup(); CreatePopup(entry.source, "SOURCE")
                        return true
                    end
                end
                local fb = ib.image:AddChild(Text(NEWFONT, SRC_SIZE * 0.38))
                if fb then
                    fb:SetString(dispname:sub(1, 1):upper())
                    fb:SetPosition(0, 0)
                    fb:SetColour(0.65, 0.58, 0.45, 1)
                    fb:SetHAlign(ANCHOR_MIDDLE); fb:SetVAlign(ANCHOR_MIDDLE)
                end
            end
        end

        -- 交互类型图标（卡片的战利品区左上角）
        local type_info = entry.loots[1] and entry.loots[1].type or nil
        local type_icon_def = type_info and type_icons[type_info] or nil
        if type_icon_def then
            local ti_atlas = GLOBAL.GetScrapbookIconAtlas and GLOBAL.GetScrapbookIconAtlas(type_icon_def.tex)
            if ti_atlas then
                local ti = WIT_CONTENT:AddChild(Image(ti_atlas, type_icon_def.tex))
                if ti then
                    local icon_sz = 36
                    ti:SetSize(icon_sz, icon_sz)
                    ti:SetPosition(-46, card_y + CARD_H / 2 - 24)
                    if type_icon_def.tip then ti:SetTooltip(type_icon_def.tip) end
                end
            end
        end

        -- 智能战利品文字（×1 隐藏，概率/数量智能显示）
        local function _LootText(loot)
            if loot.chance and loot.chance < 1.0 then
                -- 概率掉落：只有数量>1时显示数量，否则仅显示百分比
                local pct = tostring(math.floor(loot.chance * 100)) .. "%"
                if loot.count and loot.count > 1 then return tostring(loot.count) .. "  " .. pct end
                return pct
            end
            -- 必掉：始终显示数量
            if loot.count then return tostring(loot.count) end
            return nil
        end

        -- 战利品
        local loot_y = card_y + (SRC_SIZE - LOOT_SIZE) / 2 - 18
        local limit = ITEMS_PER_ROW
        WIT_expanded_sources = WIT_expanded_sources or {}
        local expanded = WIT_expanded_sources[entry.source]
        if expanded then limit = #sorted end

        -- 战利品渲染（展开时自动换行，每行最多 5 个）
        local ROW_CAP = 10
        local ROW_GAP = LOOT_SIZE + 28
        local prod_x = -40
        local row_y = loot_y
        local col = 0
        for i, loot in ipairs(sorted) do
            if i > limit then break end
            if expanded and col >= ROW_CAP then
                col = 0; row_y = row_y - ROW_GAP; prod_x = -40
            end
            local hl = (loot.prefab == WIT_NAME)
            MakeSlot(WIT_CONTENT, loot.prefab, prod_x, row_y, nil, hl, LOOT_SIZE, LOOT_SIZE)
            local txt = _LootText(loot)
            if txt then
                local ct = WIT_CONTENT:AddChild(Text(NUMBERFONT, 22))
                if ct then
                    ct:SetString(txt)
                    ct:SetPosition(prod_x, row_y - LOOT_SIZE / 2 - 7)
                    ct:SetColour(0.6, 0.55, 0.4, 1)
                end
            end
            prod_x = prod_x + LOOT_SIZE + 5
            col = col + 1
        end

        -- 展开/折叠按钮（与最后一项同行，左移 4px）
        local overflow = #sorted - ITEMS_PER_ROW
        if overflow > 0 then
            local btn_more = WIT_CONTENT:AddChild(ImageButton("images/crafting_menu.xml", "ingredient_craft.tex"))
            if btn_more then
                local bx = prod_x - 4
                local by = row_y - 14
                if expanded then bx = bx - 14; by = by - 6 end
                btn_more:SetPosition(bx, by)
                btn_more:SetScale(0.35)
                if expanded then btn_more.image:SetRotation(45) end
                btn_more:SetOnClick(function()
                    WIT_expanded_sources[entry.source] = not expanded
                    RenderSources()
                end)
            end
        end
    end
end

-- ============================
-- 卡片渲染 (from wit_render.lua)
-- ============================

function RenderCardCrafting(r, card_y)
    local ings = r.ingredients or {}
    local ing_count = math.min(#ings, 5)
    local start_x = -140
    if r.is_deconstruction_recipe then
        -- 拆解配方：一生多（物品 → 拆解产出物），间距与正常配方一致
        local gap = 48  -- 元素间间距（与正常配方中 ing → arrow 间距一致）
        MakeSlot(WIT_CONTENT, r.product or r.name, start_x, card_y, nil, false)
        MakeArrow(WIT_CONTENT, start_x + gap, card_y)
        for ii = 1, ing_count do
            local ing = ings[ii]
            MakeSlot(WIT_CONTENT, ing.type, start_x + gap * 2 + (ii - 1) * 58, card_y, ing.amount, false)
        end
    else
        -- 正常合成配方：多合一（材料 → 产物）
        for ii = 1, ing_count do
            local ing = ings[ii]
            local hl = (ing.type == WIT_NAME)
            MakeSlot(WIT_CONTENT, ing.type, start_x + (ii - 1) * 58, card_y, ing.amount, hl)
        end
        MakeArrow(WIT_CONTENT, start_x + ing_count * 58 - 10, card_y)
        MakeSlot(WIT_CONTENT, r.product or r.name, start_x + ing_count * 58 + 32, card_y, nil, false)
    end

    -- 制作站/角色/专属标识（产品图标右侧，小图标）
    local extra_icons = {}
    if r.builder_tag then
        -- 角色专属标记：使用角色对应 prototyper 图标或通用标记
        local char_map = { pyromaniac="willow", masterchef="warly", bookbuilder="wickerbottom",
            werehuman="woodie", valkyrie="wigfrid", ghostlyfriend="wendy", plantkin="wormwood",
            clockmaker="wanda", shadowmagic="maxwell", handyperson="winona",
            portableengineer="winona", pebblemaker="walter", pinetreepioneer="walter",
            spiderwhisperer="webber" }
        local char_prefab = char_map[r.builder_tag] or r.builder_tag
        local ca = GetInventoryItemAtlas(char_prefab .. ".tex")
        if ca then table.insert(extra_icons, { atlas = ca, tex = char_prefab .. ".tex", tip = r.builder_tag }) end
    end
    if r.level then
        -- tech_map 格式：{ { level, prefab_or_prefabs }, ... }
        -- prefab_or_prefabs 可以是字符串（单站）或字符串数组（同一 level 可在多站制作）
        -- 兼容规则：DST 中 prototyper 的 techtree 决定了哪些 level 的配方可在该 station 制作；
        -- 同一 level 在多个 station 的 techtree 中都包含时，所有 station 都应同时显示。
        local tech_map = {
            SCIENCE={{1, "researchlab"}, {2, "researchlab2"}},
            MAGIC={
                {1, {"researchlab", "researchlab2"}},  -- 魔 1 本：科学机器和炼金引擎都能做
                {2, "researchlab4"},                   -- 灵子分解器
                {3, "researchlab3"},                   -- 暗影操纵器
            },
            ANCIENT={
                {2, {"ancient_altar_broken", "ancient_altar"}},
                {3, "ancient_altar"},
                {4, "ancient_altar"},
            },
            CELESTIAL={{1, "moon_altar"}, {3, "moon_altar"}},
            SEAFARING={{1, "seafaring_prototyper"}, {2, "seafaring_prototyper"}},
            SCULPTING={{1, "sculptingtable"}, {2, "sculptingtable"}},
            SHADOW={{3, "shadow_forge"}},
            CARTOGRAPHY={{2, "cartographydesk"}},
            ORPHANAGE={{1, "critterlab"}},
            LOST={{1, "turfcraftingstation"}, {2, "carpentry_station"}, {3, "turfcraftingstation"}, {4, "carpentry_station"}},
        }
        -- 必须蓝图解锁的配方（硬编码，跳过制作站显示）
        local bp_blacklist = { deserthat = true }
        if not bp_blacklist[r.name] and not bp_blacklist[r.product] then
            for tech, levels in pairs(r.level) do
                local defs = tech_map[tech]
                if defs then
                    local added = {}
                    for _, pair in ipairs(defs) do
                        if pair[1] == r.level[tech] and r.level[tech] > 0 then
                            -- 将 prefab 统一为数组以便统一处理
                            local prefabs = type(pair[2]) == "table" and pair[2] or { pair[2] }
                            for _, pname in ipairs(prefabs) do
                                if not added[pname] then
                                    added[pname] = true
                                    -- 直连检查 inventoryimages 图集（不依赖 GetInventoryItemAtlas 的回退）
                                    local img_name = pname .. ".tex"
                                    local ta = nil
                                    local inv_atlases = {"images/inventoryimages.xml","images/inventoryimages1.xml","images/inventoryimages2.xml","images/inventoryimages3.xml","images/inventoryimages4.xml"}
                                    for _, a in ipairs(inv_atlases) do
                                        if GLOBAL.TheSim:AtlasContains(a, img_name) then
                                            ta = a
                                            break
                                        end
                                    end
                                    if ta then
                                        local tip = (GLOBAL.STRINGS and GLOBAL.STRINGS.NAMES and GLOBAL.STRINGS.NAMES[string.upper(pname)]) or pname
                                        table.insert(extra_icons, { atlas = ta, tex = img_name, tip = tip, prefab = pname })
                                    else
                                        local tip = (GLOBAL.STRINGS and GLOBAL.STRINGS.NAMES and GLOBAL.STRINGS.NAMES[string.upper(pname)]) or pname
                                        table.insert(extra_icons, { atlas = nil, tex = img_name, tip = tip, prefab = pname })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if r.nounlock then
        -- 站锁配方：nounlock=true 的配方无法原型解锁，需在对应制作站旁制作
        if r.level and next(r.level) then
            -- 为已添加的 station 图标追加"需在制作站旁制作"提示
            for _, icon in ipairs(extra_icons) do
                if icon.prefab == "ancient_altar" or icon.prefab == "ancient_altar_broken"
                    or icon.prefab == "shadow_forge" or icon.prefab == "moon_altar" then
                    icon.tip = icon.tip .. "\n" .. WIT_TXT.NOUNLOCK_STATION
                end
            end
        end
    end
    -- 检测配方是否必须蓝图解锁（硬编码 + nounlock+X_blueprint 兜底）
    local must_bp = false
    local bp_blacklist = { deserthat=true }  -- 少数有科技等级但必须蓝图的配方
    if bp_blacklist[r.name] or bp_blacklist[r.product] then
        must_bp = true
    elseif r.nounlock then
        local bp_check = (r.product or r.name) .. "_blueprint"
        if GLOBAL.PrefabExists and GLOBAL.PrefabExists(bp_check) then
            must_bp = true
        end
    else
        for _, lv in pairs(r.level or {}) do
            if lv >= 10 then must_bp = true; break end
        end
    end
    if must_bp then
        local ba = GLOBAL.GetInventoryItemAtlas("blueprint.tex")
            or (GLOBAL.GetScrapbookIconAtlas and GLOBAL.GetScrapbookIconAtlas("blueprint.tex"))
        if ba then
            local btip = (GLOBAL.STRINGS and GLOBAL.STRINGS.NAMES and GLOBAL.STRINGS.NAMES["BLUEPRINT"]) or "Blueprint"
            table.insert(extra_icons, { atlas = ba, tex = "blueprint.tex", tip = btip })
        end
    end
    if r.is_deconstruction_recipe then
        -- 仅当产物无正常合成配方时显示拆解图标（如恐怖圆盾等 boss 掉落品）
        local prod = r.product or r.name
        local has_normal = false
        if WIT.by_product[prod] then
            for _, pr in ipairs(WIT.by_product[prod]) do
                if not pr.is_deconstruction_recipe then
                    has_normal = true
                    break
                end
            end
        end
        if not has_normal then
            -- 拆解魔杖 3D 模型（无图集可用时渲染）
            table.insert(extra_icons, { atlas = nil, tex = nil, tip = WIT_TXT.SRC_DECONSTRUCT, prefab = "greenstaff" })
        end
    end
    if #extra_icons > 0 then
        local ex = start_x + ing_count * 58 + 68
        for _, ei in ipairs(extra_icons) do
            if ei.atlas then
                local eimg = WIT_CONTENT:AddChild(Image(ei.atlas, ei.tex))
                if eimg then
                    eimg:SetSize(20, 20); eimg:SetPosition(ex, card_y + 30)
                    eimg:SetTooltip(CN(ei.tip) or ei.tip)
                    local prefab = ei.tip
                    eimg.OnMouseButton = function(_, button, down)
                        if not down and button == 0 then
                            BuildIndexes(); ClosePopup(); CreatePopup(prefab, "SOURCE")
                        end
                    end
                end
            else
                -- 手动创建 UIAnim 3D 模型（固定小比例，适合右上角角标）
                local anim = nil
                local entry = ei.prefab and _GetScrapbookEntry(ei.prefab)
                if entry and entry.build and entry.bank then
                    anim = WIT_CONTENT:AddChild(UIAnim())
                    if anim then
                        local s = anim:GetAnimState()
                        if s then
                            s:SetBuild(entry.build)
                            s:SetBank(entry.bank)
                            if entry.anim and #entry.anim > 0 then
                                s:SetPercent(entry.anim, 0.5)
                            end
                            s:Hide("snow"); s:Hide("mouseover")
                        end
                        local sc = ({ ancient_altar=0.03, ancient_altar_broken=0.03, greenstaff=0.1 })[ei.prefab] or 0.03
                        local ox = ({ greenstaff=2 })[ei.prefab] or 0
                        local oy = ({ ancient_altar=1, ancient_altar_broken=1, greenstaff=2 })[ei.prefab] or 0
                        anim:SetScale(sc)
                        anim:SetPosition(ex + ox, card_y + 30 + oy)
                        anim:SetTooltip(CN(ei.tip) or ei.tip)
                        local prefab = ei.tip
                        anim.OnMouseButton = function(_, button, down)
                            if not down and button == 0 then
                                BuildIndexes(); ClosePopup(); CreatePopup(prefab, "SOURCE")
                            end
                        end
                    end
                end
                if not anim then
                    -- 无 scrapbook entry 时的文字兜底（inv_slot + 首字母）
                    local fb = WIT_CONTENT:AddChild(Image("images/hud.xml", "inv_slot.tex"))
                    if fb then
                        fb:SetSize(20, 20); fb:SetPosition(ex, card_y + 30)
                        fb:SetTooltip(CN(ei.tip) or ei.tip)
                        local ftxt = fb:AddChild(Text(NEWFONT, 14))
                        if ftxt then
                            ftxt:SetString((CN(ei.tip) or ei.tip):sub(1, 1):upper())
                            ftxt:SetPosition(0, 0)
                            ftxt:SetColour(0.6, 0.55, 0.4, 1)
                            ftxt:SetHAlign(ANCHOR_MIDDLE)
                            ftxt:SetVAlign(ANCHOR_MIDDLE)
                        end
                        local prefab = ei.tip
                        fb.OnMouseButton = function(_, button, down)
                            if not down and button == 0 then
                                BuildIndexes(); ClosePopup(); CreatePopup(prefab, "SOURCE")
                            end
                        end
                    end
                end
            end
            ex = ex + 24
        end
    end

    if not r.is_deconstruction_recipe then
        local state = GetRecipeBuildState(r.name)
        local can_craft = false
        if state ~= nil and state ~= "unknown" then
            if r.nounlock then
                -- 站锁配方（如远古制作站）：必须在制作站旁才能制作，不能从标准菜单直接做
                can_craft = false
            elseif state == "has_ingredients" or state == "buffered" or state == "freecrafting" then
                can_craft = true
            elseif state == "prototype" then
                -- 材料足够，需在科技站旁原型合成；在站旁时 DST build_state 即为 prototype
                can_craft = true
            end
        end
        local craft_btn = WIT_CONTENT:AddChild(ImageButton("images/crafting_menu.xml", "ingredient_craft.tex", "ingredient_craft.tex"))
        if craft_btn then
            craft_btn:SetPosition(start_x + ing_count * 58 + 32 + 32, card_y - 32)
            craft_btn:SetScale(0.35)
            craft_btn.image:SetTint(can_craft and 1 or 0.5, can_craft and 1 or 0.5, can_craft and 1 or 0.5, 1)
            craft_btn:SetOnClick(function() JumpToCraft(r) end)
        end
    end
end

function RenderCardCooking(r, card_y)
    if not r.card_def or not r.card_def.ingredients then return end

    local pri = WIT_CONTENT:AddChild(Text(NEWFONT, 18))
    if pri then
        pri:SetString(WIT_TXT.PRIORITY .. (r.priority or 0))
        pri:SetPosition(127, card_y + 30)
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

    local view = GetResolvedCookingCard(r, WIT_NAME)
    if not view then
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
        craft_btn.image:SetTint(view.can_auto_cook and 1 or 0.5, view.can_auto_cook and 1 or 0.5, view.can_auto_cook and 1 or 0.5, 1)
        craft_btn:SetOnClick(function()
            if not CanAutoCook(view) then return end
            AutoFillCookPot(view)
        end)
    end
end

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

-- ============================
-- 分类切换 + 配方获取 (from wit_category.lua)
-- ============================

local function _HasDecon(recipes)
    for _, r in ipairs(recipes or {}) do if r.is_deconstruction_recipe then return true end end
    return false
end

local function _HasCraftFrom(name)
    if WIT.by_product[name] == nil then return false end
    for _, r in ipairs(WIT.by_product[name]) do
        if not r.is_deconstruction_recipe then return true end
    end
    return false
end

local function _HasCraftUse(name)
    if WIT.by_material[name] then
        for _, r in ipairs(WIT.by_material[name]) do
            if not r.is_deconstruction_recipe then return true end
        end
    end
    return WIT.by_product[name] and _HasDecon(WIT.by_product[name]) or false
end

local function _HasCraftDeconSource(name)
    if WIT.by_material[name] == nil then return false end
    for _, r in ipairs(WIT.by_material[name]) do
        if r.is_deconstruction_recipe then return true end
    end
    return false
end

local function _HasLootSources(name)
    for _, loots in pairs(WIT.entity_loot or {}) do
        for _, l in ipairs(loots) do
            if l.prefab == name then return true end
        end
    end
    return false
end

function HasData(name, mode)
    if mode == "SOURCE" then
        return _HasCraftFrom(name) or _HasCraftDeconSource(name) or WIT.cook_foods[name] ~= nil or _HasLootSources(name)
    elseif mode == "USE" then
        return _HasCraftUse(name) or (WIT.cook_by_ingredient[name] and #WIT.cook_by_ingredient[name] > 0)
    end
    return _HasCraftFrom(name) or _HasCraftUse(name) or _HasCraftDeconSource(name)
        or WIT.cook_foods[name] ~= nil
        or (WIT.cook_by_ingredient[name] and #WIT.cook_by_ingredient[name] > 0)
        or _HasLootSources(name)
end

function GetCurrentRecipes()
    if WIT_CUR_CAT == "CRAFT_FROM" then
        local recipes = {}
        local src = WIT.by_product[WIT_NAME]
        if src then
            for _, r in ipairs(src) do
                if not r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        local decon = WIT.by_material[WIT_NAME]
        if decon then
            for _, r in ipairs(decon) do
                if r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        return SortRecipesByBuildable(recipes)
    elseif WIT_CUR_CAT == "CRAFT_USE" then
        local recipes = {}
        local src = WIT.by_material[WIT_NAME]
        if src then
            for _, r in ipairs(src) do
                if not r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        local decon = WIT.by_product[WIT_NAME]
        if decon then
            for _, r in ipairs(decon) do
                if r.is_deconstruction_recipe then table.insert(recipes, r) end
            end
        end
        return SortRecipesByBuildable(recipes)
    elseif WIT_CUR_CAT == "COOK_FROM" then
        local recipes = {}
        if WIT.cook_foods[WIT_NAME] then table.insert(recipes, WIT.cook_foods[WIT_NAME]) end
        table.sort(recipes, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
        return SortCookingByAvailable(recipes)
    elseif WIT_CUR_CAT == "COOK_USE" then
        local recipes = {}
        local src = WIT.cook_by_ingredient[WIT_NAME]
        if src then
            for _, r in ipairs(src) do table.insert(recipes, r) end
        end
        table.sort(recipes, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
        return recipes
    end
    return {}
end

function SelectCategory(cat, reset_page)
    WIT_CUR_CAT = cat
    if reset_page then WIT_PAGE = 1 end
    WIT_expanded_sources = {}  -- 切页签/翻页时重置展开

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

    -- INFO 页签隐藏翻页控件
    if WIT_PG_PREV then
        if cat == "INFO" then
            WIT_PG_PREV:Hide(); WIT_PG_NEXT:Hide(); WIT_PG_TEXT:Hide()
        else
            WIT_PG_PREV:Show(); WIT_PG_NEXT:Show(); WIT_PG_TEXT:Show()
        end
    end

    local recipes = GetCurrentRecipes()
    -- 烹饪用途：过滤 + 排序（带 pcall 保护）
    if cat == "COOK_USE" then
        local ctx = WIT_COOK_CONTEXT
        local inv_counts = ctx and ctx.snapshot and ctx.snapshot.counts or {}
        local filtered = {}
        local ok_resolve = pcall(function()
            for _, r in ipairs(recipes) do
                local view = GetResolvedCookingCard(r, WIT_NAME)
                if view then
                    r._cook_view = view
                    table.insert(filtered, r)
                end
            end
        end)
        if not ok_resolve then
            for _, r in ipairs(recipes) do
                if r.card_def and r.card_def.ingredients then
                    local raw = FlattenIngredients(r.card_def.ingredients)
                    r._cook_view = { slots = PadSlots(raw, 4), need_map = BuildNeedMap(r.card_def.ingredients), can_auto_cook = false }
                    table.insert(filtered, r)
                end
            end
        end
        table.sort(filtered, function(a, b)
            local va, vb = a._cook_view, b._cook_view
            local function GetMissingCount(view)
                if not view or not view.slots then return 4 end
                local missing = 0
                for i = 1, 4 do
                    local s = view.slots[i]
                    if s == nil then
                        missing = missing + 1
                    else
                        local need_amt = view.need_map and view.need_map[s] or 1
                        if (inv_counts[s] or 0) < need_amt then missing = missing + 1 end
                    end
                end
                return missing
            end
            local gap_a, gap_b = GetMissingCount(va), GetMissingCount(vb)
            local tier_a = va and va.can_auto_cook and 0 or (gap_a == 0 and 1 or 2)
            local tier_b = vb and vb.can_auto_cook and 0 or (gap_b == 0 and 1 or 2)
            if tier_a ~= tier_b then return tier_a < tier_b end
            if tier_a == 2 and gap_a ~= gap_b then return gap_a < gap_b end
            return (a.priority or 0) > (b.priority or 0)
        end)
        recipes = filtered
    end
    -- 每次切标签都清空并重建内容容器
    if WIT_POPUP and WIT_CONTENT then WIT_CONTENT:Kill(); WIT_CONTENT = nil end
    if WIT_POPUP then
        WIT_CONTENT = WIT_POPUP:AddChild(Widget("c"))
        if WIT_CONTENT then WIT_CONTENT:SetPosition(0, 20) end
    end
    if cat == "CRAFT_FROM" or cat == "CRAFT_USE" then
        RenderCards(recipes, 85, 90, RenderCardCrafting)
    elseif cat == "COOK_FROM" or cat == "COOK_USE" then
        RenderCards(recipes, 85, 90, RenderCardCooking)
    elseif cat == "SOURCES" then
        RenderSources()
    elseif cat == "INFO" then
        RenderItemInfo()
    end
end

-- ============================
-- 弹窗创建 (from wit_popup.lua)
-- ============================

function CreatePopup(name, mode, preferred_cat)
    BuildCookContext()
    -- 导航历史：上一次 ClosePopup 留下的条目入后退栈
    if WIT_PrevHistory then
        table.insert(WIT_BACK_STACK, WIT_PrevHistory)
        WIT_FORWARD_STACK = {}
    end
    WIT_PrevHistory = nil
    WIT_NAME = name; WIT_MODE = mode or "ITEM"; WIT_PAGE = 1
    WIT_HOVER_INFO = GetModConfigData("SHOW_HOVER_INFO")

    local avail_cats = {}
    if _HasLootSources(name) then table.insert(avail_cats, "SOURCES") end
    if _HasCraftFrom(name) or _HasCraftDeconSource(name) then table.insert(avail_cats, "CRAFT_FROM") end
    if WIT.cook_foods[name] then table.insert(avail_cats, "COOK_FROM") end
    if _HasCraftUse(name) then table.insert(avail_cats, "CRAFT_USE") end
    if WIT.cook_by_ingredient[name] and #WIT.cook_by_ingredient[name] > 0 then table.insert(avail_cats, "COOK_USE") end
    table.insert(avail_cats, "INFO")
    if #avail_cats == 0 then return end
    WIT_AVAIL_CATS = avail_cats

    local popup_parent
    local scrapbook_screen = GetActiveScrapbookScreen()
    if scrapbook_screen ~= nil then
        -- 图鉴是覆盖在玩家 HUD 上方的独立 Screen。将弹窗挂到该 Screen
        -- 的左中锚点根节点，既保证可见，也保留原有 popup_x 坐标语义。
        popup_parent = scrapbook_screen._wit_popup_root
        if popup_parent == nil then
            popup_parent = scrapbook_screen:AddChild(Widget("WITPopupScreenRoot"))
            popup_parent:SetScaleMode(SCALEMODE_PROPORTIONAL)
            popup_parent:SetHAnchor(ANCHOR_LEFT)
            popup_parent:SetVAnchor(ANCHOR_MIDDLE)
            scrapbook_screen._wit_popup_root = popup_parent
        end

        if not scrapbook_screen._wit_close_wrapped then
            local old_close = scrapbook_screen.Close
            scrapbook_screen.Close = function(screen, ...)
                if WIT_POPUP ~= nil then ClosePopupAndResume() end
                return old_close(screen, ...)
            end
            scrapbook_screen._wit_close_wrapped = true
        end

        popup_parent:MoveToFront()
    else
        popup_parent = ThePlayer.HUD.controls.left_root
        if popup_parent == nil then popup_parent = ThePlayer.HUD.controls end
    end

    WIT_POPUP = popup_parent:AddChild(Widget("WITPopup"))
    if WIT_POPUP == nil then return end

    local crafting_hud = ThePlayer.HUD.controls.craftingmenu
    local is_open = crafting_hud and crafting_hud:IsCraftingOpen()
    local pos_mode = GetModConfigData("POPUP_POSITION") or "auto"
    local popup_x
    if pos_mode == "left" then
        popup_x = 350
    elseif pos_mode == "right" then
        popup_x = 900
    else
        popup_x = is_open and 881 or 405
    end
    WIT_POPUP:SetPosition(popup_x, 35)

    local CRAFTING_ATLAS = resolvefilepath("images/crafting_menu.xml")
    local frame_w = 360; local frame_h = 480

    local fill = WIT_POPUP:AddChild(Image(CRAFTING_ATLAS, "backing.tex"))
    if fill then fill:ScaleToSize(frame_w + 50, frame_h + 18); fill:SetTint(1, 1, 1, 0.5); fill:MoveToBack() end

    local left_side = WIT_POPUP:AddChild(Image(CRAFTING_ATLAS, "side.tex"))
    if left_side then left_side:SetPosition(-frame_w/2 - 29, 1); left_side:ScaleToSize(-26, -(frame_h - 20)) end

    local right_side = WIT_POPUP:AddChild(Image(CRAFTING_ATLAS, "side.tex"))
    if right_side then right_side:SetPosition(frame_w/2 + 29, 1); right_side:ScaleToSize(26, frame_h - 20) end

    local top_edge = WIT_POPUP:AddChild(Image(CRAFTING_ATLAS, "top.tex"))
    if top_edge then top_edge:SetPosition(0, 250); top_edge:ScaleToSize(frame_w + 70, 38) end

    local bottom_edge = WIT_POPUP:AddChild(Image(CRAFTING_ATLAS, "bottom.tex"))
    if bottom_edge then bottom_edge:SetPosition(0, -248); bottom_edge:ScaleToSize(frame_w + 70, 38) end

    local title_y = 196
    local title_bg = WIT_POPUP:AddChild(Image(CRAFTING_ATLAS, "slot_bg.tex"))
    if title_bg then title_bg:SetPosition(-150, title_y); title_bg:SetScale(0.5) end
    -- 标题图标（与内容区 MakeSlot 同款交互：左键→来源 / 右键→用途）
    local icon_atlas = GetInventoryItemAtlas(name .. ".tex")
    local title_slot = WIT_POPUP:AddChild(ImageButton(icon_atlas or CRAFTING_ATLAS, (icon_atlas and name .. ".tex") or "slot_frame.tex"))
     if title_slot then
         title_slot:SetPosition(-150, title_y)
         title_slot:ForceImageSize(48, 48)
         title_slot.image:SetTint(1, 1, 1, 1)
         title_slot:SetTooltip(dispname)
         local cur_name = WIT_NAME
         title_slot:SetOnClick(function()
             BuildIndexes(); ClosePopup(); CreatePopup(cur_name, "SOURCE")
         end)
         local orig_oc = title_slot.OnControl
         title_slot.OnControl = function(btn, control, down)
             if down and control == CONTROL_SECONDARY then
                 BuildIndexes(); ClosePopup(); CreatePopup(cur_name, "USE")
                 return true
             end
             return orig_oc(btn, control, down)
         end
     end

    local dispname = CN(name) or name
    local title_x = 36    -- 右移 40px + 10px = 50px（相对原 -14）
    local title_y = 196    -- 下移 6px（原 202，+Y 向上，所以 202-6=196）
    local title = WIT_POPUP:AddChild(Text(UIFONT, 34))
    if title then
        title:SetString(dispname)
        title:SetPosition(title_x, title_y)
        title:SetHAlign(ANCHOR_LEFT)
        title:SetColour(0.95, 0.88, 0.7, 1)
        title:SetRegionSize(280, 40)
    end

    -- Mod 来源（标题下方，同 x 坐标）
    local mod_src = GetPrefabModName and GetPrefabModName(name)
    if mod_src then
        local src_t = WIT_POPUP:AddChild(Text(NEWFONT, 20))
        if src_t then
            src_t:SetString(WIT_TXT.FMT_MOD_SOURCE:format(mod_src))
            src_t:SetPosition(title_x, title_y - 20)
            src_t:SetHAlign(ANCHOR_LEFT)
            src_t:SetColour(0.45, 0.65, 0.45, 0.9)
            src_t:SetRegionSize(280, 30)
        end
    end

    local sep_top = WIT_POPUP:AddChild(Image("images/global.xml", "square.tex"))
    if sep_top then sep_top:SetSize(364, 1); sep_top:SetPosition(0, 150); sep_top:SetTint(0.3, 0.25, 0.18, 1) end

    -- 右上角按钮的悬浮缩放效果
    local function _AddHoverScale(btn, factor)
        factor = factor or 1.12
        local og = btn.OnGainFocus
        local ol = btn.OnLoseFocus
        btn.OnGainFocus = function(self)
            self:SetScale(factor, factor)
            if og then og(self) end
        end
        btn.OnLoseFocus = function(self)
            self:SetScale(1, 1)
            if ol then ol(self) end
        end
    end

    local close = WIT_POPUP:AddChild(TextButton())
    if close then
        close:SetText("×")
        close:SetTextSize(50)
        close:SetPosition(172, 213)
        close:SetTextColour(0.65, 0.58, 0.45, 1)
        close:SetTextFocusColour(1, 1, 1, 1)
        close:SetOnClick(ClosePopupAndResume)
        _AddHoverScale(close)
    end

    -- 设置按钮（打开原版 Mod 配置界面）
    local WIT_SETTINGS_OPEN = false
    local settings_root = nil
    local function _OpenSettings()
        if WIT_SETTINGS_OPEN then return end

        -- 1. 本地化配置项（文本来自 wit_lang.lua 的 WIT_TXT）
        local mod_info = GLOBAL.KnownModIndex:GetModInfo(modname)
        if mod_info and mod_info.configuration_options then
            local opts = mod_info.configuration_options
            for _, opt in ipairs(opts) do
                if opt.name == "LANGUAGE" then
                    opt.label = WIT_TXT.CFG_LANG_LABEL
                    opt.hover = WIT_TXT.CFG_LANG_HOVER
                    opt.options[1].description = WIT_TXT.CFG_LANG_AUTO
                    opt.options[2].description = WIT_TXT.CFG_LANG_ZH
                    opt.options[3].description = WIT_TXT.CFG_LANG_EN
                elseif opt.name == "KEY_R" then
                    opt.label = WIT_TXT.CFG_KEY_R_LABEL
                    opt.hover = WIT_TXT.CFG_KEY_R_HOVER
                elseif opt.name == "KEY_U" then
                    opt.label = WIT_TXT.CFG_KEY_U_LABEL
                    opt.hover = WIT_TXT.CFG_KEY_U_HOVER
                elseif opt.name == "KEY_NAV_BACK" then
                    opt.label = WIT_TXT.CFG_NAV_BACK_LABEL
                    opt.hover = WIT_TXT.CFG_NAV_BACK_HOVER
                elseif opt.name == "KEY_NAV_FORWARD" then
                    opt.label = WIT_TXT.CFG_NAV_FORWARD_LABEL
                    opt.hover = WIT_TXT.CFG_NAV_FORWARD_HOVER
                elseif opt.name == "POPUP_POSITION" then
                    opt.label = WIT_TXT.CFG_POS_LABEL
                    opt.hover = WIT_TXT.CFG_POS_HOVER
                    opt.options[1].description = WIT_TXT.CFG_POS_AUTO
                    opt.options[2].description = WIT_TXT.CFG_POS_LEFT
                    opt.options[3].description = WIT_TXT.CFG_POS_RIGHT
                elseif opt.name == "SHOW_HOVER_INFO" then
                    opt.label = WIT_TXT.CFG_HOVER_LABEL
                    opt.hover = WIT_TXT.CFG_HOVER_HOVER
                    opt.options[1].description = WIT_TXT.CFG_ON
                    opt.options[2].description = WIT_TXT.CFG_OFF
                elseif opt.name == "AUTO_PAUSE_UI" then
                    opt.label = WIT_TXT.CFG_PAUSE_LABEL
                    opt.hover = WIT_TXT.CFG_PAUSE_HOVER
                    opt.options[1].description = WIT_TXT.CFG_ON
                    opt.options[2].description = WIT_TXT.CFG_OFF
                end
            end
        end

        -- 2. 打开 Mod 配置界面（keybind.lua 会自动替换按键选项为交互式绑定）
        local ModConfigScreen = require("screens/redux/modconfigurationscreen")
        local screen = ModConfigScreen(modname, true)
        TheFrontEnd:PushScreen(screen)
        WIT_SETTINGS_OPEN = true
        settings_root = screen

        -- 3. 修正 LANGUAGE spinner 宽度
        for i, opt_w in ipairs(screen.optionwidgets) do
            local opt_data = screen.options[i]
            if opt_data and opt_data.name == "LANGUAGE" then
                pcall(function()
                    opt_w.spinner:SetWidth(260)
                end)
            end
        end

        -- 监听屏幕关闭
        local orig_ondestroy = screen.OnDestroy
        screen.OnDestroy = function(s)
            if orig_ondestroy then orig_ondestroy(s) end
            WIT_SETTINGS_OPEN = false
            settings_root = nil
        end
    end
    -- 设置按钮（纯文本，与关闭按钮风格一致）
    local cfg_btn = WIT_POPUP:AddChild(TextButton())
    if cfg_btn then
        cfg_btn:SetText("≡")
        cfg_btn:SetTextSize(42)
        cfg_btn:SetPosition(137, 214)
        cfg_btn:SetTextColour(0.65, 0.58, 0.45, 1)
        cfg_btn:SetTextFocusColour(1, 1, 1, 1)
        cfg_btn:SetTooltip(WIT_TXT.CFG_BTN_TOOLTIP)
        cfg_btn:SetOnClick(function()
            if not WIT_SETTINGS_OPEN then
                _OpenSettings()
            end
        end)
        _AddHoverScale(cfg_btn)
    end

    WIT_TAB_BTNS = {}
    local tab_y = 125
    for i, cat in ipairs(WIT_AVAIL_CATS) do
        local tb = WIT_POPUP:AddChild(TextButton())
        if tb then
            local label =(cat == "SOURCES" and WIT_TXT.TAB_SOURCES)
                or (cat == "CRAFT_FROM" and (WIT_TXT.TAB_CRAFT_FROM or WIT_TXT.TAB_CRAFTING))
                or (cat == "COOK_FROM" and (WIT_TXT.TAB_COOK_FROM or WIT_TXT.TAB_COOKING))
                or (cat == "CRAFT_USE" and (WIT_TXT.TAB_CRAFT_USE or WIT_TXT.TAB_CRAFTING))
                or (cat == "COOK_USE" and (WIT_TXT.TAB_COOK_USE or WIT_TXT.TAB_COOKING))
                or WIT_TXT.TAB_INFO
            tb:SetText(label); tb:SetTextSize(#WIT_AVAIL_CATS > 4 and 21 or 26)
            tb:SetPosition((i - (#WIT_AVAIL_CATS + 1) / 2) * (#WIT_AVAIL_CATS > 4 and 72 or 100), tab_y)
            tb:SetOnClick(function() SelectCategory(cat, true) end)
            WIT_TAB_BTNS[cat] = tb
        end
    end

    WIT_CONTENT = WIT_POPUP:AddChild(Widget("c"))
    if WIT_CONTENT then WIT_CONTENT:SetPosition(0, 20) end

    local pg_y = -210
    WIT_PG_PREV = WIT_POPUP:AddChild(ImageButton(CRAFTING_ATLAS, "scrollbar_arrow_down.tex", "scrollbar_arrow_down_hl.tex"))
    if WIT_PG_PREV then
        WIT_PG_PREV:SetScale(0.4); WIT_PG_PREV:SetPosition(-40, pg_y); WIT_PG_PREV:SetRotation(90)
        WIT_PG_PREV:SetOnClick(function() WIT_PAGE = WIT_PAGE - 1; SelectCategory(WIT_CUR_CAT, false) end)
    end

    WIT_PG_TEXT = WIT_POPUP:AddChild(Text(NEWFONT, 20))
    if WIT_PG_TEXT then WIT_PG_TEXT:SetString("1 / 1"); WIT_PG_TEXT:SetPosition(0, pg_y); WIT_PG_TEXT:SetColour(0.85, 0.78, 0.65, 1) end

    WIT_PG_NEXT = WIT_POPUP:AddChild(ImageButton(CRAFTING_ATLAS, "scrollbar_arrow_down.tex", "scrollbar_arrow_down_hl.tex"))
    if WIT_PG_NEXT then
        WIT_PG_NEXT:SetScale(0.4); WIT_PG_NEXT:SetPosition(40, pg_y); WIT_PG_NEXT:SetRotation(-90)
        WIT_PG_NEXT:SetOnClick(function() WIT_PAGE = WIT_PAGE + 1; SelectCategory(WIT_CUR_CAT, false) end)
    end
    local initial_cat = preferred_cat
    if initial_cat == nil then
        local preferred_order = mode == "USE"
            and { "CRAFT_USE","COOK_USE","SOURCES","CRAFT_FROM","COOK_FROM","INFO" }
            or {"SOURCES","CRAFT_FROM","COOK_FROM", "CRAFT_USE", "COOK_USE", "INFO" }
        for _, wanted in ipairs(preferred_order) do
            for _, cat in ipairs(WIT_AVAIL_CATS) do
                if cat == wanted then
                    initial_cat = wanted
                    break
                end
            end
            if initial_cat ~= nil then break end
        end
    end
    local has_initial = false
    for _, cat in ipairs(WIT_AVAIL_CATS) do
        if cat == initial_cat then has_initial = true; break end
    end
    SelectCategory(has_initial and initial_cat or WIT_AVAIL_CATS[1], true)
    _PauseWorldForPopup()
end

-- ============================
-- 导航历史：前进/后退
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

function WIT_NAV_BACK()
    _NavGo(WIT_BACK_STACK, WIT_FORWARD_STACK)
end

function WIT_NAV_FORWARD()
    _NavGo(WIT_FORWARD_STACK, WIT_BACK_STACK)
end

-- ============================
-- 键盘输入处理 (from wit_input.lua)
-- ============================
-- 注意：全局按键分发器在 modmain.lua 中注册，
-- 调用 WIT_DISPATCH_R / WIT_DISPATCH_U 进行转发。

function WIT_DISPATCH_R()
    local ok, e = pcall(function()
        if ThePlayer == nil then return end
        if TheFrontEnd and TheFrontEnd.textProcessorWidget then return end
        if ThePlayer.components.playercontroller ~= nil and ThePlayer.components.playercontroller.placer ~= nil then return end
        local item = GetHoverItem()
        -- 合成菜单详情面板悬浮材料/产物图标时按 R 键也可触发
        if item == nil and WIT_POPUP == nil and WIT_HOVERED_DETAIL_PREFAB then
            item = { prefab = WIT_HOVERED_DETAIL_PREFAB }
        end
        -- 图鉴面板按键也触发
        if item == nil then
            item = GetScrapbookSelectedItem()
        end
        -- 鼠标指向游戏世界实体时触发
        -- 图鉴打开时不读取被图鉴遮挡的世界实体
        if item == nil and GetActiveScrapbookScreen() == nil then
            item = GetWorldHoveredItem()
        end
        if item == nil then
            if WIT_POPUP ~= nil then ClosePopupAndResume() end
            return
        end
        local name = item.prefab or "unknown"
        BuildIndexes()
        -- if WIT_POPUP ~= nil then
        --     if WIT_NAME == name and (WIT_CUR_CAT == "CRAFT_FROM" or WIT_CUR_CAT == "COOK_FROM" or WIT_CUR_CAT == "SOURCES") then ClosePopupAndResume(); return end
        --     ClosePopup()
        -- end
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

function WIT_DISPATCH_U()
    local ok, e = pcall(function()
        if ThePlayer == nil then return end
        if TheFrontEnd and TheFrontEnd.textProcessorWidget then return end
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
        local name = item.prefab or "unknown"
        BuildIndexes()
        -- if WIT_POPUP ~= nil then
        --     if WIT_NAME == name and (WIT_CUR_CAT == "CRAFT_USE" or WIT_CUR_CAT == "COOK_USE") then ClosePopupAndResume(); return end
        --     ClosePopup()
        -- end
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

-- ============================
-- 物品信息页渲染 (from wit_iteminfo_render.lua)
-- ============================

local INFO_FONT = GLOBAL.NUMBERFONT   -- 信息栏字体，统一切换
local ICON_SIZE = 56
local FONT_SIZE = 26
local START_Y = 65
local ROW_H = 68
local CARD_W = 370
local PADDING = 14

-- 使用全局 ResolveIconAtlas

local function _fmt_num(v)
    if v == nil then return "0" end
    if v == math.floor(v) then return tostring(math.floor(v)):gsub("^-", "－") end
    return (string.format("%.1f", v)):gsub("^-", "－")
end

local function _fmt_time(seconds)
    if seconds == nil then return "?" end
    if seconds >= 480 then
        local d = seconds / 480
        if d == math.floor(d) then return math.floor(d) .. "d" end
        return string.format("%.1f", d) .. "d"
    else
        return math.floor(seconds) .. "s"
    end
end

local function _GetTooltip(icon)
    if not WIT_TXT or not WIT_TXT.ICON_TOOLTIPS then return nil end
    local key = icon:match("^(.+)%.tex$") or icon
    return WIT_TXT.ICON_TOOLTIPS[key]
end

function RenderItemInfo()
    if WIT_CONTENT == nil then return end
    WIT_CONTENT:KillAllChildren()

    local info = GetItemInfo and GetItemInfo(WIT_NAME)
    if not info or next(info) == nil then
        local t = WIT_CONTENT:AddChild(GLOBAL.Text(INFO_FONT, 24))
        if t then t:SetString(WIT_TXT.NO_INFO); t:SetPosition(0, 10); t:SetColour(0.6, 0.55, 0.4, 1) end
        return
    end

    local current_y = START_Y

    local function _RenderGroupCard(blocks)
        if #blocks == 0 then return end
        local MIN_X = -CARD_W/2 + 20
        local MAX_X = CARD_W/2 - 10
        local cx = MIN_X
        local row = 1
        local layouts = {}
        for _, b in ipairs(blocks) do
            local atlas = ResolveIconAtlas(b.icon)
            local dummy = GLOBAL.Text(INFO_FONT, FONT_SIZE)
            dummy:SetString(b.text)
            local tw, th = dummy:GetRegionSize()
            dummy:Kill()
            local has_icon = atlas ~= nil
            local bw = has_icon and (ICON_SIZE + 20 + tw) or (tw + 24)
            if cx + bw > MAX_X and not b.no_wrap then cx = MIN_X; row = row + 1 end
            table.insert(layouts, {b=b, atlas=atlas, tw=tw, bw=bw, cx=cx, row=row, has_icon=has_icon})
            cx = cx + bw + 12
        end
        if #layouts == 0 then return end
        local card_h = row * ROW_H + PADDING * 2
        local group = GLOBAL.Widget("info_card")
        WIT_CONTENT:AddChild(group)
        local bg = group:AddChild(GLOBAL.Image("images/global.xml", "square.tex"))
        bg:SetSize(CARD_W, card_h); bg:SetTint(0.12, 0.10, 0.08, 0.7); bg:MoveToBack()
        for _, l in ipairs(layouts) do
            local cy = card_h/2 - PADDING - ROW_H/2 - (l.row - 1) * ROW_H
            local w = group:AddChild(GLOBAL.Widget("block"))
            w:SetPosition(l.cx + l.bw/2, cy)
            local icon_x = -l.bw/2
            if l.has_icon then
                -- 物品栏图集图标（如 goldnugget）自带边距，缩小至 46x46 居中，与其他信息图标视觉一致
                local is_inv_icon = l.atlas and l.atlas:match("inventoryimages%d*%.xml$")
                local icon_size = is_inv_icon and (ICON_SIZE - 10) or ICON_SIZE
                local img = w:AddChild(GLOBAL.Image(l.atlas, l.b.icon))
                img:ScaleToSize(icon_size, icon_size)
                img:SetPosition(icon_x + ICON_SIZE/2, 0)
                local tip = l.b.tip or _GetTooltip(l.b.icon)
                if tip then w:SetTooltip(tip) end
                -- 恢复原本居中计算模式，废弃导致坐标扭曲的 SetRegionSize/SetHAlign
                local txt_w = w:AddChild(GLOBAL.Text(INFO_FONT, FONT_SIZE))
                txt_w:SetString(l.b.text)
                txt_w:SetColour(0.85, 0.78, 0.65, 1)
                txt_w:SetPosition(icon_x + ICON_SIZE + 10 + l.tw/2, 0)
            else
                -- Text-only pill for unresolvable icons
                local pill = w:AddChild(GLOBAL.Image("images/global.xml", "square.tex"))
                pill:SetSize(l.bw, ROW_H - 8)
                pill:SetTint(0.25, 0.22, 0.18, 0.8)
                local txt_w = w:AddChild(GLOBAL.Text(INFO_FONT, FONT_SIZE))
                txt_w:SetString(l.b.text)
                txt_w:SetColour(0.85, 0.78, 0.65, 1)
                if l.b.tip then txt_w:SetTooltip(l.b.tip) end
            end
        end
        group:SetPosition(0, current_y - card_h/2)
        current_y = current_y - card_h - 12
    end

    local blocks = {}

    -- 分组 1：食用与恢复
    if info.edible then
        local hg = info.edible.hunger or 0
        local hl = info.edible.health or 0
        local sn = info.edible.sanity or 0
        table.insert(blocks, {icon="icon_hunger.tex", text=(hg > 0 and "＋" or "") .. _fmt_num(hg), no_wrap=true})
        table.insert(blocks, {icon="icon_health.tex", text=(hl > 0 and "＋" or "") .. _fmt_num(hl), no_wrap=true})
        table.insert(blocks, {icon="icon_sanity.tex", text=(sn > 0 and "＋" or "") .. _fmt_num(sn), no_wrap=true})
        
        if info.edible.foodtype and info.edible.foodtype ~= "GENERIC" then
            local ft = tostring(info.edible.foodtype)
            local ft_name = WIT_TXT.FOODTYPE_NAMES and WIT_TXT.FOODTYPE_NAMES[ft]
            if ft_name == nil and GLOBAL.STRINGS.SCRAPBOOK ~= nil and GLOBAL.STRINGS.SCRAPBOOK.FOODTYPE then
                ft_name = GLOBAL.STRINGS.SCRAPBOOK.FOODTYPE[ft]
            end
            table.insert(blocks, {icon="icon_food.tex", text=ft_name or ft})
        end
        if info.edible.temperaturedelta and info.edible.temperaturedelta ~= 0 then
            local icon = info.edible.temperaturedelta > 0 and "icon_heat.tex" or "icon_cold.tex"
            local txt = _fmt_num(info.edible.temperaturedelta) .. "°C"
            if info.edible.temperatureduration then txt = txt .. " / " .. _fmt_num(info.edible.temperatureduration) .. "s" end
            local tip_suffix = info.edible.temperaturedelta > 0 and WIT_TXT.TIP_TEMP_HEAT or WIT_TXT.TIP_TEMP_COOL
            table.insert(blocks, {icon=icon, text=txt, tip=tip_suffix .. WIT_TXT.TIP_TEMP_DUR})
        end
    end
    if info.healer then
        table.insert(blocks, {icon="icon_health.tex", text="＋" .. _fmt_num(info.healer.health)})
    end
    _RenderGroupCard(blocks)

    -- 烹饪标签值（次级文本，位于食物类型卡片下方）
    if info.edible then
        local ing_tags = WIT.ingredient_tags and WIT.ingredient_tags[WIT_NAME]
        if ing_tags then
            local tag_parts = {}
            for tag_name, tag_value in pairs(ing_tags) do
                if tag_value > 0 then
                    table.insert(tag_parts, CN(tag_name) .. " " .. _fmt_num(tag_value))
                end
            end
            if #tag_parts > 0 then
                local tag_t = WIT_CONTENT:AddChild(GLOBAL.Text(INFO_FONT, 20))
                tag_t:SetString(table.concat(tag_parts, "  ·  "))
                tag_t:SetPosition(0, current_y)
                tag_t:SetColour(0.7, 0.65, 0.5, 0.8)
                current_y = current_y - 22
            end
        end
    end

    -- 分组 2：战斗与装备
    blocks = {}
    if info.weapon then
        local txt = tostring(info.weapon.damage)
        local tip = nil  -- 使用 ICON_TOOLTIPS 默认值
        if info.weapon.attackrange and info.weapon.attackrange > 1 then
            txt = txt .. " / " .. info.weapon.attackrange
            tip = WIT_TXT.TIP_ATK_RANGE
        end
        table.insert(blocks, {icon="icon_damage.tex", text=txt, tip=tip})
    end
    if info.armor then
        local absorb = info.armor.absorb_percent and math.floor(info.armor.absorb_percent * 100) .. "%" or "?"
        table.insert(blocks, {icon="icon_armor.tex", text=absorb})
        if info.armor.maxcondition then table.insert(blocks, {icon="icon_uses.tex", text=tostring(info.armor.maxcondition)}) end
    end
    if info.equippable then
        if info.equippable.equipslot then
            local slot_txt = tostring(info.equippable.equipslot)
            if WIT_TXT.EQUIPSLOT_NAMES and WIT_TXT.EQUIPSLOT_NAMES[slot_txt] then
                slot_txt = WIT_TXT.EQUIPSLOT_NAMES[slot_txt]
            end
            table.insert(blocks, {icon="icon_clothing.tex", text=slot_txt})
        end
        if info.equippable.walkspeedmult and info.equippable.walkspeedmult ~= 1 then
            table.insert(blocks, {icon="cane.tex", text="×" .. string.format("%.2f", info.equippable.walkspeedmult)})
        end
        if info.equippable.dapperness and info.equippable.dapperness ~= 0 then
            local dpm = info.equippable.dapperness * 60
            local sign = dpm > 0 and "＋" or ""
            table.insert(blocks, {icon="icon_sanity.tex", text=sign .. string.format("%.2f/min", dpm), tip=WIT_TXT.TIP_SANITY_EQUIP})
        end
    end
    if info.sanityaura and info.sanityaura.aura and info.sanityaura.aura ~= 0 then
        local apm = info.sanityaura.aura * 60
        local sign = apm > 0 and "＋" or ""
        table.insert(blocks, {icon="icon_sanity.tex", text=sign .. string.format("%.2f/min", apm), tip=WIT_TXT.TIP_SANITY_AURA})
    end
    _RenderGroupCard(blocks)

    -- 分组 3：工具与耐久
    blocks = {}
    if info.tools and #info.tools > 0 then
        for _, t in ipairs(info.tools) do
            local eff = t.efficiency or 1
            local txt = CN(t.action) .. "×" .. _fmt_num(eff)
            table.insert(blocks, {icon="icon_action.tex", text=txt, tip=WIT_TXT.TIP_TOOL_EFF})
        end
    end
    if info.finiteuses then table.insert(blocks, {icon="icon_uses.tex", text=tostring(info.finiteuses.maxuses)}) end
    _RenderGroupCard(blocks)

    -- 分组 4：杂项特性
    blocks = {}
    if info.perishable then
        table.insert(blocks, {icon="icon_spoil.tex", text=_fmt_time(info.perishable.perishtime), tip=WIT_TXT.TIP_SPOIL})
    end
    if info.burnable then
        table.insert(blocks, {icon="icon_burnable.tex", text=_fmt_time(info.burnable.burntime), tip=WIT_TXT.TIP_BURN})
    end
    if info.fueled then
        local tip = (info.fueled.fueltype == "USAGE") and WIT_TXT.TIP_FUEL_USAGE or WIT_TXT.TIP_FUEL_TIME
        table.insert(blocks, {icon="icon_fuel.tex", text=_fmt_time(info.fueled.maxfuel), tip=tip})
    end
    if info.sewable then table.insert(blocks, {icon="icon_sewingkit.tex", text=WIT_TXT.SEWABLE, tip=WIT_TXT.TIP_SEW}) end
    if info.waterproofer then
        local pct = math.floor((info.waterproofer.effectiveness or 0) * 100)
        table.insert(blocks, {icon="icon_wetness.tex", text=pct .. "%", tip=WIT_TXT.TIP_WATERPROOF})
    end
    if info.insulator then
        local icon = info.insulator.type == GLOBAL.SEASONS.SUMMER and "icon_heat.tex" or "icon_cold.tex"
        local tip = info.insulator.type == GLOBAL.SEASONS.SUMMER and WIT_TXT.TIP_INSULATE_SUMMER or WIT_TXT.TIP_INSULATE_WINTER
        table.insert(blocks, {icon=icon, text=math.floor(info.insulator.insulation or 0) .. "s", tip=tip})
    end
    if info.stackable and info.stackable.maxsize and info.stackable.maxsize > 1 then
        table.insert(blocks, {icon="icon_stack.tex", text="×" .. info.stackable.maxsize})
    end
    if info.tradable and info.tradable.goldvalue and info.tradable.goldvalue > 0 then
        table.insert(blocks, {icon="goldnugget.tex", text=tostring(info.tradable.goldvalue), tip=WIT_TXT.TIP_TRADE})
    end
    if info.repairable then
        if info.repairable.repairmaterial then
            local mat_name = CN(info.repairable.repairmaterial)
            table.insert(blocks, {icon="icon_wrench.tex", text=mat_name, tip=WIT_TXT.TIP_REPAIR_MAT})
        elseif info.repairable.repairitems and #info.repairable.repairitems > 0 then
            local mat_name = CN(info.repairable.repairitems[1])
            table.insert(blocks, {icon="icon_wrench.tex", text=mat_name, tip=WIT_TXT.TIP_REPAIR_MAT})
        else
            table.insert(blocks, {icon="icon_wrench.tex", text=WIT_TXT.REPAIRABLE})
        end
    end
    _RenderGroupCard(blocks)

    -- 标签与注释行
    local bottom_texts = {}
    if info.edible and info.edible.player_can_eat == false then
        if info.edible.eater_hint then
            table.insert(bottom_texts, WIT_TXT.FMT_EDIBLE_BY:format(info.edible.eater_hint))
        else
            table.insert(bottom_texts, WIT_TXT.FMT_INEDIBLE)
        end
    end

    if info.tags and #info.tags > 0 then
        local tag_str = ""
        local count = 0
        for _, tag in ipairs(info.tags) do
            if not tag:match("^_") and not tag:match("^edible_") and not tag:match("^fx") then
                if count > 0 then tag_str = tag_str .. "  " end
                tag_str = tag_str .. "[" .. CN(tag) .. "]"
                count = count + 1
                if count >= 6 then break end
            end
        end
        if #tag_str > 0 then table.insert(bottom_texts, tag_str) end
    end

    for i, txt in ipairs(bottom_texts) do
        local t = WIT_CONTENT:AddChild(GLOBAL.Text(INFO_FONT, 18))
        if t then
            t:SetString(txt)
            t:SetPosition(0, current_y - 10 - (i - 1) * 22)
            t:SetColour(0.55, 0.5, 0.4, 1)
        end
    end
end 
