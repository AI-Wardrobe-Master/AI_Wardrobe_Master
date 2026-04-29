## wzh 工作记录

### 1. 前端功能开发与整合（Module 4）

#### 1.1 本次工作的主要内容

本次工作主要围绕 **我负责的 Module 4 前端功能开发、整合与接入当前项目版本** 展开。

我在这一部分主要完成了以下几条关键前端业务链路：

- 添加卡包（Card Pack）
- 将上传/拍照后的衣物转成可展示的资产卡片
- `Profile` 页面中的 `Imported looks` 可点击进入
- Discover / Creator / Imported 流程的页面与数据链路

因此，本次我围绕这些功能继续完成整合、接线、兼容处理与验证，使其能够在当前项目中形成可运行、可测试的完整前端流程。

---

#### 1.2 我完成的前端开发内容

##### 1.2.1 梳理并确认 Module 4 前端功能范围

- 梳理 Module 4: Platform Content and Outfit Collections 对应的前端功能范围。
- 对照当前仓库中的页面、模型、服务与组件，确认需要接入的页面与业务链路。
- 明确这一部分工作的重点不是单一页面，而是卡包、创作者、导入记录、虚拟衣柜等一整条前端流程。

##### 1.2.2 完成卡包 / 创作者 / 导入相关前端模型与服务

我完成并接入了以下前端模型与服务：

- `lib/models/card_pack.dart`
- `lib/models/creator.dart`
- `lib/models/import_history.dart`
- `lib/services/card_pack_api_service.dart`
- `lib/services/creator_api_service.dart`
- `lib/services/import_api_service.dart`
- `lib/services/local_card_pack_service.dart`
- `lib/services/local_clothing_service.dart`

这些内容用于补齐：

- 卡包数据结构
- 创作者资料与列表
- 导入记录
- 本地卡包存储
- 本地简化衣物资产
- 当后端接口缺失时的本地兜底逻辑

##### 1.2.3 完成 Discover / Creator / Imported Looks 页面链路

我完成并接入了以下页面与组件：

- `DiscoverScreen`
- `CardPackDetailScreen`
- `ImportedLooksScreen`
- `CardPackCreatorScreen`
- `CreatorProfileScreen`
- `CardPackListItem`
- `CreatorListItem`
- `ClothingItemSelector`

完成后的前端效果包括：

- Discover 页面可浏览卡包与创作者
- 卡包详情页可查看卡包信息并触发导入
- 创作者页可浏览对应发布内容
- `Profile` 中的 `Imported looks` 可以真正打开
- 创建卡包时可选择已有衣物并生成卡包

##### 1.2.4 完成上传衣物后的资产卡片化链路

- 扩展 `ClothingApiService`，补回衣物列表与补图像信息逻辑。
- 修改 `ProcessingScreen`，在 3D 处理失败时支持将衣物保存为 **local simplified item**。
- 让前端即使在后端链路不完整时，仍然可以把上传衣物作为本地资产继续参与卡包流程。

这样补齐后，上传后的衣物不再只是流程终点，而是可以继续进入：

- 本地资产列表
- 卡包创建选择器
- 虚拟衣柜 / imported 展示

##### 1.2.5 完成 RootShell / Profile / Wardrobe 的整合接入

- 在 `RootShell` 的 Add BottomSheet 中加入 `Create Card Pack` 入口。
- 在 `ProfileScreen` 中加入导入统计刷新与 `ImportedLooksScreen` 跳转。
- 在 `WardrobeScreen` 中补齐本地资产、导入内容、虚拟衣柜显示与图片卡片展示逻辑。

完成后，当前前端版本已经可以支持：

- 从 Add 入口进入卡包创建
- 在 Profile 打开 imported looks
- 在衣柜中查看更接近资产卡片化的衣物展示
- 在虚拟衣柜中浏览 imported 内容

##### 1.2.6 本次补充的前端兜底方案

由于当前仓库里的后端并没有完整实现 Module 4 的所有接口，所以我在前端中补了本地降级方案，保证功能可测：

- 卡包可本地保存
- 导入记录可本地保存
- 简化衣物可本地保存
- Imported 内容可从本地记录回显到虚拟衣柜

这使得当前项目即使在 **后端接口尚未全部完成** 的情况下，也可以继续对 Module 4 前端业务流程进行演示、测试与验收。

