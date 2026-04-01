# Backend Implementation Draft

## 1. 文档目标

这份文档把 [api_interface_design.md](/mnt/d/ai_wardrobe_master/documents/backend_missing_feature_design/api_interface_design.md) 继续下沉成更接近实现的草案，目标是让后续开发可以直接按文件开工。

覆盖范围：

- 上传前置校验
- `GET /me` 与 capability 驱动的用户态返回
- `creator_profiles`
- `creator_items`
- `card_packs`
- `imports`
- `outfits`
- Virtual Wardrobe 系统托管
- imported item provenance

这份文档**不是最终代码**，但会尽量贴近当前仓库的结构和命名。

## 2. 与当前仓库对齐的约束

### 2.1 当前结构

当前后端已有：

- `backend/app/api/v1/*.py`
- `backend/app/models/*.py`
- `backend/app/schemas/*.py`
- `backend/app/crud/*.py`
- `backend/app/services/*.py`
- `backend/alembic/versions/*`

当前迁移方式已经在使用 Alembic，见 [backend/alembic/versions](/mnt/d/ai_wardrobe_master/backend/alembic/versions)。

### 2.2 当前代码风格

现状有两个特点：

1. 模型集中在 SQLAlchemy Declarative Base 下
2. CRUD 层里很多函数会自己 `commit()`

其中第 2 点对 `imports` 和 `outfits` 这种事务型功能不够好，所以新功能建议：

- **简单读操作继续走 CRUD**
- **事务型写操作上移到 service 层统一控制提交**

## 3. 推荐新增文件

建议新增以下文件：

### API 路由

```text
backend/app/api/v1/me.py
backend/app/api/v1/creator_items.py
backend/app/api/v1/creators.py
backend/app/api/v1/card_packs.py
backend/app/api/v1/imports.py
backend/app/api/v1/outfits.py
```

### Models

```text
backend/app/models/creator.py
backend/app/models/card_pack.py
backend/app/models/import_history.py
backend/app/models/outfit.py
```

### Schemas

```text
backend/app/schemas/me.py
backend/app/schemas/creator.py
backend/app/schemas/card_pack.py
backend/app/schemas/import_history.py
backend/app/schemas/outfit.py
```

### CRUD

```text
backend/app/crud/creator.py
backend/app/crud/card_pack.py
backend/app/crud/import_history.py
backend/app/crud/outfit.py
```

### Services

```text
backend/app/services/upload_validation_service.py
backend/app/services/virtual_wardrobe_service.py
backend/app/services/card_pack_import_service.py
backend/app/services/outfit_service.py
backend/app/services/outfit_thumbnail_service.py
```

### Alembic

建议至少新增两条迁移：

```text
backend/alembic/versions/20260402_000005_add_creator_pack_import_outfit_tables.py
backend/alembic/versions/20260402_000006_extend_clothing_and_wardrobe_for_provenance_and_system_fields.py
```

拆成两条的原因：

- 先建新表
- 再扩已有表

这样更容易回滚和定位问题。

## 4. 推荐模块边界

## 4.1 `me.py`

用途：

- 返回统一前端壳所需的用户基础信息、creator 状态与 capability

只做：

- 聚合读取
- 不做写操作

## 4.2 `creator_items.py`

用途：

- 承接 Creator Upload
- 复用当前 clothing pipeline

本质上是：

- “带 Creator 权限约束的 clothing item 创建入口”

## 4.3 `creators.py`

用途：

- 创作者资料查询与更新
- 创作者列表公开浏览

## 4.4 `card_packs.py`

用途：

- 创建、更新、发布、归档 Card Pack
- 公开读取分享链接

## 4.5 `imports.py`

用途：

- 导入 Pack
- 查询导入历史

这是强事务路由，核心逻辑必须走 service。

## 4.6 `outfits.py`

用途：

- 保存 / 更新 / 删除 Outfit
- 触发缩略图生成

