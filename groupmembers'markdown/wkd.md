## wkd 工作记录 - Module 2 后端

### 1. 负责范围

负责 **2.0 自动化分类与搜索支持（Automated Classification and Search Support）** 的后端实现，与另外两位同学协作搭建后端。

涉及子模块：
- 2.1 自动将服装物品分类到预定义类型
- 2.2 分配颜色和图案属性
- 2.3 支持额外的可配置服装属性（风格、季节、人群等）
- 2.4 允许手动确认或更正分类结果，并集成搜索支持

### 2. 本次已完成内容

#### 2.1 后端项目骨架

- 搭建 FastAPI 后端 `backend/` 基础结构
- 配置 `app/core/config.py`、`app/db/session.py`
- 定义 `User`、`ClothingItem` 模型，支持 `predicted_tags`、`final_tags`、`is_confirmed`

#### 2.2 AI 分类服务（含 Mock）

- 实现 `app/services/ai_service.py`：`POST /ai/classify` 所需逻辑
- 定义 Tag 结构：`{key, value}`，无置信度
- Mock 分类结果用于联调，预留品类 / 颜色 / 图案识别接口
- 待替换：接入实际开源分类模型（待选型）

#### 2.3 搜索服务

- 实现 `app/services/search_service.py` 和 `app/crud/clothing.py` 中搜索逻辑
- 搜索仅使用 `final_tags`，不使用 `predicted_tags`
- 支持多 tag 过滤：同 key 为 OR，不同 key 为 AND

#### 2.4 API 端点

- `POST /api/v1/ai/classify`：输入 `imageUrl`，返回 `predictedTags`
- `PATCH /api/v1/clothing-items/:id`：更新 `finalTags`、`isConfirmed` 等
- `GET /api/v1/clothing-items`：支持 `source`、`tagKey`、`tagValue`、`search` 过滤
- `POST /api/v1/clothing-items/search`：支持 `query`、`filters.tags`、`filters.source`

#### 2.5 对接文档

- 编写 `backend/COORDINATION.md`：列出与 Module 1、Auth、AI 模型选型相关对接项
- 提供 `scripts/init_schema.sql` 建表脚本

### 3. 待定 / 占位项

- **AI 模型**：品类、颜色、图案的实际模型接入（需调研选型）
- **Auth**：`get_current_user_id()` 当前为占位，需 JWT 解析
- **图片加载**：`_load_image_bytes()` 假定本地路径，若用 S3 需对接 storage 服务

### 4. 主要文件

- `backend/app/services/ai_service.py` - AI 分类（含 Mock）
- `backend/app/services/search_service.py` - 搜索
- `backend/app/api/v1/ai.py` - 分类 API
- `backend/app/api/v1/clothing.py` - 服装 CRUD 与搜索 API
- `backend/COORDINATION.md` - 队友对接清单

### 5. 本地启动

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

API 文档：http://localhost:8000/docs