---

#### 1.3 本次恢复工作的验证结果

- 执行了 `flutter pub get`
- 执行了 `flutter analyze --no-pub`
- 对恢复后的关键页面进行了启动级验证
- 成功重新启动前端项目，并使用 `Edge` 跑起当前版本

验证后确认：

- 当前开发内容没有引入新的阻塞性编译错误
- Module 4 关键前端链路已重新具备测试条件
- 项目可继续进行页面级手动验收

---

#### 1.4 我在这部分工作的核心贡献

本次我完成的不是单点 bug 修复，而是一次 **前端业务链路开发与当前版本整合**，核心贡献包括：

- 完成 Module 4 前端关键能力的开发与整合
- 将相关页面、模型、服务与交互链路整理并接入当前仓库
- 在当前后端不完整的情况下补足本地测试兜底
- 保证卡包、资产卡片、Imported looks 等关键功能重新可用
- 将恢复后的内容整理成独立分支并推送，便于后续 PR 与代码审查

---

### 2. Bug 修复与合并兼容性处理（2026.4.29）

#### 2.1 本次工作背景

本次工作主要围绕 **前端分支合并后的冲突与联调问题修复** 展开。根据队友反馈，在将我的前端部分与同事提交的前端内容合并后，项目出现了运行期 bug，需要对合并结果进行排查、修复，并重新验证启动流程与代码提交流程。

本次工作基于仓库：

- `AI-Wardrobe-Master/AI_Wardrobe_Master`

---

#### 2.2 本次完成内容

##### 2.2.1 拉取并比对同事版本

- 将同事提交的仓库分支单独克隆到新的目录中，避免影响我当前本地工作区。
- 对比当前本地前端分支与同事版本的 `ai_wardrobe_app/lib/` 目录结构与关键页面文件。
- 检查当前分支状态、前端差异文件、近期提交记录，确认问题来自前端合并后的兼容性，而不是单纯缺文件或缺页面。

##### 2.2.2 排查前端合并后的问题

- 对 Flutter 前端执行静态分析，确认没有新的编译级错误。
- 重点检查了以下与 Module 4 前端流程相关的页面与服务：
  - `DiscoverScreen`
  - `ProfileScreen`
  - `WardrobeScreen`
  - `RootShell`
  - `CardPackDetailScreen`
  - `CreatorApiService`
  - `api_config.dart`
- 对照现有前端实现、文档设计和运行表现，定位到合并后存在的兼容性问题主要集中在：
  - API / 文件资源地址在不同平台上的适配问题
  - 创作者信息在本地降级逻辑中的错误回退问题

##### 2.2.3 修复的具体问题

- 修复 `ai_wardrobe_app/lib/services/api_config.dart`
  - 将接口地址与文件地址改为按平台自动选择
  - Web 默认使用 `localhost`
  - Android 模拟器默认使用 `10.0.2.2`
  - 支持通过 `--dart-define=API_HOST=...` 覆盖
- 修复 `ai_wardrobe_app/lib/ui/screens/card_pack_detail_screen.dart`
  - 将卡包详情页中写死的图片地址 `http://localhost:8000` 改为统一使用 `fileBaseUrl`
  - 避免在不同设备或运行方式下出现封面图无法加载的问题
- 修复 `ai_wardrobe_app/lib/services/creator_api_service.dart`
  - 当创作者接口请求失败时，不再错误回退到本地列表中的第一个创作者
  - 改为优先匹配对应 `creatorId`
  - 若本地也不存在该创作者，则返回占位创作者信息，避免页面显示串人或跳错数据

---

#### 2.3 验证与联调结果

- 对修改后的关键文件执行 `flutter analyze`，确认前端仍然满足基础静态检查要求。
- 成功重新启动 Flutter 项目并确认可运行。
- 使用 `Edge` 成功启动前端项目，说明本次修复后的前端主流程至少满足基础运行要求。
- 相关修复完成后，可以继续由人工进行页面级功能测试。

---

#### 2.4 本次工作的价值

本次工作的核心价值在于把“已经合并但运行不稳定”的前端状态，修复为“可以正常启动并继续测试”的状态，具体体现在：

