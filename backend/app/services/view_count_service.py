"""Atomic view-count increment. Runs a single UPDATE, no read-modify-write.

- Self-views don't count: check viewer identity before calling.
- Tombstoned / non-public items are filtered by the UPDATE WHERE clause, so
  calling increment on them is a no-op (safe, zero-row UPDATE).
"""

from uuid import UUID

from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem
from app.models.creator import CardPack


def increment_clothing_item_view(db: Session, item_id: UUID) -> None:
    """Increment view_count if the item is PACK_ONLY/PUBLIC and not tombstoned."""
    db.query(ClothingItem).filter(
        ClothingItem.id == item_id,
        ClothingItem.deleted_at.is_(None),
        ClothingItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
    ).update(
        {ClothingItem.view_count: ClothingItem.view_count + 1},
        synchronize_session=False,
    )
    db.commit()


def increment_card_pack_view(db: Session, pack_id: UUID) -> None:
    """Increment view_count only for PUBLISHED packs."""
    db.query(CardPack).filter(
        CardPack.id == pack_id,
        CardPack.status == "PUBLISHED",
    ).update(
        {CardPack.view_count: CardPack.view_count + 1},
        synchronize_session=False,
    )
    db.commit()
