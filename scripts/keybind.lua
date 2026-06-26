-- Developed by rtk0c and forked by liolok, adapted for [JEI] What Is This
-- https://github.com/liolok/DST-KeyBind-UI
--
local G = GLOBAL
local C = G.UICOLOURS
local S = G.STRINGS.UI.CONTROLSSCREEN

-- code number => "KEY_*" / mouse emoji / "KEY_KP_*"
local function Raw(key)
    if type(key) ~= "string" then return key end
    local r = G.rawget(G, key)
    if r then return r end
    if key:find("^KEY_KP_") then
        -- numpad keys are stored in KEYBOARD table
        local numpad_map = { KP_0 = 269, KP_1 = 257, KP_2 = 258, KP_3 = 259, KP_4 = 260,
            KP_5 = 261, KP_6 = 262, KP_7 = 263, KP_8 = 264, KP_9 = 265,
            KP_PERIOD = 266, KP_DIVIDE = 267, KP_MULTIPLY = 106,
            KP_MINUS = 109, KP_PLUS = 107 }
        return numpad_map[key:sub(5)]
    end
    -- mouse button emoji
    local mouse = { ['\238\132\130'] = 1002, ['\238\132\131'] = 1005, ['\238\132\132'] = 1006 }
    return mouse[key]
end
-- code number => "KEY_*" / mouse emoji
local str = {}
for _, option in ipairs(modinfo.keys) do
    local key = option.data
    local num = Raw(key)
    if num then str[num] = key end
end
local function Stringify(keycode) return str[keycode] end
-- "KEY_*" / mouse emoji => localized display name or "- No Bind -"
local function Localize(key)
    local num = Raw(key)
    return num and S.INPUTS[1][num] or S.INPUTS[9][2]
end

-- keybind configurations (options that use the `modinfo.keys` list)
local configs = {}
local is_keybind = {}
for _, config in ipairs(modinfo.configuration_options) do
    if config.options == modinfo.keys then
        table.insert(configs, config)
        is_keybind[config.name] = true
    end
end

-- Initialize bindings after game start
local function InitBindings()
    for _, config in ipairs(configs) do
        KeyBind(config.name, Raw(GetModConfigData(config.name)))
    end
end
local AddInit = modinfo.client_only_mod and AddGamePostInit or AddPlayerPostInit
AddInit(InitBindings)

-- BindButton widget: replaces the standard spinner in Mod Config screen
local Image = require('widgets/image')
local ImageButton = require('widgets/imagebutton')
local PopupDialogScreen = require('screens/redux/popupdialog')

local BindButton = Class(require('widgets/widget'), function(self, param)
    Widget._ctor(self, modname .. ':KeyBindButton')
    self.title = param.title
    self.default = param.default
    self.initial = param.initial
    self.OnSet = param.OnSet
    self.OnChanged = param.OnChanged
    self.changed_image = self:AddChild(Image('images/global_redux.xml', 'wardrobe_spinner_bg.tex'))
    self.changed_image:ScaleToSize(param.width, param.height)
    self.changed_image:SetTint(1, 1, 1, 0.3)
    self.changed_image:Hide()
    self.binding_btn = self:AddChild(ImageButton('images/global_redux.xml', 'blank.tex', 'spinner_focus.tex'))
    self.binding_btn:SetOnClick(function() self:PopupKeyBindDialog() end)
    self.binding_btn:ForceImageSize(param.width, param.height)
    self.binding_btn:SetText(Localize(param.initial))
    self.binding_btn:SetTextSize(param.text_size or 30)
    self.binding_btn:SetTextColour(param.text_color or C.GOLD_CLICKABLE)
    self.binding_btn:SetTextFocusColour(C.GOLD_FOCUS)
    self.binding_btn:SetFont(G.CHATFONT)
    self.unbinding_btn = self:AddChild(ImageButton('images/global_redux.xml', 'close.tex', 'close.tex'))
    self.unbinding_btn:SetPosition(param.width / 2 + (param.offset or 10), 0)
    self.unbinding_btn:SetOnClick(function() self:Set('KEY_DISABLED') end)
    self.unbinding_btn:SetHoverText(S.UNBIND)
    self.unbinding_btn:SetScale(0.4, 0.4)
    self.focus_forward = self.binding_btn
end)

function BindButton:Set(key)
    self.binding_btn:SetText(Localize(key))
    self.OnSet(key)
    if key == self.initial then
        self.changed_image:Hide()
    else
        self.OnChanged()
        self.changed_image:Show()
    end
end

function BindButton:PopupKeyBindDialog()
    local function Setup(key)
        self:Set(key)
        TheFrontEnd:PopScreen()
        TheFrontEnd:GetSound():PlaySound('dontstarve/HUD/click_move')
    end
    local buttons = {}
    -- Add mouse buttons if available in options
    local mouse_map = { ['\238\132\130'] = 'MButton', ['\238\132\131'] = 'BButton4', ['\238\132\132'] = 'BButton5' }
    for key, _ in pairs(mouse_map) do
        for _, option in ipairs(modinfo.keys) do
            if key == option.data then
                table.insert(buttons, { text = key, cb = function() Setup(key) end })
                break
            end
        end
    end
    table.insert(buttons, { text = S.CANCEL, cb = function() TheFrontEnd:PopScreen() end })
    local text = S.CONTROL_SELECT .. '\n\n' .. string.format(S.DEFAULT_CONTROL_TEXT, Localize(self.default))
    local dialog = PopupDialogScreen(self.title, text, buttons)
    dialog.OnRawKey = function(_, keycode, down)
        local key = Stringify(keycode)
        if not key or down then return end
        Setup(key)
        return true
    end
    TheFrontEnd:PushScreen(dialog)
