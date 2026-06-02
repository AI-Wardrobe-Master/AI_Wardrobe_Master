# AI 衣柜 LangGraph 穿搭推荐 Agent 开发计划

## Summary

在后端新增一个基于 LangGraph 的穿搭推荐 Agent。这个 Agent 不做完全开放式 Codex-style loop，而是采用受控业务 workflow：系统按固定阶段编排天气、taxonomy、衣物检索、偏好记忆、搭配生成和预览生成，模型只在意图解析、检索标签选择、搭配决策、失败降级和最终解释中发挥判断作用。

第一版使用 OpenAI-compatible LLM provider，适配硅基流动、OpenRouter 等服务。衣物天气适配不新增独立 `weather` 字段，而是放入受控 `final_tags`；天气标签必须来自后端 taxonomy，不能由用户或模型自由创建。

## Key Changes

- 新增 Agent API：
  - `POST /api/v1/agent/outfit-recommendation`
  - 输入包含用户自然语言需求、可选城市/日期、可选 `wardrobeId`、是否生成预览图。
  - 输出结构化搭配推荐、衣物列表、推荐理由、天气依据、偏好依据、预览状态和降级说明。
- 新增 LangGraph workflow：
  - `parse_request`
  - `get_weather`
  - `get_clothing_taxonomy`
  - `retrieve_preference_memory`
  - `select_search_tags`
  - `search_wardrobe_items`
  - `compose_outfit`
  - `generate_outfit_preview`
  - `final_response`
- 新增 LLM 配置：
  - `LLM_BASE_URL`
  - `LLM_API_KEY`
  - `LLM_MODEL`
  - `LLM_PROVIDER_NAME`
  - 通过 OpenAI-compatible adapter 调用，不绑定单一厂商。
- 新增依赖：
  - `langgraph`
  - `langchain-core`
  - `openai`

## Tool And Data Design

- `search_wardrobe_items` 输入：
  - `user_id` 必填。
  - `wardrobe_id` 可选。
  - `source` 可选，限定 `OWNED | IMPORTED`。
  - `tags` 可选，格式为 `[{key, value}]`，只查询 `final_tags`。
  - `limit` 可选，默认 50。
  - 不暴露 `query`、`type`、`weather`。
- `get_clothing_taxonomy` 输出：
  - 后端支持的 `category` 列表。
  - `category -> preview garmentCategory` 映射。
  - 受控天气适配 taxonomy。
  - 受控季节 taxonomy。
- 衣物分类规则：
  - 衣物实体使用现有 `category`，不使用 `type`。
  - 预览生成使用 `TOP | BOTTOM | SHOES`，由 Agent 在调用预览前根据 taxonomy 映射。
  - 无法映射到预览槽位的衣物可以参与搭配解释，但不传给当前预览工具。
- 天气适配标签：
  - `season`: `spring | summer | fall | winter | all_season`
  - `weather_type`: `clear | cloudy | rain | snow | windy | humid | hot | cold`
  - `weather_profile`: 由后端锁定季节和天气类型的排列组合，例如 `summer_rain`、`winter_snow`、`all_season_clear`
  - 这些值必须由后端 taxonomy 校验，不能自由输入。
  - 存储位置为现有 `final_tags`，例如 `{"key": "weather_profile", "value": "summer_rain"}`。

## Implementation Plan

- 后端 Agent 基础设施：
  - 新增 agent router 并挂载到现有 v1 router。
  - 新增 LangGraph state、节点、条件边和工具执行包装。
  - 新增 OpenAI-compatible LLM adapter。
  - 新增统一工具返回结构：`status / error_code / retryable / message_for_agent / message_for_user / data`。
- Taxonomy：
  - 抽出统一 taxonomy 常量，供 `/attributes/options` 和 Agent 工具共用。
  - 扩展 `/attributes/options` 返回 `weatherTypes`、`weatherProfiles`、`previewCategoryMapping`。
  - 在衣物更新和 Agent 检索中校验天气相关 tag 值。
- 衣物检索：
  - 复用现有 `final_tags` 搜索逻辑。
  - Agent 专用服务返回候选衣物，包含 `id/imageUrl/category/material/style/finalTags/customTags`。
  - 当 `tags` 为空时做宽召回。
  - 当结果过少时，LangGraph 允许放宽标签重试一次。
- 偏好记忆：
  - 新增用户偏好记忆表。
  - 存储风格偏好、颜色偏好、避雷项、历史选择反馈。
  - 第一版以后端读取为主，前端完整编辑页面后置。
  - Agent 输出中区分天气依据、衣物事实依据和偏好依据。
- 预览生成：
  - 复用现有 outfit preview 后端。
  - 调用前必须完成 `category -> garmentCategory` 映射。
  - 预览失败时返回无图搭配方案，不能伪造图片 URL。

## Failure Handling

- 可恢复失败进入 LangGraph 内部处理：
  - 城市不明确。
  - 天气 provider 超时。
  - 衣物检索结果过少。
  - 预览 item/category 不匹配。
- 不可恢复失败转成用户可见降级响应：
  - 数据库不可用。
  - 用户无权限。
  - LLM provider 配置缺失。
  - 预览服务整体不可用。
  - 工具 schema 多次校验失败。
- Runtime 硬限制：
  - 最大图步骤数。
  - 单工具最大重试次数。
  - 全局超时。
  - 工具白名单。
  - 工具结果只能由后端执行器产生，模型不能伪造工具结果。

## Test Plan

- 单元测试：
  - taxonomy 中 category 到 preview slot 的映射。
  - weather taxonomy 和 `weather_profile` 受控值校验。
  - `search_wardrobe_items` 在 tags 为空和有 tags 时的行为。
  - 工具失败包装和 retryable 判断。
  - 偏好记忆读取服务。
- 集成测试：
  - “明天上海下雨，推荐一套通勤穿搭”能完成天气、taxonomy、衣物检索、偏好检索、搭配生成。
  - 衣柜缺少某类单品时返回缺失建议。
  - 预览生成失败时返回无图搭配方案。
  - LLM provider 配置缺失时返回明确错误，不进入假推荐。
- 回归测试：
  - 现有 `/clothing-items/search` 仍只基于 `final_tags`。
  - 现有 `/attributes/options` 老字段不破坏。
  - 现有 outfit preview API 不改变请求格式。
  - 现有衣物上传、更新、预览生成流程不受影响。

## Assumptions

- 第一版采用受控 LangGraph workflow，不做完全开放式 ReAct/Codex-style loop。
- 天气适配第一版存入 `final_tags`，不新增独立 `weather` 数据库列。
- 天气标签由后端 taxonomy 锁定为季节和天气类型的排列组合。
- Agent 使用 OpenAI-compatible provider，以适配硅基流动、OpenRouter 等服务。
- 偏好记忆第一版新增后端表，前端完整偏好管理页面后置。
- Flutter 第一阶段只需要调用 Agent API 并展示结构化结果。
