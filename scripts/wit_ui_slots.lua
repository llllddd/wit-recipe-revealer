-- wit_ui_slots: 物品槽位、悬浮信息与箭头控件

-- ============================
-- 物品图标 + 箭头 (from wit_slot.lua)
-- ============================

-- 创建物品槽位图标，并绑定来源/用途点击与悬浮信息。
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
        local atlas, img_name, use_cc = WIT_ResolvePrefabIcon(disp_prefab)
        if atlas ~= nil and img_name ~= nil then
    local icon = slot.image:AddChild(
        Image(atlas, img_name)
    )
        if icon then
            icon:SetSize(icon_size, icon_size)

            if use_cc then
                icon:SetEffect("shaders/ui_cc.ksh")
            end
        end
        else
            local dispname = CN(disp_prefab) or disp_prefab
            local fb = slot.image:AddChild(
                Text(NEWFONT, icon_size * 0.4)
            )

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
        -- 右键槽位时打开该 prefab 的用途页。
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

        -- 根据物品属性生成槽位悬浮摘要面板。

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
        -- 悬浮槽位时创建一行属性摘要面板。
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
        -- 鼠标离开槽位时销毁属性摘要面板。
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

-- 在配方卡片中绘制材料到产物的箭头。
function MakeArrow(parent, x, y)
    if parent == nil then return end
    local t = parent:AddChild(Text(UIFONT, 40))
    if t then t:SetString("→"); t:SetPosition(x, y); t:SetColour(0.6, 0.55, 0.4, 1) end
end
