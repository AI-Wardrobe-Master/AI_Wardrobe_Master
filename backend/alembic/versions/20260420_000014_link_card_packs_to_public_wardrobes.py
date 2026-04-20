"""Link published card packs to public wardrobes.

Revision ID: 20260420_000014
Revises: 20260418_000013
Create Date: 2026-04-20
"""

import uuid
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260420_000014"
down_revision: Union[str, None] = "20260418_000013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _generate_wid() -> str:
    return f"WRD-{uuid.uuid4().hex[:8].upper()}"


def upgrade() -> None:
    op.add_column(
        "card_packs",
        sa.Column("wardrobe_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_card_packs_wardrobe_id",
        "card_packs",
        "wardrobes",
        ["wardrobe_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint("uq_card_packs_wardrobe_id", "card_packs", ["wardrobe_id"])

    op.drop_constraint("ck_wardrobe_source", "wardrobes", type_="check")
    op.create_check_constraint(
        "ck_wardrobe_source",
        "wardrobes",
        "source IN ('MANUAL', 'OUTFIT_EXPORT', 'IMPORTED', 'CARD_PACK')",
    )

    conn = op.get_bind()
    published_packs = conn.execute(
        sa.text(
            """
            SELECT
                cp.id,
                cp.creator_id,
                cp.name,
                cp.description,
                cp.share_id,
                cp.cover_image_blob_hash,
                cp.wardrobe_id,
                u.uid AS creator_uid,
                u.username AS creator_username,
                main_w.id AS main_wardrobe_id
            FROM card_packs cp
            JOIN users u ON u.id = cp.creator_id
            LEFT JOIN wardrobes main_w
              ON main_w.user_id = cp.creator_id
             AND main_w.kind = 'MAIN'
            WHERE cp.status = 'PUBLISHED'
            """
        )
    ).fetchall()

    for row in published_packs:
        main_wardrobe_id = row.main_wardrobe_id
        if main_wardrobe_id is None:
            main_wardrobe_id = uuid.uuid4()
            conn.execute(
                sa.text(
                    """
                    INSERT INTO wardrobes (
                        id,
                        wid,
                        user_id,
                        name,
                        kind,
                        type,
                        source,
                        description,
                        cover_image_url,
                        auto_tags,
                        manual_tags,
                        is_public,
                        created_at,
                        updated_at
                    ) VALUES (
                        :id,
                        :wid,
                        :user_id,
                        'My Wardrobe',
                        'MAIN',
                        'REGULAR',
                        'MANUAL',
                        'Default main wardrobe',
                        NULL,
                        ARRAY[]::varchar[],
                        ARRAY[]::varchar[],
                        FALSE,
                        now(),
                        now()
                    )
                    """
                ),
                {
                    "id": main_wardrobe_id,
                    "wid": _generate_wid(),
                    "user_id": row.creator_id,
                },
            )

        if row.wardrobe_id is None:
            wardrobe_id = uuid.uuid4()
            conn.execute(
                sa.text(
                    """
                    INSERT INTO wardrobes (
                        id,
                        wid,
                        user_id,
                        parent_wardrobe_id,
                        name,
                        kind,
                        type,
                        source,
                        description,
                        cover_image_url,
                        auto_tags,
                        manual_tags,
                        is_public,
                        created_at,
                        updated_at
                    ) VALUES (
                        :id,
                        :wid,
                        :user_id,
                        :parent_wardrobe_id,
                        :name,
                        'SUB',
                        'VIRTUAL',
                        'CARD_PACK',
                        :description,
                        :cover_image_url,
                        :auto_tags,
                        ARRAY[]::varchar[],
                        TRUE,
                        now(),
                        now()
                    )
                    """
                ),
                {
                    "id": wardrobe_id,
                    "wid": _generate_wid(),
                    "user_id": row.creator_id,
                    "parent_wardrobe_id": main_wardrobe_id,
                    "name": row.name,
                    "description": row.description,
                    "cover_image_url": (
                        f"/files/card-packs/{row.id}/cover"
                        if row.cover_image_blob_hash
                        else None
                    ),
                    "auto_tags": [
                        value
                        for value in [row.name, row.creator_uid, row.creator_username, row.share_id]
                        if value
                    ],
                },
            )
            conn.execute(
                sa.text(
                    """
                    UPDATE card_packs
                    SET wardrobe_id = :wardrobe_id
                    WHERE id = :card_pack_id
                    """
                ),
                {
                    "wardrobe_id": wardrobe_id,
                    "card_pack_id": row.id,
                },
            )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(sa.text("DELETE FROM wardrobes WHERE source = 'CARD_PACK'"))

    op.drop_constraint("uq_card_packs_wardrobe_id", "card_packs", type_="unique")
    op.drop_constraint("fk_card_packs_wardrobe_id", "card_packs", type_="foreignkey")
    op.drop_column("card_packs", "wardrobe_id")

    op.drop_constraint("ck_wardrobe_source", "wardrobes", type_="check")
    op.create_check_constraint(
        "ck_wardrobe_source",
        "wardrobes",
        "source IN ('MANUAL', 'OUTFIT_EXPORT', 'IMPORTED')",
    )
