"""add uid and sub-wardrobe metadata

Revision ID: 20260417_000011
Revises: 20260415_000010
Create Date: 2026-04-17
"""
import uuid
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260417_000011"
down_revision: Union[str, None] = "20260415_000010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("uid", sa.String(length=32), nullable=True))
    op.create_index("ix_users_uid", "users", ["uid"], unique=True)

    op.add_column("wardrobes", sa.Column("wid", sa.String(length=32), nullable=True))
    op.add_column(
        "wardrobes",
        sa.Column("parent_wardrobe_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "wardrobes",
        sa.Column("outfit_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "wardrobes",
        sa.Column("kind", sa.String(length=20), server_default="SUB", nullable=False),
    )
    op.add_column(
        "wardrobes",
        sa.Column("source", sa.String(length=30), server_default="MANUAL", nullable=False),
    )
    op.add_column("wardrobes", sa.Column("cover_image_url", sa.Text(), nullable=True))
    op.add_column(
        "wardrobes",
        sa.Column(
            "auto_tags",
            postgresql.ARRAY(sa.String()),
            server_default=sa.text("'{}'"),
            nullable=False,
        ),
    )
    op.add_column(
        "wardrobes",
        sa.Column(
            "manual_tags",
            postgresql.ARRAY(sa.String()),
            server_default=sa.text("'{}'"),
            nullable=False,
        ),
    )
    op.add_column(
        "wardrobes",
        sa.Column(
            "is_public",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
    )

    op.create_index("ix_wardrobes_wid", "wardrobes", ["wid"], unique=True)
    op.create_index("idx_wardrobes_parent", "wardrobes", ["parent_wardrobe_id"], unique=False)
    op.create_foreign_key(
        "fk_wardrobes_parent_wardrobe_id",
        "wardrobes",
        "wardrobes",
        ["parent_wardrobe_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_wardrobes_outfit_id",
        "wardrobes",
        "outfits",
        ["outfit_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint("uq_wardrobes_outfit_id", "wardrobes", ["outfit_id"])

    op.create_check_constraint("ck_wardrobe_kind", "wardrobes", "kind IN ('MAIN', 'SUB')")
    op.create_check_constraint(
        "ck_wardrobe_source",
        "wardrobes",
        "source IN ('MANUAL', 'OUTFIT_EXPORT', 'IMPORTED')",
    )

    conn = op.get_bind()
    conn.execute(sa.text(
        "UPDATE users SET uid = 'USR-' || upper(substr(md5(random()::text || clock_timestamp()::text || id::text), 1, 8)) WHERE uid IS NULL"
    ))
    conn.execute(sa.text(
        "UPDATE wardrobes SET wid = 'WRD-' || upper(substr(md5(random()::text || clock_timestamp()::text || id::text), 1, 8)) WHERE wid IS NULL"
    ))

    conn.execute(sa.text("""
        WITH ranked AS (
            SELECT id,
                   user_id,
                   row_number() OVER (PARTITION BY user_id ORDER BY created_at NULLS LAST, id) AS rn
            FROM wardrobes
        )
        UPDATE wardrobes AS w
        SET kind = CASE WHEN ranked.rn = 1 THEN 'MAIN' ELSE 'SUB' END
        FROM ranked
        WHERE ranked.id = w.id
    """))

    missing_user_rows = conn.execute(sa.text("""
        SELECT users.id
        FROM users
        WHERE NOT EXISTS (
            SELECT 1 FROM wardrobes WHERE wardrobes.user_id = users.id
        )
    """)).fetchall()
    for row in missing_user_rows:
        conn.execute(
            sa.text("""
                INSERT INTO wardrobes (
                    id, wid, user_id, name, type, description, created_at, updated_at,
                    kind, source, auto_tags, manual_tags, is_public
                ) VALUES (
                    :id, :wid, :user_id, 'My Wardrobe', 'REGULAR', 'Default main wardrobe',
                    now(), now(), 'MAIN', 'MANUAL', ARRAY[]::varchar[], ARRAY[]::varchar[], false
                )
            """),
            {
                "id": uuid.uuid4(),
                "wid": f"WRD-{uuid.uuid4().hex[:8].upper()}",
                "user_id": row.id,
            },
        )

    conn.execute(sa.text("""
        WITH main_wardrobes AS (
            SELECT user_id, id AS main_id
            FROM wardrobes
            WHERE kind = 'MAIN'
        )
        UPDATE wardrobes AS child
        SET parent_wardrobe_id = main_wardrobes.main_id
        FROM main_wardrobes
        WHERE child.user_id = main_wardrobes.user_id
          AND child.kind = 'SUB'
          AND child.parent_wardrobe_id IS NULL
    """))

    op.alter_column("users", "uid", nullable=False)
    op.alter_column("wardrobes", "wid", nullable=False)
    op.create_index(
        "uq_wardrobes_user_main",
        "wardrobes",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("kind = 'MAIN'"),
    )


def downgrade() -> None:
    op.drop_index("uq_wardrobes_user_main", table_name="wardrobes")
    op.drop_constraint("uq_wardrobes_outfit_id", "wardrobes", type_="unique")
    op.drop_constraint("fk_wardrobes_outfit_id", "wardrobes", type_="foreignkey")
    op.drop_constraint("fk_wardrobes_parent_wardrobe_id", "wardrobes", type_="foreignkey")
    op.drop_constraint("ck_wardrobe_source", "wardrobes", type_="check")
    op.drop_constraint("ck_wardrobe_kind", "wardrobes", type_="check")
    op.drop_index("idx_wardrobes_parent", table_name="wardrobes")
    op.drop_index("ix_wardrobes_wid", table_name="wardrobes")
    op.drop_column("wardrobes", "is_public")
    op.drop_column("wardrobes", "manual_tags")
    op.drop_column("wardrobes", "auto_tags")
    op.drop_column("wardrobes", "cover_image_url")
    op.drop_column("wardrobes", "source")
    op.drop_column("wardrobes", "kind")
    op.drop_column("wardrobes", "outfit_id")
    op.drop_column("wardrobes", "parent_wardrobe_id")
    op.drop_column("wardrobes", "wid")
    op.drop_index("ix_users_uid", table_name="users")
    op.drop_column("users", "uid")