- 降低了前端分支合并后的兼容性风险
- 修复了卡包详情页资源加载异常的问题
- 修复了创作者资料页可能出现的数据串位问题
- 保证了 Module 4 相关前端流程能够继续联调和验证
- 为后续创建 PR、代码审查和团队集成提供了一个清晰、可追踪的修复分支

---

#### 2.5 相关文件

- `ai_wardrobe_app/lib/services/api_config.dart`
- `ai_wardrobe_app/lib/services/creator_api_service.dart`
- `ai_wardrobe_app/lib/ui/screens/card_pack_detail_screen.dart`

---

### 3. 简要总结

本阶段我的工作主要包括两部分：

- 第一部分是完成我负责的 Module 4 前端功能，并整合到当前仓库中；
- 第二部分是在前端合并后继续处理兼容性问题、完成 bug 修复并重新验证项目启动。

经过本次处理，项目中的卡包、创作者、Imported looks、资产卡片化与虚拟衣柜相关前端流程已经具备测试条件，前端项目也能够正常启动并继续进行人工验收。

---

### 4. 本地联调、图片上传与 3D 模型部署测试（2026.4.29）

#### 4.1 本次联调背景

本阶段工作主要围绕当前项目在本机环境中的完整运行、前后端联通、衣物图片上传、数据库保存以及后端 AI 处理流程展开。由于项目原本同时包含 Flutter 前端、FastAPI 后端、PostgreSQL、Redis、Celery、DreamO 和 Hunyuan3D 等多个模块，因此本阶段重点不是单一页面开发，而是把已有前端功能放到真实后端环境中进行联调验证。

本机环境具备：

- Flutter 开发环境
- Docker Desktop
- NVIDIA RTX 4060 Laptop GPU，约 8GB 显存
- C 盘和 D 盘均有足够空间用于 Docker 镜像、模型缓存和测试数据

#### 4.2 项目启动与环境配置

本阶段完成了以下启动和配置工作：

- 创建项目目录 `AI_MASTER`，并拉取 `AI_Wardrobe_Master` 仓库。
- 阅读项目说明和代码结构，确认项目由 Flutter 前端、FastAPI 后端、数据库、队列任务和 AI 模型服务组成。
- 使用 Docker Compose 启动后端相关服务，包括：
  - `backend`
  - `db`
  - `redis`
  - `celery-clothing`
  - `celery-beat`
  - `celery-styled-gen`
  - `dreamo`
- 启动 Flutter Web 前端，并使用 `http://127.0.0.1:3000` 进行浏览器测试。
- 多次排查前端白屏问题，最终确认白屏主要由旧 Flutter Web 进程占用端口导致，通过停止旧进程并重新启动前端恢复正常。
- 验证前端配置指向 `http://localhost:8000/api/v1`，后端健康接口、CORS 预检和部分真实 API 路由均可正常响应。

#### 4.3 图片上传与前端 Web 兼容问题修复

在 Web 端上传衣物图片时，发现 Flutter Web 不支持 `Image.file`，导致选择图库图片后页面直接报错。针对该问题完成了以下修复：

- 新增 `CapturedImage` 模型，用于同时支持本地文件路径和 Web 端图片字节数据。
- 将 Web 端图片预览逻辑改为使用 `Image.memory`。
- 调整拍照、图库选择、预览、填写信息、处理页之间的数据传递方式，使其不再依赖 Web 不支持的文件路径读取。
- 支持 PNG/JPG 图片从 Web 端上传到后端。

修复后，图库上传图片不再触发 `Image.file is not supported on Flutter Web` 错误。

#### 4.4 图片保存到数据库与本地缓存问题修复

在上传衣物并保存后，曾出现以下问题：

- 上传失败提示 `path_provider` 在 Web 端不可用。
- 图片被写入 localStorage，导致浏览器 `QuotaExceededError`。
- 新增衣物后主页需要刷新才能看到。
- 衣物详情页、主页卡片、创建卡包页面无法正确显示已上传图片。
- 新账号登录后仍看到旧账号的本地衣物缓存。

针对这些问题完成了以下调整：

- 后端支持接收并保存上传图片，将图片作为 blob 存入后端存储，并通过文件接口返回。
- 前端避免把大体积 base64 图片写入 localStorage。
- 新增远程图片加载组件，通过后端文件接口读取私有图片数据。
- 调整衣物列表、衣物详情、卡包创建、Discover 等页面的图片显示逻辑。
- 增加用户切换时清理用户相关本地缓存的逻辑，避免不同账号之间数据串用。
- 新增 wardrobe refresh 通知机制，使新增衣物后列表可以及时刷新。

