-- wit_ui_popup: 弹窗框架、标题、标签、分页与设置入口

-- ============================
-- 弹窗创建 (from wit_popup.lua)
-- ============================

-- 弹窗主体背景宽度。
local POPUP_FRAME_W = 360

-- 弹窗主体背景高度。
local POPUP_FRAME_H = 480

-- 标题区域的 Y 坐标。
local POPUP_TITLE_Y = 196

-- 页签按钮行的 Y 坐标。
local POPUP_TAB_Y = 125

-- 分页控件行的 Y 坐标。
local POPUP_PAGE_Y = -210

-- 设置界面是否已经打开，避免重复 PushScreen。
local WIT_SETTINGS_OPEN = false

-- 当前打开的设置界面引用，用于关闭时释放状态。
local WIT_SETTINGS_ROOT = nil

-- 将上一次关闭弹窗时暂存的记录压入后退栈。
local function _PushPopupHistory()
    if WIT_PrevHistory then
        table.insert(WIT_BACK_STACK, WIT_PrevHistory)
        WIT_FORWARD_STACK = {}
    end
    WIT_PrevHistory = nil
end

-- 准备烹饪上下文，并初始化当前弹窗的全局 UI 状态。
local function _PreparePopupState(name, mode)
    BuildCookContext()
    _PushPopupHistory()

    WIT_NAME = name
    WIT_MODE = mode or "ITEM"
    WIT_PAGE = 1
    -- DST API：GetModConfigData 读取是否显示槽位悬浮详情的配置。
    WIT_HOVER_INFO = GetModConfigData("SHOW_HOVER_INFO")
end

-- 根据当前 prefab 可用的数据，生成本次弹窗要显示的页签列表。
local function _BuildAvailableCategories(name)
    local avail_cats = {}

    if WIT_HasLootSources(name) then table.insert(avail_cats, "SOURCES") end
    if WIT_HasCraftFrom(name) or WIT_HasCraftDeconSource(name) then table.insert(avail_cats, "CRAFT_FROM") end
    if WIT_HasCookFrom(name) then table.insert(avail_cats, "COOK_FROM") end
    if WIT_HasCraftUse(name) then table.insert(avail_cats, "CRAFT_USE") end
    if WIT_HasCookUse(name) then table.insert(avail_cats, "COOK_USE") end

    -- 信息页永远存在，用于展示基础属性和自定义描述。
    table.insert(avail_cats, "INFO")
    return avail_cats
end

-- 为图鉴 Screen 创建专用根节点，保证 popup 显示在图鉴上层。
local function _GetOrCreateScrapbookPopupRoot(scrapbook_screen)
    local popup_root = scrapbook_screen._wit_popup_root
    if popup_root == nil then
        popup_root = scrapbook_screen:AddChild(Widget("WITPopupScreenRoot"))
        popup_root:SetScaleMode(SCALEMODE_PROPORTIONAL)
        popup_root:SetHAnchor(ANCHOR_LEFT)
        popup_root:SetVAnchor(ANCHOR_MIDDLE)
        scrapbook_screen._wit_popup_root = popup_root
    end
    return popup_root
end

-- 包装图鉴关闭逻辑：图鉴关闭时同步关闭 WIT 弹窗并恢复暂停状态。
local function _WrapScrapbookClose(scrapbook_screen)
    if scrapbook_screen._wit_close_wrapped then return end

    local old_close = scrapbook_screen.Close

    -- 在原始 Close 前先收掉 WIT 弹窗，避免残留在已关闭的 Screen 上。
    scrapbook_screen.Close = function(screen, ...)
        if WIT_POPUP ~= nil then ClosePopupAndResume() end
        if old_close then
            return old_close(screen, ...)
        end
    end
    scrapbook_screen._wit_close_wrapped = true
end

