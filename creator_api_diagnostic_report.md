# Creator API 端点诊断报告

## 执行摘要

本报告分析了 `backend/app/api/v1/creators.py` 中的 Creator 相关 API 端点，并与 `documents/API_CONTRACT.md` 中的定义进行对比。

### 关键发现

1. ✅ **GET /creators/:id** - 已实现，响应结构完整
2. ❌ **GET /creators/me/profile** - **未实现**（API 契约中定义但后端缺失）
3. ✅ **GET /me** - 已实现（在 `backend/app/api/v1/me.py` 中）
4. ✅ **PATCH /creators/:id** - 已实现

---

## 详细分析

### 1. GET /creators/:id (获取创作者资料)

**状态**: ✅ 已实现

**端点**: `backend/app/api/v1/creators.py:73-85`

**响应结构**:
```python
CreatorDetail(
    id=profile.user_id,
    username=username,
    status=profile.status,
    displayName=profile.display_name,
    brandName=profile.brand_name,
    bio=profile.bio,
    avatarUrl=None,  # TODO: migrate avatar_storage_path to blob_hash
    websiteUrl=profile.website_url,
    socialLinks=profile.social_links or {},
    isVerified=profile.is_verified,
    verifiedAt=profile.verified_at,
    createdAt=profile.created_at,
    updatedAt=profile.updated_at,
)
```

**字段对比**:

| 字段 | API 契约 | 实际实现 | 状态 |
|------|---------|---------|------|
| id | ✅ | ✅ | 匹配 |
| username | ✅ | ✅ | 匹配 |
| status | ✅ | ✅ | 匹配 |
| displayName | ✅ | ✅ | 匹配 |
| brandName | ✅ | ✅ | 匹配 |
| bio | ✅ | ✅ | 匹配 |
| avatarUrl | ✅ | ⚠️ | **始终返回 None**（待迁移） |
| websiteUrl | ✅ | ✅ | 匹配 |
| socialLinks | ✅ | ✅ | 匹配 |
| isVerified | ✅ | ✅ | 匹配 |
| verifiedAt | ✅ | ✅ | 匹配 |
| createdAt | ✅ | ✅ | 匹配 |
| updatedAt | ✅ | ✅ | 匹配 |
| followerCount | ✅ | ❌ | **缺失** |
| packCount | ✅ | ❌ | **缺失** |

**问题**:
1. `avatarUrl` 始终返回 `None`，代码中有 TODO 注释表明需要从 `avatar_storage_path` 迁移到 `blob_hash`
2. `followerCount` 和 `packCount` 在 API 契约中定义但未在响应中返回

---

### 2. GET /creators/me/profile (获取当前用户的创作者资料)

**状态**: ❌ **未实现**

**API 契约定义** (`documents/API_CONTRACT.md:1156-1164`):
```
### 7.5 Get My Creator Profile
GET /creators/me/profile

**Purpose:**
- Returns the authenticated creator's full editable profile
- Used by `Profile -> Creator Center`
```

**问题**:
- 此端点在 API 契约中明确定义
- 但在 `backend/app/api/v1/creators.py` 中**完全缺失**
- 前端可能依赖此端点获取当前用户的创作者资料进行编辑

**影响**:
- 前端无法通过专用端点获取当前用户的创作者资料
- 可能需要使用 `GET /creators/:id` 并传入当前用户 ID 作为替代方案

---

### 3. GET /me (获取当前用户上下文)

**状态**: ✅ 已实现

**端点**: `backend/app/api/v1/me.py:20-49`

**响应结构**:
```python
MeData(
    id=user.id,
    username=user.username,
    email=user.email,
    type=user.user_type,
    creatorProfile=CreatorProfileSummary(
        exists=profile is not None,
        status=creator_status,
        displayName=profile.display_name if profile else None,
        brandName=profile.brand_name if profile else None,
    ),
    capabilities=CreatorCapabilities(
        canApplyForCreator=profile is None,
        canPublishItems=creator_status == "ACTIVE",
        canCreateCardPacks=creator_status == "ACTIVE",
        canEditCreatorProfile=creator_status == "ACTIVE",
        canViewCreatorCenter=profile is not None,
    ),
)
```

