"""View-count increment and popular-ordering tests."""

import uuid

import pytest

from app.crud import card_pack as crud_card_pack
from app.crud import clothing as crud_clothing
from app.db.session import SessionLocal
from app.models.clothing_item import ClothingItem
from app.models.creator import CardPack
from app.models.user import User
from app.services.view_count_service import (
    increment_card_pack_view,
    increment_clothing_item_view,
)


def _suffix() -> str:
    return uuid.uuid4().hex[:8]


def _make_user(db):
    s = _suffix()
    u = User(
        id=uuid.uuid4(),
        uid=f"U-{s}",
        username=f"user-{s}",
        email=f"{s}@t.local",
        hashed_password="x",
        is_active=True,
        user_type="CREATOR",
    )
    db.add(u)
    db.flush()
    return u


def _make_item(db, user_id, *, catalog_visibility="PACK_ONLY"):
    item = ClothingItem(
        id=uuid.uuid4(),
        user_id=user_id,
        source="OWNED",
        catalog_visibility=catalog_visibility,
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        custom_tags=[],
        name=f"item-{_suffix()}",
    )
    db.add(item)
    db.flush()
    return item


def _make_pack(db, creator_id, *, status="PUBLISHED"):
    pack = CardPack(
        id=uuid.uuid4(),
        creator_id=creator_id,
        name=f"pack-{_suffix()}",
        pack_type="CLOTHING_COLLECTION",
        status=status,
        import_count=0,
    )
    db.add(pack)
    db.flush()
    return pack


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def test_clothing_view_increments_on_public(db):
    user = _make_user(db)
    item = _make_item(db, user.id, catalog_visibility="PACK_ONLY")
    db.commit()  # Persist so the UPDATE in increment sees the row.

    assert item.view_count == 0
    increment_clothing_item_view(db, item.id)
    db.refresh(item)
    assert item.view_count == 1


def test_clothing_view_ignored_on_private(db):
    user = _make_user(db)
    item = _make_item(db, user.id, catalog_visibility="PRIVATE")
    db.commit()

    increment_clothing_item_view(db, item.id)
    db.refresh(item)
    assert item.view_count == 0  # private items do not increment


def test_clothing_view_ignored_on_tombstoned(db):
    from datetime import datetime, timezone

    user = _make_user(db)
    item = _make_item(db, user.id, catalog_visibility="PACK_ONLY")
    item.deleted_at = datetime.now(timezone.utc)
    db.commit()

    increment_clothing_item_view(db, item.id)
    db.refresh(item)
    assert item.view_count == 0


def test_card_pack_view_increments_on_published(db):
    creator = _make_user(db)
    pack = _make_pack(db, creator.id, status="PUBLISHED")
    db.commit()

    assert pack.view_count == 0
    increment_card_pack_view(db, pack.id)
    db.refresh(pack)
    assert pack.view_count == 1


def test_card_pack_view_ignored_on_draft(db):
    creator = _make_user(db)
    pack = _make_pack(db, creator.id, status="DRAFT")
    db.commit()

    increment_card_pack_view(db, pack.id)
    db.refresh(pack)
    assert pack.view_count == 0


def test_popular_card_packs_orders_by_view_count_desc(db):
    creator = _make_user(db)
    # 3 published packs with different view counts
    p1 = _make_pack(db, creator.id, status="PUBLISHED")
    p2 = _make_pack(db, creator.id, status="PUBLISHED")
    p3 = _make_pack(db, creator.id, status="PUBLISHED")
    p1.view_count = 5
    p2.view_count = 20
    p3.view_count = 10
    db.commit()

    top = crud_card_pack.list_popular_card_packs(db, limit=50)
    top_ids = [p.id for p in top]
    # The 3 we just made should be in descending view_count order relative to each other.
    want_order = [p2.id, p3.id, p1.id]
    indices = [top_ids.index(pid) for pid in want_order]
    assert indices == sorted(indices), (
        f"expected {want_order} in descending order within popular list, got {indices}"
    )


def test_popular_card_packs_excludes_draft(db):
    creator = _make_user(db)
    p_draft = _make_pack(db, creator.id, status="DRAFT")
    p_pub = _make_pack(db, creator.id, status="PUBLISHED")
    p_draft.view_count = 999  # Artificially high but DRAFT
    p_pub.view_count = 1
    db.commit()

    top = crud_card_pack.list_popular_card_packs(db, limit=50)
    top_ids = [p.id for p in top]
    assert p_draft.id not in top_ids
    assert p_pub.id in top_ids


def test_popular_clothing_items_orders_by_view_count_desc(db):
    user = _make_user(db)
    i1 = _make_item(db, user.id, catalog_visibility="PACK_ONLY")
    i2 = _make_item(db, user.id, catalog_visibility="PACK_ONLY")
    i3 = _make_item(db, user.id, catalog_visibility="PACK_ONLY")
    i1.view_count = 5
    i2.view_count = 20
    i3.view_count = 10
    db.commit()

    top = crud_clothing.list_popular(db, limit=50)
    top_ids = [i.id for i in top]
    want_order = [i2.id, i3.id, i1.id]
    indices = [top_ids.index(iid) for iid in want_order]
    assert indices == sorted(indices)


def test_popular_clothing_items_excludes_private_and_tombstoned(db):
    from datetime import datetime, timezone

    user = _make_user(db)
    i_priv = _make_item(db, user.id, catalog_visibility="PRIVATE")
    i_tomb = _make_item(db, user.id, catalog_visibility="PACK_ONLY")
    i_tomb.deleted_at = datetime.now(timezone.utc)
    i_pub = _make_item(db, user.id, catalog_visibility="PUBLIC")
    i_priv.view_count = 999
    i_tomb.view_count = 999
    i_pub.view_count = 1
    db.commit()

    top = crud_clothing.list_popular(db, limit=50)
    top_ids = [i.id for i in top]
    assert i_priv.id not in top_ids
    assert i_tomb.id not in top_ids
    assert i_pub.id in top_ids