## 5. Model 草案

## 5.1 `backend/app/models/creator.py`

建议骨架：

```python
import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class CreatorProfile(Base):
    __tablename__ = "creator_profiles"

    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    status = Column(String(20), nullable=False, default="ACTIVE")
    display_name = Column(String(120), nullable=False)
    brand_name = Column(String(120), nullable=True)
    bio = Column(Text, nullable=True)
    avatar_storage_path = Column(Text, nullable=True)
    website_url = Column(Text, nullable=True)
    social_links = Column(JSONB, nullable=False, default={})
    is_verified = Column(Boolean, default=False)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
```

说明：

- 这里用 `user_id` 做主键即可，不必额外再造 `id`
- `status` 推荐支持：`PENDING` / `ACTIVE` / `SUSPENDED`

## 5.2 `backend/app/models/card_pack.py`

建议骨架：

```python
import uuid
from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class CardPack(Base):
    __tablename__ = "card_packs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(160), nullable=False)
    description = Column(Text, nullable=True)
    pack_type = Column(String(40), nullable=False, default="CLOTHING_COLLECTION")
    status = Column(String(20), nullable=False, default="DRAFT")
    cover_image_path = Column(Text, nullable=True)
    share_id = Column(String(64), nullable=True, unique=True)
    import_count = Column(Integer, nullable=False, default=0)
    published_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint("pack_type IN ('CLOTHING_COLLECTION')", name='ck_card_pack_type'),
        CheckConstraint("status IN ('DRAFT','PUBLISHED','ARCHIVED')", name='ck_card_pack_status'),
        Index("idx_card_pack_creator_status", "creator_id", "status"),
    )


class CardPackItem(Base):
    __tablename__ = "card_pack_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    card_pack_id = Column(
        UUID(as_uuid=True),
        ForeignKey("card_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    display_order = Column(Integer, nullable=False, default=0)
    notes = Column(Text, nullable=True)
```

说明：

- 文档里也有 `OUTFIT` 类型 pack，但当前第一阶段先只落 `CLOTHING_COLLECTION` 更稳
- `share_id` 推荐与完整链接分开存，避免域名变化导致迁移

## 5.3 `backend/app/models/import_history.py`

建议骨架：

```python
import uuid
from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class ImportHistory(Base):
    __tablename__ = "import_histories"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    card_pack_id = Column(UUID(as_uuid=True), ForeignKey("card_packs.id"), nullable=False, index=True)
    creator_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    virtual_wardrobe_id = Column(UUID(as_uuid=True), ForeignKey("wardrobes.id"), nullable=False)
    request_id = Column(String(64), nullable=False)
    status = Column(String(20), nullable=False, default="PENDING")
    item_count = Column(Integer, nullable=False, default=0)
    imported_at = Column(DateTime(timezone=True), nullable=True)
    failure_reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint("status IN ('PENDING','PROCESSING','COMPLETED','FAILED')", name='ck_import_history_status'),
        Index("idx_import_histories_user_created", "user_id", "created_at"),
        Index("uq_import_histories_user_request", "user_id", "request_id", unique=True),
    )


class ImportHistoryItem(Base):
    __tablename__ = "import_history_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    import_history_id = Column(UUID(as_uuid=True), ForeignKey("import_histories.id", ondelete="CASCADE"), nullable=False, index=True)
    clothing_item_id = Column(UUID(as_uuid=True), ForeignKey("clothing_items.id", ondelete="CASCADE"), nullable=False, index=True)
    origin_clothing_item_id = Column(UUID(as_uuid=True), ForeignKey("clothing_items.id"), nullable=False)
```

说明：

- `request_id` 改为必填，作为 API 级幂等键
- 数据库唯一索引使用 `(user_id, request_id)`
- 这只能解决“同一次操作重试”问题，不能替代“同一用户是否允许重复导入同一 Pack”的业务规则
- 因此 service 层仍需补一层 `(user_id, card_pack_id)` 的重复导入检查

