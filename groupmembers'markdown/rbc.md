## rbc 工作记录 2026.3.6

### 本次修改主题

修复后端 API 边界层中 `snake_case` 与文档约定 `camelCase` 不一致的问题，使当前已实现的 Module 2 接口更贴近 `documents/API_CONTRACT.md` 的定义。

### 已完成内容

- 调整 `backend/app/schemas/clothing_item.py`
  - `PATCH /api/v1/clothing-items/{id}` 请求体改为使用 `finalTags`、`isConfirmed`、`customTags`
  - 保留内部 Python 属性为 `final_tags`、`is_confirmed`、`custom_tags`，通过 Pydantic alias 做对外映射
  - 增加 `extra="forbid"`，拒绝旧的 `snake_case` 入参

- 调整 `backend/app/api/v1/clothing.py`
  - `GET /api/v1/clothing-items` 查询参数改为 `tagKey`、`tagValue`
  - 内部仍传递给 CRUD 层的 `tag_key`、`tag_value`

- 调整 `backend/app/schemas/ai.py`
  - `POST /api/v1/ai/classify` 请求继续使用 `imageUrl`
  - 取消对 `image_url` 的兼容
  - 补充分类接口的响应模型，统一 `predictedTags` 命名

- 调整 `backend/app/api/v1/ai.py`
  - 将 `response_model` 从 `dict` 改为明确的 `ClassifyResponse`
  - 让 FastAPI/OpenAPI 更准确展示分类接口返回结构

### 验证结果

- `python -m compileall backend/app` 通过
- 使用 Pydantic 做了最小验证：
  - `camelCase` 请求字段可以正常解析
  - 旧的 `snake_case` 请求字段会被拒绝

### 影响范围

- 本次只修了当前已经实现的 Module 2 接口命名问题
- 未处理认证、统一错误体、`meta` 字段、`images/provenance` 等其他文档不一致项