#### 4.5 卡包与 Discover 流程修复

在创建卡包和 Discover 页面测试中，发现卡包创建后无法在 Discover 中看到，且卡包创建页中衣物图片不显示。针对这些问题完成了以下修复：

- 修复卡包创建页中衣物选择器的图片加载逻辑。
- 调整卡包保存和发布后的数据读取逻辑。
- 修复 Discover 页对已发布卡包和本地发布卡包的展示逻辑。
- 修复卡包详情中远程图片 URL 拼接和私有图片读取问题。

修复后，卡包创建、选择衣物、保存、发布和 Discover 展示流程具备了继续测试的基础。

#### 4.6 移动端与无效功能处理

根据测试反馈，完成了以下界面和平台兼容调整：

- 移除衣柜页面中无法正常使用的二维码按钮。
- 在移动端非 Web 环境下锁定竖屏，避免横屏导致布局溢出。
- 优化空衣柜状态显示，使没有衣物时显示正常的空状态，而不是错误信息或异常卡片。

#### 4.7 DreamO 后端模型低显存部署

为了验证后端 AI 能力，本阶段对 DreamO 服务进行了低显存部署尝试，并完成以下工作：

- 配置 Hugging Face token 用于下载模型权重。
- 采用低显存配置：
  - `DREAMO_QUANT=nunchaku`
  - `DREAMO_OFFLOAD=true`
  - `DREAMO_NO_TURBO=true`
  - `DREAMO_VERSION=v1`
- 修复 DreamO 与 nunchaku LoRA 权重之间的不兼容问题。
- 修改 DreamO Dockerfile，在镜像构建时安装兼容版本的 nunchaku，并对缺失的 LoRA key 做兼容处理。
- 成功启动 DreamO 服务，并通过 `/health` 验证 `model_loaded=true`。
- 使用一张简单测试图调用 DreamO `/generate` 接口，确认 DreamO 可以返回生成结果。

该部分说明 DreamO 图片生成服务已经能够在本机低显存环境下运行，但它并不是衣物 3D 模型生成服务。

#### 4.8 衣物处理流程从跳过模型改回真实处理

在早期前端测试中，为了先保证上传与保存流程可用，曾临时让添加衣物时传入 `skipProcessing=true`，使后端跳过模型处理。后续在 DreamO 和后端服务具备测试条件后，将该逻辑改回真实处理流程：

- `ProcessingScreen` 上传衣物时改为传入 `skipProcessing=false`。
- 上传成功后不再直接跳转结果页，而是开始轮询 `/processing-status`。
- 当前端收到处理完成状态后，再进入衣物结果页。
- 保留处理失败时的离线保存兜底能力。

这一修改让添加衣物流程重新接入后端 Celery 处理任务。

#### 4.9 使用真实衣物图片进行模型链路测试

使用桌面图片 `71QH4abNrDL._AC_SX679_.jpg` 对真实衣物上传链路进行了测试。测试结果如下：

- 图片上传成功。
- 衣物记录成功写入数据库。
- 原始图片可以通过后端文件接口读取。
- 背景处理后的 `processed-front` 图片可以保存。
- 但 3D 模型没有生成成功，`model3dUrl` 为 `null`。
- 角度视图为空，`angleViews` 返回 `{}`。
- `/model` 接口返回 404。

日志显示最初失败原因是：

```text
No module named 'hy3dgen'
```

说明当时 `celery-clothing` 容器中没有安装 Hunyuan3D 相关依赖，衣物 pipeline 只能降级完成图片处理，不能生成 3D 模型。

#### 4.10 Hunyuan3D-2 低显存部署尝试

为了继续打通衣物 3D 生成链路，本阶段尝试将 Hunyuan3D-2 接入 `celery-clothing` 容器，并采用低显存方案：

- 将本地 `Hunyuan3D-2` 代码挂载进 `celery-clothing` 容器。
- 为 `celery-clothing` 增加 GPU 访问能力。
- 安装 Hunyuan3D 所需依赖，包括：
  - `torch`
  - `torchvision`
  - `diffusers`
  - `transformers`
  - `accelerate`
  - `pymeshlab`
  - `xatlas`
  - `safetensors`