## 5.4 `backend/app/models/outfit.py`

建议骨架：

```python
import uuid
from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Index, Integer, Numeric, String, Text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class Outfit(Base):
    __tablename__ = "outfits"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(120), nullable=False)
    description = Column(Text, nullable=True)
    thumbnail_path = Column(Text, nullable=True)
    thumbnail_status = Column(String(20), nullable=False, default="NOT_GENERATED")
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )


class OutfitItem(Base):
    __tablename__ = "outfit_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    outfit_id = Column(UUID(as_uuid=True), ForeignKey("outfits.id", ondelete="CASCADE"), nullable=False, index=True)
    clothing_item_id = Column(UUID(as_uuid=True), ForeignKey("clothing_items.id"), nullable=False)
    layer = Column(Integer, nullable=False)
    position_x = Column(Numeric(8, 4), nullable=False)
    position_y = Column(Numeric(8, 4), nullable=False)
    scale = Column(Numeric(8, 4), nullable=False)
    rotation = Column(Numeric(8, 4), nullable=False)

    __table_args__ = (
        CheckConstraint("position_x BETWEEN 0 AND 1", name="ck_outfit_pos_x"),
        CheckConstraint("position_y BETWEEN 0 AND 1", name="ck_outfit_pos_y"),
        CheckConstraint("scale BETWEEN 0.1 AND 4.0", name="ck_outfit_scale"),
        Index("idx_outfit_items_outfit_layer", "outfit_id", "layer"),
    )
```

## 5.5 `backend/app/models/clothing_item.py` 扩展建议

在现有 `ClothingItem` 上新增：

```python
catalog_visibility = Column(String(20), nullable=True)
origin_clothing_item_id = Column(
    UUID(as_uuid=True),
    ForeignKey("clothing_items.id", ondelete="SET NULL"),
    nullable=True,
)
origin_creator_id = Column(
    UUID(as_uuid=True),
    ForeignKey("users.id", ondelete="SET NULL"),
    nullable=True,
)
origin_card_pack_id = Column(
    UUID(as_uuid=True),
    ForeignKey("card_packs.id", ondelete="SET NULL"),
    nullable=True,
)
origin_import_history_id = Column(
    UUID(as_uuid=True),
    ForeignKey("import_histories.id", ondelete="SET NULL"),
    nullable=True,
)
imported_at = Column(DateTime(timezone=True), nullable=True)
```

并补充约束：

```python
CheckConstraint(
    "catalog_visibility IS NULL OR catalog_visibility IN ('PRIVATE','PACK_ONLY','PUBLIC')",
    name="ck_catalog_visibility",
)
```

## 5.6 `backend/app/models/wardrobe.py` 扩展建议

在现有 `Wardrobe` 上新增：

```python
is_system_managed = Column(Boolean, nullable=False, default=False)
system_key = Column(String(50), nullable=True)
```

并补充唯一索引：

```python
Index(
    "uq_wardrobes_user_system_key",
    "user_id",
    "system_key",
    unique=True,
    postgresql_where=sql_text("system_key IS NOT NULL"),
)
```

## 6. Pydantic Schema 草案

## 6.1 `backend/app/schemas/me.py`

```python
from pydantic import BaseModel
from uuid import UUID


class CreatorProfileSummary(BaseModel):
    exists: bool
    status: str | None = None
    displayName: str | None = None
    brandName: str | None = None


class UserCapabilities(BaseModel):
    canApplyForCreator: bool
    canPublishItems: bool
    canCreateCardPacks: bool
    canEditCreatorProfile: bool
    canViewCreatorCenter: bool


class MeResponseData(BaseModel):
    id: UUID
    username: str
    email: str
    type: str
    creatorProfile: CreatorProfileSummary
    capabilities: UserCapabilities


class MeResponse(BaseModel):
    success: bool = True
    data: MeResponseData
```

