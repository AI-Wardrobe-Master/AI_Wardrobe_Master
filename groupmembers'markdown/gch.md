## gch 
### 2026.3.6
#### 1. 筛选单视图生成模型，尝试了以下模型：
  - TRELLIS2
  - Zero123
  - stable zero123
  - Hunyuan3D 2
  - Hunyuan3D 2.1
  - midi3d
  - VGGT
最终选择Hunyuan3D 2的fast模型，兼备一定的速度和质量，较适合当前任务

#### 2. 配置依赖环境
#### 3. 配置数据库
#### 4. 完成多视图生成流程和基础代码

### 2026.3.7
#### 1. 完成相机请求、拍照、上传
##### 1. 依赖
  - pubspec.yaml
    - camera / image_picker — 摄像头拍照 + 相册选取
    - dio — HTTP 上传 & API 调用
    - permission_handler — 权限管理
    - cached_network_image — 网络图片缓存加载
    - path_provider — 文件路径
##### 2. api
  - api_config.dart
  - clothing_api_service.dart
##### 3. 拍照流程
  - camera_capture_screen.dart
    - 打开后置摄像头，显示取景框引导
    - 先拍正面（必须），拍完进入预览确认
    - 弹出底部弹窗询问「是否拍背面」，可跳过
    - 无摄像头时自动回退到相册选取
    - 完成后返回 {front: File, back: File?}
##### 4. 照片预览
  - image_preview_screen.dart
    - 全屏显示拍摄结果
    - 两个按钮：「重拍」/「使用照片」
##### 5. 处理进度
  - processing_screen.dart
    - 上传后每 2 秒轮询后端 /processing-status
    - 实时显示进度条 + 百分比
    - 4 个步骤状态：Upload → Background Removal → 3D Model Generation → Angle Rendering
    - 失败时显示错误信息和返回按钮
    - 完成后自动跳转结果页
##### 6. 角度预览
  - clothing_result_screen.dart
    - 加载 8 个角度图并展示
    - 底部缩略图列表可点击切换
    - 左右滑动手势切换角度
    - 显示当前角度度数（0° / 45° / 90° …）
    - 点击「Done」返回首页
##### 7. 修改root_shell.dart

### 2026.4.13
#### 新增「个性化场景穿搭生成」模块（DreamO 集成）

用户上传自拍 + 选择已有衣物 + 输入场景描述 → 生成写实穿搭图

##### 1. DreamO 独立推理服务
  - DreamO/server.py — FastAPI 封装 Generator 类，暴露 POST /generate 和 GET /health
  - DreamO/Dockerfile — 独立容器，隔离 torch==2.6.0 / diffusers==0.33.1 等依赖，避免与后端冲突
  - 更新 DreamO/requirements.txt — 移除 gradio/spaces，新增 fastapi/uvicorn
  - 线程安全：使用 threading.Lock 保护 GPU 推理

##### 2. 数据库
  - backend/app/models/styled_generation.py — StyledGeneration 模型（id, user_id, clothing_item FK, selfie 路径, prompt, status, result 路径, seed, guidance_scale, 尺寸, 时间戳）
  - backend/alembic/versions/20260413_000005_add_styled_generations_table.py — 迁移脚本（含索引和 CHECK 约束）

##### 3. 后端配置
  - backend/app/core/config.py — 新增 DREAMO_SERVICE_URL、DREAMO_GENERATE_TIMEOUT_SECONDS、SELFIE_* 等配置项

##### 4. API 接口（5 个端点）
  - POST /api/v1/styled-generations — 创建生成任务（multipart: 自拍 + 衣物 ID + 场景描述）
  - GET /api/v1/styled-generations/:id — 查询生成详情与状态
  - GET /api/v1/styled-generations — 分页列出历史生成记录
  - POST /api/v1/styled-generations/:id/retry — 重试失败任务
  - DELETE /api/v1/styled-generations/:id — 删除生成记录
  - 衣物未处理完成时返回 409，明确提示 garment asset not ready

##### 5. Celery 异步任务
  - 新增 styled_generation 队列，与原 clothing_pipeline 队列隔离
  - backend/app/services/styled_generation_pipeline.py — 完整流水线：
    1. 校验衣物已有 PROCESSED_FRONT 图
    2. 下载并预处理自拍（人脸检测 + 去背景 + 白底合成 + 缩放）
    3. 模板化拼装 prompt（基础质量 + 衣物遵从 + 用户场景）
    4. HTTP 调用 DreamO 推理服务
    5. 保存结果图并更新数据库状态

