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

#### 2.2 AI 分类服务（Roboflow 接入）

- 实现 `app/services/ai_service.py`：通过 Roboflow workflow 对上传图片进行分类
- 定义 Tag 结构：`{key, value}`，无置信度
- 当前自动分类主要返回后端支持的 `category` 标签
- style/season/audience 由用户手动选择（2.3.2 已移除）
- 若 Roboflow 配置缺失或调用失败，上传流程会继续创建衣物，但 predictedTags 为空

#### 2.3 可配置属性（style、season、audience）

- **2.3.1** 定义并实现属性类别：`GET /api/v1/attributes/options` 返回 style、season、audience、category、color、pattern 预定义选项
- **2.3.2** 基于图像自动分配：已移除，不做
- **2.3.3** 手动调整编辑界面：ClothingResultScreen 增加 Tags 展示与 `_TagEditScreen` 编辑页，下拉选择 + 多选 chips

#### 2.4 搜索服务

- 实现 `app/services/search_service.py` 和 `app/crud/clothing.py` 中搜索逻辑
- 搜索仅使用 `final_tags`，不使用 `predicted_tags`
- 支持多 tag 过滤：同 key 为 OR，不同 key 为 AND

#### 2.5 API 端点

- `PATCH /api/v1/clothing-items/:id`：更新 `finalTags`、`isConfirmed` 等
- `GET /api/v1/clothing-items`：支持 `source`、`tagKey`、`tagValue`、`search` 过滤
- `POST /api/v1/clothing-items/search`：支持 `query`、`filters.tags`、`filters.source`
- `GET /api/v1/attributes/options`：返回 style、season、audience 等预定义选项（2.3.1）

#### 2.6 对接文档

- 编写 `backend/COORDINATION.md`：列出与 Module 1、Auth、AI 模型选型相关对接项
- 提供 `scripts/init_schema.sql` 建表脚本

### 3. 待定 / 风险项

- **AI 模型配置**：Roboflow 需要配置 `ROBOFLOW_API_KEY`、`ROBOFLOW_WORKSPACE_NAME`、`ROBOFLOW_WORKFLOW_ID`
- **颜色/图案识别**：当前仍未接入真实模型，后续可接 colorthief / Pillow K-Means / 轻量 CNN
- **卡包封面**：前端 `coverImage` 仍按现有字符串传递，后端语义更接近 blob hash，后续可补独立上传流程

### 4. 主要文件

- `backend/app/services/ai_service.py` - AI 分类（Roboflow workflow）
- `backend/app/services/search_service.py` - 搜索
- `backend/app/api/v1/attributes.py` - 属性选项 API（2.3.1）
- `backend/app/api/v1/clothing.py` - 服装 CRUD 与搜索 API
- `backend/app/api/v1/imports.py` - 卡包导入、取消导入、导入历史
- `backend/app/schemas/imports.py` - 导入请求/响应契约
- `ai_wardrobe_app/lib/ui/screens/capture/clothing_result_screen.dart` - 标签展示与编辑（2.3.3）
- `ai_wardrobe_app/lib/services/clothing_api_service.dart` - updateClothingItem、getAttributeOptions、searchClothingItems、getModelUrl
- `ai_wardrobe_app/lib/services/creator_api_service.dart` - 创作者列表/详情/资料更新对接
- `ai_wardrobe_app/lib/services/card_pack_api_service.dart` - 卡包 CRUD、popular、share、publish、archive 对接
- `ai_wardrobe_app/lib/services/import_api_service.dart` - 卡包导入、取消导入、导入历史
- `ai_wardrobe_app/lib/services/outfit_preview_api_service.dart` - 试穿任务 API 封装
- `ai_wardrobe_app/lib/services/styled_generation_api_service.dart` - 风格生成 API 封装
- `backend/COORDINATION.md` - 队友对接清单

### 5. 本地启动

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

API 文档：http://localhost:8000/docs

---

### 6. 合并 main 后完成度对比（3月七日更新）

已将主分支 `main` 合并到 `feature/wkd-module2`。主分支包含 Module 1（gch/rbc 等）的完整实现，Module 2 与流水线已打通。对照 USER_STORIES 的完成情况如下：

| User Story | 验收标准 | 状态 | 说明 |
|------------|----------|------|------|
| **US-2.1** 自动分类 | AI 返回 Tag[]，无置信度；创建后自动分类 | ✅ 流程就绪 | `clothing_pipeline` 已调用 `ai_service.classify_bytes()`；当前接 Roboflow category |
| **US-2.2** 颜色/图案 | 检测主次色、图案类型；可手动编辑 | ⚠️ 未完全实现 | 颜色/图案真实识别仍待接入 |
| **US-2.3** 额外属性 | style、season、audience 可配置；手动选择 | ✅ | GET /attributes/options + 编辑界面完成；2.3.2 自动分配已移除 |
| **US-2.4** 手动确认 | 可查看 predictedTags、编辑 finalTags、持久化 | ✅ | PATCH 接口完整，predictedTags 不可改 |
| **US-2.5** 快速搜索 | &lt;1s，基于 finalTags，支持多过滤 | ✅ | search_service + crud 已实现 |

