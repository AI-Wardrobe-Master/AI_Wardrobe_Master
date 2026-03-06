# AI Wardrobe Master - Backend

## Module 2 实现范围

- `POST /api/v1/ai/classify` - AI 服装分类（含 Mock）
- `PATCH /api/v1/clothing-items/:id` - 标签确认/编辑
- `GET /api/v1/clothing-items` - 列表（支持 tag 过滤）
- `POST /api/v1/clothing-items/search` - 搜索（使用 finalTags）

## 快速启动

```bash
# 1. 创建虚拟环境并安装依赖
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# 2. 配置环境变量（复制 .env.example 为 .env）

# 3. 初始化数据库（需先启动 PostgreSQL）
psql -U wardrobe_user -d wardrobe_db -f scripts/init_schema.sql

# 4. 启动服务
uvicorn app.main:app --reload --port 8000
```

API 文档：http://localhost:8000/docs

## 队友对接

详见 [COORDINATION.md](./COORDINATION.md)
