from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.models.creator import CreatorProfile
from app.models.user import User


def get_by_user_id(db: Session, user_id):
    return db.query(CreatorProfile).filter(CreatorProfile.user_id == user_id).first()


def get_owned_creator_profile(db: Session, *, creator_id, current_user_id):
    return (
        db.query(CreatorProfile)
        .filter(
            CreatorProfile.user_id == creator_id,
            CreatorProfile.user_id == current_user_id,
        )
        .first()
    )


def create_profile(
    db: Session,
    *,
    user_id,
    display_name: str,
    brand_name: str | None = None,
    bio: str | None = None,
    website_url: str | None = None,
    social_links: dict[str, str] | None = None,
    status: str = "ACTIVE",
):
    profile = CreatorProfile(
        user_id=user_id,
        display_name=display_name,
        brand_name=brand_name,
        bio=bio,
        website_url=website_url,
        social_links=social_links or {},
        status=status,
    )
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


def update_profile(
    db: Session,
    profile: CreatorProfile,
    *,
    display_name: str | None = None,
    brand_name: str | None = None,
    bio: str | None = None,
    website_url: str | None = None,
    social_links: dict[str, str] | None = None,
):
    if display_name is not None:
        profile.display_name = display_name
    if brand_name is not None:
        profile.brand_name = brand_name
    if bio is not None:
        profile.bio = bio
    if website_url is not None:
        profile.website_url = website_url
    if social_links is not None:
        profile.social_links = social_links
    db.commit()
    db.refresh(profile)
    return profile


def list_public_creators(
    db: Session,
    *,
    verified: bool | None = None,
    search: str | None = None,
    page: int = 1,
    limit: int = 20,
):
    query = (
        db.query(CreatorProfile, User)
        .join(User, User.id == CreatorProfile.user_id)
        .filter(CreatorProfile.status == "ACTIVE")
    )
    if verified is not None:
        query = query.filter(CreatorProfile.is_verified == verified)
    if search:
        term = f"%{search.strip()}%"
        query = query.filter(
            or_(
                User.username.ilike(term),
                CreatorProfile.display_name.ilike(term),
                CreatorProfile.brand_name.ilike(term),
            )
        )
    total = query.count()
    rows = (
        query.order_by(
            CreatorProfile.is_verified.desc(),
            func.lower(CreatorProfile.display_name).asc(),
        )
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return rows, total


def get_public_creator_profile(db: Session, *, creator_id):
    return (
        db.query(CreatorProfile, User)
        .join(User, User.id == CreatorProfile.user_id)
        .filter(
            CreatorProfile.user_id == creator_id,
            CreatorProfile.status == "ACTIVE",
        )
        .first()
    )