#### 仍未完成项（Module 2 范围）

| 项目 | 当前状态 | 待办 |
|------|----------|------|
| AI 品类分类 | 已接 Roboflow workflow | 配置 API Key / Workspace / Workflow |
| 颜色检测 | Mock 固定 blue/white | colorthief / Pillow K-Means 等 |
| 图案识别 | Mock 固定 striped | 规则或轻量 CNN |
| Auth | 已接 JWT Bearer | 继续完善权限边界与异常提示 |
| 低置信度处理 | 无 | 内部记录策略（可选） |

#### 主分支新增能力（已合并）

- Module 1：拍照 → 去背景 → 3D 生成 → 8 角度渲染 → 持久化
- `POST /clothing-items` 上传 + 异步 pipeline
- `GET /clothing-items/{id}/processing-status` 进度查询
- `POST /clothing-items/{id}/retry` 失败重试
- Storage（S3/MinIO/Local）、Alembic 迁移、Docker Compose

---

### 7. 2.3 完成说明（3月七日更新）

已完成 2.3.1 和 2.3.3，2.3.2 按需求移除：

- **2.3.1**：`GET /attributes/options` 返回 style、season、audience 等预定义选项
- **2.3.2**：基于图像自动分配 → **已移除**，不做
- **2.3.3**：ClothingResultScreen 标签区 + `_TagEditScreen` 编辑页，支持下拉选择与多选 chips

---

### 8. 前后端连接补齐（4月29日更新）

本次在合并远端 `main` 后，针对前端 service 与后端 FastAPI 契约做了一轮补齐，目标是让已有页面不再因为字段不一致长期走本地兜底，同时把后端已有但前端未封装的接口接到 service 层。

#### 8.1 已修复的契约问题

- 创作者列表：前端从兼容 `data.creators` 调整为兼容后端实际返回的 `data.items`
- 创作者详情：`Creator.fromJson` 同时支持 `userId` 和后端返回的 `id`
- 创作者简介：兼容列表接口中的 `bioSummary`
- 卡包导入：前端 `POST /imports/card-pack` 改为发送 `card_pack_id`
- 后端 `ImportCardPackRequest` 同时支持 `card_pack_id` 和 `cardPackId`
- 卡包创建：前端显式限制当前后端支持的 `CLOTHING_COLLECTION` 类型，避免误传 `OUTFIT` 造成 422

#### 8.2 新增 / 补齐的接口连接

- 后端新增 `GET /api/v1/imports/history`
  - 返回 `data.imports`
  - 字段包含 `id`、`userId`、`cardPackId`、`cardPackName`、`creatorId`、`creatorName`、`itemCount`、`importedAt`
- 前端新增 `ImportApiService.unimportCardPack`
- 前端新增 `ClothingApiService.searchClothingItems`
- 前端新增 `ClothingApiService.getModelUrl`
- 前端补齐 `CardPackApiService`
  - `listPopularCardPacks`
  - `getCardPackByShareId`
  - `updateCardPack`
  - `archiveCardPack`
  - `deleteCardPack`
- 前端新增 `CreatorApiService.updateCreator`
- 前端新增 `OutfitPreviewApiService`
  - 创建试穿任务
  - 查询任务列表
  - 查询任务详情
  - 保存试穿结果
- 前端新增 `StyledGenerationApiService`
  - 创建风格生成任务
  - 查询生成历史
  - 查询生成详情
  - 重试失败任务
  - 删除生成任务

#### 8.3 新增测试与验证

- 新增 `backend/tests/test_imports_contract.py`
  - 验证导入请求同时支持 snake_case 与 camelCase
  - 验证 `GET /imports/history` 返回前端需要的字段结构
- 已通过：
  - `python -m py_compile backend/app/api/v1/imports.py backend/app/schemas/imports.py backend/tests/test_imports_contract.py`
  - `git diff --check`
  - Cursor lints 检查：前端改动文件无报错
- 当前本机环境缺少 `pytest`、`fastapi`、`dart`、`flutter` 命令，因此未能运行完整后端测试和 Flutter analyze / format

#### 8.4 当前结论

核心前后端连接已经基本补齐：

- Auth / Me / Clothing / Attributes / Wardrobe / CardPack / Creator / Imports 主链路已对齐
- Outfit Preview 与 Styled Generation 已完成 service 层连接
- 仍未做完整 UI 流程补齐，相关能力目前属于“前端可调用 API，页面入口后续再接”