说明：

- `GET /me` 只返回“用户事实 + creator 状态 + capabilities”。
- 不在响应里加入 `entryHints`、`showCreatorEntryInDiscover` 之类的 UI 提示字段。
- 页面入口显隐由前端根据 capability 自行映射。

## 6.2 `backend/app/schemas/creator.py`

建议拆：

- `CreatorProfileUpdate`
- `CreatorProfileResponse`
- `CreatorListResponse`
- `CreatorItemCreateResponse`
- `CreatorItemUpdate`

关键请求体：

```python
class CreatorProfileUpdate(BaseModel):
    displayName: str | None = None
    brandName: str | None = None
    bio: str | None = None
    websiteUrl: str | None = None
    socialLinks: dict[str, str] | None = None
```

## 6.3 `backend/app/schemas/card_pack.py`

关键请求体：

```python
class CardPackCreate(BaseModel):
    name: str
    description: str | None = None
    type: str = "CLOTHING_COLLECTION"
    itemIds: list[UUID]
    coverImage: str | None = None


class CardPackUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    itemIds: list[UUID] | None = None
    coverImage: str | None = None
```

## 6.4 `backend/app/schemas/import_history.py`

```python
class ImportCardPackRequest(BaseModel):
    cardPackId: UUID
    requestId: str
```

## 6.5 `backend/app/schemas/outfit.py`

```python
class OutfitPosition(BaseModel):
    x: float
    y: float


class OutfitItemInput(BaseModel):
    clothingItemId: UUID
    layer: int
    position: OutfitPosition
    scale: float
    rotation: float


class OutfitCreate(BaseModel):
    name: str
    description: str | None = None
    items: list[OutfitItemInput]


class OutfitUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    items: list[OutfitItemInput] | None = None
```

## 7. API 路由签名草案

## 7.1 `backend/app/api/v1/me.py`

```python
router = APIRouter(tags=["me"])


@router.get("/me", response_model=MeResponse)
def get_me(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    ...
```

## 7.2 `backend/app/api/v1/creator_items.py`

```python
router = APIRouter(prefix="/creator-items", tags=["creator-items"])


@router.post("", status_code=202)
async def create_creator_item(...):
    ...


@router.get("/{item_id}")
def get_creator_item(...):
    ...


@router.patch("/{item_id}")
def update_creator_item(...):
    ...


@router.delete("/{item_id}", status_code=204)
def delete_creator_item(...):
    ...
```

说明：

- 创建逻辑应尽量复用 `clothing.py` 的文件上传与 pipeline 逻辑
- 权限依赖走 `get_current_creator_user_id`
- 更新、删除、读取私有 Creator Item 时，必须通过 `item_id + creator_id` 联合查询完成所有权校验

## 7.3 `backend/app/api/v1/creators.py`

```python
router = APIRouter(prefix="/creators", tags=["creators"])


@router.get("")
def list_creators(...):
    ...


@router.get("/{creator_id}")
def get_creator_profile(...):
    ...


@router.patch("/{creator_id}")
def update_creator_profile(...):
    ...


@router.get("/{creator_id}/items")
def list_creator_items(...):
    ...


@router.get("/{creator_id}/card-packs")
def list_creator_card_packs(...):
    ...
```

说明：

- `PATCH /creators/{creator_id}` 不能只校验“当前用户是 creator”
- 还必须保证 `creator_id == current_user_id`，或者在 CRUD 层直接使用 `get_owned_creator_profile(db, creator_id, current_user_id)`

## 7.4 `backend/app/api/v1/card_packs.py`

```python
router = APIRouter(prefix="/card-packs", tags=["card-packs"])


@router.post("", status_code=201)
def create_card_pack(...):
    ...


@router.get("/{pack_id}")
def get_card_pack(...):
    ...


@router.get("/share/{share_id}")
def get_card_pack_by_share_id(...):
    ...


@router.patch("/{pack_id}")
def update_card_pack(...):
    ...


@router.post("/{pack_id}/publish")
def publish_card_pack(...):
    ...


@router.post("/{pack_id}/archive")
def archive_card_pack(...):
    ...


@router.delete("/{pack_id}", status_code=204)
def delete_card_pack(...):
    ...
```

