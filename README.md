# AI Wardrobe Master

AI Wardrobe Master 团队协作仓库：Flutter 应用与组员文档。

## 仓库结构（顶层）

```
ai_wardrobe/
├── ai_wardrobe_app/              # Flutter 应用（智能衣柜 Demo）
│   ├── lib/                      # UI、主题等代码
│   ├── android/, ios/, web/ ...  # 各平台工程
│   └── README.md
├── documents/                    # 项目技术文档（架构、API、数据模型等）
├── groupmembers'markdown/        # 组员 markdown（进度、分工、个人贡献）
└── README.md                     # 本文件
```

## 快速开始（Flutter App）

```bash
# 进入应用目录
cd ai_wardrobe_app

# 安装依赖
flutter pub get

# 在浏览器中运行（适合快速预览布局）
flutter run -d chrome

# 在已连接的真机上运行（iOS / Android）
flutter devices          # 查看设备 ID
flutter run -d <device-id>
```

> 更详细的环境配置、真机调试和常用命令，请见 `documents/FLUTTER_GUIDE_ZH.md` / `documents/FLUTTER_GUIDE_EN.md`。

## 子目录说明

- **`ai_wardrobe_app/`**  
  - Flutter 前端 Demo，包含：  
    - 底部导航 / Web 左侧导航壳（Wardrobe / Discover / Add / Visualize / Profile）  
    - Wardrobe / Discover / Profile 空状态页面  
    - Outfit 可视化画布（灰色剪影模特 + 可点击身体区域）  
    - 明 / 暗主题切换（Profile → Settings → Dark mode）

- **`documents/`**（技术文档总入口）  
  - `README.md`：文档导航与说明  
  - `TECH_STACK.md`：整体技术栈与架构概览  
  - `USER_STORIES.md`：用户故事与需求  
  - `DATA_MODEL.md`：数据模型与实体关系  
  - `API_CONTRACT.md`：API 设计与接口约定  
  - `BACKEND_ARCHITECTURE.md`：后端（FastAPI + PostgreSQL）架构  
  - `FLUTTER_ARCHITECTURE.md`：Flutter 架构与代码分层建议  
  - `FLUTTER_GUIDE_ZH.md` / `FLUTTER_GUIDE_EN.md`：Flutter 使用手册（中 / 英）

- **`groupmembers'markdown/`**  
  - 记录各组员的工作内容、分工与进度，例如 `cht.md`（前端样板、文档整理等）。

## 推荐阅读顺序（给新加入的队友）

1. `documents/TECH_STACK.md`：先了解整体技术栈和系统结构。  
2. `documents/USER_STORIES.md`：知道我们要解决什么问题。  
3. `documents/DATA_MODEL.md` + `documents/API_CONTRACT.md`：熟悉实体和接口。  
4. `documents/FLUTTER_ARCHITECTURE.md`：看 Flutter 端的推荐架构。  
5. `documents/FLUTTER_GUIDE_ZH.md`：按步骤在本地跑起来 App。
