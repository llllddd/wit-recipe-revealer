-- wit_ui_icons: 图标、图鉴 entry 与 atlas 解析

-- UIAnim 动画控件（官方图鉴详情页用于实体 3D 模型渲染）
local UIAnim = GLOBAL.require("widgets/uianim")

-- ============================
-- 图标图集解析（提取为全局，供悬浮面板和 RenderItemInfo 共用）
-- ============================
-- 图鉴数据缓存：完整 entry（含 tex/build/bank/anim/type）
local _scrapbook_entry_map = nil

-- 获取并缓存官方图鉴数据中某个 prefab 的完整 entry。
function WIT_GetScrapbookEntry(prefab)
    if _scrapbook_entry_map == nil then
        _scrapbook_entry_map = {}

        local ok, data = pcall(
            GLOBAL.require,
            "screens/redux/scrapbookdata"
        )

        if ok and type(data) == "table" then
            for _, entry in pairs(data) do
                if type(entry) == "table"
                    and type(entry.prefab) == "string" then
                    _scrapbook_entry_map[entry.prefab] = entry
                end
            end
        end
    end

    return _scrapbook_entry_map[prefab]
end

-- 用 entry.prefab 查官方图鉴 entry
function WIT_GetScrapbookEntryByPrefab(prefab)
    if type(prefab) ~= "string" or prefab == "" then
        return nil
    end

    WIT_BuildScrapbookEntryMaps()

    return WIT_scrapbook_entry_map_by_prefab[prefab]
end

-- 用 entry.name 查官方图鉴 entry
function WIT_GetScrapbookEntryByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    WIT_BuildScrapbookEntryMaps()

    return WIT_scrapbook_entry_map_by_name[name]
end

-- 读取某个 prefab 在图鉴中登记的 tex 文件名。
function WIT_GetScrapbookTex(prefab)
    local entry = WIT_GetScrapbookEntry(prefab)
    return entry and entry.tex or nil
end

-- 处理不显示的图片
local WIT_ICON_PREFAB_ALIASES = {
}

-- 处理特殊命名prefab
-- 将逻辑 prefab 归一化为实际用于查找图标的 prefab。
local function WIT_NormalizeIconPrefab(prefab)
    if type(prefab) ~= "string"
        or prefab == "" then
        return prefab
    end

    local icon_prefab = prefab

    -- 冬季盛宴：
    -- wintercooking_latkes → latkes
    icon_prefab = icon_prefab:gsub(
        "^wintercooking_",
        ""
    )
    --Wendy
    icon_prefab = icon_prefab:gsub(
        "^wendy_recipe_",
        ""
    )
    -- 弹弓运行时变体：
    -- slingshotex → slingshot
    -- slingshot2ex → slingshot
    if icon_prefab:match("^slingshot%d*ex$") then
        icon_prefab = "slingshot"
    end

    -- 所有以 _blueprint 结尾的配方蓝图
    -- recipe_blueprint → blueprint
    -- 配方代码_blueprint → blueprint
    if icon_prefab:match("_blueprint$") then
        icon_prefab = "blueprint"
    end

    -- 其他明确别名
    icon_prefab =
        WIT_ICON_PREFAB_ALIASES[icon_prefab]
        or icon_prefab

    return icon_prefab
end

-- 按覆盖表、图鉴 tex、同名 tex 和兜底规则解析 prefab 图标。
function WIT_ResolvePrefabIcon(prefab)
    if type(prefab) ~= "string" or prefab == "" then
        return nil, nil, false
    end

    local icon_prefab = WIT_NormalizeIconPrefab(prefab)
    local entry = WIT_GetScrapbookEntry(icon_prefab)

    -- 1. 图鉴记录
    if entry ~= nil
        and type(entry.tex) == "string"
        and entry.tex ~= "" then

        local tex = entry.tex
        local atlas = nil

        if GLOBAL.GetScrapbookIconAtlas ~= nil then
            atlas = GLOBAL.GetScrapbookIconAtlas(tex)
        end

        if atlas == nil then
            atlas = GLOBAL.GetInventoryItemAtlas(tex, true)
        end

        if atlas ~= nil then
            return atlas, tex, false
        end
    end

    -- 3. 同名图鉴图标
    local tex = icon_prefab .. ".tex"
    local atlas = nil

    if GLOBAL.GetScrapbookIconAtlas ~= nil then
        atlas = GLOBAL.GetScrapbookIconAtlas(tex)
    end

    -- 4. 同名库存图标
    if atlas == nil then
        atlas = GLOBAL.GetInventoryItemAtlas(tex, true)
    end

    if atlas ~= nil then
        return atlas, tex, false
    end

    -- 5. 棋子草图兜底
    -- 部分旧棋子草图没有独立 tex，实际使用通用 sketch 图标
    if icon_prefab:match("^chesspiece_.+_sketch$") then
        local sketch_tex = "sketch.tex"
        local sketch_atlas = nil

        if GLOBAL.GetScrapbookIconAtlas ~= nil then
            sketch_atlas =
                GLOBAL.GetScrapbookIconAtlas(
                    sketch_tex
                )
        end

        if sketch_atlas == nil
            and GLOBAL.GetInventoryItemAtlas ~= nil then

            sketch_atlas =
                GLOBAL.GetInventoryItemAtlas(
                    sketch_tex,
                    true
                )
        end

        if sketch_atlas ~= nil then
            return sketch_atlas, sketch_tex, false
        end
    end

    return nil, nil, false
