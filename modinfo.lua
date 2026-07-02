name = "[JEI] What Is This"
description = "悬浮物品按 R 查看配方来源，按 U 查看用途。支持合成、烹饪双向查询，实时背包材料匹配。\n\nHover over an item and press R to see how to craft it, or U to see what it can be used for.\n\n一个类似 JEI 的饥荒配方查询工具。\n\n[v1.3.6] 合成菜单详情面板图标支持左/右键+悬浮 R/U 查询；新增导航前进/后退历史功能，默认绑定鼠标侧键\n[v1.3.6] Crafting menu detail icons now support left/right click + hover R/U lookup; added navigation back/forward history, default to mouse side buttons"
author = "凝筝"
version = "1.3.7"
api_version = 10
client_only_mod = true
dst_compatible = true
all_clients_require_mod = false
priority = 0

-- Workshop 图标
icon_atlas = "images/modicon.xml"
icon = "modicon.tex"

-- ============================
-- 全键盘按键定义（供 KEY_R / KEY_U 使用）
-- ============================
local keyboard = {
    { 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12' },
    { '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' },
    { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M' },
    { 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' },
    { 'Space', 'Tab', 'LShift', 'LCtrl', 'LSuper', 'LAlt' },
    { 'RAlt', 'RSuper', 'RCtrl', 'RShift', 'Enter', 'Backspace' },
    { 'BackQuote', 'Minus', 'Equals', 'LeftBracket', 'RightBracket' },
    { 'Backslash', 'Semicolon', 'Quote', 'Period', 'Comma', 'Slash' },
    { 'Up', 'Down', 'Left', 'Right', 'Insert', 'Delete', 'Home', 'End', 'PageUp', 'PageDown' },
}
local numpad = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'Period', 'Divide', 'Multiply', 'Minus', 'Plus' }
local mouse_btns = { '\238\132\130', '\238\132\131', '\238\132\132' }  -- 中键, 侧键1, 侧键2
local key_disabled = { description = 'Disabled', data = 'KEY_DISABLED' }
keys = { key_disabled }
for i = 1, #keyboard do
    for j = 1, #keyboard[i] do
        local key = keyboard[i][j]
        keys[#keys + 1] = { description = key, data = 'KEY_' .. key:upper() }
    end
    keys[#keys + 1] = key_disabled
end
for i = 1, #numpad do
    local key = numpad[i]
    keys[#keys + 1] = { description = 'Numpad ' .. key, data = 'KEY_KP_' .. key:upper() }
end
for i = 1, #mouse_btns do
    keys[#keys + 1] = { description = mouse_btns[i], data = mouse_btns[i] }
end

-- 配置项（运行时由 _OpenSettings 根据语言动态本地化）
configuration_options =
{
    {
        name = "LANGUAGE",
        label = "界面语言",
        hover = "选择 Mod 界面显示语言（切换后需重启游戏生效）",
        options =
        {
            {description = "自动", data = "auto"},
            {description = "中文", data = "zh"},
            {description = "英文", data = "en"},
        },
        default = "auto",
    },
    {
        name = "KEY_R",
        label = "来源查询键",
        hover = "悬浮物品后按下此键，查看该物品的制作/烹饪配方及获取来源",
        options = keys,
        default = "KEY_R",
    },
    {
        name = "KEY_U",
        label = "用途查询键",
        hover = "悬浮物品后按下此键，查看该物品的用途",
        options = keys,
        default = "KEY_U",
    },
    {
        name = "KEY_NAV_BACK",
        label = "导航后退键",
        hover = "在 WIT 弹窗中按下此键，回退到上一个浏览的物品",
        options = keys,
        default = '\238\132\131',
    },
    {
        name = "KEY_NAV_FORWARD",
        label = "导航前进键",
        hover = "在 WIT 弹窗中按下此键，前进到下一个浏览的物品",
        options = keys,
        default = '\238\132\132',
    },
    {
        name = "POPUP_POSITION",
        label = "弹窗位置",
        hover = "信息弹窗的水平显示位置",
        options =
        {
            {description = "自动（跟随合成栏）", data = "auto"},
            {description = "居左", data = "left"},
            {description = "居右", data = "right"},
        },
        default = "auto",
    },
    {
        name = "SHOW_HOVER_INFO",
        label = "图标悬浮详情",
        hover = "在弹窗内悬浮物品图标时，显示该物品的核心属性数值（图标+数字）",
        options =
        {
            {description = "开", data = true},
            {description = "关", data = false},
        },
        default = true,
    },
    {
        name = "AUTO_PAUSE_UI",
        label = "打开UI自动暂停",
        hover = "单人世界中打开本模组主界面时自动暂停世界；多人模式下不生效",
        options =
        {
            {description = "开", data = true},
            {description = "关", data = false},
        },
        default = true,
    },
}
