STYLE_OPTIONS = [
    "casual", "formal", "business", "sporty", "bohemian",
    "vintage", "minimalist", "streetwear", "elegant", "other",
]

SEASON_OPTIONS = ["spring", "summer", "fall", "winter", "all_season"]

AUDIENCE_OPTIONS = ["men", "women", "unisex", "kids", "teen"]

CATEGORY_OPTIONS = [
    "T_SHIRT", "SHIRT", "BLOUSE", "POLO", "TANK_TOP",
    "SWEATER", "HOODIE", "SWEATSHIRT", "CARDIGAN",
    "JEANS", "TROUSERS", "SHORTS", "SKIRT", "LEGGINGS", "SWEATPANTS",
    "JACKET", "COAT", "BLAZER", "PUFFER", "WIND_BREAKER", "VEST",
    "DRESS", "JUMPSUIT", "ROMPER",
    "SNEAKERS", "BOOTS", "SANDALS", "DRESS_SHOES", "HEELS", "SLIPPERS",
    "HAT", "SCARF", "BELT",
    "OTHER",
]

COLOR_OPTIONS = [
    "black", "white", "gray", "navy", "blue", "red", "green",
    "yellow", "orange", "brown", "pink", "purple", "beige",
]

PATTERN_OPTIONS = [
    "solid", "striped", "checked", "floral", "geometric",
    "polka_dot", "animal_print", "abstract", "other",
]

WEATHER_TYPE_OPTIONS = [
    "clear", "cloudy", "rain", "snow", "windy", "humid", "hot", "cold",
]

# Weather profile values are intentionally generated from controlled season and
# weather type vocabularies. This prevents free-form weather tags from making
# wardrobe search harder for the Agent.
WEATHER_PROFILE_OPTIONS = [
    f"{season}_{weather_type}"
    for season in SEASON_OPTIONS
    for weather_type in WEATHER_TYPE_OPTIONS
]

# Clothing item `category` and preview API `garmentCategory` are different
# concepts. This mapping is the explicit bridge from wardrobe data to preview
# generation slots.
CATEGORY_TO_PREVIEW_GARMENT_CATEGORY = {
    "T_SHIRT": "TOP",
    "SHIRT": "TOP",
    "BLOUSE": "TOP",
    "POLO": "TOP",
    "TANK_TOP": "TOP",
    "SWEATER": "TOP",
    "HOODIE": "TOP",
    "SWEATSHIRT": "TOP",
    "CARDIGAN": "TOP",
    "DRESS": "TOP",
    "JUMPSUIT": "TOP",
    "ROMPER": "TOP",
    "JEANS": "BOTTOM",
    "TROUSERS": "BOTTOM",
    "SHORTS": "BOTTOM",
    "SKIRT": "BOTTOM",
    "LEGGINGS": "BOTTOM",
    "SWEATPANTS": "BOTTOM",
    "SNEAKERS": "SHOES",
    "BOOTS": "SHOES",
    "SANDALS": "SHOES",
    "DRESS_SHOES": "SHOES",
    "HEELS": "SHOES",
    "SLIPPERS": "SHOES",
}


def get_clothing_taxonomy() -> dict:
    """Returns the controlled clothing taxonomy used by UI and Agent tools.

    Returns:
        A dictionary containing editable clothing attributes, controlled weather
        tags, and the category-to-preview-slot mapping.
    """
    # Keep all taxonomy values behind one function so `/attributes/options` and
    # Agent tooling cannot drift into different vocabularies.
    return {
        "style": STYLE_OPTIONS,
        "season": SEASON_OPTIONS,
        "audience": AUDIENCE_OPTIONS,
        "category": CATEGORY_OPTIONS,
        "color": COLOR_OPTIONS,
        "pattern": PATTERN_OPTIONS,
        "weatherTypes": WEATHER_TYPE_OPTIONS,
        "weatherProfiles": WEATHER_PROFILE_OPTIONS,
        "previewCategoryMapping": CATEGORY_TO_PREVIEW_GARMENT_CATEGORY,
    }