**字段对比**:

| 字段 | API 契约 | 实际实现 | 状态 |
|------|---------|---------|------|
| id | ✅ | ✅ | 匹配 |
| username | ✅ | ✅ | 匹配 |
| email | ✅ | ✅ | 匹配 |
| type | ✅ | ✅ | 匹配 |
| creatorProfile.exists | ✅ | ✅ | 匹配 |
| creatorProfile.status | ✅ | ✅ | 匹配 |
| creatorProfile.displayName | ✅ | ✅ | 匹配 |
| creatorProfile.brandName | ✅ | ✅ | 匹配 |
| capabilities.* | ✅ | ✅ | 匹配 |

**注意**: `creatorProfile` 是一个摘要对象，不包含完整的创作者资料字段（如 `bio`, `avatarUrl`, `websiteUrl`, `socialLinks` 等）

---

### 4. PATCH /creators/:id (更新创作者资料)

**状态**: ✅ 已实现

**端点**: `backend/app/api/v1/creators.py:88-110`

**可更新字段**:
```python
CreatorProfileUpdate(
    display_name: str | None
    brand_name: str | None
    bio: str | None
    website_url: str | None
    social_links: dict[str, str] | None
)
```

**字段对比**:

| 字段 | API 契约 | 实际实现 | 状态 |
|------|---------|---------|------|
| displayName | ✅ | ✅ | 匹配 |
| brandName | ✅ | ✅ | 匹配 |
| bio | ✅ | ✅ | 匹配 |
| websiteUrl | ✅ | ✅ | 匹配 |
| socialLinks | ✅ | ✅ | 匹配 |

**注意**: 不能通过此端点更新 `avatarUrl`（需要单独的图片上传流程）

---

## status 字段处理逻辑

### 数据库模型 (`backend/app/models/creator.py:30`)

```python
status = Column(String(20), nullable=False, default="ACTIVE")

__table_args__ = (
    CheckConstraint(
        "status IN ('PENDING','ACTIVE','SUSPENDED')",
        name="ck_creator_profile_status",
    ),
)
```

**有效值**:
- `PENDING` - 申请审核中
- `ACTIVE` - 可以发布内容
- `SUSPENDED` - 暂时受限

### status 字段在各端点中的使用

1. **GET /creators/:id**: 直接返回 `profile.status`
2. **GET /me**: 返回 `profile.status`（如果创作者资料存在）
3. **PATCH /creators/:id**: **不允许更新 status**（status 是系统管理字段）

### status 验证逻辑

**在 GET /me 中的能力判断**:
```python
capabilities=CreatorCapabilities(
    canApplyForCreator=profile is None,
    canPublishItems=creator_status == "ACTIVE",
    canCreateCardPacks=creator_status == "ACTIVE",
    canEditCreatorProfile=creator_status == "ACTIVE",
    canViewCreatorCenter=profile is not None,
)
```

**关键逻辑**:
- 只有 `status == "ACTIVE"` 的创作者才能发布内容和创建卡包
- `PENDING` 和 `SUSPENDED` 状态的创作者无法发布内容
- 所有状态的创作者都可以查看创作者中心（只要资料存在）

---

## 缺失字段汇总

### 1. avatarUrl 问题

**当前状态**:
- 数据库有 `avatar_storage_path` 字段
- 响应中 `avatarUrl` 始终为 `None`
- 代码中有 TODO 注释: `# TODO: migrate avatar_storage_path to blob_hash`

**影响**:
- 前端无法显示创作者头像
- 需要实现从 `avatar_storage_path` 到 blob 系统的迁移

### 2. followerCount 和 packCount

**API 契约要求**:
```json
{
  "followerCount": 1250,
  "packCount": 15
}
```

**当前实现**:
- `GET /creators/:id` 不返回这些字段
- `GET /creators` 列表端点中计算了 `packCount`，但详情端点中缺失

