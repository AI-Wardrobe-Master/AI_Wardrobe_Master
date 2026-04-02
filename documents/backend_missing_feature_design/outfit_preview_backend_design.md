# Outfit Preview Backend Design

## 1. 文档目的

本文档定义当前阶段的 `outfit preview` 后端方案，并明确前端需要完成的工作边界。

本方案只解决一个问题：

- 用户提交一次试穿预览请求后，系统能够异步生成一张试穿或整套穿搭预览图，并把结果持久化，供后续确认保存。

本方案**不**试图一次性解决完整的 Outfit 画布编辑、多人多件搭配、智能推荐或复杂提示词策略管理。

---

## 2. 当前已确认的产品边界

基于本轮讨论，当前版本固定以下约束：

1. 输入目标是**单件试穿预览**或**整套穿搭预览**。
2. 当前只允许一个用户图像输入。
3. 服饰输入支持两种模式：
   - 单件衣物试穿
   - 一整套穿搭，当前允许由 `TOP`、`BOTTOM`、`SHOES` 组成
4. 当前不允许同类别多件叠穿，例如多件上衣或多双鞋同时提交。
5. 用户图像只允许两类：
   - `FULL_BODY`
   - `UPPER_BODY`
6. 服饰类别当前只允许三类：
   - `TOP`
   - `BOTTOM`
   - `SHOES`
7. 前端负责在提交前完成输入筛选与初步判定。
8. 后端只做轻校验，不承担复杂视觉检测职责。
9. 后端新增独立的 `outfit_preview_tasks`，不复用现有 `processing_tasks`。
10. `outfits` 不是“生成任务表”，只保存用户最终确认的预览结果。
11. `outfits` 与相关衣物通过外键关联，不在 `outfits` 中重复保存衣物明细快照。
12. 外部生成服务当前固定为阿里云 DashScope 千问图像模型 `wan2.7-image-pro`。

---

## 3. 领域拆分

当前需要明确区分 3 个对象：

### 3.1 Outfit Preview Task

表示一次“请求系统生成试穿图”的异步任务。

它负责记录：

- 谁发起的请求
- 输入是什么
- 任务进行到哪一步
- 生成出来的结果图在哪里
- 失败时为什么失败

### 3.2 Outfit

表示用户对某次成功预览结果进行确认后，真正保存下来的穿搭结果。

它负责记录：

- 归属用户
- 预览结果图
- 来源预览任务
- 关联了哪些衣物

### 3.3 ClothingItem

表示衣橱里的衣物资产。

当前 `outfit` 只通过外键关联 `clothing_items`，不直接保存衣物快照字段。

---

## 4. 前端必须完成的工作

前端在当前方案里不是“纯上传壳子”，它必须承担输入约束职责。

### 4.1 提交前校验职责

前端必须在本地完成以下判定，只有通过后才能调用后端：

- 仅允许提交 1 张用户照片
- 允许提交 1 件衣物，或一整套穿搭
- 用户照片必须被前端判定为 `FULL_BODY` 或 `UPPER_BODY`
- 每件衣物必须被前端判定为 `TOP`、`BOTTOM` 或 `SHOES`
- 如果是整套穿搭，不允许同类别重复，例如两个 `TOP`
- 当前允许的整套穿搭组合是围绕 `TOP`、`BOTTOM`、`SHOES` 的组合
- 当前不开放多上衣叠穿、多下装叠穿、多双鞋叠穿

### 4.2 提交给后端的结构化字段

前端不能只传图片文件，必须一并传递结构化元数据：

- `person_view_type`
- `clothing_item_ids[]`
- `garment_categories[]`

其中：

- `person_view_type` 取值：`FULL_BODY | UPPER_BODY`
- `garment_categories` 取值：`TOP | BOTTOM | SHOES`
- `clothing_item_ids` 表示当前预览所用衣物在本系统中的既有衣物主键集合

要求：

- `clothing_item_ids` 与 `garment_categories` 必须一一对应
- 每个请求至少 1 件衣物
- 整套穿搭最多 3 件衣物

### 4.3 前端需要配合的约束

当前方案要求预览任务与衣橱中的真实衣物建立关联，因此前端不能只上传一张任意服饰图就发起试穿。

前端应按以下方式工作：

- 用户自拍由前端直接上传
- 服饰来源应当是用户已存在的 `clothing_item`
- 前端提交 `clothing_item_ids[]`
- 后端根据这些 `clothing_item_ids` 读取对应衣物图像作为生成输入

这样做的原因是：

- 生成成功后，`outfit` 可以直接通过外键引用衣物
- 不需要为 preview 任务重复保存临时服饰文件
- 不会出现“生成结果存在，但无法与系统衣物资产建立关系”的悬空记录

### 4.4 前端非职责

前端当前不负责：

