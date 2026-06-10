name = "[JEI] What Is This"
description = "悬浮物品按 R 查看配方来源，按 U 查看用途。支持合成、烹饪双向查询，实时背包材料匹配。\n\nHover over an item and press R to see how to craft it, or U to see what it can be used for.\n\n一个类似 JEI 的饥荒配方查询工具。"
author = "凝筝"
version = "1.0.4"
api_version = 10
client_only_mod = true
dst_compatible = true
all_clients_require_mod = false
priority = 0

-- Workshop 图标
icon_atlas = "images/modicon.xml"
icon = "modicon.tex"

-- 配置项
configuration_options =
{
    {
        name = "LANGUAGE",
        label = "语言 / Language",
        hover = "选择界面语言 / Select UI language",
        options =
        {
            {description = "自动 (Auto)", data = "auto"},
            {description = "中文", data = "zh"},
            {description = "English", data = "en"},
        },
        default = "auto",
    },
    {
        name = "KEY_R",
        label = "R 键 - 来源查询",
        options =
        {
            {description = "R (默认)", data = 114},
            {description = "F", data = 102},
            {description = "T", data = 116},
            {description = "Y", data = 121},
            -- 选常用键
            {description = "C", data = 99},
            {description = "V", data = 118},
        },
        default = 114,
    },
    {
        name = "KEY_U",
        label = "U 键 - 用途查询",
        options =
        {
            {description = "U (默认)", data = 117},
            {description = "F", data = 102},
            {description = "T", data = 116},
            {description = "Y", data = 121},
            {description = "C", data = 99},
            {description = "V", data = 118},
        },
        default = 117,
    },
}