end

local BUTTON_NAME = 'keybind_button@' .. modname

-- ModConfigurationScreen Injection: replace spinners with BindButtons
AddClassPostConstruct('screens/redux/modconfigurationscreen', function(self)
    if self.modname ~= modname then return end
    local list = self.options_scroll_list
    local OldApplyDataToWidget = list.update_fn
    list.update_fn = function(context, widget, data, ...)
        OldApplyDataToWidget(context, widget, data, ...)
        local opt = widget.opt
        local spinner = opt.spinner
        opt.focus_forward = spinner
        if opt[BUTTON_NAME] then opt[BUTTON_NAME]:Kill() end
        local config = data and data.option or {}
        if not is_keybind[config.name] then return end
        spinner:Hide()
        local button = BindButton({
            width = 225,
            height = 40,
            text_size = 25,
            text_color = C.GOLD,
            offset = 0,
            title = config.label,
            default = config.default,
            initial = data.initial_value,
            OnSet = function(key)
                self.options[widget.real_index].value = key
                data.selected_value = key
            end,
            OnChanged = function() self:MakeDirty() end,
        })
        button:SetPosition(spinner:GetPosition())
        button:Set(data.selected_value)
        button:Show()
        opt[BUTTON_NAME] = opt:AddChild(button)
        opt.focus_forward = button
    end
    list:RefreshView()
end)

-- OptionsScreen ("Settings > Controls") Injection
local Text = require('widgets/text')
local TEMPLATES = require('widgets/redux/templates')
local OptionsScreen = require('screens/redux/optionsscreen')

local _key = {}  -- config => current key
local function Header(title)
    local h = Widget(modname .. ':KeyBindHeader')
    h.txt = h:AddChild(Text(G.HEADERFONT, 32, title, C.GOLD_SELECTED))
    h.txt:SetPosition(-60, 0)
    h.bg = h:AddChild(TEMPLATES.ListItemBackground(700, 48))
    h.bg:SetImageNormalColour(0, 0, 0, 0)
    h.bg:SetImageFocusColour(0, 0, 0, 0)
    h.bg:SetPosition(-60, 0)
    h.bg:SetScale(1.025, 1)
    h.controlId, h.control = 0, {}
    h.changed_image = { Show = function() end, Hide = function() end }
    h.binding_btn = { SetText = function() end }
    return h
end

local function BindEntry(parent, config)
    local w = Widget(modname .. ':KeyBindEntry')
    local x = -371
    local button_width = 250
    local button_height = 48
    local label_width = 375
    w:SetHoverText(config.hover, { offset_x = -60, offset_y = 60, wordwrap = true })
    w:SetScale(1, 1, 0.75)
    w.bg = w:AddChild(TEMPLATES.ListItemBackground(700, button_height))
    w.bg:SetPosition(-60, 0)
    w.bg:SetScale(1.025, 1)
    w.label = w:AddChild(Text(G.CHATFONT, 28, config.label, C.GOLD_UNIMPORTANT))
    w.label:SetHAlign(G.ANCHOR_LEFT)
    w.label:SetRegionSize(label_width, 50)
    w.label:SetPosition(x + label_width / 2, 0)
    w.label:SetClickable(false)
    w[BUTTON_NAME] = w:AddChild(BindButton({
        width = button_width,
        height = button_height,
        title = config.label,
        default = config.default,
        initial = _key[config],
        OnSet = function(key) _key[config] = key end,
        OnChanged = function() parent:MakeDirty() end,
    }))
    w[BUTTON_NAME]:SetPosition(x + label_width + 15 + button_width / 2, 0)
    w.controlId, w.control = 0, {}
    w.changed_image = { Show = function() end, Hide = function() end }
    w.binding_btn = { SetText = function() end }
    w.focus_forward = w[BUTTON_NAME]
    return w
end

AddClassPostConstruct('screens/redux/optionsscreen', function(self)
    local list = self.kb_controllist
    local items = list.items
    if #configs > 0 then table.insert(items, list:AddChild(Header(modinfo.name))) end
    for _, config in ipairs(configs) do
        _key[config] = GetModConfigData(config.name)
        table.insert(items, list:AddChild(BindEntry(self, config)))
    end
    list:SetList(items, true)
end)

-- Reset to default binds when "Reset Binds" is clicked
local OldLoadDefaultControls = OptionsScreen.LoadDefaultControls
function OptionsScreen:LoadDefaultControls()
    for _, widget in ipairs(self.kb_controllist.items) do
        local button = widget[BUTTON_NAME]
        if button then button:Set(button.default) end
    end
    return OldLoadDefaultControls(self)
end

-- Sync binds to mod config on "Apply" / "Accept Changes"
local OldSave = OptionsScreen.Save
function OptionsScreen:Save(...)
    for config, key in pairs(_key) do
        KeyBind(config.name, Raw(key))
        G.KnownModIndex:SetConfigurationOption(modname, config.name, key)
    end
    G.KnownModIndex:SaveConfigurationOptions(function() end, modname, modinfo.configuration_options, true)
    return OldSave(self, ...)
end
