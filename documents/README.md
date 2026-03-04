# AI Wardrobe Master - Documentation Overview

## 文档结构

本项目包含以下核心文档，用于指导 Flutter 应用的开发：

```
documents/
├── README.md                    # 本文件 - 文档导航
├── TECH_STACK.md                # 技术栈总览 ⭐ 新增
├── USER_STORIES.md              # 用户故事和需求
├── DATA_MODEL.md                # 数据模型和实体定义
├── API_CONTRACT.md              # API 接口规范
├── BACKEND_ARCHITECTURE.md      # 后端架构设计 (FastAPI + PostgreSQL)
├── FLUTTER_ARCHITECTURE.md      # Flutter 架构设计
├── FLUTTER_GUIDE_ZH.md          # Flutter 使用手册（中文）
└── FLUTTER_GUIDE_EN.md          # Flutter Quick Guide (English)
```

---

## 文档说明

### 0. TECH_STACK.md - 技术栈总览 ⭐ 新增

**用途：** 完整的技术栈说明和架构概览

**内容：**
- 前后端技术栈详细说明
- 架构图和组件关系
- 开发环境要求
- 部署选项和成本估算
- 性能目标和扩展策略
- 安全和监控考虑

**适用人群：**
- 技术负责人：技术选型
- 架构师：系统设计
- 开发团队：技术了解
- 运维团队：部署规划

**核心技术：**
- **Backend**: FastAPI + PostgreSQL + S3/MinIO
- **Frontend**: Flutter + Dart
- **Infrastructure**: Docker + Docker Compose
- **Storage**: PostgreSQL (metadata) + S3/MinIO (images)

---

### 2. USER_STORIES.md - 用户故事

**用途：** 定义功能需求和用户场景

**内容：**
- 24 个详细的用户故事，覆盖 5 个核心模块
- 每个故事包含：角色、需求、目标、验收标准
- 优先级划分（P0/P1/P2）

**适用人群：**
- 产品经理：理解功能需求
- 开发团队：明确实现目标
- 测试团队：编写测试用例

**关键模块：**
1. 衣物数字化（4 个故事）
2. 自动分类与搜索（5 个故事）
3. 衣柜管理（3 个故事）
4. 平台内容交互（4 个故事）
5. 搭配可视化（4 个故事）

---

### 3. DATA_MODEL.md - 数据模型

**用途：** 定义数据结构和关系

**内容：**
- 8 个核心实体的完整定义
- 使用 Freezed 的 Dart 类定义
- 实体关系图（ERD）
- SQLite 数据库表结构
- 数据验证规则
- 示例数据

**适用人群：**
- 后端开发：数据库设计
- Flutter 开发：模型类实现
- 架构师：系统设计

**核心实体：**
1. `User` - 用户（消费者/创作者）
2. `ClothingItem` - 衣物资产
3. `Wardrobe` - 衣柜
4. `WardrobeItem` - 衣柜-衣物关联
5. `Outfit` - 搭配
6. `Creator` - 创作者信息
7. `CardPack` - 内容包
8. `ImportHistory` - 导入历史

**关键特性：**
- 来源隔离（Owned vs Imported）
- 溯源追踪（Provenance）
- 多对多关系（衣柜-衣物）
- 引用完整性保护

---

### 4. API_CONTRACT.md - API 接口规范

**用途：** 定义前后端通信协议

**内容：**
- 60+ RESTful API 端点
- 请求/响应格式
- 错误码定义
- 认证机制（JWT）
- 分页规范
- 速率限制

**适用人群：**
- 后端开发（FastAPI）：API 实现
- Flutter 开发：API 调用
- 测试团队：接口测试

**API 模块：**
1. 认证（注册、登录）
2. 衣物管理（CRUD、搜索）
3. 衣柜管理
4. 搭配管理
5. 内容包管理
6. 导入操作
7. 创作者管理
8. 图像处理
9. AI 分类
10. 用户资料

**示例端点：**
```
POST   /api/v1/clothing-items          # 创建衣物
GET    /api/v1/clothing-items          # 列表查询
POST   /api/v1/clothing-items/search   # 搜索
POST   /api/v1/wardrobes/:id/items     # 添加到衣柜
POST   /api/v1/imports/card-pack       # 导入内容包
```

---

### 5. BACKEND_ARCHITECTURE.md - 后端架构设计 ⭐ 新增

**用途：** 指导 FastAPI 后端开发

**内容：**
- FastAPI + PostgreSQL + S3/MinIO 架构
- 完整的项目结构
- SQLAlchemy 模型定义
- Pydantic Schema 定义
- 存储服务实现（S3/MinIO/Local）
- Docker Compose 配置
- 数据库迁移（Alembic）
- 代码示例和最佳实践

**适用人群：**
- 后端开发团队（主要）
- DevOps 工程师
- 架构师

