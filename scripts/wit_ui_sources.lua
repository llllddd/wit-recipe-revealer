-- wit_ui_sources: 获取来源页签渲染

-- ============================
-- 来源渲染 (SOURCES tab)
-- ============================

-- 渲染 SOURCES 页签，展示当前物品可由哪些实体产出。
function RenderSources()
    if WIT_CONTENT == nil then return end
    WIT_CONTENT:KillAllChildren()
    
    -- 扫描 WIT.entity_loot，找出包含当前物品的实体
    local matched = {}
    for ename, loots in pairs(WIT.entity_loot or {}) do
        -- 找到掉落物品
        if ename == WIT_NAME then
            table.insert(matched, { source = ename, loots = loots })
                break
        end
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
            -- 点击来源实体图标时跳转到该实体的来源页。
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
                -- 点击来源兜底图标时跳转到该实体的来源页。
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
