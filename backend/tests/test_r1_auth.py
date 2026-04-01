import asyncio
import unittest
from datetime import datetime, timezone
from unittest.mock import Mock, patch
from uuid import UUID, uuid4

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError

from app.api.deps import get_current_user_id
from app.api.v1.auth import login, register
from app.api.v1 import clothing as clothing_api
from app.api.v1 import wardrobe as wardrobe_api
from app.core.security import create_access_token, get_password_hash, verify_password
from app.models.clothing_item import ClothingItem
from app.models.user import User
from app.models.wardrobe import WardrobeItem
from app.schemas.auth import LoginRequest, RegisterRequest
from app.schemas.clothing_item import ClothingItemUpdate
from app.schemas.wardrobe import WardrobeItemAdd


class FakeQuery:
    def __init__(self, items):
        self._items = list(items)
        self._criteria = []

    def filter(self, *criteria):
        self._criteria.extend(criteria)
        return self

    def order_by(self, *args, **kwargs):
        return self

    def first(self):
        for item in self._items:
            if self._matches(item):
                return item
        return None

    def all(self):
        return [item for item in self._items if self._matches(item)]

    def _matches(self, item):
        for criterion in self._criteria:
            left = getattr(criterion, "left", None)
            right = getattr(criterion, "right", None)
            key = getattr(left, "key", None)
            value = getattr(right, "value", None)
            if key is None:
                continue
            if getattr(item, key) != value:
                return False
        return True


class FakeSession:
    def __init__(self, users):
        self.users = {user.id: user for user in users}
        self._pending_user = None

    def get(self, model, key):
        if model is User:
            return self.users.get(key)
        return None

    def query(self, model):
        if model is User:
            return FakeQuery(self.users.values())
        raise AssertionError(f"Unexpected query model: {model}")

    def add(self, instance):
        if not isinstance(instance, User):
            raise AssertionError(f"Unexpected add model: {type(instance)}")
        self._pending_user = instance

    def commit(self):
        if self._pending_user is not None:
            if self._pending_user.id is None:
                self._pending_user.id = uuid4()
            if self._pending_user.created_at is None:
                self._pending_user.created_at = datetime.now(timezone.utc)
            self.users[self._pending_user.id] = self._pending_user
            self._pending_user = None

    def refresh(self, instance):
        return instance


def make_user(*, user_id: UUID, email: str, password: str, active: bool = True) -> User:
    return User(
        id=user_id,
        username=email.split("@")[0],
        email=email,
        hashed_password=get_password_hash(password),
        user_type="CONSUMER",
        is_active=active,
        created_at=datetime.now(timezone.utc),
    )