- 将模型路径切换为公开的 `tencent/Hunyuan3D-2mini`。
- 使用 `hunyuan3d-dit-v2-mini-fast` 子模型作为低显存测试权重。
- 配置低显存参数：
  - 开启 CPU offload。
  - 跳过 texture paint pipeline。
  - 降低 inference steps。
  - 降低 octree resolution。
  - 降低 num chunks。
- 暂停 DreamO 服务以释放 GPU 显存。

容器内检查结果显示：

- CUDA 可以识别 RTX 4060 Laptop GPU。
- `hy3dgen`、`torch`、`diffusers`、`transformers`、`pymeshlab`、`xatlas` 均可导入。
- Hunyuan3D-2mini-fast 权重成功开始下载，并写入 Docker volume。

#### 4.11 Hunyuan3D 测试结论：内存不足导致 worker 被杀

继续使用同一张 polo 衣物图进行 Hunyuan3D 低显存测试时，任务并非卡在普通推理慢，而是在模型加载阶段被系统杀掉。

关键现象：

- 任务状态停留在 `PROCESSING`，进度约 `30%`。
- 日志显示 Hunyuan3D-2mini-fast 权重已经下载完成并开始加载。
- 随后 Celery worker 出现：

```text
Worker exited prematurely: signal 9 (SIGKILL)
```

根据 Docker stats，当时容器可用内存限制约为 7.6GB，而 Hunyuan3D mini-fast 加载阶段仍然超过该资源限制，导致 worker 被系统直接杀掉。

因此，本次测试结论是：

- 当前机器磁盘空间足够。
- GPU 可被 Docker 识别。
- Hunyuan3D 依赖和权重下载链路已经基本打通。
- 但在当前 Docker 内存限制和 16GB 系统内存环境下，即使使用 mini-fast、CPU offload、跳过 texture，仍不足以完成模型加载。
- 当前失败主要是内存不足，不是单纯等待时间过长。

#### 4.12 当前阶段保留的结果与后续建议

当前已经可用的能力：

- 前端可以正常启动。
- 后端、数据库、Redis、文件存储可以正常运行。
- 衣物图片上传和保存成功。
- 衣物原图和 processed-front 图片可以保存并回显。
- DreamO 图片生成服务已经在低显存方案下验证可用。
- Hunyuan3D 代码、依赖、权重下载路径已经完成初步配置。

当前尚未完成的能力：

- Hunyuan3D 生成 `model.glb` 尚未成功。
- 角度视图渲染尚未成功。
- 衣物详情页中的真实 3D 预览仍然无法依赖 Hunyuan3D 产物展示。

后续建议：

- 优先增加 Docker Desktop 可用内存限制，例如提高到 12GB 或更高。
- 关闭不必要的前台应用，释放系统内存。
- 保持 DreamO 在 Hunyuan3D 测试期间停止运行，避免占用显存。
- 若仍无法加载，可考虑进一步拆分 Hunyuan3D 为独立服务，或改用更轻量的占位 3D 生成方案作为课程项目演示。
- 如果目标是前端展示和流程验收，可以先使用已上传图片和占位 3D 卡片完成演示；如果目标是真实 3D 生成，则需要更高内存环境或更轻量模型。

#### 4.13 本阶段工作价值

本阶段工作的主要价值在于把项目从“前端页面可运行”推进到“真实本地环境联调可验证”的状态：

- 明确了图片上传、数据库保存和文件回显链路已经可用。
- 明确了 DreamO 与 Hunyuan3D 在项目中的职责不同。
- 找到了衣物 3D 生成失败的真实原因，不再停留在猜测阶段。
- 完成了 Hunyuan3D 低显存部署的初步工程配置。
- 通过实际日志和资源监控确认当前瓶颈是内存不足，而不是代码没有调用模型或测试时间不够。

---

### 5. 个人资料人脸素材、Visualize 联通与页面体验优化（2026.4.29）

#### 5.1 本阶段工作背景

在前端流程继续完善过程中，项目需要支持用户上传个人头像或人脸照片，并将该素材自动用于后续的穿搭预览、全身照生成或 Visualize 相关功能。同时，考虑到部分用户不希望上传真实人脸照片，因此还需要提供虚拟头像作为替代素材。

