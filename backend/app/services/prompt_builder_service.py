"""Prompt template assembly for DreamO multi-garment styled generation."""

SLOT_ORDER = ("HAT", "TOP", "PANTS", "SHOES")
SLOT_DEFAULT_DESCRIPTOR = {
    "HAT": "a hat",
    "TOP": "a top",
    "PANTS": "pants",
    "SHOES": "shoes",
}

PLURAL_LIKE = {"jeans", "pants", "shoes", "sneakers", "boots", "trousers", "shorts"}

DEFAULT_NEGATIVE_TEMPLATE = (
    "blurry, low quality, deformed body, extra fingers, extra limbs, "
    "duplicated person, wrong clothing, bad anatomy, oversaturated face, plastic skin"
)


def _article(descriptor: str) -> str:
    """Return 'a' / 'an' / '' (empty for plural-like words)."""
    lower = descriptor.strip().lower()
    if not lower:
        return ""
    words = lower.split()
    first, last = words[0], words[-1]
    if last in PLURAL_LIKE or first in PLURAL_LIKE:
        return ""
    return "an" if lower[:1] in "aeiou" else "a"


def _with_article(descriptor: str) -> str:
    art = _article(descriptor)
    return f"{art} {descriptor}".strip()


def _join_garments(garments: list[tuple[str, str]]) -> str:
    """Enforce HAT→TOP→PANTS→SHOES ordering regardless of input order."""
    by_slot: dict[str, str] = {slot: desc for slot, desc in garments}
    ordered = [(slot, by_slot[slot]) for slot in SLOT_ORDER if slot in by_slot]
    parts = [_with_article(desc) for _, desc in ordered]
    if not parts:
        return "clothing"
    if len(parts) == 1:
        return parts[0]
    if len(parts) == 2:
        return f"{parts[0]} and {parts[1]}"
    return ", ".join(parts[:-1]) + f", and {parts[-1]}"


def build_prompt(
    scene_prompt: str,
    gender: str,
    garments: list[tuple[str, str]],
) -> str:
    """Compose final DreamO prompt.

    Args:
        scene_prompt: Free-form scene from user (e.g. "in a coffee shop").
        gender: "male" or "female" (case-insensitive).
        garments: List of (slot, descriptor) pairs where slot is
                  HAT/TOP/PANTS/SHOES and descriptor is the clothing item's
                  name/category. Caller is expected to pass deduplicated slots;
                  ordering is NOT required (we enforce HAT→TOP→PANTS→SHOES).
    """
    gender_word = "man" if gender.strip().lower() == "male" else "woman"
    phrase = _join_garments(garments)
    return (
        f"A realistic full-body fashion portrait of a {gender_word}, "
        f"wearing {phrase}, in {scene_prompt.strip()}, smiling, "
        "natural skin texture, detailed fabric, high quality, photographic lighting"
    )


def get_negative_prompt(user_negative: str | None = None) -> str:
    """Combine default negative prompt with optional user override."""
    if user_negative and user_negative.strip():
        return f"{DEFAULT_NEGATIVE_TEMPLATE}, {user_negative.strip()}"
    return DEFAULT_NEGATIVE_TEMPLATE