- 生成提示词
- 选择模型
- 计算最终存储路径
- 判定任务成功还是失败
- 直接创建 `outfit`

前端只能：

- 发起预览任务
- 轮询任务状态
- 在成功后调用保存接口

---

## 5. 后端职责

### 5.1 后端只做轻校验

后端在当前版本只做以下校验：

- 当前用户存在且已认证
- `clothing_item_ids[]` 全部属于当前用户
- `person_view_type` 取值合法
- `garment_categories[]` 取值合法
- 同一请求中不存在重复类别冲突
- 所有关联衣物都存在至少一张可用于生成的图像
- 上传的用户自拍文件可解码、类型合法、大小合法

后端**不**负责：

- 从原始图像重新识别人像是否全身或半身
- 自动判断衣物到底是上衣、裤子还是鞋子
- 支持超出当前约束的任意多衣物组合推理

### 5.2 后端的核心动作

后端收到请求后应完成：

1. 接收用户自拍上传
2. 根据 `clothing_item_ids[]` 取出服饰图
3. 基于 `person_view_type + garment_categories[]` 选择 prompt 模板
4. 创建 `outfit_preview_tasks`
5. 投递异步生成任务
6. 生成成功后写回结果图路径
7. 允许用户在成功后将结果保存为 `outfit`

### 5.3 外部生成模型

当前固定使用阿里云 DashScope 千问图像模型：

- Provider: `DashScope`
- Model: `wan2.7-image-pro`
- Endpoint: `https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation`

后端应在 service 层封装 HTTP 调用，不要把原始请求拼接放在 route 里。

当前已确认该接口是**同步式返回**：

- 单次 HTTP 请求返回最终结果
- 不需要额外的任务查询接口
- 后端在收到成功响应后即可提取结果图 URL、下载并落盘

---

## 6. API 设计

## 6.1 创建预览任务

`POST /outfit-preview-tasks`

请求类型：

- `multipart/form-data`

请求字段：

- `person_image`: 用户自拍，必填
- `clothing_item_ids[]`: 衣物主键集合，必填
- `person_view_type`: `FULL_BODY | UPPER_BODY`
- `garment_categories[]`: `TOP | BOTTOM | SHOES`

图片要求：

- `person_image` 仅支持 `240 x 240` 像素
- 非 `240 x 240` 的图片必须直接拒绝
- 其他图片格式校验仍按既有上传规则处理

说明：

- 本接口当前不接收第二张外部服饰上传图
- 后端会根据 `clothing_item_ids[]` 解析衣物图像输入

响应：

```json
{
  "success": true,
  "data": {
    "id": "preview-task-001",
    "status": "PENDING",
    "clothingItemIds": ["item-001", "item-002", "item-003"],
    "personViewType": "FULL_BODY",
    "garmentCategories": ["TOP", "BOTTOM", "SHOES"],
    "createdAt": "2026-04-02T12:00:00Z"
  }
}
```

返回码：

- `202 Accepted`

### 6.2 查询预览任务

`GET /outfit-preview-tasks/{task_id}`

响应字段：

- `id`
- `status`
- `previewImageUrl`
- `errorCode`
- `errorMessage`
- `createdAt`
- `startedAt`
- `completedAt`

状态值：

- `PENDING`
- `PROCESSING`
- `COMPLETED`
- `FAILED`

### 6.3 列出我的预览任务

`GET /outfit-preview-tasks`

支持：

- `page`
- `limit`
- `status`

用途：

- 前端查看历史试穿记录
- 调试与排障

### 6.4 保存成功预览为 Outfit

`POST /outfit-preview-tasks/{task_id}/save`

行为：

- 仅允许从 `COMPLETED` 的 preview task 创建
- 创建 `outfits`
- 创建 `outfit_items`
- `outfits.preview_task_id` 回指来源任务
- `outfits.preview_image_path` 保存最终结果图

说明：

- 这一步才是“正式保存穿搭”
- 不是所有 preview task 都必须转成 outfit

---

## 7. 数据库设计

## 7.1 `outfit_preview_tasks`

