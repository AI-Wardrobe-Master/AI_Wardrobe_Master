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
