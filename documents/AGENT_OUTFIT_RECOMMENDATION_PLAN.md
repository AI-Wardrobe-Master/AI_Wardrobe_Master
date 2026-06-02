# AI 衣柜 LangGraph 穿搭推荐 Agent 开发计划

## Summary

在后端新增一个基于 LangGraph 的会话式穿搭推荐 Agent。这个 Agent 不做完全开放式 Codex-style loop，而是采用“外层受控 workflow + 内部 LLM tool loop”的结构：系统固定管理会话加载、权限边界、工具执行、缓存、预览生成和最终响应；模型在推荐子流程中自行决定何时调用衣物检索、如何放宽检索条件、如何处理工具失败，以及何时结束并输出结构化穿搭方案。

第一版使用 OpenAI-compatible LLM provider，适配硅基流动、OpenRouter 等服务。衣物天气适配不新增独立 `weather` 字段，而是放入受控 `final_tags`；天气标签必须来自后端 taxonomy，不能由用户或模型自由创建。

Agent 的产品入口应支持持续对话。用户可以先要求“明天通勤穿什么”，再继续说“这套太正式了，换休闲一点”或“不要黑色鞋子”。因此后端不能只实现一次性推荐请求，必须保存 `conversation_id`、历史消息、上一轮推荐和本轮临时约束。

## Key Changes

- 新增 Agent API：
  - `POST /api/v1/agent/outfit-recommendation`
  - 保留为单次推荐和开发调试入口。
  - 输入包含用户自然语言需求、可选城市/日期、可选 `wardrobeId`、是否生成预览图。
  - 输出结构化搭配推荐、衣物列表、推荐理由、天气依据、偏好依据、预览状态和降级说明。
- 新增会话式 Agent API：
  - `POST /api/v1/agent/chat`
  - 输入包含 `conversationId` 可选、用户消息、可选城市/日期、可选 `wardrobeId`、是否生成预览图。
  - 首轮请求由后端创建会话；后续请求通过 `conversationId` 读取历史上下文和上一轮推荐。
  - 输出包含 `conversationId`、assistant 消息、当前结构化穿搭推荐、工具执行 trace、预览状态和降级说明。
- 新增 LangGraph workflow：
  - `load_conversation_context`
  - `get_weather`
  - `retrieve_preference_memory`
  - `outfit_agent_loop`
  - `generate_outfit_preview`
  - `persist_conversation_turn`
  - `final_response`
- 新增 LLM tool-calling adapter：
  - 支持 OpenAI-compatible `tools` 请求参数。
  - 支持读取 assistant `tool_calls`。
  - 支持把后端工具执行结果作为 `role=tool` 消息回填。
  - 保留 `complete_json()` 作为简单 JSON 输出能力，但推荐子流程不再依赖单次 JSON 调用。
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
  - `user_id` 后端注入，不暴露给模型。
  - `wardrobe_id` 可选。
  - `source` 可选，限定 `OWNED | IMPORTED`。
  - `category` 可选，限定后端 taxonomy。
  - `tags` 可选，格式为 `[{key, value}]`，只查询 `final_tags`。
  - `limit` 可选，默认 50。
  - 不暴露 `query`、`type`、`weather`。
  - 当模型不指定 `category` 和 `tags` 时，工具做宽召回。
- `search_wardrobe_items` 输出：
  - `items`：候选衣物列表，包含 `id/name/category/previewGarmentCategory/color/material/style/matchedTags`。
  - 不向模型返回 `imageUrl/source/finalTags/customTags/predictedTags`；预览生成通过 `clothing item id` 在后端解析衣物图片。
  - `total`：本次返回数量。
  - `appliedFilters`：实际使用的过滤条件。
  - `messageForAgent`：告诉模型是否结果过少、是否建议放宽条件。
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
- 工具调用缓存：
  - 每轮 Agent run 内维护 `tool_cache`。
  - cache key 使用 `tool_name + user_id + normalized_args`。
  - 相同参数的重复工具调用直接返回缓存结果。
  - 放宽或收紧过滤条件会形成新的 cache key。
  - 缓存只优化本轮执行，不替代数据库和会话持久化。

## Conversation Design