建议新增表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `UUID` PK | 任务主键 |
| `user_id` | `UUID` FK -> `users.id` | 发起用户 |
| `person_image_path` | `TEXT` | 自拍存储路径 |
| `person_view_type` | `VARCHAR(20)` | `FULL_BODY` / `UPPER_BODY` |
| `garment_categories` | `JSONB` | 本次提交衣物类别列表，允许 `TOP` / `BOTTOM` / `SHOES` |
| `input_count` | `INTEGER` | 本次使用的衣物数量 |
| `prompt_template_key` | `VARCHAR(100)` | 选择到的 prompt 模板标识 |
| `provider_name` | `VARCHAR(50)` | 外部模型提供方，当前固定为 `DashScope` |
| `provider_model` | `VARCHAR(100)` | 外部模型名称，当前固定为 `wan2.7-image-pro` |
| `provider_job_id` | `VARCHAR(255)` nullable | 外部任务标识 |
| `status` | `VARCHAR(20)` | `PENDING` / `PROCESSING` / `COMPLETED` / `FAILED` |
| `preview_image_path` | `TEXT` nullable | 最终预览图 |
| `error_code` | `VARCHAR(100)` nullable | 错误码 |
| `error_message` | `TEXT` nullable | 错误说明 |
| `started_at` | `TIMESTAMP` nullable | 开始处理时间 |
| `completed_at` | `TIMESTAMP` nullable | 完成时间 |
| `created_at` | `TIMESTAMP` | 创建时间 |

建议索引：

- `idx_outfit_preview_tasks_user_created(user_id, created_at)`
- `idx_outfit_preview_tasks_status(status, created_at)`

### 7.1.1 `outfit_preview_task_items`

由于一个 preview task 现在可以关联多件衣物，建议新增关联表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `UUID` PK | 主键 |
| `task_id` | `UUID` FK -> `outfit_preview_tasks.id` | 所属任务 |
| `clothing_item_id` | `UUID` FK -> `clothing_items.id` | 关联衣物 |
| `garment_category` | `VARCHAR(20)` | `TOP` / `BOTTOM` / `SHOES` |
| `sort_order` | `INTEGER` | 输入顺序 |
| `garment_image_path` | `TEXT` | 本次生成使用的衣物图路径 |
| `created_at` | `TIMESTAMP` | 创建时间 |

建议约束：

- `UNIQUE(task_id, clothing_item_id)`
- 同一 `task_id` 下 `garment_category` 不得重复

### 7.2 `outfits`

当前版本里，`outfits` 的职责与之前“画布布局存档”不同，应调整为“已确认的预览结果”。

建议字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `UUID` PK | Outfit 主键 |
| `user_id` | `UUID` FK -> `users.id` | 所属用户 |
| `preview_task_id` | `UUID` FK -> `outfit_preview_tasks.id` | 来源预览任务 |
| `name` | `VARCHAR(120)` nullable | 用户命名，可选 |
| `preview_image_path` | `TEXT` | 最终确认的预览图 |
| `created_at` | `TIMESTAMP` | 创建时间 |
| `updated_at` | `TIMESTAMP` | 更新时间 |

注意：

- `outfits` 不再承担生成状态记录
- `outfits` 只保存成功结果，不保存处理中状态

### 7.3 `outfit_items`

建议保留关联表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `UUID` PK | 主键 |
| `outfit_id` | `UUID` FK -> `outfits.id` | 所属 outfit |
| `clothing_item_id` | `UUID` FK -> `clothing_items.id` | 关联衣物 |
| `created_at` | `TIMESTAMP` | 创建时间 |

当前版本建议增加约束：

- `UNIQUE(outfit_id, clothing_item_id)`

当前版本中，单件试穿会生成 1 条 `outfit_items`，整套穿搭则会生成多条 `outfit_items`，其中可包含鞋子。

保留关联表的理由是：

- 避免后续从单件扩展到多件时再次改模
- 满足“通过外键关联相关衣物”的要求

---

## 8. Prompt 选择规则

当前版本不做复杂策略系统，只做一个简单的后端映射层。

输入维度只有两个：

- `person_view_type`
- `garment_categories[]`

因此当前至少需要覆盖以下模板键：

- `full_body_top_tryon`
- `full_body_bottom_tryon`
- `full_body_shoes_tryon`
- `full_body_outfit_tryon`
- `upper_body_top_tryon`
- `upper_body_bottom_tryon`

说明：

- `UPPER_BODY + SHOES` 不是推荐组合，若产品暂不开放，应由前端拦截
- `OUTFIT` 不是单独类别，而是后端根据 `garment_categories[]` 组合推断出的模板分支

说明：

- 后端根据这两个枚举值选择模板键
- 具体 prompt 文本由服务层内部维护
- 当前不展开更复杂的 prompt version 管理

---

## 9. 异步任务流

建议流程如下：

1. API 接收请求
2. 保存用户自拍到对象存储
3. 读取 `clothing_item_ids[]` 对应衣物图
4. 插入 `outfit_preview_tasks(status=PENDING)`
5. 投递异步 worker
6. worker 领取任务并置为 `PROCESSING`
7. worker 调用外部生成 API
8. 成功后保存结果图并写回 `preview_image_path`
9. 将任务置为 `COMPLETED`
10. 若失败则置为 `FAILED`，记录 `error_code` 和 `error_message`

### 9.1 与现有处理流水线的边界

当前 `processing_tasks` 是围绕 `clothing_items` 的单品处理流水线。

