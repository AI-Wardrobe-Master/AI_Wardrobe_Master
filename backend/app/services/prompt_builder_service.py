"""
Prompt template assembly for DreamO styled generation.

Combines a base quality prompt, garment conformity instructions,
and the user's scene description into a single prompt.
Negative prompts are similarly assembled from defaults + user overrides.
"""

BASE_QUALITY_TEMPLATE = (
    "a realistic full-body fashion portrait, "
    "natural skin texture, detailed fabric, "
    "high quality, photographic lighting"
)

GARMENT_CONFORMITY_TEMPLATE = (
    "wearing the provided garment, "
    "preserve garment appearance and category, "
    "preserve clothing color and major silhouette"
)

DEFAULT_NEGATIVE_TEMPLATE = (
    "blurry, low quality, deformed body, extra fingers, extra limbs, "
    "duplicated person, wrong clothing, bad anatomy, "
    "oversaturated face, plastic skin"
)


def build_prompt(
    scene_prompt: str,
    *,
    base_quality: str = BASE_QUALITY_TEMPLATE,
    garment_conformity: str = GARMENT_CONFORMITY_TEMPLATE,
) -> str:
    """
    Assemble the final prompt from templates and user scene input.

    Order: base quality → garment conformity → user scene prompt
    """
    parts = [base_quality, garment_conformity, scene_prompt.strip()]
    return ", ".join(p for p in parts if p)


def get_negative_prompt(
    user_negative: str | None = None,
    *,
    default_negative: str = DEFAULT_NEGATIVE_TEMPLATE,
) -> str:
    """
    Combine the default negative prompt with any user-provided additions.
    """
    if user_negative and user_negative.strip():
        return f"{default_negative}, {user_negative.strip()}"
    return default_negative
