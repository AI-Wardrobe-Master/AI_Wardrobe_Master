"""consolidate creator_items into clothing_items; add multi-garment junction,
gender, lease fields on styled_generations; view_count on clothing_items and
card_packs; deleted_at tombstone on clothing_items; import_count CHECK; plus
partial indexes for popular queries.

Revision ID: 20260420_000015
Revises: 20260420_000014
Create Date: 2026-04-20
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260420_000015"
down_revision: Union[str, None] = "20260420_000014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # -- A. clothing_items: absorb CreatorItem columns ------------------
    op.add_column(
        "clothing_items",
        sa.Column(
            "catalog_visibility",
            sa.String(20),
            nullable=False,
            server_default="PRIVATE",
        ),
    )
    op.create_check_constraint(
        "ck_clothing_catalog_visibility",
        "clothing_items",
        "catalog_visibility IN ('PRIVATE','PACK_ONLY','PUBLIC')",
    )
    op.add_column(
        "clothing_items",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "clothing_items",
        sa.Column(
            "view_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.alter_column(
        "clothing_items",
        "imported_from_creator_item_id",
        new_column_name="imported_from_clothing_item_id",
    )

    # -- B. card_packs -------------------------------------------------
    op.add_column(
        "card_packs",
        sa.Column(
            "view_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.create_check_constraint(
        "ck_card_pack_import_count_nonneg",
        "card_packs",
        "import_count >= 0",
    )

    # -- C. styled_generations -----------------------------------------
    op.add_column(
        "styled_generations",
        sa.Column("gender", sa.String(10), nullable=True),
    )
    op.add_column(
        "styled_generations",
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "styled_generations",
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "styled_generations",
        sa.Column("worker_id", sa.String(255), nullable=True),
    )

    # -- D. Merge creator_items rows -> clothing_items -----------------
    conn = op.get_bind()

    # D.1 clothing_items rows mirror each creator_items row (same UUID).
    conn.execute(
        sa.text(
            """
            INSERT INTO clothing_items (
                id, user_id, source,
                predicted_tags, final_tags, is_confirmed,
                name, description, custom_tags,
                category, material, style,
                preview_svg_state, preview_svg_available, sync_status,
                imported_from_card_pack_id, imported_from_clothing_item_id,
                catalog_visibility, deleted_at, view_count,
                created_at, updated_at
            )
            SELECT
                ci.id,
                ci.creator_id,
                'OWNED',
                ci.predicted_tags,
                ci.final_tags,
                ci.is_confirmed,
                ci.name,
                ci.description,
                ci.custom_tags,
                NULL, NULL, NULL,
                'PLACEHOLDER', FALSE, 'SYNCED',
                NULL, NULL,
                ci.catalog_visibility,
                NULL,
                0,
                ci.created_at,
                ci.updated_at
            FROM creator_items ci
            WHERE NOT EXISTS (
                SELECT 1 FROM clothing_items WHERE clothing_items.id = ci.id
            )
            """
        )
    )

    # D.2 copy creator_item_images -> images.
    conn.execute(
        sa.text(
            """
            INSERT INTO images (id, clothing_item_id, image_type, blob_hash, angle, created_at)
            SELECT gen_random_uuid(), cii.creator_item_id, cii.image_type,
                   cii.blob_hash, cii.angle, cii.created_at
            FROM creator_item_images cii
            WHERE NOT EXISTS (
                SELECT 1 FROM images i
                WHERE i.clothing_item_id = cii.creator_item_id
                  AND i.image_type = cii.image_type
                  AND (i.angle IS NOT DISTINCT FROM cii.angle)
            )
            """
        )
    )

    # D.3 copy creator_models_3d -> models_3d.
    conn.execute(
        sa.text(
            """
            INSERT INTO models_3d (
                id, clothing_item_id, model_format, blob_hash,
                vertex_count, face_count, created_at
            )
            SELECT gen_random_uuid(), cm.creator_item_id, cm.model_format,
                   cm.blob_hash, cm.vertex_count, cm.face_count, cm.created_at
            FROM creator_models_3d cm
            WHERE NOT EXISTS (
                SELECT 1 FROM models_3d m WHERE m.clothing_item_id = cm.creator_item_id
            )
            """
        )
    )

    # D.4 retarget card_pack_items FK.
    op.drop_constraint(
        "card_pack_items_creator_item_id_fkey",
        "card_pack_items",
        type_="foreignkey",
    )
    op.alter_column(
        "card_pack_items",
        "creator_item_id",
        new_column_name="clothing_item_id",
    )
    op.create_foreign_key(
        "card_pack_items_clothing_item_id_fkey",
        "card_pack_items",
        "clothing_items",
        ["clothing_item_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.execute(
        "ALTER INDEX uq_card_pack_items_pack_creator_item "
        "RENAME TO uq_card_pack_items_pack_clothing_item"
    )

    # D.5 retarget clothing_items.imported_from_clothing_item_id FK.
    op.drop_constraint(
        "fk_clothing_items_imported_creator_item",
        "clothing_items",
        type_="foreignkey",
    )
    op.create_foreign_key(
        "fk_clothing_items_imported_clothing_item",
        "clothing_items",
        "clothing_items",
        ["imported_from_clothing_item_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # D.6 drop the old creator_* tables (children first).
    op.drop_table("creator_processing_tasks")
    op.drop_table("creator_models_3d")
    op.drop_table("creator_item_images")
    op.drop_table("creator_items")

    # -- E. Styled generation junction + gender backfill ---------------
    op.create_table(
        "styled_generation_clothing_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "generation_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("styled_generations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "clothing_item_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("clothing_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("slot", sa.String(10), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "slot IN ('HAT','TOP','PANTS','SHOES')", name="ck_sgci_slot"
        ),
        sa.UniqueConstraint(
            "generation_id", "slot", name="uq_sgci_gen_slot"
        ),
    )
    op.create_index(
        "idx_sgci_generation",
        "styled_generation_clothing_items",
        ["generation_id"],
    )
    op.create_index(
        "idx_sgci_clothing_item",
        "styled_generation_clothing_items",
        ["clothing_item_id"],
    )

    conn.execute(
        sa.text(
            """
            INSERT INTO styled_generation_clothing_items
                (id, generation_id, clothing_item_id, slot, position)
            SELECT gen_random_uuid(), sg.id, sg.source_clothing_item_id, 'TOP', 0
            FROM styled_generations sg
            WHERE sg.source_clothing_item_id IS NOT NULL
            """
        )
    )

    conn.execute(
        sa.text(
            "UPDATE styled_generations SET gender='FEMALE' WHERE gender IS NULL"
        )
    )
    op.alter_column("styled_generations", "gender", nullable=False)
    op.create_check_constraint(
        "ck_styled_gen_gender",
        "styled_generations",
        "gender IN ('MALE','FEMALE')",
    )

    # -- F. Indexes ----------------------------------------------------
    op.create_index(
        "idx_clothing_items_popular",
        "clothing_items",
        [sa.text("view_count DESC"), sa.text("created_at DESC")],
        postgresql_where=sa.text(
            "catalog_visibility IN ('PACK_ONLY','PUBLIC') AND deleted_at IS NULL"
        ),
    )
    op.create_index(
        "idx_card_packs_popular",
        "card_packs",
        [sa.text("view_count DESC"), sa.text("created_at DESC")],
        postgresql_where=sa.text("status = 'PUBLISHED'"),
    )
    op.create_index(
        "idx_clothing_items_not_deleted",
        "clothing_items",
        ["user_id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index(
        "idx_clothing_items_catalog_visibility",
        "clothing_items",
        ["user_id", "catalog_visibility"],
    )


def downgrade() -> None:
    # Reverse F
    op.drop_index("idx_clothing_items_catalog_visibility", "clothing_items")
    op.drop_index("idx_clothing_items_not_deleted", "clothing_items")
    op.drop_index("idx_card_packs_popular", "card_packs")
    op.drop_index("idx_clothing_items_popular", "clothing_items")

    # Reverse E
    op.drop_constraint("ck_styled_gen_gender", "styled_generations", type_="check")
    op.drop_index("idx_sgci_clothing_item", "styled_generation_clothing_items")
    op.drop_index("idx_sgci_generation", "styled_generation_clothing_items")
    op.drop_table("styled_generation_clothing_items")

    # Reverse D: recreate creator_items shell (data is lost for child tables).
    op.create_table(
        "creator_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "creator_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "catalog_visibility",
            sa.String(20),
            nullable=False,
            server_default="PACK_ONLY",
        ),
        sa.Column(
            "processing_status",
            sa.String(20),
            nullable=False,
            server_default="COMPLETED",
        ),
        sa.Column(
            "predicted_tags",
            postgresql.JSONB,
            nullable=False,
            server_default="[]",
        ),
        sa.Column(
            "final_tags", postgresql.JSONB, nullable=False, server_default="[]"
        ),
        sa.Column("is_confirmed", sa.Boolean, server_default=sa.text("false")),
        sa.Column("name", sa.String(200)),
        sa.Column("description", sa.Text),
        sa.Column(
            "custom_tags", postgresql.ARRAY(sa.String), server_default="{}"
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
    )

    # Child tables: recreate shells (empty) so a subsequent upgrade can
    # SELECT from them without failing. Original child-table data is
    # permanently lost on downgrade — acceptable for one-way prod migration.
    op.create_table(
        "creator_item_images",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "creator_item_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("creator_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("image_type", sa.String(20), nullable=False),
        sa.Column("blob_hash", sa.String(64), nullable=False),
        sa.Column("angle", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_table(
        "creator_models_3d",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "creator_item_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("creator_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "model_format",
            sa.String(10),
            nullable=False,
            server_default="glb",
        ),
        sa.Column("blob_hash", sa.String(64), nullable=False),
        sa.Column("vertex_count", sa.Integer(), nullable=True),
        sa.Column("face_count", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_table(
        "creator_processing_tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "creator_item_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("creator_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("task_type", sa.String(30), nullable=False),
        sa.Column(
            "attempt_no",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
        ),
        sa.Column("retry_of_task_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="PENDING",
        ),
        sa.Column(
            "progress",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("worker_id", sa.String(255), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )

    op.drop_constraint(
        "fk_clothing_items_imported_clothing_item",
        "clothing_items",
        type_="foreignkey",
    )
    op.execute(
        "ALTER INDEX uq_card_pack_items_pack_clothing_item "
        "RENAME TO uq_card_pack_items_pack_creator_item"
    )
    op.drop_constraint(
        "card_pack_items_clothing_item_id_fkey",
        "card_pack_items",
        type_="foreignkey",
    )
    op.alter_column(
        "card_pack_items",
        "clothing_item_id",
        new_column_name="creator_item_id",
    )
    op.create_foreign_key(
        "card_pack_items_creator_item_id_fkey",
        "card_pack_items",
        "creator_items",
        ["creator_item_id"],
        ["id"],
        ondelete="CASCADE",
    )

    # Reverse C
    op.drop_column("styled_generations", "worker_id")
    op.drop_column("styled_generations", "lease_expires_at")
    op.drop_column("styled_generations", "started_at")
    op.drop_column("styled_generations", "gender")

    # Reverse B
    op.drop_constraint(
        "ck_card_pack_import_count_nonneg", "card_packs", type_="check"
    )
    op.drop_column("card_packs", "view_count")

    # Reverse A
    op.alter_column(
        "clothing_items",
        "imported_from_clothing_item_id",
        new_column_name="imported_from_creator_item_id",
    )
    op.create_foreign_key(
        "fk_clothing_items_imported_creator_item",
        "clothing_items",
        "creator_items",
        ["imported_from_creator_item_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.drop_column("clothing_items", "view_count")
    op.drop_column("clothing_items", "deleted_at")
    op.drop_constraint(
        "ck_clothing_catalog_visibility", "clothing_items", type_="check"
    )
    op.drop_column("clothing_items", "catalog_visibility")