class R1AuthTests(unittest.TestCase):
    def test_register_returns_jwt_for_new_user(self):
        db = FakeSession([])

        response = register(
            RegisterRequest(
                username="newuser",
                email="newuser@example.com",
                password="secret123",
            ),
            db,
        )

        self.assertTrue(response.success)
        self.assertEqual(response.data.user.username, "newuser")
        self.assertEqual(response.data.user.email, "newuser@example.com")
        self.assertEqual(response.data.user.user_type, "CONSUMER")
        self.assertTrue(response.data.token)

        created_user = next(iter(db.users.values()))
        self.assertNotEqual(created_user.hashed_password, "secret123")
        self.assertTrue(verify_password("secret123", created_user.hashed_password))

    def test_register_rejects_duplicate_email(self):
        existing_user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )

        with self.assertRaises(HTTPException) as ctx:
            register(
                RegisterRequest(
                    username="another_user",
                    email="owner@example.com",
                    password="secret123",
                ),
                FakeSession([existing_user]),
            )

        self.assertEqual(ctx.exception.status_code, 409)
        self.assertEqual(ctx.exception.detail, "Email already registered")

    def test_register_rejects_duplicate_username(self):
        existing_user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )

        with self.assertRaises(HTTPException) as ctx:
            register(
                RegisterRequest(
                    username=existing_user.username,
                    email="another@example.com",
                    password="secret123",
                ),
                FakeSession([existing_user]),
            )

        self.assertEqual(ctx.exception.status_code, 409)
        self.assertEqual(ctx.exception.detail, "Username already taken")

    def test_register_defaults_user_type_to_consumer(self):
        response = register(
            RegisterRequest(
                username="newuser",
                email="newuser@example.com",
                password="secret123",
            ),
            FakeSession([]),
        )

        self.assertEqual(response.data.user.user_type, "CONSUMER")

    def test_register_ignores_requested_user_type_for_now(self):
        response = register(
            RegisterRequest(
                username="creator_user",
                email="creator@example.com",
                password="secret123",
                userType="CREATOR",
            ),
            FakeSession([]),
        )

        self.assertEqual(response.data.user.user_type, "CONSUMER")

    def test_register_validates_email(self):
        with self.assertRaises(ValidationError):
            RegisterRequest(
                username="newuser",
                email="not-an-email",
                password="secret123",
            )

    def test_register_validates_password_length(self):
        with self.assertRaises(ValidationError):
            RegisterRequest(
                username="newuser",
                email="newuser@example.com",
                password="short",
            )

    def test_login_returns_jwt_for_valid_credentials(self):
        user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )
        response = login(
            LoginRequest(email="owner@example.com", password="secret123"),
            FakeSession([user]),
        )

        self.assertTrue(response.success)
        self.assertEqual(response.data.user.email, "owner@example.com")
        self.assertTrue(response.data.token)

    def test_login_rejects_invalid_password(self):
        user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )

        with self.assertRaises(HTTPException) as ctx:
            login(
                LoginRequest(email="owner@example.com", password="wrong-pass"),
                FakeSession([user]),
            )

        self.assertEqual(ctx.exception.status_code, 401)

    def test_empty_token_returns_401(self):
        user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )

        with self.assertRaises(HTTPException) as ctx:
            get_current_user_id(None, FakeSession([user]))

        self.assertEqual(ctx.exception.status_code, 401)

    def test_invalid_token_returns_401(self):
        user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )

        with self.assertRaises(HTTPException) as ctx:
            get_current_user_id(
                HTTPAuthorizationCredentials(
                    scheme="Bearer",
                    credentials="definitely-not-a-jwt",
                ),
                FakeSession([user]),
            )

        self.assertEqual(ctx.exception.status_code, 401)

    def test_non_bearer_scheme_returns_401(self):
        user = make_user(
            user_id=uuid4(),
            email="owner@example.com",
            password="secret123",
        )

        with self.assertRaises(HTTPException) as ctx:
            get_current_user_id(
                HTTPAuthorizationCredentials(
                    scheme="Basic",
                    credentials="not-a-bearer-token",
                ),
                FakeSession([user]),
            )

        self.assertEqual(ctx.exception.status_code, 401)

    def test_user_cannot_read_other_users_clothing_item(self):
        owner_id = uuid4()
        intruder_id = uuid4()
        item_id = uuid4()
        db = object()
        item = ClothingItem(id=item_id, user_id=owner_id, source="OWNED")

        def fake_get(session, requested_item_id, user_id):
            if session is db and requested_item_id == item_id and user_id == owner_id:
                return item
            return None

        with patch.object(clothing_api.crud_clothing, "get", side_effect=fake_get):
            with self.assertRaises(HTTPException) as ctx:
                clothing_api.get_clothing_item(item_id, db, intruder_id)

        self.assertEqual(ctx.exception.status_code, 404)

    def test_user_cannot_modify_other_users_clothing_item(self):
        owner_id = uuid4()
        intruder_id = uuid4()
        item_id = uuid4()
        db = object()

        def fake_update(session, requested_item_id, user_id, **kwargs):
            if session is db and requested_item_id == item_id and user_id == owner_id:
                return ClothingItem(id=item_id, user_id=owner_id, source="OWNED")
            return None

        body = ClothingItemUpdate(name="stolen")

        with patch.object(clothing_api.crud_clothing, "update", side_effect=fake_update):
            with self.assertRaises(HTTPException) as ctx:
                clothing_api.update_clothing_item(item_id, body, db, intruder_id)

        self.assertEqual(ctx.exception.status_code, 404)

    def test_user_cannot_read_other_users_processing_status(self):
        item_id = uuid4()

        with patch.object(clothing_api.crud_clothing, "get", return_value=None):
            with self.assertRaises(HTTPException) as ctx:
                clothing_api.get_processing_status(item_id, object(), uuid4())

        self.assertEqual(ctx.exception.status_code, 404)

    def test_user_cannot_retry_other_users_processing(self):
        item_id = uuid4()
        db = Mock()
        db.query.return_value.filter.return_value.with_for_update.return_value.first.return_value = None

        with patch.object(clothing_api.crud_clothing, "get", return_value=None):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(clothing_api.retry_processing(item_id, db, uuid4()))

        self.assertEqual(ctx.exception.status_code, 404)

    def test_user_cannot_add_other_users_item_to_wardrobe(self):
        wardrobe_id = uuid4()
        item_id = uuid4()
        body = WardrobeItemAdd(clothingItemId=item_id)

        with patch.object(wardrobe_api.crud_wardrobe, "add_item_to_wardrobe", return_value=None):
            with self.assertRaises(HTTPException) as ctx:
                wardrobe_api.add_item_to_wardrobe(wardrobe_id, body, object(), uuid4())

        self.assertEqual(ctx.exception.status_code, 404)

    def test_valid_token_returns_current_user_id(self):
        user_id = uuid4()
        user = make_user(
            user_id=user_id,
            email="owner@example.com",
            password="secret123",
        )
        token = create_access_token(str(user_id))

        current_user_id = get_current_user_id(
            HTTPAuthorizationCredentials(scheme="Bearer", credentials=token),
            FakeSession([user]),
        )

        self.assertEqual(current_user_id, user_id)


if __name__ == "__main__":
    unittest.main()