-- 解析弹窗应该挂载到哪个父节点：图鉴优先，否则使用玩家 HUD。
local function _ResolvePopupParent()
    local scrapbook_screen = GetActiveScrapbookScreen()
    if scrapbook_screen ~= nil then
        local popup_parent = _GetOrCreateScrapbookPopupRoot(scrapbook_screen)
        _WrapScrapbookClose(scrapbook_screen)
        popup_parent:MoveToFront()
        return popup_parent
    end

    local hud_controls = ThePlayer.HUD.controls
    return hud_controls.left_root or hud_controls
end

-- 根据配置和制作栏开关状态计算弹窗横向位置。
local function _ResolvePopupX()
    local crafting_hud = ThePlayer.HUD.controls.craftingmenu
    local is_open = crafting_hud and crafting_hud:IsCraftingOpen()
    -- DST API：GetModConfigData 读取弹窗位置配置。
    local pos_mode = GetModConfigData("POPUP_POSITION") or "auto"

    if pos_mode == "left" then return 350 end
    if pos_mode == "right" then return 900 end
    return is_open and 881 or 405
end

-- 绘制弹窗背景、四边框和半透明底板。
local function _DrawPopupFrame(crafting_atlas)
    local fill = WIT_POPUP:AddChild(Image(crafting_atlas, "backing.tex"))
    if fill then
        fill:ScaleToSize(POPUP_FRAME_W + 50, POPUP_FRAME_H + 18)
        fill:SetTint(1, 1, 1, 0.5)
        fill:MoveToBack()
    end

    local left_side = WIT_POPUP:AddChild(Image(crafting_atlas, "side.tex"))
    if left_side then
        left_side:SetPosition(-POPUP_FRAME_W / 2 - 29, 1)
        left_side:ScaleToSize(-26, -(POPUP_FRAME_H - 20))
    end

    local right_side = WIT_POPUP:AddChild(Image(crafting_atlas, "side.tex"))
    if right_side then
        right_side:SetPosition(POPUP_FRAME_W / 2 + 29, 1)
        right_side:ScaleToSize(26, POPUP_FRAME_H - 20)
    end

    local top_edge = WIT_POPUP:AddChild(Image(crafting_atlas, "top.tex"))
    if top_edge then
        top_edge:SetPosition(0, 250)
        top_edge:ScaleToSize(POPUP_FRAME_W + 70, 38)
    end

    local bottom_edge = WIT_POPUP:AddChild(Image(crafting_atlas, "bottom.tex"))
    if bottom_edge then
        bottom_edge:SetPosition(0, -248)
        bottom_edge:ScaleToSize(POPUP_FRAME_W + 70, 38)
    end
end

-- 为右上角按钮增加简单悬浮放大效果。
local function _AddHoverScale(btn, factor)
    factor = factor or 1.12
    local old_gain_focus = btn.OnGainFocus
    local old_lose_focus = btn.OnLoseFocus

    -- 鼠标移入按钮时放大，保留原控件焦点行为。
    btn.OnGainFocus = function(self)
        self:SetScale(factor, factor)
        if old_gain_focus then old_gain_focus(self) end
    end

    -- 鼠标移出按钮时还原，保留原控件失焦行为。
    btn.OnLoseFocus = function(self)
        self:SetScale(1, 1)
        if old_lose_focus then old_lose_focus(self) end
    end
end

-- 创建标题左侧物品图标，并复用格子左键来源/右键用途跳转语义。
local function _CreateTitleIcon(name, dispname, crafting_atlas)
    local title_bg = WIT_POPUP:AddChild(Image(crafting_atlas, "slot_bg.tex"))
    if title_bg then
        title_bg:SetPosition(-150, POPUP_TITLE_Y)
        title_bg:SetScale(0.5)
    end
    local title_slot = nil
    -- 识别对应实体的icon
    title_slot = CreateEntityIconWidget(WIT_POPUP, name, 48, -150, POPUP_TITLE_Y)

    if title_slot == nil then return end

    title_slot:SetPosition(-150, POPUP_TITLE_Y)
    title_slot:ForceImageSize(48, 48)
    title_slot.image:SetTint(1, 1, 1, 1)
    title_slot:SetTooltip(dispname)

    local cur_name = WIT_NAME

    -- 标题图标左键打开当前物品的来源页。
    title_slot:SetOnClick(function()
        BuildIndexes()
        ClosePopup()
        CreatePopup(cur_name, "SOURCE")
    end)

    local old_on_control = title_slot.OnControl

    -- 标题图标右键打开当前物品的用途页。
    title_slot.OnControl = function(btn, control, down)
        if down and control == CONTROL_SECONDARY then
            BuildIndexes()
            ClosePopup()
            CreatePopup(cur_name, "USE")
            return true
        end
        return old_on_control(btn, control, down)
    end