`outfit_preview_tasks` 不能混入 `processing_tasks`，因为两者语义不同：

- `processing_tasks`: 处理衣物资产
- `outfit_preview_tasks`: 生成用户试穿预览

因此：

- 新增独立模型
- 新增独立 service
- 新增独立异步 task 入口

---

## 10. 存储策略

建议对象存储路径拆分：

- 用户自拍：`outfit-previews/{user_id}/{task_id}/person.jpg`
- 结果图：`outfit-previews/{user_id}/{task_id}/result.png`

说明：

- `garment_image_path` 通常来自既有 `clothing_item` 图像，不需要重复上传
- 若后续支持外部服饰图上传，再引入独立服饰输入路径

---

## 10.1 DashScope 千问请求模版

后端调用 DashScope 时，HTTP 结构应与以下模版保持一致，只是输入图片 URL 和文本提示会由服务层动态组装：

```bash
curl --location 'https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation' \
--header 'Content-Type: application/json' \
--header "Authorization: Bearer $DASHSCOPE_API_KEY" \
--data '{
    "model": "wan2.7-image-pro",
    "input": {
        "messages": [
            {
                "role": "user",
                "content": [
                    {"image": "https://example.com/person.jpg"},
                    {"image": "https://example.com/top.png"},
                    {"image": "https://example.com/bottom.png"},
                    {"image": "https://example.com/shoes.png"},
                    {"text": "根据输入图片生成自然真实的试穿预览图"}
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
}'
```

实现要求：

- `Authorization` 来自后端环境变量，不得由前端传入
- `content` 中图片顺序必须稳定，建议顺序为 `person -> top -> bottom -> shoes`
- `text` 提示由后端根据模板键动态生成
- 后端需要记录本次请求所用的 provider、model 和模板键

### 10.2 DashScope 成功响应格式

当前已确认 `wan2.7-image-pro` 成功时会同步返回如下结构：

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

后端解析规则：

- 必须先校验 `output.finished == true`
- 从 `output.choices[0].message.content[]` 中寻找 `type == "image"` 的对象
- 读取其中的 `image` 作为结果图 URL
- `request_id` 需要记录到日志，并建议持久化到任务表的 provider 请求标识字段
- `usage` 可作为调试和后续计费统计依据，当前阶段可先记录日志

如果出现以下任一情况，应视为任务失败：

- `output.finished != true`
- `choices` 为空
- `content` 中找不到 `type == "image"` 的对象
- `image` 字段为空

### 10.3 DashScope 异常响应格式

当前已确认异常时会返回如下结构：

```json
{
  "request_id": "a4d78a5f-655f-9639-8437-xxxxxx",
  "code": "InvalidParameter",
  "message": "num_images_per_prompt must be 1"
}
```

后端处理规则：

- `request_id` 必须记录到日志
- `code` 写入 `outfit_preview_tasks.error_code`
- `message` 写入 `outfit_preview_tasks.error_message`
- 任务状态置为 `FAILED`

错误处理建议：

- 对 `InvalidParameter` 这类请求构造错误，不做自动重试
- 对网络超时、上游 `5xx`、临时连接错误，可在 worker 层做有限重试

---

## 11. 前后端联调要求

前端联调时必须满足：

1. 只能从当前用户自己的衣物里选择 1 件衣物
2. 或从当前用户自己的衣物里选择一整套穿搭，允许包含鞋子
3. 必须提交 `clothing_item_ids[]`
4. 必须提交 `person_view_type`
5. 必须提交 `garment_categories[]`
6. 收到 `202` 后开始轮询任务状态
7. 只有在 `COMPLETED` 后才允许点击“保存穿搭”

后端联调时必须保证：

1. 越权读取他人 `clothing_item` 返回 `404`
2. 任务失败时状态明确，不出现永久 `PENDING`
3. 失败后能返回错误信息
4. 成功任务能返回可访问的 `previewImageUrl`

---

## 12. 非目标

当前阶段明确不做：

- 复杂 outfit 画布布局保存
- 叠穿层级编辑
- 智能推荐搭配
- prompt AB 实验平台
- 前端直接上传任意陌生服饰图并保存为可关联 outfit

---

## 13. 推荐落地顺序

1. 先落 `outfit_preview_tasks`、`outfit_preview_task_items` 表和 SQLAlchemy 模型
2. 再落 `POST /outfit-preview-tasks` 和 `GET /outfit-preview-tasks/{id}`
3. 接着打通异步生成 worker
4. 然后新增 `POST /outfit-preview-tasks/{id}/save`
5. 最后再补列表接口与清理策略

这个顺序的原因是：

- 先跑通“提交请求 -> 产出图片”
- 再补“成功结果保存为 outfit”
- 避免一开始把 outfit 管理和 preview 任务耦合在一起
