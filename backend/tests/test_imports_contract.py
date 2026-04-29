import unittest
from datetime import datetime, timezone
from uuid import uuid4

from app.api.v1.imports import list_import_history
from app.models.card_pack_import import CardPackImport
from app.models.clothing_item import ClothingItem
from app.models.creator import CardPack, CreatorProfile
from app.models.user import User
from app.schemas.imports import ImportCardPackRequest


class FakeQuery:
    def __init__(self, items):
        self._items = list(items)
        self._criteria = []
        self._offset = 0
        self._limit = None

    def filter(self, *criteria):
        self._criteria.extend(criteria)
        return self

    def order_by(self, *args, **kwargs):
        return self

    def offset(self, value):
        self._offset = value
        return self

    def limit(self, value):
        self._limit = value
        return self

    def count(self):
        return len(self._filtered())

    def all(self):
        rows = self._filtered()[self._offset :]
        if self._limit is not None:
            rows = rows[: self._limit]
        return rows

    def _filtered(self):
        rows = self._items
        for criterion in self._criteria:
            left = getattr(criterion, "left", None)
            right = getattr(criterion, "right", None)
            key = getattr(left, "key", None)
            value = getattr(right, "value", None)
            if key is None:
                continue
            rows = [item for item in rows if getattr(item, key) == value]
        return rows


class FakeSession:
    def __init__(self, *, users, profiles, packs, imports, clothing_items):
        self.users = {user.id: user for user in users}
        self.profiles = {profile.user_id: profile for profile in profiles}
        self.packs = {pack.id: pack for pack in packs}
        self.imports = list(imports)
        self.clothing_items = list(clothing_items)

    def get(self, model, key):
        if model is User:
            return self.users.get(key)
        if model is CreatorProfile:
            return self.profiles.get(key)
        if model is CardPack:
            return self.packs.get(key)
        return None

    def query(self, model):
        if model is CardPackImport:
            return FakeQuery(self.imports)
        if model is ClothingItem:
            return FakeQuery(self.clothing_items)
        raise AssertionError(f"Unexpected query model: {model}")


class ImportContractTests(unittest.TestCase):
    def test_import_card_pack_request_accepts_snake_and_camel_case(self):
        pack_id = uuid4()

        snake = ImportCardPackRequest.model_validate({"card_pack_id": str(pack_id)})
        camel = ImportCardPackRequest.model_validate({"cardPackId": str(pack_id)})

        self.assertEqual(snake.card_pack_id, pack_id)
        self.assertEqual(camel.card_pack_id, pack_id)

    def test_list_import_history_returns_frontend_shape(self):
        user_id = uuid4()
        creator_id = uuid4()
        pack_id = uuid4()
        import_id = uuid4()
        imported_at = datetime.now(timezone.utc)
        db = FakeSession(
            users=[
                User(
                    id=creator_id,
                    uid="USR-CREATOR",
                    username="creator",
                    email="creator@example.com",
                    hashed_password="hashed",
                    user_type="CREATOR",
                )
            ],
            profiles=[
                CreatorProfile(
                    user_id=creator_id,
                    status="ACTIVE",
                    display_name="Creator Name",
                    social_links={},
                    is_verified=True,
                )
            ],
            packs=[
                CardPack(
                    id=pack_id,
                    creator_id=creator_id,
                    name="Capsule",
                    pack_type="CLOTHING_COLLECTION",
                    status="PUBLISHED",
                    import_count=1,
                )
            ],
            imports=[
                CardPackImport(
                    id=import_id,
                    user_id=user_id,
                    card_pack_id=pack_id,
                    imported_at=imported_at,
                )
            ],
            clothing_items=[
                ClothingItem(
                    id=uuid4(),
                    user_id=user_id,
                    source="IMPORTED",
                    imported_from_card_pack_id=pack_id,
                )
            ],
        )

        response = list_import_history(page=1, limit=20, db=db, user_id=user_id)

        self.assertTrue(response.success)
        self.assertEqual(response.data.pagination["total"], 1)
        self.assertEqual(len(response.data.imports), 1)
        item = response.data.imports[0]
        self.assertEqual(item.id, str(import_id))
        self.assertEqual(item.cardPackId, str(pack_id))
        self.assertEqual(item.cardPackName, "Capsule")
        self.assertEqual(item.creatorId, str(creator_id))
        self.assertEqual(item.creatorName, "Creator Name")
        self.assertEqual(item.itemCount, 1)
        self.assertEqual(item.importedAt, imported_at)


if __name__ == "__main__":
    unittest.main()
