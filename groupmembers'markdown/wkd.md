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
- Mock 仅返回 category、color、pattern；style/season/audience 由用户手动选择（2.3.2 已移除）
- 待替换：接入实际开源分类模型（待选型）

#### 2.3 可配置属性（style、season、audience）

- **2.3.1** 定义并实现属性类别：`GET /api/v1/attributes/options` 返回 style、season、audience、category、color、pattern 预定义选项
- **2.3.2** 基于图像自动分配：已移除，不做
- **2.3.3** 手动调整编辑界面：ClothingResultScreen 增加 Tags 展示与 `_TagEditScreen` 编辑页，下拉选择 + 多选 chips

#### 2.4 搜索服务

- 实现 `app/services/search_service.py` 和 `app/crud/clothing.py` 中搜索逻辑
- 搜索仅使用 `final_tags`，不使用 `predicted_tags`
- 支持多 tag 过滤：同 key 为 OR，不同 key 为 AND

#### 2.5 API 端点

- `POST /api/v1/ai/classify`：输入 `imageUrl`，返回 `predictedTags`
- `PATCH /api/v1/clothing-items/:id`：更新 `finalTags`、`isConfirmed` 等
- `GET /api/v1/clothing-items`：支持 `source`、`tagKey`、`tagValue`、`search` 过滤
- `POST /api/v1/clothing-items/search`：支持 `query`、`filters.tags`、`filters.source`
- `GET /api/v1/attributes/options`：返回 style、season、audience 等预定义选项（2.3.1）

#### 2.6 对接文档

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
- `backend/app/api/v1/attributes.py` - 属性选项 API（2.3.1）
- `backend/app/api/v1/clothing.py` - 服装 CRUD 与搜索 API
- `ai_wardrobe_app/lib/ui/screens/capture/clothing_result_screen.dart` - 标签展示与编辑（2.3.3）
- `ai_wardrobe_app/lib/services/clothing_api_service.dart` - updateClothingItem、getAttributeOptions
- `backend/COORDINATION.md` - 队友对接清单

### 5. 本地启动

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

API 文档：http://localhost:8000/docs

---

### 6. 合并 main 后完成度对比（2025.3 更新）

已将主分支 `main` 合并到 `feature/wkd-module2`。主分支包含 Module 1（gch/rbc 等）的完整实现，Module 2 与流水线已打通。对照 USER_STORIES 的完成情况如下：

| User Story | 验收标准 | 状态 | 说明 |
|------------|----------|------|------|
| **US-2.1** 自动分类 | AI 返回 Tag[]，无置信度；创建后自动分类 | ✅ 流程就绪 | `clothing_pipeline` 已调用 `ai_service.classify_bytes()`；**⚠️ 仍为 Mock** |
| **US-2.2** 颜色/图案 | 检测主次色、图案类型；可手动编辑 | ⚠️ Mock | 品类/颜色/图案均返回固定值，需接入实际模型 |
| **US-2.3** 额外属性 | style、season、audience 可配置；手动选择 | ✅ | GET /attributes/options + 编辑界面完成；2.3.2 自动分配已移除 |
| **US-2.4** 手动确认 | 可查看 predictedTags、编辑 finalTags、持久化 | ✅ | PATCH 接口完整，predictedTags 不可改 |
| **US-2.5** 快速搜索 | &lt;1s，基于 finalTags，支持多过滤 | ✅ | search_service + crud 已实现 |

#### 仍未完成项（Module 2 范围）

| 项目 | 当前状态 | 待办 |
|------|----------|------|
| AI 品类分类 | Mock 固定返回 T_SHIRT | 选型并接入真实模型 |
| 颜色检测 | Mock 固定 blue/white | colorthief / Pillow K-Means 等 |
| 图案识别 | Mock 固定 striped | 规则或轻量 CNN |
| Auth | `get_current_user_id()` 固定 UUID | 接入 JWT 校验 |
| 低置信度处理 | 无 | 内部记录策略（可选） |

#### 主分支新增能力（已合并）

- Module 1：拍照 → 去背景 → 3D 生成 → 8 角度渲染 → 持久化
- `POST /clothing-items` 上传 + 异步 pipeline
- `GET /clothing-items/{id}/processing-status` 进度查询
- `POST /clothing-items/{id}/retry` 失败重试
- Storage（S3/MinIO/Local）、Alembic 迁移、Docker Compose

---

### 7. 2.3 完成说明（2025.3 更新）

已完成 2.3.1 和 2.3.3，2.3.2 按需求移除：

- **2.3.1**：`GET /attributes/options` 返回 style、season、audience 等预定义选项
- **2.3.2**：基于图像自动分配 → **已移除**，不做
- **2.3.3**：ClothingResultScreen 标签区 + `_TagEditScreen` 编辑页，支持下拉选择与多选 chips
