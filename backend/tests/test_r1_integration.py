import socket
import threading
import time
import unittest
from contextlib import closing
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import uuid4

import httpx
import uvicorn

from app.core.security import create_access_token, get_password_hash
from app.db.session import get_db
from app.main import app
from app.models.user import User
from app.models.wardrobe import Wardrobe


class FakeQuery:
    def __init__(self, items):
        self._items = list(items)
        self._criteria = []

    def filter(self, *criteria):
        self._criteria.extend(criteria)
        return self

    def first(self):
        for item in self._items:
            if self._matches(item):
                return item
        return None

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
        self.wardrobes = {}
        self._pending_user = None
        self._pending_wardrobes = []

    def get(self, model, key):
        if model is User:
            return self.users.get(key)
        return None

    def query(self, model):
        if model is User:
            return FakeQuery(self.users.values())
        if model is Wardrobe:
            return FakeQuery(self.wardrobes.values())
        raise AssertionError(f"Unexpected query model: {model}")

    def add(self, instance):
        if isinstance(instance, User):
            self._pending_user = instance
        elif isinstance(instance, Wardrobe):
            self._pending_wardrobes.append(instance)
        else:
            raise AssertionError(f"Unexpected add model: {type(instance)}")

    def commit(self):
        if self._pending_user is not None:
            if self._pending_user.id is None:
                self._pending_user.id = uuid4()
            if self._pending_user.created_at is None:
                self._pending_user.created_at = datetime.now(timezone.utc)
            self.users[self._pending_user.id] = self._pending_user
            self._pending_user = None
        for wardrobe in self._pending_wardrobes:
            if wardrobe.id is None:
                wardrobe.id = uuid4()
            if wardrobe.created_at is None:
                wardrobe.created_at = datetime.now(timezone.utc)
            self.wardrobes[wardrobe.id] = wardrobe
        self._pending_wardrobes = []

    def refresh(self, instance):
        return instance


def make_user(email: str, password: str) -> User:
    user_id = uuid4()
    return User(
        id=user_id,
        uid=f"USR-{str(user_id)[:8].upper()}",
        username=email.split("@")[0],
        email=email,
        hashed_password=get_password_hash(password),
        user_type="CONSUMER",
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )


def _find_free_port() -> int:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class LiveServer:
    def __init__(self, application):
        self._application = application
        self.port = _find_free_port()
        self._server = uvicorn.Server(
            uvicorn.Config(
                application,
                host="127.0.0.1",
                port=self.port,
                log_level="warning",
            )
        )
        self._thread = threading.Thread(target=self._server.run, daemon=True)

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self) -> None:
        self._thread.start()
        for _ in range(50):
            if self._server.started:
                return
            time.sleep(0.1)
        raise RuntimeError("Timed out waiting for test server to start")

    def stop(self) -> None:
        self._server.should_exit = True
        self._thread.join(timeout=5)
        if self._thread.is_alive():
            raise RuntimeError("Timed out waiting for test server to stop")


class R1IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = LiveServer(app)
        cls.server.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        app.dependency_overrides.clear()

    def tearDown(self):
        app.dependency_overrides.clear()

    def request(self, method: str, path: str, **kwargs) -> httpx.Response:
        with httpx.Client(base_url=self.server.base_url, timeout=5.0) as client:
            return client.request(method, path, **kwargs)

    def test_login_endpoint_returns_token_over_http(self):
        user = make_user("owner@example.com", "secret123")
        fake_db = FakeSession([user])
        app.dependency_overrides[get_db] = lambda: fake_db

        response = self.request(
            "POST",
            "/api/v1/auth/login",
            json={"email": "owner@example.com", "password": "secret123"},
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["data"]["user"]["email"], "owner@example.com")
        self.assertTrue(payload["data"]["token"])

    def test_register_endpoint_returns_token_over_http(self):
        fake_db = FakeSession([])
        app.dependency_overrides[get_db] = lambda: fake_db

        response = self.request(
            "POST",
            "/api/v1/auth/register",
            json={
                "username": "newuser",
                "email": "newuser@example.com",
                "password": "secret123",
            },
        )

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["data"]["user"]["username"], "newuser")
        self.assertEqual(payload["data"]["user"]["email"], "newuser@example.com")
        self.assertEqual(payload["data"]["user"]["type"], "CONSUMER")
        self.assertTrue(payload["data"]["token"])

    def test_register_endpoint_rejects_duplicate_email_over_http(self):
        user = make_user("owner@example.com", "secret123")
        fake_db = FakeSession([user])
        app.dependency_overrides[get_db] = lambda: fake_db

        response = self.request(
            "POST",
            "/api/v1/auth/register",
            json={
                "username": "anotheruser",
                "email": "owner@example.com",
                "password": "secret123",
            },
        )

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "Email already registered")

    def test_protected_route_rejects_missing_bearer_header(self):
        app.dependency_overrides[get_db] = lambda: FakeSession([])

        response = self.request("GET", "/api/v1/wardrobes")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "Could not validate credentials")

    def test_protected_route_rejects_invalid_bearer_token(self):
        user = make_user("owner@example.com", "secret123")
        app.dependency_overrides[get_db] = lambda: FakeSession([user])

        response = self.request(
            "GET",
            "/api/v1/wardrobes",
            headers={"Authorization": "Bearer definitely-not-a-jwt"},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "Could not validate credentials")

    def test_protected_route_accepts_valid_bearer_token(self):
        user = make_user("owner@example.com", "secret123")
        fake_db = FakeSession([user])
        app.dependency_overrides[get_db] = lambda: fake_db
        captured = {}

        def fake_list_wardrobes(session, user_id):
            captured["session"] = session
            captured["user_id"] = user_id
            return []

        token = create_access_token(str(user.id))

        with patch(
            "app.api.v1.wardrobe.crud_wardrobe.list_wardrobes",
            side_effect=fake_list_wardrobes,
        ):
            response = self.request(
                "GET",
                "/api/v1/wardrobes",
                headers={"Authorization": f"Bearer {token}"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"items": []})
        self.assertIs(captured["session"], fake_db)
        self.assertEqual(captured["user_id"], user.id)

    def test_openapi_declares_http_bearer_scheme(self):
        response = self.request("GET", "/api/v1/openapi.json")

        self.assertEqual(response.status_code, 200)
        security_schemes = response.json()["components"]["securitySchemes"]
        self.assertEqual(
            security_schemes["HTTPBearer"],
            {"type": "http", "scheme": "bearer"},
        )


if __name__ == "__main__":
    unittest.main()