##### 6. 三个独立服务模块
  - selfie_preprocessing_service.py — OpenCV Haar 人脸检测、亮度/模糊校验、去背景、白底合成
  - dreamo_client_service.py — httpx 异步 HTTP 客户端，调用 DreamO /generate
  - prompt_builder_service.py — 可配置的 prompt 模板拼装 + 默认 negative prompt

##### 7. Docker Compose 更新
  - 新增 redis 服务（Celery broker）
  - 新增 dreamo 服务（GPU，port 9000，120s 启动等待）
  - 新增 celery-clothing 和 celery-styled-gen 两个独立 worker
  - 新增 dreamo_models 持久化卷

##### 8. 代码清理
  - 删除 DreamO/ 中不需要的文件：app.py、example_inputs/、pyproject.toml、README.md、dreamo_v1.1.md、.git/
  - 删除 Hunyuan3D-2/ 中不需要的文件：gradio_app.py、blender_addon.py、examples/、assets/、docs/、minimal_demo.py、minimal_vae_demo.py、api_server.py、README 等

##### 9. 文档
  - documents/DREAMO_INTEGRATION.md — 架构说明、显存需求、本地开发、API 契约、prompt 调参、故障排查
  - documents/FLUTTER_STYLED_GENERATION_GUIDE.md — 前端同学对接指南（端点、UI 流程、Dart 示例、错误处理）
  - 更新 documents/API_CONTRACT.md — 新增第 10 节 Styled Generations
  - 更新 documents/BACKEND_ARCHITECTURE.md — 新增 StyledGeneration 实体和 DreamO 流水线说明
  - 更新 backend/README.md — 新增模块说明、Celery worker 启动命令、DreamO 服务说明

### 2026.4.15-16
#### 内容寻址存储（CAS）重构 + 卡包导入/删除流程

##### 1. 内容寻址存储（CAS）
  - 新增 `blobs` 表：所有二进制文件（图片、GLB 模型）按 SHA-256 哈希去重存储
  - 新增 `BlobStorage` 字节层（LocalBlobStorage + S3BlobStorage），文件路径 `blobs/{hash[:2]}/{hash[2:4]}/{hash}`
  - 新增 `BlobService` 引用计数层：ingest_upload / addref / release，PostgreSQL advisory lock 保证并发安全
  - 替换全部 12 个 `storage_path TEXT` 列为 `blob_hash CHAR(64) FK→blobs`
  - 删除旧 `storage_service.py`，全部 API / pipeline / service 切换到新 blob 接口
  - 新增 `/files` 业务路由：按 `/files/clothing-items/{id}/{kind}` 格式流式返回内容，不暴露哈希

##### 2. 卡包导入/退订流程
  - 新增 `card_pack_imports` 表，记录"用户 U 导入了卡包 P"
  - `POST /imports/card-pack`：整包导入，为每个 creator_item 创建快照 clothing_items（source=IMPORTED），共享 blob 引用
  - `DELETE /imports/card-pack/{pack_id}`：退订整包，删除所有来自该包的 clothing_items，释放 blob 引用
  - `clothing_items` 新增 `imported_from_card_pack_id` 和 `imported_from_creator_item_id` 弱引用追溯来源

##### 3. 删除逻辑
  - 新增 `DELETE /clothing-items/{id}`：消费者可以删除自己的衣物（OWNED 或 IMPORTED），释放 blob 引用
  - 卡包 ARCHIVE 无条件允许；HARD DELETE 需要 import_count=0
  - 创作者衣物在已发布卡包中时禁止删除

##### 4. 异步 GC
  - 新增 `gc_sweep` Celery 任务：每小时扫描 `ref_count=0` 且超过 24 小时的 blob，物理删除
  - advisory lock 防止 GC 和 ingest 的竞态
  - Docker Compose 新增 `celery-beat` 服务

##### 5. 数据库迁移
  - 新增 Alembic 迁移 `20260415_000010`（接在 `20260413_000005` 之后）
  - 此前修复了迁移链分叉问题（`20260413_000005` 的 down_revision 从 `20260401_000004` 改为 `20260402_000007`）

##### 6. 运维工具
  - `backend/scripts/verify_blob_refcount.py`：校验所有业务表的 blob_hash 引用计数与 `blobs.ref_count` 一致性

##### 7. 涉及文件统计
  - 新增 9 个文件，修改 ~28 个文件，删除 1 个文件
  - 总计 +4604 / -499 行

