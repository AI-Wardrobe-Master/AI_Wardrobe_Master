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
