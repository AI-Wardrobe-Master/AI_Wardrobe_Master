#!/usr/bin/env python3
"""Run focused database-backed checks for the outfit Agent search tool."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.db.session import SessionLocal  # noqa: E402
from app.models.clothing_item import ClothingItem, Image  # noqa: E402
from app.models.user import User  # noqa: E402
from app.schemas.agent import OutfitRecommendationRequest  # noqa: E402
from app.services.clothing_taxonomy import get_clothing_taxonomy  # noqa: E402
from app.services.outfit_agent_service import OutfitRecommendationAgent  # noqa: E402
from app.services.outfit_agent_tools import OutfitAgentToolExecutor  # noqa: E402

DEFAULT_EMAIL = "00001@gmail.com"
EXPECTED_SEED_COUNT = 30
SEARCH_TOOL_NAME = "search_wardrobe_items"
FORBIDDEN_MODEL_ITEM_FIELDS = {
    "imageUrl",
    "source",
    "finalTags",
    "customTags",
    "predictedTags",
    "isConfirmed",
    "description",
}


@dataclass(frozen=True)
class ToolCase:
    """One search tool scenario and its expected high-level outcome."""

    name: str
    arguments: dict[str, Any]
    expected_status: str
    min_total: int | None = None
    expected_total: int | None = None
    expected_error_code: str | None = None


def parse_args() -> argparse.Namespace:
    """Parse command-line options.

    Returns:
        Parsed script arguments.
    """
    parser = argparse.ArgumentParser(
        description="Test search_wardrobe_items against the local database."
    )
    parser.add_argument("--email", default=DEFAULT_EMAIL)
    parser.add_argument("--expected-seed-count", type=int, default=EXPECTED_SEED_COUNT)
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print full result payloads as JSON for each case.",
    )
    return parser.parse_args()


def get_user_by_email(db: Session, email: str) -> User:
    """Load the target user by email.

    Args:
        db: Active SQLAlchemy session.
        email: User email to look up.

    Returns:
        Matching user row.

    Raises:
        RuntimeError: If no active user exists for the email.
    """
    user = db.query(User).filter(User.email == email, User.is_active.is_(True)).first()
    if user is None:
        raise RuntimeError(f"Active user not found for email: {email}")
    return user


def count_seed_items(db: Session, user_id: Any) -> tuple[int, int]:
    """Count agent seed clothing items and processed-front images.

    Args:
        db: Active SQLAlchemy session.
        user_id: Target user UUID.

    Returns:
        Pair of seed item count and processed-front image count.
    """
    # The seed script marks every generated clothing item with `agent_seed`.
    seed_items = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == user_id,
            ClothingItem.deleted_at.is_(None),
            ClothingItem.custom_tags.any("agent_seed"),
        )
        .all()
    )
    seed_ids = [item.id for item in seed_items]
    if not seed_ids:
        return 0, 0

    # The Agent preview path prefers PROCESSED_FRONT, so verify these rows exist.
    image_count = (
        db.query(Image)
        .filter(
            Image.clothing_item_id.in_(seed_ids),
            Image.image_type == "PROCESSED_FRONT",
        )
        .count()
    )
    return len(seed_items), image_count


def build_executor(db: Session, user_id: Any) -> OutfitAgentToolExecutor:
    """Build the real search tool executor without initializing the LLM.

    Args:
        db: Active SQLAlchemy session.
        user_id: Target user UUID.

    Returns:
        Configured outfit Agent tool executor.
    """
    # The payload builder is an instance method, but it does not depend on graph
    # or LLM state. `__new__` avoids constructing the full Agent workflow.
    agent_shell = OutfitRecommendationAgent.__new__(OutfitRecommendationAgent)
    return OutfitAgentToolExecutor(
        db=db,
        user_id=user_id,
        request=OutfitRecommendationRequest(message="search tool test", limit=50),
        taxonomy=get_clothing_taxonomy(),
        clothing_payload_builder=agent_shell._clothing_item_payload,
    )


def tool_cases() -> list[ToolCase]:
    """Return the fixed search scenarios covered by this script.

    Returns:
        Ordered search tool cases.
    """
    return [
        ToolCase(
            name="broad_recall_default_limit",
            arguments={},
            expected_status="success",
            expected_total=20,
        ),
        ToolCase(
            name="summer_tag",
            arguments={"tags": [{"key": "season", "value": "summer"}], "limit": 50},
            expected_status="success",
            min_total=1,
        ),
        ToolCase(
            name="rain_weather_type",
            arguments={
                "tags": [{"key": "weather_type", "value": "rain"}],
                "limit": 50,
            },
            expected_status="success",
            min_total=1,
        ),
        ToolCase(
            name="t_shirt_category",
            arguments={"category": "T_SHIRT", "limit": 50},
            expected_status="success",
            min_total=1,
        ),
        ToolCase(
            name="legal_empty_category",
            arguments={"category": "DRESS_SHOES", "limit": 50},
            expected_status="success",
            expected_total=0,
        ),
        ToolCase(
            name="invalid_type_field",
            arguments={"type": "DRESS_SHOES"},
            expected_status="failed",
            expected_error_code="INVALID_TOOL_ARGUMENTS",
        ),
    ]


def execute_case(
    executor: OutfitAgentToolExecutor,
    case: ToolCase,
    *,
    show_json: bool,
) -> None:
    """Execute one tool case, print its output, and assert expectations.

    Args:
        executor: Configured tool executor.
        case: Tool scenario to run.
        show_json: Whether to print the full tool result payload.

    Raises:
        AssertionError: If the tool result does not match expectations.
    """
    result = executor.execute(
        tool_name=SEARCH_TOOL_NAME,
        raw_arguments=case.arguments,
        cache={},
    )
    data = result.data or {}
    total = data.get("total")
    items = data.get("items") or []

    print(f"case={case.name}")
    print(f"  args={json.dumps(case.arguments, ensure_ascii=False, sort_keys=True)}")
    print(f"  status={result.status}")
    print(f"  errorCode={result.error_code}")
    print(f"  total={total}")
    print(f"  firstItems={format_item_preview(items)}")
    if show_json:
        print(
            "  payload="
            + json.dumps(
                result.model_dump(mode="json", by_alias=True),
                ensure_ascii=False,
                sort_keys=True,
            )
        )

    # Keep assertions at the business-contract level so item ordering changes do
    # not make this script brittle.
    assert result.status == case.expected_status, case.name
    if case.expected_error_code is not None:
        assert result.error_code == case.expected_error_code, case.name
    if case.expected_total is not None:
        assert total == case.expected_total, case.name
    if case.min_total is not None:
        assert isinstance(total, int) and total >= case.min_total, case.name
    assert_no_forbidden_item_fields(items, case.name)


def assert_no_forbidden_item_fields(items: list[dict[str, Any]], case_name: str) -> None:
    """Assert that model-facing item payloads stay compact.

    Args:
        items: Tool result item payloads.
        case_name: Search case name used in assertion errors.
    """
    for item in items:
        leaked = sorted(FORBIDDEN_MODEL_ITEM_FIELDS.intersection(item))
        assert not leaked, f"{case_name} leaked fields: {leaked}"


def format_item_preview(items: list[dict[str, Any]]) -> str:
    """Format a compact preview of returned clothing items.

    Args:
        items: Tool result item payloads.

    Returns:
        One-line item preview.
    """
    preview = [
        (
            f"{item.get('name')}|{item.get('category')}|"
            f"{item.get('previewGarmentCategory')}|"
            f"{json.dumps(item.get('matchedTags'), ensure_ascii=False)}"
        )
        for item in items[:5]
    ]
    return json.dumps(preview, ensure_ascii=False)


def main() -> int:
    """Run search tool checks.

    Returns:
        Process exit code.
    """
    args = parse_args()
    with SessionLocal() as db:
        user = get_user_by_email(db, args.email)
        seed_count, image_count = count_seed_items(db, user.id)
        print(f"userEmail={user.email}")
        print(f"userId={user.id}")
        print(f"agentSeedItemCount={seed_count}")
        print(f"processedFrontImageCount={image_count}")

        if seed_count != args.expected_seed_count:
            raise RuntimeError(
                f"Expected {args.expected_seed_count} seed items, found {seed_count}"
            )
        if image_count != args.expected_seed_count:
            raise RuntimeError(
                f"Expected {args.expected_seed_count} processed images, found {image_count}"
            )

        executor = build_executor(db, user.id)
        for case in tool_cases():
            execute_case(executor, case, show_json=args.json)

    print("search_tool_verification=success")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
