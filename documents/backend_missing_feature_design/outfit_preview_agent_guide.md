# Outfit Preview Implementation Agent Guide

## 1. 文档目的

本文档用于指导下游代码实现 agent 落地当前版本的 `outfit preview` 后端能力。

本 guide 不讨论产品是否合理，也不重新定义需求。输入需求已经在
`outfit_preview_backend_design.md` 中确认，本 guide 只回答：

- 现在应该改哪些代码
- 应该按什么顺序实现
- 哪些能力本阶段不要碰
- 完成后如何判断实现是合格的

---

## 2. 本阶段唯一目标

实现一条稳定的后端链路：

`用户提交试穿请求`
-> `创建 outfit_preview_task`
-> `异步调用外部生成 API`
-> `产出 preview image`
-> `用户可将成功结果保存为 outfit`

当前版本支持两种输入：

- 单件试穿预览
- 一整套穿搭预览，当前可包含 `TOP`、`BOTTOM`、`SHOES`

---

## 3. 已确认的约束

实现 agent 必须遵守以下约束，不得自行扩 scope：

1. 当前只支持 1 张用户自拍。
2. 当前支持：
   - 1 件衣物试穿
   - 一整套穿搭预览，当前可包含 `TOP`、`BOTTOM`、`SHOES`
3. 当前不支持同类别多件叠穿，例如多件上衣或多双鞋。
4. 当前只支持：
   - `person_view_type`: `FULL_BODY | UPPER_BODY`
   - `garment_category`: `TOP | BOTTOM | SHOES`
5. 前端负责输入类型筛选，后端只做轻校验。
6. 生成任务必须落到新的 `outfit_preview_tasks`。
7. 不能把 outfit preview 混进现有 `processing_tasks`。
8. `outfits` 只保存用户确认后的结果，不保存处理中状态。
9. `outfit` 通过外键关联 `clothing_items`，不在 `outfit` 内复制衣物明细。
10. 外部生成服务固定使用阿里云 DashScope 千问模型 `wan2.7-image-pro`。

---

## 4. 当前代码基线

当前仓库已存在：

- 用户鉴权体系
- `clothing_items`
- `images`
- `models_3d`
- `processing_tasks`
- 异步任务链路

当前可参考入口：

- [backend/app/models/clothing_item.py](/mnt/d/AI_Wardrobe_Master/backend/app/models/clothing_item.py)
- [backend/app/api/v1/clothing.py](/mnt/d/AI_Wardrobe_Master/backend/app/api/v1/clothing.py)
- [backend/app/services/clothing_pipeline.py](/mnt/d/AI_Wardrobe_Master/backend/app/services/clothing_pipeline.py)
- [backend/app/tasks.py](/mnt/d/AI_Wardrobe_Master/backend/app/tasks.py)
- [backend/app/api/v1/router.py](/mnt/d/AI_Wardrobe_Master/backend/app/api/v1/router.py)

当前仓库尚未实现：

- `outfit_preview_tasks`
- `outfit_preview_task_items`
- `outfits`
- `outfit_items`
- preview task API
- preview task service
- preview result save flow

---

## 5. 需要新增或修改的代码范围

### 5.1 SQLAlchemy 模型

新增：

- `backend/app/models/outfit_preview.py`

应包含：

- `OutfitPreviewTask`
- `OutfitPreviewTaskItem`
- `Outfit`
- `OutfitItem`

要求：

- `OutfitPreviewTask` 负责记录任务状态与结果图
- `Outfit` 负责记录已确认结果
- `OutfitItem` 负责关联 `Outfit` 与 `ClothingItem`

同时更新：

- `backend/app/models/__init__.py`
- 如项目使用统一 Base 导入，需确保新模型被 Alembic 识别

### 5.2 数据迁移

新增 Alembic migration，创建：

- `outfit_preview_tasks`
- `outfit_preview_task_items`
- `outfits`
- `outfit_items`

最低要求：

- 所有 FK 正确
- 状态字段有 `CHECK`
- `outfit_preview_task_items` 能表达一个 task 对应多件衣物
- 同一 `task_id` 下 `garment_category` 不可重复
- `outfit_items` 有唯一约束 `(outfit_id, clothing_item_id)`
- 补充必要索引

如果项目仍维护 `backend/scripts/init_schema.sql`，必须同步更新。

### 5.3 Pydantic Schema

新增：

- `backend/app/schemas/outfit_preview.py`

至少包含：

- `OutfitPreviewTaskCreateResponse`
- `OutfitPreviewTaskDetail`
- `OutfitPreviewTaskListResponse`
- `OutfitPreviewSaveResponse`
- 如需内部结构，可补：
  - `OutfitPreviewTaskStatus`
  - `OutfitPreviewTaskListItem`

### 5.4 CRUD

新增：

- `backend/app/crud/outfit_preview.py`

建议提供：