**建议**:
- 在 `CreatorDetail` schema 中添加这些字段
- 在 `_to_creator_detail` 函数中计算或查询这些值

### 3. GET /creators/me/profile 端点缺失

**影响**:
- 前端无法使用专用端点获取当前用户的完整创作者资料
- 可能需要使用 `GET /creators/:id` 作为替代

**建议实现**:
```python
@router.get("/me/profile", response_model=CreatorProfileResponse)
def get_my_creator_profile(
    db: Session = Depends(get_db),
    current_user_id: UUID = Depends(get_current_user_id),
):
    profile = crud_creator.get_by_user_id(db, current_user_id)
    if profile is None:
        raise HTTPException(404, "Creator profile not found")
    user = db.get(User, current_user_id)
    return CreatorProfileResponse(data=_to_creator_detail(profile, user.username))
```

---

## 与 API_CONTRACT.md 的一致性检查

### ✅ 一致的部分

1. **基本字段**: `id`, `username`, `status`, `displayName`, `brandName`, `bio`, `websiteUrl`, `socialLinks`
2. **时间戳**: `createdAt`, `updatedAt`, `verifiedAt`
3. **验证标志**: `isVerified`
4. **status 枚举值**: `PENDING`, `ACTIVE`, `SUSPENDED`
5. **更新端点**: PATCH 支持的字段与契约一致

### ❌ 不一致的部分

1. **avatarUrl**: 始终返回 `None`（待迁移）
2. **followerCount**: 契约中定义但未实现
3. **packCount**: 契约中定义但未实现
4. **GET /creators/me/profile**: 契约中定义但端点缺失

---

## 建议修复优先级

### 高优先级 (P0)

1. **实现 GET /creators/me/profile 端点**
   - 前端可能依赖此端点
   - 实现简单，可复用现有逻辑

2. **修复 avatarUrl 返回 None 的问题**
   - 影响用户体验
   - 需要实现 blob 系统迁移或临时方案

### 中优先级 (P1)

3. **添加 followerCount 和 packCount 字段**
   - API 契约中明确定义
   - 需要数据库查询或缓存

### 低优先级 (P2)

4. **完善 status 字段的业务逻辑**
   - 添加状态转换的端点（如申请成为创作者、管理员审核等）
   - 当前只能通过数据库直接修改

---

## 测试建议

### 单元测试

1. 测试 `GET /creators/:id` 返回完整字段
2. 测试 `GET /me` 的 `creatorProfile` 和 `capabilities` 逻辑
3. 测试 `PATCH /creators/:id` 的字段更新
4. 测试不同 `status` 值对 `capabilities` 的影响

### 集成测试

1. 测试创建用户 → 创建创作者资料 → 获取资料的完整流程
2. 测试 `status` 为 `PENDING` 时无法发布内容
3. 测试 `status` 为 `SUSPENDED` 时的权限限制

### API 契约测试

1. 使用 API 契约作为测试规范
2. 验证所有端点的响应结构与契约一致
3. 验证所有必需字段都存在

---

## 总结

### 当前状态

- **GET /creators/:id**: 基本实现，但缺少 `avatarUrl`, `followerCount`, `packCount`
- **GET /creators/me/profile**: **完全缺失**
- **GET /me**: 完整实现，返回创作者摘要和能力
- **PATCH /creators/:id**: 完整实现，支持所有可编辑字段
- **status 字段**: 正确实现验证和能力判断逻辑

### 关键问题

1. ❌ `GET /creators/me/profile` 端点缺失
2. ⚠️ `avatarUrl` 始终为 `None`
3. ⚠️ `followerCount` 和 `packCount` 未实现

### 建议行动

1. 立即实现 `GET /creators/me/profile` 端点
2. 修复 `avatarUrl` 的 blob 迁移问题
3. 在 `GET /creators/:id` 响应中添加 `followerCount` 和 `packCount`
4. 更新 API 测试以验证与契约的一致性