### 2026.4.20
#### 多件衣物 DreamO + 创作者/消费者衣物表合并 + 三档删除 + 浏览量 + 数据库健壮性

##### 1. 多件衣物 DreamO 支持
  - `POST /api/v1/styled-generations` 不再只接受单件衣物：
    - 新增 `gender` 字段（required，`"male" | "female"`）
    - 新增 `clothing_items` 字段（required，JSON string，编码 1~4 件衣物数组，每项含 `id` + `slot ∈ {HAT,TOP,PANTS,SHOES}`，slot 全局唯一）
    - 旧 `clothing_item_id` 字段保留一个版本作为 DEPRECATED 兼容 shim
  - 响应新增 `gender` 和 `garments: [{id, slot, name, imageUrl}]` 字段，按 HAT→TOP→PANTS→SHOES 顺序返回
  - 新增 `styled_generation_clothing_items` 多对多 junction 表（`generation_id`, `clothing_item_id`, `slot`, `sort_order`），`unique(generation_id, slot)` 防同 slot 冲突
  - `styled_generations` 新增 `gender VARCHAR(10)` 列
  - Pipeline 改为：按 slot 顺序从 junction 表批量拉取 garments → 校验每件都有 `PROCESSED_FRONT` → 组装 gender-aware prompt → 组装 `garment_images: [...]` → 调 DreamO
  - DreamO 服务端 + 客户端都改为 `garment_images` 列表；旧 `garment_image` 单数作为 deprecated shim 保留
  - Prompt builder 新增 gender-aware 基础短语和 HAT→TOP→PANTS→SHOES 按槽位拼装的多件衣物模板

##### 2. 创作者/消费者衣物表合并
  - `creator_items` 表完全合入 `clothing_items`，系统只剩一张 canonical 衣物表
  - 所有衣物（OWNED / IMPORTED / 创作者原创）都走同一张表，通过 `catalog_visibility ∈ {PRIVATE, PACK_ONLY, PUBLIC}` 控制发布可见性
  - `card_pack_items.clothing_item_id` 直接引用合并后的 `clothing_items.id`，不再有独立的 `creator_item_id`
  - `/creator-items/*` 这批旧端点改为薄 legacy shim，内部委托给统一的 `/clothing-items/*`
  - `imported_from_creator_item_id` 改名为 `imported_from_clothing_item_id`（自引用 FK）
  - Alembic 迁移 `20260420_000015` 负责数据搬迁：`creator_items` → `clothing_items`（含 blob 引用、origin 字段）、更新 `card_pack_items` FK、重命名 `imported_from_*` 列、回填 `catalog_visibility`

##### 3. 三档删除生命周期（spec §4.7）
  - Tier 1：`catalog_visibility = PRIVATE` OR 从未发布 → 硬删，release 全部 blob
  - Tier 2：已发布但 0 下游消费者导入 → 硬删
  - Tier 3：已发布且存在下游 `imported_from_clothing_item_id` 引用 → tombstone（设 `deleted_at`，从所有列表/搜索端点隐藏，但保留行以便 backlink 解析）
  - 消费者卸载卡包（un-import）时会级联将其拥有的 tombstone 副本硬删并 release blob
  - `clothing_items` 新增 `deleted_at TIMESTAMPTZ` 列，所有列表/搜索 query 增加 `deleted_at IS NULL` 过滤

##### 4. 浏览量 + Top10
  - `clothing_items` 和 `card_packs` 都新增 `view_count INTEGER NOT NULL DEFAULT 0` 列
  - 详情 GET 走 `UPDATE ... SET view_count = view_count + 1 RETURNING view_count` 原子自增，返回值即为响应字段
  - 只有 `PUBLISHED` 状态的卡包累积浏览量；创作者本人访问自己的卡包/衣物不计数（short-circuit）
  - 新增 `GET /api/v1/card-packs/popular?limit=10` 端点：返回 `PUBLISHED` 卡包按 `view_count DESC, published_at DESC` 排序，响应 shape 同 `GET /card-packs`
  - 详情响应（`GET /clothing-items/:id`, `GET /creator-items/:id`, `GET /card-packs/:id`）均包含 `viewCount: int`
  - 新增 `(status, view_count DESC)` 复合索引加速 popular 查询