本阶段工作主要围绕 **Profile 个人资料页的人脸素材管理** 和 **Visualize 模块的人脸素材复用** 展开，并同步处理衣物详情页图片显示体验问题。

#### 5.2 个人资料页人脸照片功能

本阶段在 `ProfileScreen` 中新增了“用于生成的人脸照片”相关能力：

- 支持从相机拍照上传人脸照片。
- 支持从图库选择已有图片。
- 选择图片后进入裁切页面，方便用户从非大头照中裁切出人脸区域。
- 裁切结果统一保存为头像生成素材。
- 支持清除当前人脸素材。
- 支持按当前登录用户隔离保存，避免不同账号之间头像素材串用。

相关新增或修改文件包括：

- `ai_wardrobe_app/lib/services/face_profile_service.dart`
- `ai_wardrobe_app/lib/ui/screens/face_crop_screen.dart`
- `ai_wardrobe_app/lib/ui/screens/profile_screen.dart`

#### 5.3 虚拟头像替代方案

为了保护用户隐私并降低测试门槛，本阶段新增了两个内置虚拟头像选项：

- 男性虚拟头像
- 女性虚拟头像

用户可以不上传真人照片，而是直接选择虚拟头像作为后续生成素材。虚拟头像由前端渲染为图片字节并保存，后续页面读取时与真实裁切头像保持统一接口。

该设计使 Profile 页面的人脸来源可以覆盖三种情况：

- 用户自拍
- 用户从图库上传
- 用户选择虚拟头像

#### 5.4 Visualize 模块与 Profile 人脸素材联通

本阶段将 Visualize 中原本需要单独上传人脸照片的流程，与 Profile 个人资料页的人脸素材进行了联通：

- Visualize 页面会自动读取当前用户在 Profile 中保存的人脸素材。
- 如果用户选择了虚拟头像，Visualize 可以直接使用虚拟头像生成的图片字节。
- 如果用户在 Visualize 中重新选择或裁切人脸，也会同步保存回 Profile，方便后续继续复用。
- 当没有可用人脸素材时，Visualize 会提示用户先选择素材，而不是直接进入不可用流程。

这样处理后，人脸素材从一次性上传变成了可复用的用户资料能力，减少了重复操作，也使个人资料页和预览生成功能之间形成了更完整的数据链路。

#### 5.5 衣物详情页图片显示与缩放体验优化

在衣物详情页测试中发现，原始衣物图片在详情页中存在两个体验问题：

- 图片在页面中被裁切，只能看到局部区域。
- 鼠标滚轮在未点开图片的情况下会触发图片缩放，影响页面滚动体验。

针对该问题，本阶段进行了如下优化：

- 详情页内嵌图片改为完整显示，避免默认裁切。
- 页面中的图片不再直接使用滚轮缩放。
- 用户点击图片后进入全屏查看模式。
- 只有在全屏查看模式中才允许使用滚轮或手势缩放图片。
- 保留页面正常滚动能力，避免图片区域劫持滚轮事件。

相关修改文件：

- `ai_wardrobe_app/lib/ui/screens/clothing_detail_screen.dart`

#### 5.6 本阶段验证结果

完成修改后，对相关前端文件进行了静态分析和运行级验证：

- `Profile` 页面可以选择拍照、图库上传或虚拟头像。
- 人脸图片裁切后可以保存并在页面回显。
- 不同登录用户之间的人脸素材独立保存。
- Visualize 页面可以自动读取 Profile 中的人脸素材。
- 衣物详情页图片可以完整显示，并且不再影响页面滚动。

#### 5.7 本阶段工作价值

本阶段工作的主要价值在于补齐了“用户个人素材”这一关键前端能力，使项目后续的全身照生成、穿搭预览和个性化展示具备更自然的数据来源。

具体价值包括：

- 提高了 Profile 页面在 AI 生成流程中的实际作用。
- 降低了用户在 Visualize 中重复上传人脸的操作成本。
- 提供虚拟头像，兼顾隐私和测试便利性。
- 优化详情页图片交互，减少误缩放和图片裁切带来的使用问题。
- 为后续接入真实生成接口提供了更清晰的人脸素材入口。

---

### 6. Windows 桌面应用打包与本地一键启动包（2026.4.29）

#### 6.1 本阶段工作背景