end

-- 创建标题文本和标题下方的 Mod 来源说明。
local function _CreateTitleText(name, dispname)
    local title_x = 36
    local title = WIT_POPUP:AddChild(Text(UIFONT, 34))
    if title then
        title:SetString(dispname)
        title:SetPosition(title_x, POPUP_TITLE_Y)
        title:SetHAlign(ANCHOR_LEFT)
        title:SetColour(0.95, 0.88, 0.7, 1)
        title:SetRegionSize(280, 40)
    end

    local mod_src = GetPrefabModName and GetPrefabModName(name)
    if mod_src then
        local src_t = WIT_POPUP:AddChild(Text(NEWFONT, 20))
        if src_t then
            src_t:SetString(WIT_TXT.FMT_MOD_SOURCE:format(mod_src))
            src_t:SetPosition(title_x, POPUP_TITLE_Y - 20)
            src_t:SetHAlign(ANCHOR_LEFT)
            src_t:SetColour(0.45, 0.65, 0.45, 0.9)
            src_t:SetRegionSize(280, 30)
        end
    end
end

-- 创建标题区和内容区之间的细分隔线。
local function _CreateTitleSeparator()
    local sep_top = WIT_POPUP:AddChild(Image("images/global.xml", "square.tex"))
    if sep_top then
        sep_top:SetSize(364, 1)
        sep_top:SetPosition(0, 150)
        sep_top:SetTint(0.3, 0.25, 0.18, 1)
    end
end

-- 创建右上角关闭按钮。
local function _CreateCloseButton()
    local close = WIT_POPUP:AddChild(TextButton())
    if close == nil then return end

    close:SetText("×")
    close:SetTextSize(50)
    close:SetPosition(172, 213)
    close:SetTextColour(0.65, 0.58, 0.45, 1)
    close:SetTextFocusColour(1, 1, 1, 1)
    close:SetOnClick(ClosePopupAndResume)
    _AddHoverScale(close)
end

-- 按当前语言覆盖 Mod 配置项的显示文本。
local function _LocalizeConfigOptions(opts)
    for _, opt in ipairs(opts or {}) do
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

-- 修正语言选项 spinner 宽度，避免中文/英文文本被截断。
local function _ResizeLanguageSpinner(screen)
    for i, opt_w in ipairs(screen.optionwidgets or {}) do
        local opt_data = screen.options and screen.options[i]
        if opt_data and opt_data.name == "LANGUAGE" then
            pcall(function()
                opt_w.spinner:SetWidth(260)
            end)
        end
    end
end

-- 监听设置界面销毁事件，重置设置窗口打开状态。
local function _WatchSettingsDestroy(screen)
    local old_on_destroy = screen.OnDestroy

    -- 设置界面关闭时释放引用，让按钮可以再次打开配置页。
    screen.OnDestroy = function(s)
        if old_on_destroy then old_on_destroy(s) end
        WIT_SETTINGS_OPEN = false
        WIT_SETTINGS_ROOT = nil
    end
end

-- 打开原版 Mod 配置界面，并在打开前应用当前语言的配置项文本。
local function _OpenSettings()
    if WIT_SETTINGS_OPEN then return end

    local mod_info = GLOBAL.KnownModIndex:GetModInfo(modname)
    if mod_info and mod_info.configuration_options then
        _LocalizeConfigOptions(mod_info.configuration_options)
    end

    local ModConfigScreen = require("screens/redux/modconfigurationscreen")
    local screen = ModConfigScreen(modname, true)
    TheFrontEnd:PushScreen(screen)

    WIT_SETTINGS_OPEN = true
    WIT_SETTINGS_ROOT = screen

    _ResizeLanguageSpinner(screen)
    _WatchSettingsDestroy(screen)