end

-- 图标图集解析（用于物品/战利品图集查找）
-- 为来源实体或战利品解析可用于 Image 的 atlas 与 tex。
function ResolveEntityIconAtlas(name)
    local atlas, tex = WIT_ResolvePrefabIcon(name)
    return atlas, tex
end

-- 创建实体来源图标控件
-- 实体 → UIAnim() 动态渲染 3D 模型（无框，与图鉴详情页一致）
-- 物品 → Image 库存图集（纯图标无框）
-- 返回带有 SetTooltip/OnMouseButton 支持的 widget
-- 创建可点击的实体/物品图标控件，实体优先使用 UIAnim 渲染。
function CreateEntityIconWidget(parent, prefab, size, pos_x, pos_y)
    if type(prefab) ~= "string" or prefab == "" then
        return nil
    end
    
    local icon_prefab = WIT_NormalizeIconPrefab(prefab)
    local entry = WIT_GetScrapbookEntryByPrefab(icon_prefab)
    if entry == nil then 
        entry = WIT_GetScrapbookEntryByName(icon_prefab)
    end
    print("sdsdsadadfds",entry)
    -- ImageButton 作为交互基础（tooltip + click）
    local btn = parent:AddChild(ImageButton("images/hud.xml", "inv_slot.tex"))
    if not btn then return nil end

    btn:SetPosition(pos_x, pos_y)
    btn:ForceImageSize(size, size)
    btn.image:SetTint(0, 0, 0, 0)  -- 透明背景

    -- 物品/食物 → 库存图集 Image
    if entry ~= nil and (entry.type == "item" or entry.type == "food") then
        local atlas, tex = WIT_ResolvePrefabIcon(prefab)

        if atlas ~= nil and tex ~= nil then
            btn.image:SetTint(1, 1, 1, 1)
            btn:SetTextures(atlas, tex)
        end

        return btn
    end

    -- 实体 → UIAnim
    if entry ~= nil and entry.build and entry.bank then
        local anim = btn:AddChild(UIAnim())

        if anim then
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

                s:Hide("snow")
                s:Hide("mouseover")

                if entry.hide then
                    for _, h in ipairs(entry.hide) do
                        s:Hide(h)
                    end
                end

                if entry.hidesymbol then
                    for _, h in ipairs(entry.hidesymbol) do
                        s:HideSymbol(h)
                    end
                end

                local x1, y1, x2, y2 = s:GetVisualBB()

                if x1 and x2 and y1 and y2 then
                    local aw = x2 - x1
                    local ay = y2 - y1

                    if aw > 0 and ay > 0 then
                        local TARGET = size
                        local SCALE = math.min(TARGET * 1.4 / aw, TARGET * 1.4 / ay)

                        if entry.type == "giant" then
                            SCALE = SCALE * 1.25
                        end

                        SCALE = math.max(0.04, math.min(0.6, SCALE))
                        anim:SetScale(SCALE)
                    end
                end
            end)

            anim:SetClickable(false)
        end

        return btn
    end

    -- 兜底 1：entry.tex
    if entry ~= nil and entry.tex then
        local atlas = nil

        if GLOBAL.GetScrapbookIconAtlas ~= nil then
            atlas = GLOBAL.GetScrapbookIconAtlas(entry.tex)
        end

        if atlas == nil then
            atlas = GLOBAL.GetInventoryItemAtlas(entry.tex, true)
        end

        if atlas ~= nil then
            btn.image:SetTint(1, 1, 1, 1)
            btn:SetTextures(atlas, entry.tex)
            return btn
        end
    end

    -- 兜底 2：普通图标解析
    local atlas, tex = WIT_ResolvePrefabIcon(prefab)

    if atlas ~= nil and tex ~= nil then
        btn.image:SetTint(1, 1, 1, 1)
        btn:SetTextures(atlas, tex)
        return btn
    end

    -- 找不到图标时仍返回透明按钮，避免上层逻辑 nil 报错
    return btn
end

-- 解析通用 UI 图标所在 atlas，供信息页和提示图标复用。
function ResolveIconAtlas(icon)
    -- 尝试用单个 tex 名从 scrapbook、内置图集和库存图集中解析 atlas。
    local function try_one(name)
        if GLOBAL.GetScrapbookIconAtlas then
            local a = GLOBAL.GetScrapbookIconAtlas(name)
            if a then return a end
        end
        local atlases = {"images/scrapbook_icons1.xml", "images/scrapbook_icons2.xml", "images/scrapbook_icons3.xml"}
        for _, a in ipairs(atlases) do
            if GLOBAL.TheSim:AtlasContains(a, name) then return a end
        end
        local ia = GLOBAL.GetInventoryItemAtlas(name,true)
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
