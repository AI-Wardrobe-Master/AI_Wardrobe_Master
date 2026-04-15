import unittest
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException

from app.api.deps import get_current_creator_user_id
from app.api.v1.creators import update_creator_profile
from app.api.v1.me import get_me
from app.crud import creator as crud_creator
from app.models.creator import CreatorProfile
from app.models.user import User
from app.schemas.creator import CreatorProfileUpdate


class FakeQuery:
    def __init__(self, items):
        self._items = list(items)
        self._criteria = []

    def join(self, *args, **kwargs):
        return self

    def filter(self, *criteria):
        self._criteria.extend(criteria)
        return self

    def order_by(self, *args, **kwargs):
        return self

    def offset(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self

    def count(self):
        return len(self.all())

    def first(self):
        results = self.all()
        return results[0] if results else None

    def all(self):
        return [item for item in self._items if self._matches(item)]

    def _matches(self, item):
        target = item[0] if isinstance(item, tuple) else item
        for criterion in self._criteria:
            left = getattr(criterion, "left", None)
            right = getattr(criterion, "right", None)
            key = getattr(left, "key", None)
            value = getattr(right, "value", None)
            if key is None:
                continue
            if getattr(target, key) != value:
                return False
        return True


class FakeSession:
    def __init__(self, users, profiles):
        self.users = {user.id: user for user in users}
        self.profiles = {profile.user_id: profile for profile in profiles}

    def get(self, model, key):
        if model is User:
            return self.users.get(key)
        return None

    def query(self, model):
        if model is CreatorProfile:
            return FakeQuery(self.profiles.values())
        raise AssertionError(f"Unexpected query model: {model}")

    def commit(self):
        return None

    def refresh(self, instance):
        return instance


def make_user(user_id, *, user_type="CONSUMER"):
    return User(
        id=user_id,
        username=f"user-{str(user_id)[:8]}",
        email=f"{str(user_id)[:8]}@example.com",
        hashed_password="hashed",
        user_type=user_type,
        is_active=True,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


def make_profile(user_id, *, status="ACTIVE", display_name="Creator Name"):
    return CreatorProfile(
        user_id=user_id,
        status=status,
        display_name=display_name,
        brand_name="Brand",
        bio="Bio",
        social_links={"instagram": "https://instagram.com/test"},
        is_verified=False,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


class CreatorFoundationTests(unittest.TestCase):
    def test_get_current_creator_user_id_requires_active_profile(self):
        user_id = uuid4()
        db = FakeSession([make_user(user_id)], [])
        with self.assertRaises(HTTPException) as ctx:
            get_current_creator_user_id(user_id, db)
        self.assertEqual(ctx.exception.status_code, 403)

    def test_get_current_creator_user_id_accepts_active_profile(self):
        user_id = uuid4()
        db = FakeSession([make_user(user_id)], [make_profile(user_id, status="ACTIVE")])
        self.assertEqual(get_current_creator_user_id(user_id, db), user_id)

    def test_get_me_without_creator_profile(self):
        user_id = uuid4()
        db = FakeSession([make_user(user_id)], [])
        response = get_me(db, user_id)
        self.assertFalse(response.data.creator_profile.exists)
        self.assertTrue(response.data.capabilities.can_apply_for_creator)
        self.assertFalse(response.data.capabilities.can_view_creator_center)

    def test_get_me_with_active_creator_profile(self):
        user_id = uuid4()
        db = FakeSession([make_user(user_id)], [make_profile(user_id)])
        response = get_me(db, user_id)
        self.assertTrue(response.data.creator_profile.exists)
        self.assertEqual(response.data.creator_profile.status, "ACTIVE")
        self.assertTrue(response.data.capabilities.can_publish_items)
        self.assertTrue(response.data.capabilities.can_create_card_packs)

    def test_update_creator_profile_requires_ownership(self):
        owner_id = uuid4()
        other_id = uuid4()
        db = FakeSession([make_user(owner_id)], [make_profile(owner_id)])
        with self.assertRaises(HTTPException) as ctx:
            update_creator_profile(
                owner_id,
                CreatorProfileUpdate(displayName="New Name"),
                db,
                other_id,
            )
        self.assertEqual(ctx.exception.status_code, 404)

    def test_crud_update_profile_changes_fields(self):
        owner_id = uuid4()
        profile = make_profile(owner_id)
        db = FakeSession([make_user(owner_id)], [profile])
        updated = crud_creator.update_profile(
            db,
            profile,
            display_name="Updated",
            brand_name="New Brand",
            bio="Updated Bio",
            website_url="https://example.com",
            social_links={"tiktok": "https://tiktok.com/@creator"},
        )
        self.assertEqual(updated.display_name, "Updated")
        self.assertEqual(updated.brand_name, "New Brand")
        self.assertEqual(updated.website_url, "https://example.com")
        self.assertIn("tiktok", updated.social_links)
