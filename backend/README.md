# AI Wardrobe Master - Backend

## Module 2 实现范围

- `POST /api/v1/ai/classify` - AI 服装分类（Roboflow workflow）
- `PATCH /api/v1/clothing-items/:id` - 标签确认/编辑
- `GET /api/v1/clothing-items` - 列表（支持 tag 过滤）
- `POST /api/v1/clothing-items/search` - 搜索（使用 finalTags）

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
```

API 文档：http://localhost:8000/docs

## 前端联调用 Docker

前端开发者推荐直接在仓库根目录运行：

```bash
docker compose up --build
```

这套 compose 会自动完成：

- 启动 PostgreSQL 16
- 等待数据库 ready
- 自动执行 `alembic upgrade head`
- 自动插入固定 demo 用户
- 启动 FastAPI 服务

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
- 当前 demo 用户是固定占位用户，ID 为 `00000000-0000-0000-0000-000000000001`

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
  ai-wardrobe-backend
```

镜像启动时会自动等待数据库、执行 migration、插入 demo 用户，然后再启动 API。

## 当前实现说明

- `POST /api/v1/clothing-items`
  - 当前实际接收的 multipart 字段是：`front_image`、`back_image`、`name`、`description`
  - 当前实现不在创建时接收 `customTags`
  - `customTags` 属于用户可选补充信息，当前通过 `PATCH /api/v1/clothing-items/{id}` 添加或修改
- `GET /api/v1/clothing-items/{id}` 当前会返回 `customTags`
- `POST /api/v1/clothing-items` 创建完成后会自动触发分类流程，初始写入 `predictedTags` 和 `finalTags`
- 当前自动分类只写入 `category` 标签，且仅接受 Roboflow workflow 已支持的值：
  `dress`、`hat`、`longsleeve`、`outwear`、`pants`、`shirt`、`shoes`、`shorts`、`t-shirt`
- `season`、`style`、`audience` 当前不再由后端自动生成，改为用户后续手动补充到 `finalTags`
- 当前认证仍是 demo 占位，使用固定测试用户，不是真实 JWT

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
