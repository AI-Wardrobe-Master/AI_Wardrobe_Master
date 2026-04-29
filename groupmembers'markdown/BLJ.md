## blj 工作记录

### 2026.3.6
#### 1. 可视化模块首轮实现

这一阶段主要完成 `Visualize` 页面及其相关交互，目标是把原本偏占位式的页面推进成一个可以演示完整穿搭流程的前端模块。

#### 2. 已完成内容

##### 2.1 可视化主画布重构
- 将原来的占位式区域替换为全身参考照片画布
- 在画布上保留四个身体区域入口：
  - `Head`
  - `Upper Body`
  - `Lower Body`
  - `Feet`
- 每个区域通过半透明 `+` 热点进入选衣流程
- 画布支持展示已穿衣物状态，而不是只显示空白占位

##### 2.2 分区服饰选择
- 为四个身体区域分别建立可选服饰目录
- `Head` 与 `Feet` 使用单件穿戴逻辑
- `Upper Body` 与 `Lower Body` 支持分层穿搭
- 分层规则当前为最多 3 层：
  - `Layer 1`
  - `Layer 2`
  - `Layer 3`

##### 2.3 服饰卡片交互重构
- 点击卡片正文：进入衣物详情入口
- 点击 `Wear`：执行穿上逻辑
- 点击 `Remove`：执行脱下逻辑
- 相比旧版 `Actions` 入口，移动端交互更直接

##### 2.4 分层穿搭逻辑
- 上衣和下装点击 `Wear` 后不会直接替换
- 系统会弹出层级选择面板
- 用户可以明确指定穿在 `Layer 1/2/3`
- 目标层已有衣物时会提示替换关系

##### 2.5 已穿标签展示优化
- 将过大的横向标签缩小为更紧凑的状态展示
- 上衣和下装已穿标签支持堆叠显示
- 标签支持点击后进入详情入口
- 标签位置重新调整，尽量避免遮挡 `+` 热点
- 标签文案统一从 `Active` 调整为 `Wearing`

##### 2.6 衣物详情入口预留
- 已预留“点击卡片正文 / 点击已穿标签进入衣物详情”的路径
- 当前可显示基础信息、当前穿着状态、所属区域、材质、描述
- 该部分当时仍属于过渡版详情入口

##### 2.7 预览生成流程
- 页面底部提供 `Generate Preview`
- 流程为：
  1. 用户完成穿搭选择
  2. 点击 `Generate Preview`
  3. 弹出预览弹窗
  4. 展示生成效果图
  5. 支持 `Close` / `Save to Gallery`
- 当时使用的是预置预览图资源，用于打通交互，不代表真实后端生成

##### 2.8 清空逻辑
- 页面底部保留 `Clear`
- 清空当前已选服饰与分层状态
- 回到原始参考图状态，便于重新搭配

##### 2.9 保存到手机相册
- 完成 Android 原生保存逻辑接入
- Flutter 通过 `MethodChannel` 调用 Android 原生代码
- Android 使用 `MediaStore` 将预览图写入系统相册

#### 3. 当时涉及文件
- `ai_wardrobe_app/lib/ui/screens/outfit_canvas_screen.dart`
- `ai_wardrobe_app/android/app/src/main/kotlin/com/example/ai_wardrobe_app/MainActivity.kt`
- `ai_wardrobe_app/pubspec.yaml`
- `ai_wardrobe_app/assets/visualization/source/full_body_reference.jpg`
- `ai_wardrobe_app/assets/visualization/preview/generated_outfit_preview.jpg`
- `ai_wardrobe_app/test/ui/screens/outfit_canvas_screen_test.dart`

#### 4. 当时验证结果
- 本地 `flutter test` 通过
- 新增可视化页面 Widget Test
- Android 真机完成安装与运行
- 验证了：
  - 打开服饰选择器
  - 点击卡片进入详情入口
  - 点击 `Wear` 选择层级
  - 点击 `Remove` 脱下衣物
  - 点击 `Generate Preview` 弹出预览
  - 点击 `Save to Gallery` 保存到手机相册

### 2026.4.20
#### 基于主分支提交 `e4e6a9f feat: ship wardrobe sharing and mobile validation fixes` 的扩展工作

