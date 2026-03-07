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

---

## rbc 工作记录 2026.3.7

### 本次修改主题
完善了数据库
为后端补上可实际使用的 Alembic 数据库迁移能力，并把当前 Module 2 demo 依赖的数据库结构落成第一版 migration。

### 已完成内容

- 补充 Alembic 目录结构
  - 新增 `backend/alembic/env.py`
  - 新增 `backend/alembic/script.py.mako`
  - 新增 `backend/alembic/versions/20260307_000001_init_module2_schema.py`

- 落地第一版初始化迁移
  - 在 migration 中创建 `users`、`clothing_items`、`images`、`models_3d`、`processing_tasks`
  - 补齐外键、级联删除、状态约束、GIN 索引与组合索引
  - 使用 `CREATE EXTENSION IF NOT EXISTS pgcrypto` 支持 `gen_random_uuid()`

- 校正 ORM 与数据库结构的一致性
  - 为 `user_id`、`clothing_item_id` 等字段补充 `ForeignKey`
  - 为 `processing_tasks` 增加 `(clothing_item_id, created_at)` 索引
  - 为 `clothing_items.final_tags`、`custom_tags` 增加 GIN 索引定义
  - 修复 `backend/app/models/user.py` 缺少 `UUID` 导入的问题

- 更新后端使用说明
  - 在 `backend/README.md` 中补充 `alembic upgrade head`、`alembic current`、`alembic revision` 的基本命令

### 验证结果

- `python -m compileall backend/app/models backend/app/services` 通过
- 当前环境未安装 `sqlalchemy` 运行依赖，因此未执行真实的 Alembic 升级命令和数据库连接验证

### 影响范围

- 后端数据库初始化不再只能依赖 `scripts/init_schema.sql`
- 后续表结构变更可以通过 Alembic migration 进行版本化管理
- 当前 Module 2 demo 所需的核心表结构已经有可追踪的迁移起点
