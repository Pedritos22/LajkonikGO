from datetime import datetime
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class ConfirmationStatus:
    UNCONFIRMED = "unconfirmed"
    VERIFIED = "verified"
    REJECTED = "rejected"


class RewardStatus:
    ACTIVE = "active"
    REDEEMED = "redeemed"
    EXPIRED = "expired"


# 1. CITIES
class City(Base):
    __tablename__ = "cities"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)


# 2. PLACES
class Place(Base):
    __tablename__ = "places"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    city_id: Mapped[int] = mapped_column(ForeignKey("cities.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(String(50), nullable=False)
    image_url: Mapped[str | None] = mapped_column(String, nullable=True)

    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    radius_meters: Mapped[float] = mapped_column(Float, default=50.0)
    points_reward: Mapped[int] = mapped_column(Integer, default=10)

    accessibility_wheelchair: Mapped[bool | None] = mapped_column(Boolean, nullable=True, default=None)
    accessibility_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str | None] = mapped_column(String(100), nullable=True)
    confirmation_status: Mapped[str] = mapped_column(String(50), default="unconfirmed")

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


# 3. USERS
class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    email: Mapped[str] = mapped_column(String(120), unique=True, nullable=False)
    points: Mapped[int] = mapped_column(Integer, default=0)
    pref: Mapped[dict | None] = mapped_column(JSONB, nullable=True)


# 4. VISITS
class Visit(Base):
    __tablename__ = "visits"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    place_id: Mapped[int] = mapped_column(ForeignKey("places.id"), nullable=False)
    points_earned: Mapped[int] = mapped_column(Integer, default=0)
    visited_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# 5. REWARDS
class Reward(Base):
    __tablename__ = "rewards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(150), nullable=False)
    cost_pts: Mapped[int] = mapped_column(Integer, nullable=False)
    partner_name: Mapped[str] = mapped_column(String(100), nullable=False)


# 6. USER_REWARDS
class UserReward(Base):
    __tablename__ = "user_rewards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    reward_id: Mapped[int] = mapped_column(ForeignKey("rewards.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="active")
    redeemed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)