在 Web 版联调基本可用后，进一步尝试将项目打包成更接近桌面软件的 Windows 应用形式，方便在本机进行演示、测试和交付。由于项目并不是单纯前端应用，而是同时依赖 Docker 后端、数据库、Redis、Celery、DreamO 和可选的 Hunyuan3D，因此本阶段采用“Flutter Windows 桌面前端 + Docker 后端 + 一键启动脚本”的方案。

#### 6.2 Windows 桌面构建环境检查

本阶段首先检查并补齐了 Windows 桌面构建环境：

- 启用 Flutter Windows Desktop 支持。
- 检查 `flutter doctor -v`。
- 确认 Flutter 可以识别 `Windows (desktop)` 设备。
- 确认 Visual Studio Community 2026 和 Windows 10 SDK 可用于 Windows 桌面构建。
- 确认 Android SDK 和 Chrome 的缺失不影响 Windows 桌面打包。

由于原始项目目录包含中文路径，Windows MSBuild 在 release 构建时出现路径编码问题。因此将 Flutter 前端复制到英文路径下进行构建：

```text
D:\AI_Wardrobe_Windows_Build\ai_wardrobe_app
```

#### 6.3 Flutter Windows release 构建

在英文路径下执行了 Windows release 构建：

```powershell
flutter clean
flutter pub get
flutter build windows --release
```

最终成功生成 Windows 桌面前端：

```text
D:\AI_Wardrobe_Windows_Build\ai_wardrobe_app\build\windows\x64\runner\Release\ai_wardrobe_app.exe
```

同时确认 Flutter Windows 应用不能只复制单个 exe，必须保留整个 `Release` 目录中的 `data`、`flutter_windows.dll` 和插件 DLL。

#### 6.4 本地应用包整理

为了方便使用和交付，本阶段整理了完整的本地应用包：

```text
D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master
```

目录结构包括：

```text
AI_Wardrobe_Master/
  app/
  server/
  start_app.bat
  stop_app.bat
  README.txt
```

其中：

- `app/` 存放 Windows 桌面前端。
- `server/` 存放 Docker Compose 后端、backend 代码、DreamO 代码和环境变量配置。
- `start_app.bat` 用于启动 Docker 后端并打开桌面应用。
- `stop_app.bat` 用于停止 Docker 后端服务。
- `README.txt` 用于说明基本使用方式。

同时生成了完整压缩包：

```text
D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master_Full_Local_App.zip
```

#### 6.5 低资源默认配置

考虑到当前电脑虽然具备 RTX 4060 Laptop GPU，但 Hunyuan3D 在本地低内存环境中仍可能导致 worker 被杀死，因此应用包默认采用低资源配置：

- `HUNYUAN3D_ENABLED=false`
- `HUNYUAN3D_LOW_VRAM=true`
- `HUNYUAN3D_SKIP_TEXTURE=true`
- `DREAMO_OFFLOAD=true`
- `DREAMO_DEFAULT_STEPS=4`

这样可以保证前端、数据库、文件上传、DreamO 相关流程优先保持可用，而不会因为 Hunyuan3D 启动失败影响整体演示。

#### 6.6 配置校验与文档补充

打包完成后执行了 Docker Compose 配置校验：

```powershell
docker compose config --quiet
```

校验通过，说明打包目录中的 Compose 配置结构可被 Docker 正常解析。

同时新增维护文档：

```text
documents/WINDOWS_LOCAL_APP_PACKAGE_GUIDE.md
```

该文档说明了：

- 应用包定位
- 目录结构
- 启动和停止方式
- `.env` 中的关键配置
- 如何重新构建 Windows 前端
- 如何重新生成压缩包
- 常见问题和维护注意事项

#### 6.7 本阶段工作价值

本阶段工作的主要价值在于把项目从“开发环境运行”进一步推进为“可移动、可启动、可演示的 Windows 本地应用包”：

- 提供了比浏览器页面更接近真实应用的使用方式。
- 保留 Docker 后端，避免强行把复杂后端和模型塞入单文件 exe。
- 使用一键脚本降低启动门槛。
- 避开中文路径导致的 Windows 构建问题。
- 默认关闭 Hunyuan3D，保证本机演示稳定性。
- 为后续课程展示、测试分发和项目验收提供了更清晰的交付形态。

---