- `create_outfit_preview_task`
- `replace_outfit_preview_task_items`
- `get_owned_outfit_preview_task`
- `list_owned_outfit_preview_tasks`
- `mark_outfit_preview_processing`
- `mark_outfit_preview_completed`
- `mark_outfit_preview_failed`
- `create_outfit_from_preview_task`

约束：

- 所有 owner 读取必须在查询层带 `user_id`
- 不允许 route 先按 `id` 查询再在内存里比 owner

### 5.5 Service

新增：

- `backend/app/services/outfit_preview_service.py`

建议职责拆分：

- `create_preview_task(...)`
- `resolve_garment_images_for_preview(...)`
- `select_prompt_template(...)`
- `enqueue_preview_generation(...)`
- `save_outfit_from_preview_task(...)`

必要约束：

- route 层不直接拼接业务逻辑
- 事务应集中在 service 层

### 5.6 异步任务

根据当前项目现状，新增独立 preview task 入口。

可选位置：

- `backend/app/tasks.py`

或新增：

- `backend/app/tasks/outfit_preview.py`

需要完成：

- 根据 task id 读取 `OutfitPreviewTask`
- 读取该 task 下的 `OutfitPreviewTaskItem`
- 按稳定顺序组装 DashScope 请求
- 调用阿里云 DashScope 千问多模态生成 API
- 更新任务状态
- 保存结果图
- 记录失败原因

关键要求：

- 失败时不能把任务永远留在 `PENDING`
- 调度失败要能明确标记为失败，或同步返回错误

### 5.7 API Route

新增：

- `backend/app/api/v1/outfit_preview.py`

并在 [backend/app/api/v1/router.py](/mnt/d/AI_Wardrobe_Master/backend/app/api/v1/router.py) 注册。

当前阶段至少实现：

- `POST /outfit-preview-tasks`
- `GET /outfit-preview-tasks/{task_id}`
- `GET /outfit-preview-tasks`
- `POST /outfit-preview-tasks/{task_id}/save`

### 5.8 对象存储

如果当前项目已有统一存储服务，复用它。

本阶段只新增路径约定，不新增第二套存储基础设施：

- 自拍输入：`outfit-previews/{user_id}/{task_id}/person.*`
- 生成结果：`outfit-previews/{user_id}/{task_id}/result.*`

---

## 6. 路由行为要求

## 6.1 `POST /outfit-preview-tasks`

输入：

- `person_image`
- `clothing_item_ids[]`
- `person_view_type`
- `garment_categories[]`

校验：

- 当前用户已登录
- `clothing_item_ids[]` 全部属于当前用户
- `person_view_type` 合法
- `garment_categories[]` 合法
- 同一请求中不允许重复类别
- `person_image` 仅支持 `240 x 240` 像素
- 非 `240 x 240` 的 `person_image` 必须直接拒绝
- 自拍文件 MIME / 文件大小 / 可解码性合法
- 所有 `clothing_item` 都存在可用于预览的图像

行为：

1. 上传自拍图
2. 创建 `outfit_preview_tasks(status=PENDING)`
3. 创建 `outfit_preview_task_items`
4. 投递异步任务
5. 返回 `202`

### 6.2 `GET /outfit-preview-tasks/{task_id}`

行为：

- 只允许查看自己的任务
- 返回任务状态、结果图、错误信息、时间戳

### 6.3 `GET /outfit-preview-tasks`

行为：

- 返回当前用户自己的任务列表
- 默认按 `created_at desc`

### 6.4 `POST /outfit-preview-tasks/{task_id}/save`

校验：

- 任务属于当前用户
- 状态为 `COMPLETED`
- 存在 `preview_image_path`

行为：

1. 创建 `outfits`
2. 根据 `outfit_preview_task_items` 创建 1 条或多条 `outfit_items`
3. 将 `preview_task_id` 写入 `outfits`
4. 返回新建 outfit

幂等建议：

- 若同一 task 已保存过 outfit，可直接返回已存在对象，或返回 `409`
- 本阶段二选一，但必须行为稳定

---

## 7. Prompt 规则

本阶段不要设计复杂 prompt 平台。

只需要在 service 中实现一个稳定映射：

- `FULL_BODY + TOP` -> `full_body_top_tryon`
- `FULL_BODY + BOTTOM` -> `full_body_bottom_tryon`
- `FULL_BODY + SHOES` -> `full_body_shoes_tryon`
- `FULL_BODY + TOP+BOTTOM`
  -> `full_body_outfit_tryon`
- `FULL_BODY + TOP+BOTTOM+SHOES`
  -> `full_body_outfit_tryon`
- `UPPER_BODY + TOP` -> `upper_body_top_tryon`
- `UPPER_BODY + BOTTOM` -> `upper_body_bottom_tryon`

注意：

- prompt 选择必须在后端完成
- 但 prompt 内容本身不需要在本阶段做成配置中心

### 7.1 DashScope 调用要求

本阶段外部模型固定为：

- Provider: `DashScope`
- Model: `wan2.7-image-pro`
- Endpoint:
  `https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation`