这一阶段不再只是 `Visualize` 单页，而是把之前的可视化、衣柜分享、Discover 公开浏览、个人页登录态、共享详情与真机验证合并成一条完整链路。  
本节内容主要根据以下提交与其相关改动文件整理：

- `e4e6a9f feat: ship wardrobe sharing and mobile validation fixes`
- 相关迁移：
  - `20260417_000011_add_uid_and_subwardrobe_metadata.py`
  - `20260418_000012_add_clothing_metadata_fields.py`
  - `20260418_000013_fix_preview_svg_availability_defaults.py`
  - `20260420_000014_link_card_packs_to_public_wardrobes.py`

#### 1. 本轮主要目标

把以下问题真正修到可上线演示的程度，而不是只做界面占位：

- 登录后个人页仍显示 `not signed in`
- 子衣柜分享入口不完整
- Discover 中 `packs` 和 `wardrobes` 分裂
- 共享衣柜里的衣物卡点不开
- 跨账号打开共享衣物时只能看到名称，看不到图片
- 首页长按“删除”后只是缩略图消失，没有真正删除并清缓存
- `Visualize` 顶部标题过高，遮挡内容
- 需要新增“人脸 + 衣物 + 场景”的第二种可视化入口，但后端模型还未部署

#### 2. 登录注册与个人页状态修正

##### 2.1 后端认证入口整理
涉及文件：
- `backend/app/api/v1/auth.py`
- `backend/app/schemas/auth.py`
- `backend/app/crud/user.py`