说明：

- 所有写接口都必须通过 `pack_id + creator_id` 联合查询做所有权校验
- 不允许在拿到任意 pack 后仅靠 `if pack.creator_id != user_id` 做补丁式判断

## 7.5 `backend/app/api/v1/imports.py`

```python
router = APIRouter(prefix="/imports", tags=["imports"])


@router.post("/card-pack", status_code=201)
def import_card_pack(...):
    ...


@router.get("/history")
def list_import_history(...):
    ...
```

## 7.6 `backend/app/api/v1/outfits.py`

```python
router = APIRouter(prefix="/outfits", tags=["outfits"])


@router.post("", status_code=201)
def create_outfit(...):
    ...


@router.get("")
def list_outfits(...):
    ...


@router.get("/{outfit_id}")
def get_outfit(...):
    ...


@router.patch("/{outfit_id}")
def update_outfit(...):
    ...


@router.delete("/{outfit_id}", status_code=204)
def delete_outfit(...):
    ...


@router.post("/{outfit_id}/thumbnail")
def generate_outfit_thumbnail(...):
    ...
```

## 8. 关键 Service 草案

## 8.1 `upload_validation_service.py`

建议提供：

```python
class UploadValidationError(Exception):
    ...


def validate_image_upload(
    file: UploadFile,
    *,
    field_name: str,
    allowed_mime_types: set[str] | None = None,
    max_bytes: int = 10 * 1024 * 1024,
) -> bytes:
    ...
```

职责：

- 校验 MIME
- 校验空文件
- 校验大小
- 校验图片能否被解码

这样 `clothing.py` 和 `creator_items.py` 都能复用。

## 8.2 `virtual_wardrobe_service.py`

建议提供：

```python
SYSTEM_VIRTUAL_WARDROBE_KEY = "DEFAULT_VIRTUAL_IMPORTED"


def get_or_create_virtual_wardrobe(db: Session, user_id: UUID) -> Wardrobe:
    ...


def assert_wardrobe_is_mutable(wardrobe: Wardrobe) -> None:
    ...
```

职责：

- 获取或创建系统虚拟衣橱
- 阻止系统衣橱被重命名或删除

## 8.3 `card_pack_import_service.py`

这是整个新功能里最核心的 service。

建议提供：

```python
class CardPackImportService:
    def import_pack(
        self,
        db: Session,
        *,
        user_id: UUID,
        card_pack_id: UUID,
        request_id: str,
    ) -> ImportHistory:
        ...
```

内部步骤建议严格固定为：

1. 按 `(user_id, request_id)` 查询是否已有导入记录；若已有且 `card_pack_id` 相同，则返回既有记录；若对应其他 Pack，则抛 `requestId conflict`
2. 查询 pack 与 pack items
3. 校验 pack 为 `PUBLISHED`
4. 校验当前用户是否已存在该 Pack 的 `PENDING`、`PROCESSING` 或 `COMPLETED` 导入记录
5. 获取或创建 virtual wardrobe
6. 创建 `import_histories(status=PENDING)`
7. 将状态更新为 `PROCESSING`
8. 为每个 pack item 复制出用户域 `clothing_item`
9. 复制 `images`、`models_3d` 引用
10. 回填 provenance 字段
11. 写入 `wardrobe_items`
12. 写入 `import_history_items`
13. 更新 `card_packs.import_count`
14. 更新 `import_histories(status=COMPLETED, imported_at=...)`
15. 记录成功 metrics 与结构化日志
16. `db.commit()`

失败时：

