-- wit_ui_cards: 制作/烹饪卡片渲染

local UIAnim = GLOBAL.require("widgets/uianim")

-- ============================
-- 卡片渲染 (from wit_render.lua)
-- ============================

-- 渲染单条制作/拆解配方卡片。
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
        local ca = GetInventoryItemAtlas(char_prefab .. ".tex", true)
        if ca then table.insert(extra_icons, { atlas = ca, tex = char_prefab .. ".tex", tip = r.builder_tag, prefab = char_prefab, }) end
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
        local ba = GLOBAL.GetInventoryItemAtlas("blueprint.tex",true)
            or (GLOBAL.GetScrapbookIconAtlas and GLOBAL.GetScrapbookIconAtlas("blueprint.tex"))
        if ba then
            local btip = (GLOBAL.STRINGS and GLOBAL.STRINGS.NAMES and GLOBAL.STRINGS.NAMES["BLUEPRINT"]) or "Blueprint"
            table.insert(extra_icons, { atlas = ba, tex = "blueprint.tex", tip = btip, prefab = "blueprint", })
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
                    local prefab = ei.prefab or ei.tip
                    -- 点击额外来源图标时跳转到对应 prefab 的来源页。
                    eimg.OnMouseButton = function(_, button, down)
                        if not down and button == 0 then
                            BuildIndexes(); ClosePopup(); CreatePopup(prefab, "SOURCE")
                        end
                    end
                end
            else
                -- 手动创建 UIAnim 3D 模型（固定小比例，适合右上角角标）
                local anim = nil
                local entry = ei.prefab and WIT_GetScrapbookEntry(ei.prefab)
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
                        -- 点击 3D 来源角标时跳转到对应 prefab 的来源页。
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
                        -- 点击文字兜底角标时跳转到对应 prefab 的来源页。
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

-- 渲染单条烹饪配方卡片。
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

-- 按分页渲染配方卡片列表。
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