服务层应按如下请求结构调用：

```json
{
  "model": "wan2.7-image-pro",
  "input": {
    "messages": [
      {
        "role": "user",
        "content": [
          {"image": "person_image_url"},
          {"image": "top_image_url"},
          {"image": "bottom_image_url"},
          {"image": "shoes_image_url"},
          {"text": "dynamic prompt text"}
        ]
      }
    ]
  },
  "parameters": {
    "size": "2K",
    "n": 1,
    "watermark": false,
    "thinking_mode": true
  }
}
```

实现要求：

- `Authorization` 使用后端环境变量中的 `DASHSCOPE_API_KEY`
- 图片顺序保持稳定，推荐顺序：`person -> top -> bottom -> shoes`
- 未提供的类别不出现在 `content` 里
- 必须把 `provider_name` 和 `provider_model` 写入数据库

### 7.2 DashScope 响应解析要求

当前已确认 `wan2.7-image-pro` 是**同步返回最终结果**，不是异步任务式接口。

成功响应结构要点：

```json
{
  "output": {
    "choices": [
      {
        "finish_reason": "stop",
        "message": {
          "content": [
            {
              "image": "https://dashscope-xxx.oss-xxx.aliyuncs.com/xxx.png?Expires=xxx",
              "type": "image"
            }
          ],
          "role": "assistant"
        }
      }
    ],
    "finished": true
  },
  "usage": {
    "image_count": 1,
    "input_tokens": 10867,
    "output_tokens": 2,
    "size": "1488*704",
    "total_tokens": 10869
  },
  "request_id": "71dfc3c6-f796-9972-97e4-bc4efc4faxxx"
}
```

实现 agent 必须按以下规则解析：

1. 校验 `output.finished == true`
2. 读取 `output.choices[0].message.content`
3. 查找其中 `type == "image"` 的对象
4. 取其 `image` 字段作为外部结果图 URL
5. 记录 `request_id`
6. 将结果图下载到本系统存储，再写入 `preview_image_path`

下列情况一律按失败处理：

- `output.finished != true`
- `choices` 为空
- `content` 中没有图片对象
- `image` URL 为空

异常响应结构要点：

```json
{
  "request_id": "a4d78a5f-655f-9639-8437-xxxxxx",
  "code": "InvalidParameter",
  "message": "num_images_per_prompt must be 1"
}
```

实现 agent 必须按以下规则处理：

1. 将 `request_id` 记录日志
2. 将 `code` 写入 `error_code`
3. 将 `message` 写入 `error_message`
4. 将任务状态更新为 `FAILED`

重试要求：

- `InvalidParameter` 这类明确请求错误不得自动重试
- 网络异常、超时、上游 `5xx` 可以做有限重试

---

## 8. 与前端的契约

实现 agent 不需要开发前端，但必须遵守前端契约：

1. 前端负责筛掉非法输入组合
2. 后端不能假设前端一定正确，仍需做轻校验
3. 当前前端提交的是：
   - 自拍文件
   - 枚举元数据
   - `clothing_item_ids[]`
4. 当前前端允许选择单件衣物，也允许选择一整套穿搭，且可包含鞋子
5. 后端不支持当前前端直接上传陌生服饰图并保存为 outfit

若代码实现中发现当前前端无法提交 `clothing_item_ids[]`，需要在结果中明确指出阻塞点，但不要擅自改需求去支持匿名服饰上传。

---

## 9. 不要做的事情

本阶段禁止实现以下扩展：

- outfit 画布布局字段
- layer / position / scale / rotation
- prompt 策略平台化
- 生成结果自动推荐
- 任意外部服饰图导入为持久 outfit
- 把 preview task 合并进 `processing_tasks`

这些都属于下一阶段议题，不应混入本次交付。

---

## 10. 推荐实现顺序

1. 建表和模型
2. 建 schema 和 CRUD
3. 打通 `POST /outfit-preview-tasks`
4. 打通异步 worker 更新状态
5. 打通 `GET /outfit-preview-tasks/{id}`
6. 打通 `POST /outfit-preview-tasks/{id}/save`
7. 最后补列表接口和测试

原因：

- 先保证请求能走通
- 再保证结果能落库
- 最后补用户体验型接口

---

## 11. 完成标准

实现完成后，至少应满足以下验收：

1. 用户提交合法请求后收到 `202`
2. 任务不会永久停在 `PENDING`
3. 成功时能返回 `previewImageUrl`
4. 失败时能返回明确错误
5. 非本人任务不能访问
6. 非本人 `clothing_item_ids[]` 不能用于生成
7. 成功任务能保存为 `outfit`
8. 保存后的 `outfit` 能通过外键关联到对应的一件或多件 `clothing_item`

---

## 12. 最终交付物

下游 agent 的交付应包含：

- 模型代码
- migration
- schema
- CRUD
- service
- route
- async task 接入
- 必要测试或最少手动验证说明

如果某一步做不到，必须在结果里明确指出缺口，而不是静默跳过。