- 捕获异常
- 回滚事务
- 若需要保留失败记录，则单独开启新事务记录 `FAILED`
- 记录失败 metrics、`failure_code` 和结构化错误日志

## 8.4 `outfit_service.py`

建议提供：

```python
class OutfitService:
    def create_outfit(...):
        ...

    def update_outfit(...):
        ...

    def replace_items(...):
        ...
```

约束：

- 必须验证所有 `clothing_item_id` 属于当前用户
- 更新 items 时采用“全量替换”

## 8.5 `outfit_thumbnail_service.py`

第一阶段建议做成占位实现：

```python
def queue_thumbnail_generation(db: Session, outfit_id: UUID) -> None:
    ...
```

原因：

- 先把 API 与状态流补齐
- 真正的渲染可以后面再接

## 9. CRUD 草案

## 9.1 读操作可以继续简单 CRUD

例如：

- `crud/creator.py`
- `crud/card_pack.py`
- `crud/outfit.py`

提供：

- `get_*`
- `list_*`
- `create_*`
- `delete_*`

## 9.2 写操作不要在事务型路径里立即 commit

建议对新的 CRUD 采用两套风格：

### 轻量操作

可以内部 `commit()`

### 事务型操作

提供 `flush-only` 版本，例如：

```python
def create_import_history(db: Session, *, ..., commit: bool = True) -> ImportHistory:
    db.add(obj)
    db.flush()
    if commit:
        db.commit()
        db.refresh(obj)
    return obj
```

这样 service 层能把 `commit=False` 传下去。

## 9.3 所有权安全的 CRUD 约束

仅有“按主键取对象”的 CRUD，不足以支撑文档里声明的资源所有权边界。

建议至少补下面这类函数：

```python
def get_owned_creator_profile(db: Session, *, creator_id: UUID, current_user_id: UUID) -> CreatorProfile | None:
    ...


def get_owned_creator_item(db: Session, *, item_id: UUID, creator_id: UUID) -> ClothingItem | None:
    ...


def get_owned_card_pack(db: Session, *, pack_id: UUID, creator_id: UUID) -> CardPack | None:
    ...


def get_owned_outfit(db: Session, *, outfit_id: UUID, user_id: UUID) -> Outfit | None:
    ...
```

约束：

- 写操作必须优先走这类“带 owner 条件”的查询函数
- 查不到就统一视为 `404`，不要对未拥有的资源暴露“资源存在但无权限”的差异化信息

## 10. `GET /me` capability 组装逻辑

建议在 `me.py` 中集中写，不要散在前端推导。

推荐逻辑：

```python
creator_profile = crud_creator.get_by_user_id(db, user_id)

creator_status = creator_profile.status if creator_profile else None

capabilities = {
    "canApplyForCreator": creator_profile is None,
    "canPublishItems": creator_status == "ACTIVE",
    "canCreateCardPacks": creator_status == "ACTIVE",
    "canEditCreatorProfile": creator_status == "ACTIVE",
    "canViewCreatorCenter": creator_profile is not None,
}
```

注意：

- 这里故意只返回 capability，不返回任何页面显隐提示
- `Discover`、`Profile`、Banner、快捷入口的展示策略属于前端 IA，不应塞回 `/me`

## 11. 路由注册草案

`backend/app/api/v1/router.py` 建议改成：

```python
from app.api.v1 import (
    ai,
    auth,
    card_packs,
    clothing,
    creator_items,
    creators,
    imports,
    me,
    outfits,
    wardrobe,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(me.router)
api_router.include_router(ai.router, prefix="/ai", tags=["AI Classification"])
api_router.include_router(clothing.router)
api_router.include_router(creator_items.router)
api_router.include_router(creators.router)
api_router.include_router(card_packs.router)
api_router.include_router(imports.router)
api_router.include_router(outfits.router)
api_router.include_router(wardrobe.router)
```

## 12. 权限依赖草案

在 `backend/app/api/deps.py` 增加：

