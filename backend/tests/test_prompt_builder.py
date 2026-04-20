from app.services.prompt_builder_service import build_prompt, get_negative_prompt


def test_single_top_male():
    p = build_prompt("in a coffee shop", "male", [("TOP", "blue denim jacket")])
    assert "a man" in p
    assert "a blue denim jacket" in p
    assert "in a coffee shop" in p
    assert "smiling" in p


def test_single_top_female():
    p = build_prompt("at the park", "female", [("TOP", "white blouse")])
    assert "a woman" in p
    assert "a white blouse" in p
    assert "at the park" in p


def test_four_garments():
    p = build_prompt(
        "at the park",
        "female",
        [
            ("HAT", "red baseball cap"),
            ("TOP", "white blouse"),
            ("PANTS", "dark jeans"),
            ("SHOES", "white sneakers"),
        ],
    )
    assert "a red baseball cap" in p
    assert "a white blouse" in p
    # Plural-like: no article.
    assert "dark jeans" in p
    assert "a dark jeans" not in p
    assert "white sneakers" in p
    assert "a white sneakers" not in p
    # Oxford comma before "and".
    assert ", and " in p


def test_slot_ordering_enforced():
    """Regardless of input order, HAT comes before SHOES in the prompt."""
    p = build_prompt(
        "at night",
        "male",
        [
            ("SHOES", "black boots"),
            ("HAT", "beanie"),
        ],
    )
    assert p.index("beanie") < p.index("black boots")


def test_case_insensitive_gender():
    p1 = build_prompt("outside", "MALE", [("TOP", "shirt")])
    p2 = build_prompt("outside", "male", [("TOP", "shirt")])
    p3 = build_prompt("outside", "  Male  ", [("TOP", "shirt")])
    assert p1 == p2 == p3
    assert "a man" in p1


def test_article_vowel_start():
    p = build_prompt("at home", "female", [("TOP", "orange sweater")])
    assert "an orange sweater" in p


def test_negative_prompt_default():
    n = get_negative_prompt()
    assert "blurry" in n
    assert "deformed body" in n


def test_negative_prompt_appends_user():
    n = get_negative_prompt("cartoon")
    assert n.startswith("blurry")  # default first
    assert n.endswith("cartoon")   # user addition appended


def test_negative_prompt_ignores_blank_user():
    n1 = get_negative_prompt("")
    n2 = get_negative_prompt("   ")
    n3 = get_negative_prompt(None)
    from app.services.prompt_builder_service import DEFAULT_NEGATIVE_TEMPLATE
    assert n1 == n2 == n3 == DEFAULT_NEGATIVE_TEMPLATE


def test_empty_garments_uses_fallback():
    p = build_prompt("at home", "male", [])
    assert "wearing clothing" in p
