# 数据库 Schema 问题诊断报告

## 执行摘要

检查了数据库迁移文件 `20260402_000005_add_creator_foundation.py`，发现了与文档定义的严重不一致。


---

###  display_name 长度不一致

**迁移文件** (第 33 行):
```python
sa.Column("display_name", sa.String(length=120), nullable=False),  # ❌ 120
```

**文档要求** (`BACKEND_ARCHITECTURE.md`):
```sql
display_name VARCHAR(100)
```

**影响**: 
- ⚠️ 与规范不一致，但不影响功能

---

### 字段命名不一致

**迁移文件** (第 36 行):
```python
sa.Column("avatar_storage_path", sa.Text(), nullable=True),  # ❌ avatar_storage_path
```

**文档要求** (`BACKEND_ARCHITECTURE.md`):
```sql
avatar_url TEXT
```

**影响**: 
- ⚠️ 字段名称不同
- API 响应中 avatarUrl 始终返回 None
- 需要迁移或重命名

---

### 缺失字段

**迁移文件**: 没有以下字段

**文档要求** (`BACKEND_ARCHITECTURE.md`):
```sql
follower_count INTEGER DEFAULT 0
pack_count INTEGER DEFAULT 0
```

**影响**: 
- ❌ API 契约要求返回这些字段，但数据库中不存在
- 前端无法显示创作者的关注者数量和发布包数量