```python
def get_current_creator_user_id(
    user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
) -> UUID:
    creator_profile = crud_creator.get_by_user_id(db, user_id)
    if creator_profile is None or creator_profile.status != "ACTIVE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Creator permission required",
        )
    return user_id
```

这样更接近统一界面的 capability 模型，也避免把权限继续绑死在 `users.user_type` 上。

## 12.1 Import 可观测性草案

导入链路需要最小监控与问题追踪设计，否则上线后只能靠查数据库定位问题。

建议新增：

```python
def log_import_event(
    *,
    event: str,
    request_id: str,
    import_history_id: UUID | None,
    user_id: UUID,
    card_pack_id: UUID,
    creator_id: UUID | None,
    item_count: int | None = None,
    failure_code: str | None = None,
) -> None:
    ...


def record_import_metric(...):
    ...
```

最少事件：

- `card_pack_import_started`
- `card_pack_import_completed`
- `card_pack_import_failed`
- `card_pack_import_idempotent_reused`
- `card_pack_import_duplicate_blocked`

最少指标：

- Counter: `card_pack_import_started_total`
- Counter: `card_pack_import_completed_total`
- Counter: `card_pack_import_failed_total`
- Counter: `card_pack_import_duplicate_blocked_total`
- Histogram: `card_pack_import_duration_ms`
- Histogram: `card_pack_import_item_count`

失败原因建议标准化为：

- `PACK_NOT_FOUND`
- `PACK_NOT_PUBLISHED`
- `PACK_ALREADY_IMPORTED`
- `PACK_DATA_CORRUPTED`
- `VIRTUAL_WARDROBE_ERROR`
- `DB_WRITE_FAILED`

这样才能稳定回答两个运营问题：

- 导入成功率是多少
- 最近失败主要卡在哪一类原因上

## 13. Alembic 落地建议

## 13.1 第一条迁移：新表

文件建议：

`20260402_000005_add_creator_pack_import_outfit_tables.py`

内容：

- 创建 `creator_profiles`
- 创建 `card_packs`
- 创建 `card_pack_items`
- 创建 `import_histories`
- 创建 `import_history_items`
- 创建 `outfits`
- 创建 `outfit_items`

## 13.2 第二条迁移：已有表扩展

文件建议：

`20260402_000006_extend_clothing_and_wardrobe_for_provenance_and_system_fields.py`

内容：

- 为 `clothing_items` 增加 provenance 字段
- 为 `clothing_items` 增加 `catalog_visibility`
- 为 `wardrobes` 增加 `is_system_managed`
- 为 `wardrobes` 增加 `system_key`
- 创建新的部分唯一索引

## 13.3 是否需要改 `scripts/init_schema.sql`

如果仓库仍保留“新环境可直接跑 init schema”的用法，则建议同步更新：

- [init_schema.sql](/mnt/d/ai_wardrobe_master/backend/scripts/init_schema.sql)

否则新环境只跑 Alembic，旧 SQL 很快就会漂移。

## 14. 最小可交付实现顺序

### Phase 1

- `upload_validation_service.py`
- `me.py`
- `creator_profiles`
- `get_current_creator_user_id`

### Phase 2

- `outfits` 全套
- `virtual_wardrobe_service.py`

### Phase 3

- `creator_items`
- `card_packs`

### Phase 4

- `imports`
- provenance 字段回填

### Phase 5

- thumbnail 后处理
- creator dashboard 统计

## 15. 最后结论

如果要尽快把新功能做成可开发的后端方案，最稳的方式不是一次性把所有能力一起塞进现有文件，而是：

- 维持现有目录结构
- 新增独立模型与路由
- 把事务型逻辑集中到 service
- 用 Alembic 分两步迁移
- 用 `GET /me` 把统一界面的前端状态驱动起来

一句话概括这份草案：

> 路由分域、模型独立、事务上收、权限渐进、前端状态统一由 `/me` 驱动。
