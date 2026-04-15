# 队友对接清单 (COORDINATION)

> 本文档列出需要与其他队友确认或协作的内容，待对接完成后再统一修改代码。

---

## 一、Module 1 队友（服装数字化与注册）

### 1.1 图片存储与 imageUrl

| 问题 | 当前占位 | 待确认 |
|------|----------|--------|
| 图片存储根路径 | `LOCAL_STORAGE_PATH=./storage` | 实际存储路径？S3/MinIO 配置？ |
| `imageUrl` 格式 | 假设为相对路径，如 `images/item-001-front.jpg` | 实际格式？是否带域名？ |
| 图片加载接口 | `ai_service._load_image_bytes()` 从本地文件读取 | 若用 S3，需要 `storage_service.download()` 或类似接口 |

**影响文件**：`app/core/config.py`、`app/services/ai_service.py`

### 1.2 Clothing 创建流程

| 问题 | 当前状态 | 待确认 |
|------|----------|--------|
| POST /clothing-items 由谁实现？ | 已实现 | 创建时会同步调用 `AIService.classify_bytes()`，并在建 item 时写入 `predicted_tags`、`final_tags` |
| 创建时是否同步调用分类？ | 已明确 | 分类包含在 `POST /clothing-items` 内部；后续异步 pipeline 只处理背景移除、3D 与角度图 |

**影响**：标签现在在创建阶段就可用，前端可在 `processing-status.classification == completed` 后读取 `GET /clothing-items/{id}`。

### 1.3 数据库与迁移

| 问题 | 当前状态 | 待确认 |
|------|----------|--------|
| 数据库由谁创建？ | 提供 `scripts/init_schema.sql` | 是否统一用 Alembic？ |
| users 表 | 已提供最小 User 模型 | Auth 队友可能扩展，需同步 |

---

## 二、Auth 队友（若单独负责认证）

### 2.1 当前用户获取

| 问题 | 当前占位 | 待确认 |
|------|----------|--------|
| `get_current_user_id()` | 固定返回测试 UUID | JWT 校验方式？从 `Authorization: Bearer <token>` 解析？ |
| 用户不存在时的处理 | 未处理 | 返回 401？ |

**影响文件**：`app/api/deps.py`

---

## 三、Module 2 内部待定（wkd）

### 3.1 AI 分类模型选型

| 项目 | 当前状态 | 待定 |
|------|----------|------|
| 服装品类分类 | Mock 返回 `T_SHIRT` | 选用模型？Hugging Face / TF / ONNX？ |
| 颜色检测 | Mock 返回 `blue, white` | colorthief / Pillow K-Means？ |
| 图案识别 | Mock 返回 `striped` | 规则 / 轻量 CNN？ |
| 依赖 | 无 | 选型后加入 `requirements.txt` |

**影响文件**：`app/services/ai_service.py`、`requirements.txt`

### 3.2 低置信度处理

| 问题 | 说明 |
|------|------|
| 是否在内部保存置信度？ | 文档规定 API 不返回置信度，但后端可内部记录 |
| 低置信度时策略？ | 使用 `category: OTHER` 兜底？或保留「待确认」标记？ |

---

## 四、统一修改入口汇总

对接完成后，按下列顺序修改：

1. **数据库**：确认 `init_schema.sql` 或 Alembic 迁移脚本
2. **配置**：`.env` 与 `app/core/config.py` 中的存储、数据库
3. **Auth**：`app/api/deps.py` 中 `get_current_user_id()`
4. **图片加载**：`app/services/ai_service._load_image_bytes()`
5. **AI 模型**：`app/services/ai_service._classify_mock()` 替换为实际调用

---

## 五、已实现且可独立测试的部分

以下接口在「有数据库 + 临时 user_id」前提下可测：

- `PATCH /api/v1/clothing-items/:id`：需 clothing_items 有数据
- `GET /api/v1/clothing-items`：同上
- `POST /api/v1/clothing-items/search`：同上

运行方式：

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

数据库需先执行 `scripts/init_schema.sql` 或通过 Alembic 迁移。