- 前端形态：
  - 聊天窗口用于输入连续自然语言需求。
  - 当前推荐区域展示本轮 outfit、衣物卡片、缺失单品、预览状态。
  - 用户继续说“换休闲一点”“不要白色”“加一件外套”时，前端复用同一个 `conversationId`。
- 后端会话状态：
  - `conversation_id`：一段 Agent 对话的稳定 ID。
  - `messages`：用户和 assistant 的可见聊天记录。
  - `last_recommendation`：上一轮结构化 outfit，用于处理“这套”“刚才那件”等指代。
  - `last_tool_trace`：上一轮工具调用摘要，用于调试，不作为模型唯一事实来源。
  - `temporary_constraints`：本轮或最近几轮对话中的临时约束，例如“不穿黑色鞋子”。
- 数据持久化优先级：
  - 第一版可以只新增会话和消息表，保存聊天记录与结构化推荐快照。
  - LangGraph checkpoint 可以后置；它适合恢复运行中状态，不应该替代产品级聊天记录。

## Implementation Plan

- 后端 Agent 基础设施：
  - 新增 agent router 并挂载到现有 v1 router。
  - 新增会话式 `POST /api/v1/agent/chat`，保留单次推荐接口作为兼容入口。
  - 新增 LangGraph state、节点、条件边、LLM tool loop 和工具执行包装。
  - 扩展 OpenAI-compatible LLM adapter，支持 tool-calling messages。
  - 新增统一工具返回结构：`status / error_code / retryable / message_for_agent / message_for_user / data`。
- 会话持久化：
  - 新增 Agent conversation 表。
  - 新增 Agent message 表。
  - 每轮保存用户消息、assistant 消息、结构化推荐、工具 trace 摘要。
  - 后端读取最近 N 轮消息和上一轮推荐进入 prompt，避免无限增长上下文。
- Taxonomy：
  - 抽出统一 taxonomy 常量，供 `/attributes/options` 和 Agent 工具共用。
  - 扩展 `/attributes/options` 返回 `weatherTypes`、`weatherProfiles`、`previewCategoryMapping`。
  - 在衣物更新和 Agent 检索中校验天气相关 tag 值。
- 推荐子循环：
  - 将当前固定的 `search_wardrobe_items -> compose_outfit` 改为 `outfit_agent_loop`。
  - LLM 每一步可以选择调用 `get_clothing_taxonomy`、`search_wardrobe_items`、`retrieve_preference_memory`。
  - 工具执行结果回填给 LLM，由 LLM 判断是否需要再次检索、放宽条件或直接输出最终推荐。
  - loop 结束条件为模型不再调用工具，并返回符合 schema 的最终 recommendation。
  - 程序仍然校验最终 outfit 中的 clothing id，只允许使用工具返回过的衣物。
- 衣物检索工具：
  - 复用现有 `final_tags` 搜索逻辑。
  - Agent 专用服务返回候选衣物，包含 `id/name/category/previewGarmentCategory/color/material/style/matchedTags`。
  - 当 `tags` 为空时做宽召回。
  - 当结果过少时，工具把失败或低召回状态返回给模型，由模型决定是否放宽条件重试。
- Agent 测试衣物 seed：
  - 使用 `test/clothing/clothing_seed.json` 作为 30 张测试衣物的元数据来源。
  - 使用 `test/clothing/images_no_bg` 中的去背景 PNG 作为衣物图片。
  - 目标测试账号使用邮箱 `00001@gmail.com`，脚本通过该邮箱查询真实 `users.id`，不能把邮箱当作 `user_id` 写入衣物表。
  - 图片通过现有 `BlobService` 写入 blob 存储和 `blobs` 表，不直接绕过存储层。
  - 衣物图片记录使用 `image_type="PROCESSED_FRONT"`，方便后续预览服务优先选用去背景图。
  - 每件测试衣物写入 `custom_tags`：`agent_seed` 和 `seed_id:<seed item id>`，用于幂等更新，避免重复插入。
  - 每件测试衣物写入主衣柜，保证 Agent 默认衣柜检索和后续 `wardrobeId` 过滤都有数据基础。
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