##### 5. 数据库健壮性
  - `BlobService.release()` 现在先拿 `pg_advisory_xact_lock(hash)` 再递减 `ref_count`，消除与并发 ingest / GC 的 double-decrement 竞态
  - `StyledGeneration` / `ProcessingTask` 的 retry 路径在重新入队前显式 release 上一次失败产生的 blob，防止失败循环导致 blob 泄漏
  - `card_pack.import_count` 的硬删前检查改走 `SELECT ... FOR UPDATE`，修掉原先 "检查时 0 但实际已被别人 +1" 的 TOCTOU
  - 新增 CHECK 约束 `ck_card_pack_import_count_nonneg` 防下溢
  - 新增 Celery beat 任务每小时 reap-stuck：扫描 `styled_generations` 和 `processing_tasks` 中 `PROCESSING` 超过 `lease_expires_at` 的行，翻成 `FAILED`
  - 新增每周 orphan-file GC sweep（本地存储专用），对账磁盘字节 vs `blobs` 注册表，删除孤儿文件；S3 存储继续沿用现有 `gc_sweep`
  - `SECRET_KEY` 新增生产环境校验器：`ENV=production` 时禁止使用 dev 默认值，启动即报错
  - 修掉 wardrobe 列表端点的 N+1：之前每个 `wardrobe_items` 行单独拉 `clothing_items`，改成一次 joinedload
  - `files.py` 卡包封面路由加鉴权 guard：`DRAFT` / `ARCHIVED` 卡包的封面对非 owner 返回 404（之前按 blob hash 直读，泄漏 DRAFT 封面字节）

##### 6. 审计发现与决策

  - **`/auth/register` userType 行为**（2026-04-20 确认）：
    - 当前行为：后端**尊重前端传入**的 `userType`。传 `CREATOR` 则直接创建 CREATOR 账号并立即获得全部 creator capabilities；传 `CONSUMER` 或不传则创建 CONSUMER 账号；不合法值返回 422。
    - 历史背景：更早的某个迭代里曾存在"静默 clamp 为 CONSUMER"的逻辑，但那个 clamp 在最近的某次提交被意外去掉且未文档化。本轮重构发现了这个已经事实上存在的行为漂移。
    - **决策**：保持当前行为（尊重前端输入）。理由：
      1. 简化后端——无需维护一条后续的"CONSUMER 升级为 CREATOR"的路径，gating 留给前端处理；
      2. 与 `CreatorProfile` 的生命周期解耦——创建账号即可决定身份，不需要额外的申请 + 审批状态机；
      3. 对前端影响可控——前端可通过 UI 门槛（邀请码、审核链接等）控制谁能看到 `userType=CREATOR` 选项。
    - 对应文档已同步：`documents/API_CONTRACT.md` §1.1 详细列出了 userType 字段、可选值、默认回退、错误码矩阵，以及明确的 "Product implication: enforce the gate on the frontend" 注解。
    - 测试：原先检查 clamp 行为的 `test_register_ignores_requested_user_type_for_now` 与新行为矛盾，已删除（FU-T05 标记为 resolved）。

##### 7. 变更范围（按模块）
  - backend：styled_generations pipeline + schema + API + prompt builder + DreamO client
  - backend：clothing_items 表加 `catalog_visibility` / `deleted_at` / `view_count` / 重命名 `imported_from_*`
  - backend：card_packs 加 `view_count` + popular 端点
  - backend：3-tier delete dispatcher + tombstone 过滤
  - backend：release() advisory lock、TOCTOU fix、reap-stuck beat、orphan GC、SECRET_KEY validator、N+1 fix、files.py 鉴权 guard
  - DreamO：server.py + client 接受 `garment_images` 列表
  - 迁移：`20260420_000015`（合并 creator_items、新列、新约束、新索引）
  - 文档：`API_CONTRACT.md`、`BACKEND_ARCHITECTURE.md`、`DATA_MODEL.md`、`DREAMO_INTEGRATION.md` 同步更新

##### 8. Follow-ups — 测试重写清单 <a id="fu-test-rewrites"></a>

合并后以下测试文件被 quarantine（module-level `pytest.skip` + 具体理由）。每个单独列一个重写 TODO 以便后续认领。Skip 消息里引用本节锚点 `gch.md #fu-test-rewrites`。

