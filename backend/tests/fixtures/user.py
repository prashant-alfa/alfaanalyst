import pytest
import uuid
from tests.utils.user_creds import main_user
from sqlalchemy import select
import asyncio


def _mark_user_verified(email: str) -> None:
    # The app currently requires verified users for JWT login in production config.
    # Tests create users via /api/auth/register, so we flip is_verified in the test DB.
    from app.dependencies import async_session_maker
    from app.models.user import User
    
    async def _do():
        async with async_session_maker() as session:
            user = (await session.execute(select(User).where(User.email == email))).scalar_one_or_none()
            if user is not None:
                user.is_verified = True
                await session.commit()

    # Use an explicit loop to avoid relying on any test runner loop state.
    loop = asyncio.new_event_loop()
    try:
        loop.run_until_complete(_do())
    finally:
        loop.close()

@pytest.fixture
def create_user(test_client):
    def _create_user(name=None, email=main_user["email"], password=main_user["password"]):
        # Generate unique name if not provided to avoid UNIQUE constraint failures
        if name is None:
            name = f"testuser_{uuid.uuid4().hex[:8]}"
        response = test_client.post("/api/auth/register", json={"name": name, "email": email, "password": password})
        assert response.status_code == 201, response.json()
        _mark_user_verified(email)
        return {"name": name, "email": email, "password": password}
    return _create_user
