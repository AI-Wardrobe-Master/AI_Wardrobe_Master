# Windows 本地应用打包与一键启动维护说明

## 1. 功能定位

本项目原本主要以 Flutter Web 前端配合 Docker 后端的方式运行。为方便在 Windows 环境下进行演示和本地测试，当前额外提供了一套 Windows 本地应用包方案：

- Flutter 前端打包为 Windows 桌面应用。
- FastAPI 后端、PostgreSQL、Redis、Celery、DreamO 仍通过 Docker Compose 启动。
- 通过 `start_app.bat` 和 `stop_app.bat` 提供一键启动和停止入口。
- Hunyuan3D 默认关闭，避免在低内存或低显存环境中启动失败。

该方案不是把所有后端和模型强行塞进一个单文件 exe，而是将前端应用、后端服务配置和启动脚本组织成一个可移动的本地应用包。

## 2. 当前打包产物位置

当前已生成的本地应用包位于：

```text
D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master
```

完整压缩包位于：

```text
D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master_Full_Local_App.zip
```

Windows 前端 release 产物位于：

```text
D:\AI_Wardrobe_Windows_Build\ai_wardrobe_app\build\windows\x64\runner\Release
```

## 3. 应用包目录结构

应用包结构如下：

```text
AI_Wardrobe_Master/
  app/
    ai_wardrobe_app.exe
    data/
    flutter_windows.dll
    file_selector_windows_plugin.dll
    permission_handler_windows_plugin.dll

  server/
    backend/
    DreamO/
    Hunyuan3D-2/
    docker-compose.yml
    .env

  start_app.bat
  stop_app.bat
  README.txt
```

各目录作用：

- `app/`：Flutter Windows 桌面前端，运行时需要保留整个目录，不能只复制单独的 exe。
- `server/`：Docker Compose 后端运行目录，包含后端代码、DreamO 服务代码和环境变量配置。
- `start_app.bat`：启动 Docker 后端并打开 Windows 桌面前端。
- `stop_app.bat`：停止 Docker 后端服务，但保留数据库和模型缓存卷。
- `README.txt`：面向使用者的简要说明。

## 4. 启动流程

使用步骤：

1. 先启动 Docker Desktop。
2. 双击 `start_app.bat`。
3. 脚本会进入 `server/` 目录并执行：

```bat
docker compose up -d --build
```

4. Docker 服务启动后，脚本会打开：

```text
app\ai_wardrobe_app.exe
```

5. 使用结束后，关闭桌面应用，再双击 `stop_app.bat` 停止后端。

## 5. 关键环境变量

应用包中的 `server\.env` 默认采用低资源配置：

```env
HUNYUAN3D_ENABLED=false
HUNYUAN3D_LOW_VRAM=true
HUNYUAN3D_SKIP_TEXTURE=true
HUNYUAN3D_SHAPE_STEPS=12
HUNYUAN3D_OCTREE_RESOLUTION=256
HUNYUAN3D_NUM_CHUNKS=4000

DREAMO_OFFLOAD=true
DREAMO_DEFAULT_STEPS=4
DREAMO_GENERATE_TIMEOUT_SECONDS=900

BACKEND_HOST_PORT=8000
DREAMO_HOST_PORT=9000
POSTGRES_HOST_PORT=5432
REDIS_HOST_PORT=6379
```

说明：

- `HUNYUAN3D_ENABLED=false`：默认跳过 Hunyuan3D，避免本地 3D 模型生成占用过高资源。
- `DREAMO_OFFLOAD=true`：DreamO 使用低显存策略。
- `DREAMO_DEFAULT_STEPS=4`：降低默认生成步数，减少等待时间和资源压力。
- `HUGGINGFACE_HUB_TOKEN` / `HF_TOKEN`：如果在新电脑上需要下载受限模型权重，可在 `.env` 中填写。

## 6. 重新构建 Windows 前端

由于原项目路径中包含中文目录，Windows MSBuild 可能出现路径编码问题。因此当前采用英文路径进行 Windows release 构建：

```text
D:\AI_Wardrobe_Windows_Build\ai_wardrobe_app
```

重新构建步骤：

```powershell
cd D:\AI_Wardrobe_Windows_Build\ai_wardrobe_app
flutter clean
flutter pub get
flutter build windows --release
```

构建成功后产物会生成在：

```text
build\windows\x64\runner\Release
```

更新应用包时，将该 `Release` 目录中的全部文件复制到：

```text
D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master\app
```

注意：Flutter Windows 应用不能只复制 `ai_wardrobe_app.exe`，还必须携带 `data/`、`flutter_windows.dll` 和插件 DLL。

## 7. 重新打包压缩包

如果更新了 `app/` 或 `server/`，可以重新生成 zip：

```powershell
$pkgRoot = 'D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master'
$zip = 'D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master_Full_Local_App.zip'
Compress-Archive -Path $pkgRoot -DestinationPath $zip -Force
```

## 8. 验证方式

基础验证：

```powershell
cd D:\AI_Wardrobe_Windows_Package\AI_Wardrobe_Master\server
docker compose config --quiet
```

运行验证：

1. 启动 Docker Desktop。
2. 双击 `start_app.bat`。
3. 检查 Docker 容器是否启动：

```powershell
docker compose ps
```

4. 打开桌面应用后，测试登录、衣物列表、图片上传、Discover、Visualize 等主要页面。

## 9. 常见问题

### 9.1 为什么不能做成真正的单文件 exe？

项目不仅包含 Flutter 前端，还包含 Python 后端、数据库、Redis、Celery worker、DreamO 和模型权重。强行打成单个 exe 会导致体积过大、启动复杂、GPU 与 Docker 权限难以管理，也不利于维护。

因此当前采用“桌面前端 + Docker 后端 + 一键脚本”的工程方案。

### 9.2 为什么第一次启动很慢？

第一次启动可能需要构建 Docker 镜像、初始化数据库、加载 DreamO，或者下载模型权重。后续如果 Docker volume 没有删除，启动会明显更快。

### 9.3 停止脚本会不会删除数据？

`stop_app.bat` 使用：

```bat
docker compose down
```

该命令会停止并移除容器，但不会删除 Docker volumes，因此数据库数据和模型缓存会保留。

### 9.4 Hunyuan3D 为什么默认关闭？

当前本地测试环境中，Hunyuan3D 即使使用 mini-fast 和低显存参数，也可能在加载阶段因为内存不足导致 worker 被系统终止。为保证演示和前端流程可用，当前本地应用包默认关闭 Hunyuan3D。

如需重新启用，可修改 `server\.env`：

```env
HUNYUAN3D_ENABLED=true
```

但需要同时确认 Docker Desktop 内存限制、系统内存、GPU 显存和模型权重均满足要求。