已完成内容：
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/logout`
- 注册与登录时都调用 `ensure_main_wardrobe`
- 登录响应补充 `uid`

结果：
- 用户注册或登录后可立即拿到稳定的业务编号 `uid`
- 不会再因为主衣柜缺失导致后续页面状态异常

##### 2.2 `/me` 驱动个人页
涉及文件：
- `backend/app/api/v1/me.py`
- `ai_wardrobe_app/lib/services/me_api_service.dart`
- `ai_wardrobe_app/lib/ui/screens/profile_screen.dart`

已完成内容：
- `/me` 返回当前用户真实上下文
- 返回字段包括：
  - `id / uid / username / email / type`
  - `creatorProfile`
  - `capabilities`
- 个人页从 `/me` 拉取数据，而不是依赖旧本地占位信息

结果：
- “登录后个人页仍显示 not signed in” 已修复
- 个人页可以正确展示 UID、账号信息和创作者相关状态

#### 3. 主壳层与入口结构调整

涉及文件：
- `ai_wardrobe_app/lib/ui/root_shell.dart`

已完成内容：
- 移动端主结构统一为：
  - `Wardrobe`
  - `Discover`
  - 中央 `Add`
  - `Visualize`
  - `Profile`
- 中央 `Add` 提供两条主路径：
  - `CameraCaptureScreen -> ClothingIntakeScreen`
  - `CardPackCreatorScreen`
- Web 侧同步使用 `NavigationRail`

结果：
- 页面层级更统一
- 可视化与个人页都进入主壳层稳定导航

#### 4. 可视化升级为双模式 Hub

##### 4.1 Visualize 一级入口重构
涉及文件：
- `ai_wardrobe_app/lib/ui/screens/visualization_hub_screen.dart`
- `ai_wardrobe_app/lib/ui/screens/outfit_canvas_screen.dart`

已完成内容：
- 原先的单一 `Visualize` 页面升级为 Hub
- 顶部高度和 `Discover` 等一级页对齐
- 增加两个 tab：
  - `Canvas Studio`
  - `Face + Scene`
- `Canvas Studio` 继续承接 3 月已经完成的 `OutfitCanvasScreen`

结果：
- 旧有可视化能力得到保留
- 页面标题层级统一，不再因标题过高遮挡内容

##### 4.2 Face + Scene Demo 新增
涉及文件：
- `ai_wardrobe_app/lib/ui/screens/scene_preview_demo_screen.dart`

已完成内容：
- 支持上传用户人脸照
- 支持从衣柜中选择一张衣物资料卡
- 支持输入场景描述
- 点击 `Generate Demo Preview` 返回固定 demo 图

说明：
- 这里明确是 demo 流程
- 当前不是后端真实 AI 生成
- 这样先把前端交互、参数组织和入口逻辑稳定下来

#### 5. 子衣柜公开分享与 Discover 合并

##### 5.1 衣柜模型扩展
涉及文件：
- `backend/app/models/wardrobe.py`
- `backend/app/schemas/wardrobe.py`
- `backend/app/crud/wardrobe.py`
- `backend/app/api/v1/wardrobe.py`

已完成内容：
- 为 wardrobe 增加共享和检索所需字段：
  - `wid`
  - `parent_wardrobe_id`
  - `outfit_id`
  - `kind`
  - `type`
  - `source`
  - `cover_image_url`
  - `auto_tags`
  - `manual_tags`
  - `is_public`

语义：
- `kind`: `MAIN / SUB`
- `type`: `REGULAR / VIRTUAL`
- `source`: `MANUAL / OUTFIT_EXPORT / IMPORTED / CARD_PACK`
- `wid`: 对外分享和检索的业务编号

##### 5.2 子衣柜分享入口修复
涉及文件：
- `ai_wardrobe_app/lib/ui/screens/wardrobe_screen.dart`
- `ai_wardrobe_app/lib/services/wardrobe_service.dart`

已完成内容：
- 分享子衣柜前，如果当前 `isPublic = false`，先更新为 `true`
- 然后再复制或展示分享使用的 `wid`

结果：
- 修复“打开子衣柜之后还是看不见分享”问题
- 分享状态和 Discover 浏览状态保持一致

##### 5.3 Discover 中 packs 与 wardrobes 合并
涉及文件：
- `ai_wardrobe_app/lib/ui/screens/discover_screen.dart`
- `backend/app/crud/card_pack.py`

已完成内容：
- Discover 当前只有两个 tab：
  - `Wardrobes`
  - `Creators`
- 公开的 card pack 和共享 wardrobe 统一出现在 `Wardrobes` 中
- 仅通过来源标签区分：
  - `source == CARD_PACK` -> `Card Pack`
  - 其他共享子衣柜 -> `Shared Wardrobe`

结果：
- 用户不需要再理解两套公开内容入口
- 产品语义统一为“公开可访问的子衣柜”

##### 5.4 按 `wid` / `ownerUid` 搜索共享内容
涉及文件：
- `backend/app/crud/wardrobe.py`
- `ai_wardrobe_app/lib/ui/screens/discover_screen.dart`

已完成内容：
- 公开检索覆盖：
  - 衣柜名称
  - `wid`
  - `ownerUid`
  - `ownerUsername`
  - 描述
  - 自动标签 / 手动标签

结果：
- Discover 中可直接通过发布者 UID 或衣柜 WID 搜索共享内容

#### 6. 共享衣柜详情和共享衣物详情页

##### 6.1 共享衣柜详情
涉及文件：
- `ai_wardrobe_app/lib/ui/screens/shared_wardrobe_detail_screen.dart`

已完成内容：
- 通过 `fetchWardrobeByWid` 加载共享衣柜
- 通过 `fetchPublicWardrobeItemsByWid` 加载公开衣物
- 页面展示 `WID`、`Publisher UID` 等元信息
- 共享衣物卡从静态展示改为可点击

结果：
- 修复“分享衣柜里点不开衣物资料卡”的问题

##### 6.2 共享衣物只读详情
涉及文件：
- `ai_wardrobe_app/lib/ui/screens/shared_clothing_detail_screen.dart`

已完成内容：
- 新增共享场景下专用只读详情页
- 展示：
  - 图片
  - 名称
  - 描述
  - WID
  - Publisher UID
  - 材质、风格、标签等元信息
- 不暴露删除、编辑等私有操作

结果：
- 共享内容浏览和私有衣物管理彻底分开
- 交互语义更清楚

#### 7. 跨账号共享图片权限修复

涉及文件：
- `backend/app/api/v1/files.py`

问题根因：
- 共享 wardrobe 接口会返回共享衣物的图片 URL
- 但旧的 `/files/clothing-items/{item_id}/{kind}` 只允许衣物所有者访问
- 因此其他账号只能看到名称，图片加载失败

已完成内容：
- 增加 `_can_view_shared_clothing_item`
- 文件接口改为支持可选登录态
- 允许以下两类访问：
  - 衣物所有者本人
  - 该衣物属于公开 `SUB` wardrobe 的其他账号

结果：
- 跨账号查看共享衣物时可以正常看到图片
- 私有衣物仍不会被错误暴露

#### 8. 首页删除语义修正与本地缓存清理

涉及文件：
- `ai_wardrobe_app/lib/ui/screens/wardrobe_screen.dart`
- `ai_wardrobe_app/lib/services/clothing_api_service.dart`
- `ai_wardrobe_app/lib/services/local_clothing_service.dart`

已完成内容：
- 主衣柜长按：
  - 调用真实衣物删除接口
  - 删除衣物实体
  - 清理本地缓存与本地索引
- 子衣柜长按：
  - 只移除 wardrobe 与 clothing item 的关联

结果：
- “删除”不再只是让首页预览缩略图消失
- 主衣柜里的衣物会真正从首页消失，并清理对应缓存

#### 9. 卡包发布与公开子衣柜映射

涉及文件：
- `backend/app/crud/card_pack.py`
- `backend/app/api/v1/card_packs.py`

已完成内容：
- 发布 card pack 时，创建或复用一个公开 `SUB` wardrobe
- 该 wardrobe 标记：
  - `source = CARD_PACK`
  - `is_public = True`
- 归档 card pack 时，将对应共享 wardrobe 隐藏

结果：
- card pack 与共享 wardrobe 使用同一套 Discover 浏览抽象
- 与产品上“packs 和 wardrobes 本质相同”的要求一致

#### 10. 真机联调与跨账号验证

##### 10.1 Android 真机联调方式
- 本地后端启动
- Windows 通过 USB 连接 Android 手机
- 使用 `adb reverse tcp:8000 tcp:8000`
- Flutter 真机访问本地 `127.0.0.1:8000`

##### 10.2 已实际验证的流程
- 注册与登录
- 个人页通过 `/me` 正确显示账号状态
- 子衣柜分享
- Discover 公开 wardrobe 列表
- 通过 `wid` / `publisher uid` 搜索共享内容
- A 账号分享，B 账号可在 Discover 中看到
- B 账号打开共享衣柜时能够看到共享衣物图片
- 共享衣物卡可点开进入只读详情页
- 主衣柜长按删除后，衣物从首页消失并清理缓存
- `Visualize` 页面标题高度与其他一级页对齐

#### 11. 本轮主要新增或重构文件

##### Flutter
- `ai_wardrobe_app/lib/services/auth_api_service.dart`
- `ai_wardrobe_app/lib/services/me_api_service.dart`
- `ai_wardrobe_app/lib/services/local_wardrobe_service.dart`
- `ai_wardrobe_app/lib/ui/screens/clothing_detail_screen.dart`
- `ai_wardrobe_app/lib/ui/screens/scene_preview_demo_screen.dart`
- `ai_wardrobe_app/lib/ui/screens/shared_clothing_detail_screen.dart`
- `ai_wardrobe_app/lib/ui/screens/shared_wardrobe_detail_screen.dart`
- `ai_wardrobe_app/lib/ui/screens/visualization_hub_screen.dart`

##### Backend
- `backend/alembic/versions/20260417_000011_add_uid_and_subwardrobe_metadata.py`
- `backend/alembic/versions/20260418_000012_add_clothing_metadata_fields.py`
- `backend/alembic/versions/20260418_000013_fix_preview_svg_availability_defaults.py`
- `backend/alembic/versions/20260420_000014_link_card_packs_to_public_wardrobes.py`

#### 12. 总结

和 3 月 6 日那一版相比，这一轮不是只增加一个界面，而是把以下能力真正连成了完整闭环：

- 登录注册
- `/me` 用户态
- 子衣柜分享
- Discover 公共浏览
- 按 `wid` / `uid` 搜索
- 共享衣物详情
- 跨账号共享图片权限
- 首页删除与缓存清理
- `Visualize` 双模式入口
- Android 真机验证

因此，`blj` 这部分工作现在可以同时覆盖：

- 原有可视化模块建设
- 后续共享链路、个人页状态、Discover 合并和真机验证相关扩展

这份记录已经不再是单纯的页面说明，而是与主分支真实 commit 和落地代码一致的工作说明。