**核心技术栈：**
- **API**: FastAPI 0.109+
- **Database**: PostgreSQL 15+
- **ORM**: SQLAlchemy 2.0+
- **Storage**: S3 / MinIO / Local
- **Auth**: JWT (python-jose)
- **Validation**: Pydantic V2
- **Migration**: Alembic
- **Container**: Docker

**项目结构：**
```
backend/
├── app/
│   ├── api/          # API endpoints
│   ├── models/       # SQLAlchemy models
│   ├── schemas/      # Pydantic schemas
│   ├── crud/         # CRUD operations
│   ├── services/     # Business logic
│   ├── core/         # Core utilities
│   └── db/           # Database
├── alembic/          # Migrations
├── tests/            # Tests
└── docker-compose.yml
```

---

### 6. FLUTTER_ARCHITECTURE.md - Flutter 架构设计

**用途：** 指导 Flutter 应用开发

**内容：**
- 推荐的项目结构（Clean Architecture）
- 状态管理方案（Provider/Riverpod）
- 导航策略（go_router）
- 依赖注入（get_it）
- 推荐的 Flutter 包
- SQLite 数据库设计
- 代码示例和最佳实践

**适用人群：**
- Flutter 开发团队（主要）
- 架构师
- 技术负责人

**核心内容：**

#### 项目结构
```
lib/
├── core/           # 核心工具和常量
├── data/           # 数据层（模型、仓库、数据源）
├── domain/         # 业务逻辑层（实体、用例）
├── presentation/   # UI 层（页面、组件、状态）
└── services/       # 服务层（相机、图像处理、AI）
```

#### 推荐技术栈
- **状态管理：** Provider（简单）或 Riverpod（高级）
- **导航：** go_router
- **网络：** dio + retrofit
- **本地存储：** sqflite + shared_preferences
- **图像：** image_picker + camera + cached_network_image
- **依赖注入：** get_it + injectable
- **JSON 序列化：** freezed + json_serializable

#### 架构模式
```
UI Widget → State Manager → Use Case → Repository → Data Source → Database/API
```

---

## 文档之间的关系

```
                    ┌─────────────────────┐
                    │   TECH_STACK.md     │
                    │   (技术选型总览)      │
                    └──────────┬──────────┘
                               │
                ┌──────────────┴──────────────┐
                │                             │
                ▼                             ▼
┌─────────────────────┐           ┌─────────────────────┐
│  USER_STORIES.md    │           │  DATA_MODEL.md      │
│  (功能需求)          │           │  (数据结构)          │
└──────────┬──────────┘           └──────────┬──────────┘
           │                                  │
           └──────────────┬───────────────────┘
                          │
                          ▼
                ┌─────────────────────┐
                │  API_CONTRACT.md    │
                │  (接口协议)          │
                └──────────┬──────────┘
                           │
           ┌───────────────┴───────────────┐
           │                               │
           ▼                               ▼
┌─────────────────────┐        ┌─────────────────────┐
│ BACKEND_ARCH.md     │        │ FLUTTER_ARCH.md     │
│ (后端实现)           │        │ (前端实现)           │
│ FastAPI+PostgreSQL  │        │ Flutter+Dart        │
└─────────────────────┘        └─────────────────────┘
```

---

## 使用指南

### 对于技术负责人/架构师 ⭐ 新增

1. **首先阅读：** `TECH_STACK.md`
   - 了解完整技术栈
   - 评估技术选型
   - 规划架构设计

2. **参考：** `USER_STORIES.md`
   - 理解业务需求
   - 确认功能范围

3. **参考：** `BACKEND_ARCHITECTURE.md` 和 `FLUTTER_ARCHITECTURE.md`
   - 审查架构设计
   - 提供技术指导

---

### 对于产品经理

1. **首先阅读：** `USER_STORIES.md`
   - 了解所有功能需求
   - 确认优先级
   - 补充遗漏的场景

2. **参考：** `DATA_MODEL.md`
   - 理解数据关系
   - 确认业务规则

### 对于后端开发（FastAPI）⭐ 新增

1. **首先阅读：** `BACKEND_ARCHITECTURE.md`
   - 搭建 FastAPI 项目结构
   - 配置 PostgreSQL 数据库
   - 设置 S3/MinIO 或本地存储
   - 实现核心架构

2. **参考：** `DATA_MODEL.md`
   - 创建 SQLAlchemy 模型
   - 设计数据库表结构
   - 实现数据验证

3. **参考：** `API_CONTRACT.md`
   - 实现所有 API 端点
   - 遵循响应格式
   - 实现错误处理

4. **参考：** `USER_STORIES.md`
   - 理解业务逻辑
   - 验证实现正确性

---

### 对于 Flutter 开发

1. **首先阅读：** `FLUTTER_ARCHITECTURE.md`
   - 搭建项目结构
   - 安装推荐的包
   - 实现核心架构

2. **参考：** `DATA_MODEL.md`
   - 创建 Dart 模型类
   - 实现 JSON 序列化
   - 设计本地数据库

