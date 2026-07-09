-- wit_ui_info: 物品信息页渲染

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

-- 格式化数值显示，兼容整数、小数和负号样式。
local function _fmt_num(v)
    if v == nil then return "0" end
    if v == math.floor(v) then return tostring(math.floor(v)):gsub("^-", "－") end
    return (string.format("%.1f", v)):gsub("^-", "－")
end

-- 将秒数格式化为游戏天数或秒数文本。
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

-- 根据图标 tex 名查找本地化 tooltip 文本。
local function _GetTooltip(icon)
    if not WIT_TXT or not WIT_TXT.ICON_TOOLTIPS then return nil end
    local key = icon:match("^(.+)%.tex$") or icon
    return WIT_TXT.ICON_TOOLTIPS[key]
end

-- 渲染 INFO 页签，展示当前物品的属性、标签和说明。
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

    -- 将一组属性块渲染成自动换行的信息卡片。

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
