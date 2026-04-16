"""CAS storage refactor: blobs table, column renames, card_pack_imports

Revision ID: 20260415_000010
Revises: 20260413_000005
Create Date: 2026-04-15
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260415_000010"
down_revision: Union[str, None] = "20260413_000005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Create blobs table
    op.create_table(
        "blobs",
        sa.Column("blob_hash", sa.String(64), primary_key=True),
        sa.Column("byte_size", sa.BigInteger(), nullable=False),
        sa.Column("mime_type", sa.String(100), nullable=False),
        sa.Column("ref_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("first_seen_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("last_referenced_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("pending_delete_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_check_constraint("ck_blob_ref_count", "blobs", "ref_count >= 0")
    op.create_index(
        "idx_blobs_pending_delete", "blobs", ["pending_delete_at"],
        postgresql_where=sa.text("pending_delete_at IS NOT NULL"),
    )

    # 2. Create card_pack_imports table
    op.create_table(
        "card_pack_imports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("card_pack_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("card_packs.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("imported_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "card_pack_id", name="uq_card_pack_imports_user_pack"),
    )
    op.create_index("idx_card_pack_imports_pack", "card_pack_imports", ["card_pack_id"])

    # 3. clothing_items: add imported_from columns
    op.add_column("clothing_items",
        sa.Column("imported_from_card_pack_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column("clothing_items",
        sa.Column("imported_from_creator_item_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.create_foreign_key(
        "fk_clothing_items_imported_pack", "clothing_items", "card_packs",
        ["imported_from_card_pack_id"], ["id"], ondelete="SET NULL")
    op.create_foreign_key(
        "fk_clothing_items_imported_creator_item", "clothing_items", "creator_items",
        ["imported_from_creator_item_id"], ["id"], ondelete="SET NULL")
    op.create_index("idx_clothing_items_imported_from_pack", "clothing_items",
                    ["imported_from_card_pack_id"])

    # 4. Column swaps: storage_path -> blob_hash
    COLUMN_SWAPS = [
        ("images", "storage_path", "blob_hash", False),
        ("creator_item_images", "storage_path", "blob_hash", False),
        ("models_3d", "storage_path", "blob_hash", False),
        ("creator_models_3d", "storage_path", "blob_hash", False),
        ("styled_generations", "selfie_original_path", "selfie_original_blob_hash", False),
        ("styled_generations", "selfie_processed_path", "selfie_processed_blob_hash", True),
        ("styled_generations", "result_image_path", "result_image_blob_hash", True),
        ("outfit_preview_tasks", "person_image_path", "person_image_blob_hash", False),
        ("outfit_preview_tasks", "preview_image_path", "preview_image_blob_hash", True),
        ("outfit_preview_task_items", "garment_image_path", "garment_image_blob_hash", False),
        ("outfits", "preview_image_path", "preview_image_blob_hash", False),
        ("card_packs", "cover_image_storage_path", "cover_image_blob_hash", True),
    ]
    for table, old_col, new_col, nullable in COLUMN_SWAPS:
        op.drop_column(table, old_col)
        op.add_column(table, sa.Column(
            new_col, sa.String(64),
            sa.ForeignKey("blobs.blob_hash"),
            nullable=nullable,
        ))

    # 5. Drop redundant file_size and mime_type columns
    op.drop_column("images", "file_size")
    op.drop_column("images", "mime_type")
    op.drop_column("creator_item_images", "file_size")
    op.drop_column("creator_item_images", "mime_type")
    op.drop_column("models_3d", "file_size")
    op.drop_column("creator_models_3d", "file_size")


def downgrade() -> None:
    # Reverse column swaps
    COLUMN_SWAPS = [
        ("images", "blob_hash", "storage_path"),
        ("creator_item_images", "blob_hash", "storage_path"),
        ("models_3d", "blob_hash", "storage_path"),
        ("creator_models_3d", "blob_hash", "storage_path"),
        ("styled_generations", "selfie_original_blob_hash", "selfie_original_path"),
        ("styled_generations", "selfie_processed_blob_hash", "selfie_processed_path"),
        ("styled_generations", "result_image_blob_hash", "result_image_path"),
        ("outfit_preview_tasks", "person_image_blob_hash", "person_image_path"),
        ("outfit_preview_tasks", "preview_image_blob_hash", "preview_image_path"),
        ("outfit_preview_task_items", "garment_image_blob_hash", "garment_image_path"),
        ("outfits", "preview_image_blob_hash", "preview_image_path"),
        ("card_packs", "cover_image_blob_hash", "cover_image_storage_path"),
    ]
    for table, old_col, new_col in COLUMN_SWAPS:
        op.drop_column(table, old_col)
        op.add_column(table, sa.Column(new_col, sa.Text(), nullable=True))

    # Restore file_size / mime_type
    op.add_column("images", sa.Column("file_size", sa.BigInteger(), nullable=True))
    op.add_column("images", sa.Column("mime_type", sa.String(50), nullable=True))
    op.add_column("creator_item_images", sa.Column("file_size", sa.BigInteger(), nullable=True))
    op.add_column("creator_item_images", sa.Column("mime_type", sa.String(50), nullable=True))
    op.add_column("models_3d", sa.Column("file_size", sa.BigInteger(), nullable=True))
    op.add_column("creator_models_3d", sa.Column("file_size", sa.BigInteger(), nullable=True))

    op.drop_index("idx_clothing_items_imported_from_pack", "clothing_items")
    op.drop_constraint("fk_clothing_items_imported_creator_item", "clothing_items", type_="foreignkey")
    op.drop_constraint("fk_clothing_items_imported_pack", "clothing_items", type_="foreignkey")
    op.drop_column("clothing_items", "imported_from_creator_item_id")
    op.drop_column("clothing_items", "imported_from_card_pack_id")

    op.drop_table("card_pack_imports")
    op.drop_table("blobs")