3. **参考：** `API_CONTRACT.md`
   - 实现 API 客户端
   - 处理网络请求
   - 错误处理

4. **参考：** `USER_STORIES.md`
   - 实现 UI 页面
   - 完成用户流程
   - 编写测试用例

### 对于测试团队

1. **首先阅读：** `USER_STORIES.md`
   - 根据验收标准编写测试用例
   - 覆盖所有用户场景

2. **参考：** `API_CONTRACT.md`
   - 编写接口测试
   - 验证错误处理

---

## 开发流程建议

### Backend Phase 1: 后端基础搭建（3-5 天）⭐ 新增

**任务：**
1. 初始化 FastAPI 项目
2. 配置 PostgreSQL 数据库
3. 设置 Alembic 迁移
4. 配置 S3/MinIO 或本地存储
5. 实现 JWT 认证
6. 创建基础 CRUD 操作

**参考文档：**
- `BACKEND_ARCHITECTURE.md` - 完整后端架构
- `DATA_MODEL.md` - 数据库表结构

**产出：**
- 可运行的 FastAPI 应用
- PostgreSQL 数据库已初始化
- 存储服务已配置
- 认证系统可用

---

### Backend Phase 2: 核心 API 实现（5-7 天）

**任务：**
1. 实现衣物管理 API
2. 实现衣柜管理 API
3. 实现图像上传和处理
4. 实现搜索功能
5. 编写单元测试

**参考文档：**
- `API_CONTRACT.md` - API 端点定义
- `USER_STORIES.md` - 业务逻辑

**产出：**
- 完整的 CRUD API
- 图像上传功能
- 搜索和过滤功能

---

### Backend Phase 3: 高级功能（5-7 天）

**任务：**
1. 实现搭配管理 API
2. 实现创作者和内容包功能
3. 实现导入功能
4. 添加 AI 分类（可选）
5. 性能优化

**参考文档：**
- `API_CONTRACT.md` - 高级端点
- `USER_STORIES.md` - US-4.x, US-5.x

**产出：**
- 完整的后端 API
- 所有功能可用
- 测试覆盖率 > 70%

---

### Frontend Phase 1.1: 项目初始化（1-2 天）

**任务：**
1. 更新 `pubspec.yaml`，添加推荐的依赖包
2. 创建 `FLUTTER_ARCHITECTURE.md` 中定义的文件夹结构
3. 配置依赖注入（get_it）
4. 配置路由（go_router）
5. 设置主题和常量

**参考文档：**
- `FLUTTER_ARCHITECTURE.md` - 项目结构和依赖

**产出：**
- 完整的项目骨架
- 可运行的空白应用

---

### Frontend Phase 1.2: 数据层实现（3-5 天）

**任务：**
1. 创建所有 Freezed 模型类
2. 实现 SQLite 数据库
3. 创建 Repository 接口和实现
4. 实现 API 客户端（如果有后端）

**参考文档：**
- `DATA_MODEL.md` - 实体定义和数据库结构
- `API_CONTRACT.md` - API 端点
- `FLUTTER_ARCHITECTURE.md` - 代码示例

**产出：**
- 完整的数据模型
- 可用的本地数据库
- API 客户端（可选）

---

### Frontend Phase 1.3: 核心功能实现（10-15 天）

**任务：**
1. **衣物数字化**
   - 相机集成
   - 图像处理
   - 自动分类
   - 数据存储

2. **衣柜管理**
   - 创建/编辑/删除衣柜
   - 添加/移除衣物
   - 列表展示

3. **搜索功能**
   - 关键词搜索
   - 多条件筛选
   - 结果展示

**参考文档：**
- `USER_STORIES.md` - US-1.x, US-2.x, US-3.x
- `FLUTTER_ARCHITECTURE.md` - 服务层实现

**产出：**
- 可拍照并保存衣物
- 可创建和管理衣柜
- 可搜索衣物

---

### Frontend Phase 1.4: 高级功能（10-15 天）

**任务：**
1. **搭配可视化**
   - 2.5D 画布
   - 拖拽交互
   - 保存搭配

2. **创作者功能**
   - 内容包创建
   - 分享链接生成

3. **导入功能**
   - 一键导入
   - 来源隔离
   - 溯源追踪

**参考文档：**
- `USER_STORIES.md` - US-4.x, US-5.x
- `DATA_MODEL.md` - Provenance 相关

**产出：**
- 完整的搭配功能
- 创作者和导入功能

---

### Frontend Phase 1.5: 优化和测试（5-7 天）

**任务：**
1. 性能优化
2. UI/UX 优化
3. 单元测试
4. Widget 测试
5. 集成测试
6. Bug 修复

**参考文档：**
- `FLUTTER_ARCHITECTURE.md` - 测试策略
- `USER_STORIES.md` - 验收标准

**产出：**
- 稳定的 MVP 版本
- 测试覆盖率 > 70%

