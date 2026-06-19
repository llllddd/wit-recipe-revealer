name = "[JEI] What Is This"
description = "悬浮物品按 R 查看配方来源，按 U 查看用途。支持合成、烹饪双向查询，实时背包材料匹配。\n\nHover over an item and press R to see how to craft it, or U to see what it can be used for.\n\n一个类似 JEI 的饥荒配方查询工具。"
author = "凝筝"
version = "1.3.3"
api_version = 10
client_only_mod = true
dst_compatible = true
all_clients_require_mod = false
priority = 0

-- Workshop 图标
icon_atlas = "images/modicon.xml"
icon = "modicon.tex"

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
        hover = "悬浮物品后按下此键，查看该物品的制作/烹饪配方",
        options =
        {
            {description = "Z", data = 122},
            {description = "X", data = 120},
            {description = "C", data = 99},
            {description = "V", data = 118},
            {description = "B", data = 98},
            {description = "N", data = 110},
            {description = "M", data = 109},
            {description = "F", data = 102},
            {description = "G", data = 103},
            {description = "H", data = 104},
            {description = "J", data = 106},
            {description = "K", data = 107},
            {description = "L", data = 108},
            {description = "Q", data = 113},
            {description = "R (默认)", data = 114},
            {description = "T", data = 116},
            {description = "Y", data = 121},
            {description = "U", data = 117},
            {description = "I", data = 105},
            {description = "O", data = 111},
            {description = "P", data = 112},
        },
        default = 114,
    },
    {
        name = "KEY_U",
        label = "用途查询键",
        hover = "悬浮物品后按下此键，查看该物品的用途",
        options =
        {
            {description = "Z", data = 122},
            {description = "X", data = 120},
            {description = "C", data = 99},
            {description = "V", data = 118},
            {description = "B", data = 98},
            {description = "N", data = 110},
            {description = "M", data = 109},
            {description = "F", data = 102},
            {description = "G", data = 103},
            {description = "H", data = 104},
            {description = "J", data = 106},
            {description = "K", data = 107},
            {description = "L", data = 108},
            {description = "Q", data = 113},
            {description = "R", data = 114},
            {description = "T", data = 116},
            {description = "Y", data = 121},
            {description = "U (默认)", data = 117},
            {description = "I", data = 105},
            {description = "O", data = 111},
            {description = "P", data = 112},
        },
        default = 117,
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
}
