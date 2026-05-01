# AI Wardrobe Master - Backend

## 已实现的 API 模块

### Module 2: 衣物数字化
- `POST /api/v1/clothing-items` - 创建衣物（上传图片，异步处理）
- `PATCH /api/v1/clothing-items/:id` - 标签确认/编辑
- `GET /api/v1/clothing-items` - 列表（支持 tag 过滤）
- `POST /api/v1/clothing-items/search` - 搜索（使用 finalTags）

### Module 5: DreamO 个性化穿搭生成
- `POST /api/v1/styled-generations` - 创建生成任务（上传自拍 + 选择衣物 + 场景描述）
- `GET /api/v1/styled-generations/:id` - 查询生成详情
- `GET /api/v1/styled-generations` - 分页列出历史生成记录
- `POST /api/v1/styled-generations/:id/retry` - 重试失败的生成
- `DELETE /api/v1/styled-generations/:id` - 删除生成记录

## 快速启动

```bash
# 1. 创建虚拟环境并安装依赖
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# 2. 配置环境变量（复制 .env.example 为 .env）

# Roboflow workflow 至少需要：
# ROBOFLOW_API_URL=https://serverless.roboflow.com
# ROBOFLOW_API_KEY=<your-key>
# ROBOFLOW_WORKSPACE_NAME=bcs-workspace-vo3qr
# ROBOFLOW_WORKFLOW_ID=custom-workflow

# 3. 初始化数据库（需先启动 PostgreSQL）
alembic upgrade head

# 如需直接初始化一套空库，也可执行
psql -U wardrobe_user -d wardrobe_db -f scripts/init_schema.sql

# 4. 启动服务
uvicorn app.main:app --reload --port 8000

# 5. 启动 Celery worker（处理衣物数字化长任务）
celery -A app.core.celery_app.celery_app worker -Q clothing_pipeline --loglevel=info

# 6. 启动 DreamO 专用 Celery worker（需要单独终端）
celery -A app.core.celery_app.celery_app worker -Q styled_generation --loglevel=info

# 7. 启动 DreamO 推理服务（需要 GPU，在 DreamO/ 目录下用独立虚拟环境）
# cd ../DreamO && python -m venv venv && source venv/bin/activate
# pip install -r requirements.txt
# uvicorn server:app --port 9000
```

API 文档：http://localhost:8000/docs

## 前端联调用 Docker

前端开发者推荐直接在仓库根目录运行：

```bash
# Outfit Preview 功能需要 DashScope API key
export DASHSCOPE_API_KEY=sk-your-key-here

docker compose up --build
```

这套 compose 会自动完成：

- 启动 PostgreSQL 16
- 启动 Redis（Celery broker）
- 等待数据库 ready
- 自动执行 `alembic upgrade head`
- 自动准备一个可登录的开发 seed user
- 启动 FastAPI 服务
- 启动 Celery clothing_pipeline worker
- 启动 Celery styled_generation worker
- 启动 DreamO 推理服务（需要 NVIDIA GPU）

启动后可直接访问：

- API 文档：`http://localhost:8000/docs`
- API Base URL：`http://localhost:8000/api/v1`

如果本机的 `5432` 或 `8000` 已被占用，可以临时覆盖端口：

```bash
POSTGRES_HOST_PORT=55432 BACKEND_HOST_PORT=18000 \
API_BASE_URL=http://localhost:18000 \
docker compose up --build
```

常用命令：

```bash
# 后台启动
docker compose up --build -d

# 查看日志
docker compose logs -f backend

# 停止服务
docker compose down

# 停止并清空数据库与本地存储
docker compose down -v
```

说明：

- `docker-compose.yml` 位于仓库根目录，不在 `backend/` 目录下
- compose 已经注入数据库连接参数，不需要再手动复制 `.env`
- `DASHSCOPE_API_KEY` 用于 Outfit Preview（穿搭预览）功能，调用阿里云 DashScope wan2.6-image 模型生成试穿效果图。需要在阿里云 DashScope 控制台获取国内版 API key。不设置此项则 outfit preview 功能不可用，其余功能不受影响。
- 本地 seed user 默认信息：
  - `email`: `demo@example.com`
  - `password`: `demo123456`
  - `user_id`: `00000000-0000-0000-0000-000000000001`

## 单独运行 Docker 镜像

如果不使用 compose，后端镜像仍然依赖一个可连接的 PostgreSQL：

```bash
docker build -t ai-wardrobe-backend ./backend
docker run --rm -p 8000:8000 \
  -e POSTGRES_SERVER=<db-host> \
  -e POSTGRES_USER=wardrobe_user \
  -e POSTGRES_PASSWORD=wardrobe_pass \
  -e POSTGRES_DB=wardrobe_db \
  -e POSTGRES_PORT=5432 \
  -e LOCAL_STORAGE_PATH=/app/storage \
  -e API_BASE_URL=http://localhost:8000 \
  -e DASHSCOPE_API_KEY=sk-your-key-here \
  ai-wardrobe-backend
```

镜像启动时会自动等待数据库、执行 migration、准备 seed user，然后再启动 API。

## 当前实现说明

- `POST /api/v1/clothing-items`
  - 当前实际接收的 multipart 字段是：`front_image`、`back_image`、`name`、`description`
  - 当前实现不在创建时接收 `customTags`
  - 当前接口只负责保存原图、创建 `PENDING` 的处理任务并入队，不会在 API 请求里同步跑完整 3D pipeline
  - `customTags` 属于用户可选补充信息，当前通过 `PATCH /api/v1/clothing-items/{id}` 添加或修改
- `GET /api/v1/clothing-items/{id}` 当前会返回 `customTags`
- `POST /api/v1/clothing-items` 入队后，worker 会异步完成背景去除、分类、3D 生成和多角度渲染
- 当前自动分类只写入 `category` 标签，且仅接受 Roboflow workflow 已支持的值：
  `dress`、`hat`、`longsleeve`、`outwear`、`pants`、`shirt`、`shoes`、`shorts`、`t-shirt`
- `season`、`style`、`audience` 当前不再由后端自动生成，改为用户后续手动补充到 `finalTags`
- 当前受保护接口需要 Bearer JWT
- 先调用 `POST /api/v1/auth/login` 获取 token，再访问衣物/衣橱接口

## 处理失败与重试

- 最新任务状态通过 `GET /api/v1/clothing-items/{id}/processing-status` 轮询。
- 如果任务失败：
  - 保留 `clothing_items`、`processing_tasks`、`original_front`、`original_back`
  - 清理 `processed_*`、`model.glb`、`angle_*` 及其数据库记录
- `POST /api/v1/clothing-items/{id}/retry` 仅允许重试最新的 `FAILED` 任务。
- retry 会新建一个 task，复用原图，并在重新执行前清空旧的派生产物。
- 同一件衣物同一时刻最多只有一个活跃任务（`PENDING` 或 `PROCESSING`）。

登录示例：

```bash
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo123456"}'
```

注册示例：

```bash
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"new_user","email":"new_user@example.com","password":"secret123"}'
```

注册成功后会直接返回 JWT，可立刻用于访问受保护接口。

## 数据库迁移

```bash
# 迁移到最新版本
alembic upgrade head

# 查看当前迁移版本
alembic current

# 新建迁移文件（后续开发使用）
alembic revision -m "describe change"
```

## 队友对接

详见 [COORDINATION.md](./COORDINATION.md)