- 可恢复失败进入 `outfit_agent_loop` 内部处理：
  - 城市不明确。
  - 天气 provider 超时。
  - 衣物检索结果过少。
  - 某个 category 完全缺失。
  - 某个天气标签没有匹配衣物。
  - 预览 item/category 不匹配。
  - 工具返回 retryable failure。
- 可恢复失败处理方式：
  - 工具返回 `AgentToolResult`，其中 `messageForAgent` 明确说明失败事实。
  - 后端把工具结果作为 tool message 回填给模型。
  - 模型可以选择重试、放宽过滤条件、换一类衣物，或结束并向用户说明缺失。
- 不可恢复失败转成用户可见降级响应：
  - 数据库不可用。
  - 用户无权限。
  - LLM provider 配置缺失。
  - 预览服务整体不可用。
  - 工具 schema 多次校验失败。
- Runtime 硬限制：
  - 最大图步骤数。
  - 最大 LLM/tool loop 轮数。
  - 单工具最大重试次数。
  - 全局超时。
  - 工具白名单。
  - 工具结果只能由后端执行器产生，模型不能伪造工具结果。
  - 最终 recommendation 必须经过 clothing id allow-list 校验。
  - 如果模型达到工具轮数上限仍继续请求工具，后端关闭 tools 并强制要求模型基于已有工具结果输出最终 JSON。

## Test Plan

- 单元测试：
  - taxonomy 中 category 到 preview slot 的映射。
  - weather taxonomy 和 `weather_profile` 受控值校验。
  - `search_wardrobe_items` 在 tags 为空和有 tags 时的行为。
  - `search_wardrobe_items` 输入 schema 校验，不接受 `query/type/weather`。
  - 工具失败包装和 retryable 判断。
  - 偏好记忆读取服务。
  - tool cache 对相同参数命中，对不同过滤条件不命中。
  - 最终 recommendation 过滤掉未由工具返回的 clothing id。
- 集成测试：
  - “明天上海下雨，推荐一套通勤穿搭”能完成天气、taxonomy、衣物检索、偏好检索、搭配生成。
  - 用户继续说“这套太正式了，换休闲一点”时，Agent 能读取上一轮推荐并生成新方案。
  - 用户继续说“不要黑色鞋子”时，Agent 能把临时约束应用到下一轮推荐。
  - 衣物检索第一次结果过少时，模型能放宽条件再次调用工具。
  - 工具返回 retryable failure 时，模型能重试或生成降级说明。
  - 衣柜缺少某类单品时返回缺失建议。
  - 预览生成失败时返回无图搭配方案。
  - LLM provider 配置缺失时返回明确错误，不进入假推荐。
- 回归测试：
  - 现有 `/clothing-items/search` 仍只基于 `final_tags`。
  - 现有 `/attributes/options` 老字段不破坏。
  - 现有 outfit preview API 不改变请求格式。
  - 现有衣物上传、更新、预览生成流程不受影响。

## Assumptions

- 第一版采用外层受控 LangGraph workflow，推荐子流程使用 LLM tool loop。
- 这个 Agent 是会话式产品能力，不只是单次推荐 API。
- 天气适配第一版存入 `final_tags`，不新增独立 `weather` 数据库列。
- 天气标签由后端 taxonomy 锁定为季节和天气类型的排列组合。
- Agent 使用 OpenAI-compatible provider，以适配硅基流动、OpenRouter 等服务。
- 当前硅基流动 `Pro/deepseek-ai/DeepSeek-V3.2` 已验证支持 OpenAI-compatible `tool_calls` 和 `role=tool` 回填。
- 弱上下文验证中模型曾连续 5 轮继续调用衣柜检索工具；补充后端 taxonomy、合法 tag key 和合法 tag value 后，模型能使用 `weather_type=rain`、`style=business` 并自然停止。
- 即使正确上下文可以显著改善工具参数质量，正式实现仍必须加入最大工具轮数、工具参数校验和强制收束，不能把安全边界交给模型自觉遵守。
- 偏好记忆第一版新增后端表，前端完整偏好管理页面后置。
- Flutter 第一阶段需要提供聊天框，并展示当前结构化推荐结果。
