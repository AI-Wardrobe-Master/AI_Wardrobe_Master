"""3-tier delete lifecycle tests (DB-level, no HTTP)."""

import uuid

import pytest

from app.crud import clothing as crud_clothing
from app.db.session import SessionLocal
from app.models.clothing_item import ClothingItem
from app.models.creator import CardPack, CardPackItem
from app.models.user import User
from app.services.blob_service import BlobService


def _make_user(db, username="alice"):
    # Use a random suffix so tests can be re-run without unique-constraint clashes
    # even if a prior rollback was incomplete.
    suffix = uuid.uuid4().hex[:8]
    user = User(
        id=uuid.uuid4(),
        uid=f"U-{suffix}",
        username=f"{username}-{suffix}",
        email=f"{username}-{suffix}@test.local",
        hashed_password="x",
        user_type="CREATOR",
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


def _make_clothing_item(db, user_id, *, catalog_visibility="PRIVATE", name="test-item"):
    item = ClothingItem(
        id=uuid.uuid4(),
        user_id=user_id,
        source="OWNED",
        catalog_visibility=catalog_visibility,
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        custom_tags=[],
        name=name,
    )
    db.add(item)
    db.flush()
    return item


def _make_pack_with_item(db, creator_id, clothing_item_id, status="PUBLISHED"):
    pack = CardPack(
        id=uuid.uuid4(),
        creator_id=creator_id,
        name="test-pack",
        pack_type="CLOTHING_COLLECTION",
        status=status,
        import_count=0,
    )
    db.add(pack)
    db.flush()
    link = CardPackItem(
        id=uuid.uuid4(),
        card_pack_id=pack.id,
        clothing_item_id=clothing_item_id,
        sort_order=0,
    )
    db.add(link)
    db.flush()
    return pack


def _make_imported_copy(db, user_id, canonical_id):
    imported = ClothingItem(
        id=uuid.uuid4(),
        user_id=user_id,
        source="IMPORTED",
        catalog_visibility="PRIVATE",
        predicted_tags=[],
        final_tags=[],
        is_confirmed=True,
        custom_tags=[],
        imported_from_clothing_item_id=canonical_id,
    )
    db.add(imported)
    db.flush()
    return imported


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def test_case1_unpublished_hard_deletes(db):
    """Case 1: item never in any PUBLISHED pack -> hard delete."""
    user = _make_user(db, "creator1")
    item = _make_clothing_item(db, user.id, catalog_visibility="PRIVATE")
    blob_svc = BlobService()

    outcome = crud_clothing.delete_with_lifecycle(
        db, item_id=item.id, user_id=user.id, blob_service=blob_svc,
    )
    assert outcome == "HARD_DELETED"
    assert db.query(ClothingItem).filter_by(id=item.id).first() is None
    db.rollback()


def test_case2_published_no_imports_hard_deletes(db):
    """Case 2: item in PUBLISHED pack but no imports -> hard delete."""
    user = _make_user(db, "creator2")
    item = _make_clothing_item(db, user.id, catalog_visibility="PACK_ONLY")
    _make_pack_with_item(db, user.id, item.id, status="PUBLISHED")
    blob_svc = BlobService()

    outcome = crud_clothing.delete_with_lifecycle(
        db, item_id=item.id, user_id=user.id, blob_service=blob_svc,
    )
    assert outcome == "HARD_DELETED"
    assert db.query(ClothingItem).filter_by(id=item.id).first() is None
    # CardPackItem row should be gone too.
    assert db.query(CardPackItem).filter_by(clothing_item_id=item.id).count() == 0
    db.rollback()


def test_case3_published_with_imports_tombstones(db):
    """Case 3: item in PUBLISHED pack with >=1 import -> tombstone."""
    creator = _make_user(db, "creator3")
    consumer = _make_user(db, "consumer3")
    item = _make_clothing_item(db, creator.id, catalog_visibility="PACK_ONLY")
    _make_pack_with_item(db, creator.id, item.id, status="PUBLISHED")
    imported = _make_imported_copy(db, consumer.id, item.id)
    blob_svc = BlobService()

    outcome = crud_clothing.delete_with_lifecycle(
        db, item_id=item.id, user_id=creator.id, blob_service=blob_svc,
    )
    assert outcome == "TOMBSTONED"
    # Row survives, deleted_at set.
    canonical = db.query(ClothingItem).filter_by(id=item.id).first()
    assert canonical is not None
    assert canonical.deleted_at is not None
    # CardPackItem removed.
    assert db.query(CardPackItem).filter_by(clothing_item_id=item.id).count() == 0
    # Imported copy's backlink preserved.
    db.refresh(imported)
    assert imported.imported_from_clothing_item_id == item.id
    db.rollback()


def test_case4_unpublished_in_draft_pack_hard_deletes(db):
    """Sanity: item in a DRAFT pack (not PUBLISHED) behaves like case 1."""
    user = _make_user(db, "creator4")
    item = _make_clothing_item(db, user.id, catalog_visibility="PACK_ONLY")
    _make_pack_with_item(db, user.id, item.id, status="DRAFT")
    blob_svc = BlobService()

    outcome = crud_clothing.delete_with_lifecycle(
        db, item_id=item.id, user_id=user.id, blob_service=blob_svc,
    )
    assert outcome == "HARD_DELETED"
    db.rollback()


def test_not_found_returns_none(db):
    """Unknown / already-deleted item returns None."""
    user = _make_user(db, "creator5")
    blob_svc = BlobService()
    outcome = crud_clothing.delete_with_lifecycle(
        db, item_id=uuid.uuid4(), user_id=user.id, blob_service=blob_svc,
    )
    assert outcome is None
    db.rollback()
