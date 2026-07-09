-- wit_ui: UI 门面文件，按依赖顺序加载拆分后的 UI 模块
--
-- 这个文件只负责集中导入模块，具体实现放在 scripts/wit_ui_*.lua 中。
-- 下面的加载顺序很重要：先加载共享工具，再加载 UI 组件，
-- 最后加载由这些组件组合出来的高层交互逻辑。

-- 图标和贴图集设置，供后续 UI 模块使用。
modimport("scripts/wit_ui_icons")

-- 共享常量和辅助函数。
modimport("scripts/wit_ui_common")

-- 排序辅助逻辑，供槽位、来源和卡片视图使用。
modimport("scripts/wit_ui_sort")

-- 可复用的 UI 构建模块。
modimport("scripts/wit_ui_slots")
modimport("scripts/wit_ui_sources")
modimport("scripts/wit_ui_cards")
modimport("scripts/wit_ui_categories")

-- 弹窗布局、输入处理，以及最终的信息面板组装逻辑。
modimport("scripts/wit_ui_popup")
modimport("scripts/wit_ui_input")
modimport("scripts/wit_ui_info")