end

-- 创建右上角设置按钮，点击后打开原版 Mod 配置界面。
local function _CreateSettingsButton()
    local cfg_btn = WIT_POPUP:AddChild(TextButton())
    if cfg_btn == nil then return end

    cfg_btn:SetText("≡")
    cfg_btn:SetTextSize(42)
    cfg_btn:SetPosition(137, 214)
    cfg_btn:SetTextColour(0.65, 0.58, 0.45, 1)
    cfg_btn:SetTextFocusColour(1, 1, 1, 1)
    cfg_btn:SetTooltip(WIT_TXT.CFG_BTN_TOOLTIP)

    -- 设置按钮只在没有配置界面打开时响应，避免重复 PushScreen。
    cfg_btn:SetOnClick(function()
        if not WIT_SETTINGS_OPEN then
            _OpenSettings()
        end
    end)
    _AddHoverScale(cfg_btn)
end

-- 将内部页签类型转换为当前语言下的显示文本。
local function _GetTabLabel(cat)
    if cat == "SOURCES" then return WIT_TXT.TAB_SOURCES end
    if cat == "CRAFT_FROM" then return WIT_TXT.TAB_CRAFT_FROM or WIT_TXT.TAB_CRAFTING end
    if cat == "COOK_FROM" then return WIT_TXT.TAB_COOK_FROM or WIT_TXT.TAB_COOKING end
    if cat == "CRAFT_USE" then return WIT_TXT.TAB_CRAFT_USE or WIT_TXT.TAB_CRAFTING end
    if cat == "COOK_USE" then return WIT_TXT.TAB_COOK_USE or WIT_TXT.TAB_COOKING end
    return WIT_TXT.TAB_INFO
end

