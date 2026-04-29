"""Migration integration test - verifies post-migration schema state."""

from sqlalchemy import text

from app.db.session import SessionLocal


def test_creator_items_data_migrated_to_clothing_items():
    """Assumes migration has already run (head). Verifies column/table shape."""
    db = SessionLocal()
    try:
        cols = db.execute(
            text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='clothing_items' "
                "AND column_name IN ("
                "'catalog_visibility','deleted_at','view_count',"
                "'imported_from_clothing_item_id'"
                ")"
            )
        ).fetchall()
        assert len(cols) == 4, f"missing columns: {cols}"

        exists = db.execute(
            text(
                "SELECT 1 FROM information_schema.tables "
                "WHERE table_name='creator_items'"
            )
        ).fetchone()
        assert exists is None, "creator_items table still exists post-migration"

        col = db.execute(
            text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='card_pack_items' AND column_name='clothing_item_id'"
            )
        ).fetchone()
        assert col is not None

        constraint = db.execute(
            text(
                "SELECT 1 FROM information_schema.check_constraints "
                "WHERE constraint_name='ck_sgci_slot'"
            )
        ).fetchone()
        assert constraint is not None

        view_count = db.execute(
            text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='card_packs' AND column_name='view_count'"
            )
        ).fetchone()
        assert view_count is not None
    finally:
        db.close()