- **`backend/tests/test_card_pack_flow.py`** — FU-T01：改写对齐合并后的 `ClothingItem` schema。原测试 import 已删除的 `CreatorItem`/`CreatorItemImage`。覆盖范围高（CRUD + share/publish 全流程），建议优先重写。
- **`backend/tests/test_outfit_preview_flow.py`** — FU-T02：改写对齐 CAS schema。原测试用已删除的 `_absolute_storage_url` helper 和 `storage_path=...` 字段；现在要走 `blob_hash=...`。覆盖 outfit 预览端到端 + 保存流程，目前空白。
- **`backend/tests/test_clothing_processing.py`** — FU-T03：改写对齐 `blob_hash`。原测试构造 `Image(storage_path=...)` 全文要替换。覆盖上传 + 后台流水线 + retry，核心流程。
- **`backend/tests/test_creator_foundation.py`** — FU-T04：补齐 User fixture 的 `uid` 字段 + 改写 `/me` 响应断言。小范围。
- ~~**`backend/tests/test_r1_auth.py::test_register_ignores_requested_user_type_for_now`** — FU-T05~~：✅ **已解决（2026-04-20）**。产品决策保留"尊重前端 userType"的新行为（见 §6），原测试与新行为矛盾，已从 `test_r1_auth.py` 删除。

##### 9. 本轮最终清理 + 文档同步（2026-04-20 晚间）

Final code review 后收到 4 处改进建议，选"B 方案"全部落地（+ 额外的文档更新）：

1. **Race fix（spec §4.7 concurrency）**：`delete_with_lifecycle` 先前仅 `FOR UPDATE` 锁 ClothingItem 行，未锁引用它的 PUBLISHED pack。并发 `POST /imports/card-pack`（锁了 pack 行但没锁 items）理论上能跟 publisher 的删除交错。
   - 修复：把 `in_published_pack` 的 `EXISTS` 查询换成 `JOIN + FOR UPDATE + .all()`，同时拿到所有引用本 item 的 PUBLISHED pack 行锁。
   - 结果：publisher 的 delete 和 importer 的 snapshot 现在必然串行化通过 pack 行锁。

2. **死代码清理**：合并后 `app/schemas/creator.py` 里 8 个 `CreatorItem*` 类（`CreatorItemCreateResponseData`、`CreatorItemCreateResponse`、`CreatorItemUpdate`、`CreatorItemDetail`、`CreatorItemResponse`、`PublicCreatorItem`、`CreatorItemListData`、`CreatorItemListResponse`）已无任何 importer，删掉；同步移除 `ImageSetResponse, Tag` 的 unused import。文件从 169 行缩到 100 行。

3. **`SECRET_KEY` validator 严格化**：原先只匹配字面量 `production` / `prod`，`ENV=Prod-EU` 或 `ENV=' production '`（带空格）会静默漏过，让 dev 默认 key 流入生产。
   - 修复：先 `.strip().lower()`，然后用 `startswith("prod") or startswith("stag") or == "live"` 匹配——prod 系和 staging 系都硬拦住。
   - 验证：`ENV=production` / `ENV=Prod-EU` / `ENV='  staging  '` 全部 raise；`ENV=development`（默认）照常 warn 通过。

4. **Quarantine 指针化**：原来 4 个被 quarantine 的测试文件 skip 消息都以"Tracked in follow-ups"结尾，没有具体定位。改成引用 `gch.md §8 FU-T01..T05`，每个 FU 列有独立的改写范围、阻塞点。其中 FU-T05 本轮即已 resolved。

5. **`/auth/register` userType 语义文档化**：
   - `documents/API_CONTRACT.md` §1.1 重写：加字段表（类型、是否必须、默认值、合法值）、明确"backend 不做 gating、前端控制入口"的产品含义、补 CONSUMER 与 CREATOR 两种成功响应示例、列错误码矩阵（409 重复、422 不合法）。
   - 删除与新行为矛盾的旧测试 `test_register_ignores_requested_user_type_for_now`。

涉及 commits（按时间）：
  - `ac3a50a` — fix(clothing): lock PUBLISHED packs in delete_with_lifecycle
  - `aa8d833` — refactor(schemas): prune unused CreatorItem schemas after merge
  - `18f5b63` — fix(config): tighten ENV validator — strip + prefix match prod/stag/live
  - `b83ccd9` — docs(followups): link quarantined tests to FU-T01..FU-T05 in gch.md
  - 本 commit：API_CONTRACT.md userType 语义 + gch.md §6/§8/§9 更新 + 删除过时测试

测试状态：**60 passed, 22 skipped, 0 failed**。原 skip 掉的 `test_register_ignores_requested_user_type_for_now` 被改写成 `test_register_honors_requested_user_type`（断言新行为），比上轮多 1 个 passing 测试、少 1 个 skip。
