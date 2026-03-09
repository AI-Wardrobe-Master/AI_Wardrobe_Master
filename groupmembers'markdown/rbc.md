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

---

## rbc 工作记录 2026.3.7（未提交修改补充）

### 本次修改主题

补齐前后端联调所需的 Docker 启动链路，并同步修正文档与接口返回细节，使本地联调流程更接近“开箱即用”。

### 已完成内容

- 增加容器化联调入口
  - 新增仓库根目录 `docker-compose.yml`
  - 提供 `db` 与 `backend` 两个服务，统一本地 PostgreSQL 和 FastAPI 启动方式
  - 支持通过环境变量覆盖宿主机端口与 `API_BASE_URL`

- 调整后端镜像启动流程
  - 修改 `backend/Dockerfile`，增加 `PYTHONDONTWRITEBYTECODE` 与 `PYTHONUNBUFFERED`
  - 将容器默认启动命令改为执行 `scripts/docker_start.py`
  - 新增 `backend/scripts/docker_start.py`，负责：
    - 等待数据库就绪
    - 自动执行 `alembic upgrade head`
    - 自动创建固定 demo 用户
    - 创建本地存储目录后再启动 `uvicorn`

- 更新后端和联调说明
  - 更新 `backend/README.md`
  - 补充基于 `docker compose up --build` 的启动说明、端口覆盖方式、日志查看和清理命令
  - 明确 compose 场景下不需要额外复制 `.env`
  - 补充当前 demo 用户和当前认证状态说明

- 调整环境配置说明
  - 更新 `backend/.env.example`
  - 明确该文件主要用于非 Docker 的本地直跑场景
  - 说明 compose 会直接向容器注入环境变量

- 修正接口返回与文档一致性
  - 修改 `backend/app/schemas/clothing_item.py`
  - 在 `ClothingItemResponse` 中补回 `customTags`
  - 修改 `backend/app/api/v1/clothing.py`
  - 让 `GET /api/v1/clothing-items/{id}` 实际返回 `customTags`
  - 更新 `documents/API_CONTRACT.md`
  - 标注当前本地 demo base URL、认证仍为固定 demo 用户
  - 明确创建衣物接口当前实际接收的 multipart 字段为 `front_image`、`back_image`
  - 补充“创建时暂不接收 `customTags`，后续通过 PATCH 编辑”的实现说明
  - 补充详情接口当前会返回 `customTags`

### 影响范围

- 前端或联调同学可以通过一条 `docker compose up --build` 拉起数据库和后端
- 后端容器启动时会自动完成 migration 和 demo 用户准备，减少手工初始化步骤
---

## rbc 工作记录 2026.3.9

### 本次修改主题

将 Module 2 的服装分类从本地 mock 改为可配置的 Roboflow workflow 接入，并收缩当前自动标签范围，只保留模型真实支持的 `category`。

### 已完成内容

- 改造分类服务
  - 修改 `backend/app/services/ai_service.py`
  - 移除原有 mock 分类、mock `style`、mock `season`、mock `audience`
  - 增加 Roboflow workflow 调用逻辑，支持通过环境变量配置 `api_url`、`api_key`、`workspace_name`、`workflow_id`
  - 增加类别归一化和结果解析逻辑，兼容 `t_shirt` / `t-shirt` / `long sleeve` / `outerwear` 等常见变体
  - 当前只将一个主类别写入 `predictedTags`，格式为 `{ "key": "category", "value": "<label>" }`

- 收缩当前支持的 category 范围
  - 当前后端自动分类仅保留：
    `dress`、`hat`、`longsleeve`、`outwear`、`pants`、`shirt`、`shoes`、`shorts`、`t-shirt`
  - 在 `documents/DATA_MODEL.md` 中将其他历史类型先注释为“暂不启用”

- 调整配置与说明
  - 修改 `backend/app/core/config.py`
  - 修改 `backend/.env.example`
  - 修改 `backend/README.md`
  - 新增 Roboflow workflow 相关环境变量说明，默认 `api_url` 对齐为 `https://serverless.roboflow.com`

- 同步接口与数据模型文档
  - 修改 `documents/API_CONTRACT.md`
  - 修改 `documents/DATA_MODEL.md`
  - 将示例中的自动预测结果改为当前实现：仅自动返回 `category`
  - 明确 `season`、`style`、`audience` 由用户后续手动补充到 `finalTags`

### 影响范围

- `POST /api/v1/ai/classify` 与上传流程里的自动分类结果不再混入伪造的 `style` / `season` / `audience`
- 前后端联调时，`predictedTags`/`finalTags` 的初始内容会更贴近当前模型能力
- 若后续需要恢复更多自动标签，应以新增真实模型能力为前提，而不是继续扩展 mock 枚举