-- 创建顶部页签按钮，并把按钮引用保存给 SelectCategory 更新状态。
local function _CreateTabs()
    WIT_TAB_BTNS = {}

    for i, cat in ipairs(WIT_AVAIL_CATS) do
        local tab_btn = WIT_POPUP:AddChild(TextButton())
        if tab_btn then
            local compact = #WIT_AVAIL_CATS > 4
            tab_btn:SetText(_GetTabLabel(cat))
            tab_btn:SetTextSize(compact and 21 or 26)
            tab_btn:SetPosition((i - (#WIT_AVAIL_CATS + 1) / 2) * (compact and 72 or 100), POPUP_TAB_Y)

            -- 点击页签时重置页码并刷新当前内容区。
            tab_btn:SetOnClick(function()
                SelectCategory(cat, true)
            end)
            WIT_TAB_BTNS[cat] = tab_btn
        end
    end
end

-- 创建内容容器；具体卡片由 SelectCategory/RenderContent 管理。
local function _CreateContentRoot()
    WIT_CONTENT = WIT_POPUP:AddChild(Widget("c"))
    if WIT_CONTENT then
        WIT_CONTENT:SetPosition(0, 20)
    end
end

-- 创建分页按钮和页码文本。
local function _CreatePagination(crafting_atlas)
    WIT_PG_PREV = WIT_POPUP:AddChild(ImageButton(crafting_atlas, "scrollbar_arrow_down.tex", "scrollbar_arrow_down_hl.tex"))
    if WIT_PG_PREV then
        WIT_PG_PREV:SetScale(0.4)
        WIT_PG_PREV:SetPosition(-40, POPUP_PAGE_Y)
        WIT_PG_PREV:SetRotation(90)

        -- 上一页：修改页码后让当前页签重新渲染。
        WIT_PG_PREV:SetOnClick(function()
            WIT_PAGE = WIT_PAGE - 1
            SelectCategory(WIT_CUR_CAT, false)
        end)
    end

    WIT_PG_TEXT = WIT_POPUP:AddChild(Text(NEWFONT, 20))
    if WIT_PG_TEXT then
        WIT_PG_TEXT:SetString("1 / 1")
        WIT_PG_TEXT:SetPosition(0, POPUP_PAGE_Y)
        WIT_PG_TEXT:SetColour(0.85, 0.78, 0.65, 1)
    end

    WIT_PG_NEXT = WIT_POPUP:AddChild(ImageButton(crafting_atlas, "scrollbar_arrow_down.tex", "scrollbar_arrow_down_hl.tex"))
    if WIT_PG_NEXT then
        WIT_PG_NEXT:SetScale(0.4)
        WIT_PG_NEXT:SetPosition(40, POPUP_PAGE_Y)
        WIT_PG_NEXT:SetRotation(-90)

        -- 下一页：修改页码后让当前页签重新渲染。
        WIT_PG_NEXT:SetOnClick(function()
            WIT_PAGE = WIT_PAGE + 1
            SelectCategory(WIT_CUR_CAT, false)
        end)
    end
end

-- 判断候选页签是否存在于本次可用页签列表中。
local function _CategoryExists(wanted_cat)
    for _, cat in ipairs(WIT_AVAIL_CATS) do
        if cat == wanted_cat then return true end
    end
    return false
end

-- 根据打开模式和调用方偏好，选择弹窗打开时默认展示的页签。
local function _ResolveInitialCategory(mode, preferred_cat)
    if preferred_cat ~= nil and _CategoryExists(preferred_cat) then
        return preferred_cat
    end

    local preferred_order = mode == "USE"
        and { "CRAFT_USE", "COOK_USE", "SOURCES", "CRAFT_FROM", "COOK_FROM", "INFO" }
        or { "SOURCES", "CRAFT_FROM", "COOK_FROM", "CRAFT_USE", "COOK_USE", "INFO" }

    for _, wanted in ipairs(preferred_order) do
        if _CategoryExists(wanted) then
            return wanted
        end
    end

    return WIT_AVAIL_CATS[1]
end

-- 创建 WIT 主弹窗，组装标题、标签、分页和初始内容。
function CreatePopup(name, mode, preferred_cat)
    -- 准备：构建烹饪上下文，初始化弹窗状态与导航历史。
    _PreparePopupState(name, mode)

    -- 页签：根据当前 prefab 的数据生成可展示页签。
    WIT_AVAIL_CATS = _BuildAvailableCategories(name)
    if #WIT_AVAIL_CATS == 0 then return end

    -- 挂载：确定弹窗父节点，并创建主 Widget。
    local popup_parent = _ResolvePopupParent()
    -- 把创建出来的弹窗保存到全局变量里，后面绘制标题、按钮、分页时都会往 WIT_POPUP 里面加子控件
    WIT_POPUP = popup_parent:AddChild(Widget("WITPopup"))
    if WIT_POPUP == nil then return end

    -- 布局：根据配置和当前 HUD 状态设置弹窗坐标。
    WIT_POPUP:SetPosition(_ResolvePopupX(), 35)

    -- 资源：准备渲染弹窗所需的图集和显示名称。
    local crafting_atlas = resolvefilepath("images/crafting_menu.xml")
    local dispname = CN(name) or name

    -- 绘制：创建外框、标题区、按钮、页签和分页控件。
    _DrawPopupFrame(crafting_atlas)
    _CreateTitleIcon(name, dispname, crafting_atlas)
    _CreateTitleText(name, dispname)
    _CreateTitleSeparator()
    _CreateCloseButton()
    _CreateSettingsButton()
    _CreateTabs()
    _CreateContentRoot()
    _CreatePagination(crafting_atlas)

    -- 内容：选择初始页签并渲染内容。
    SelectCategory(_ResolveInitialCategory(mode, preferred_cat), true)

    -- 暂停：根据配置暂停世界，避免打开 UI 时游戏继续流逝。
    WIT_PauseWorldForPopup()
end
