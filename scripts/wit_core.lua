-- wit_core: 数据层加载器
--
-- 这个文件只负责按依赖顺序加载数据层子模块。
-- 真正实现被拆到 scripts/wit_core_*.lua，避免单文件继续膨胀。
--
-- 加载顺序很重要：
--   1. base      定义库存遍历、烹饪 alias、共享 helper。
--   2. indexes   构建制作/烹饪/图鉴/来源索引。
--   3. itemdata  临时采集 prefab 组件属性。
--   4. cooking   烹饪卡片求解、自动填锅、烹饪锅状态。

WIT_CORE = WIT_CORE or {}

modimport("scripts/wit_core_base.lua")
modimport("scripts/wit_core_indexes.lua")
modimport("scripts/wit_core_itemdata.lua")
modimport("scripts/wit_core_cooking.lua")
