from datetime import datetime
from sqlalchemy import Boolean, CheckConstraint, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint, func
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
    adventure_key: Mapped[str | None] = mapped_column(String(60), unique=True)
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
    email: Mapped[str | None] = mapped_column(String(120), unique=True, nullable=True)
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


class GameSession(Base):
    __tablename__ = 'game_sessions'
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Skin(Base):
    __tablename__ = 'skins'
    __table_args__ = (CheckConstraint('cost_points >= 0', name='ck_skin_cost'),)
    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    cost_points: Mapped[int] = mapped_column(Integer)


class GameProfile(Base):
    __tablename__ = 'game_profiles'
    __table_args__ = (UniqueConstraint('user_id', 'mode', name='uq_game_profile_user_mode'),
                     CheckConstraint("mode IN ('gps', 'demo')", name='ck_game_profile_mode'),
                     CheckConstraint('points >= 0', name='ck_game_profile_points'))
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'))
    mode: Mapped[str] = mapped_column(String(8))
    points: Mapped[int] = mapped_column(Integer, default=0, server_default='0')
    selected_skin: Mapped[str | None] = mapped_column(ForeignKey('skins.id'), nullable=True)


class SkinOwnership(Base):
    __tablename__ = 'skin_ownerships'
    __table_args__ = (UniqueConstraint('profile_id', 'skin_id', name='uq_skin_ownership'),)
    id: Mapped[int] = mapped_column(primary_key=True)
    profile_id: Mapped[int] = mapped_column(ForeignKey('game_profiles.id'))
    skin_id: Mapped[str] = mapped_column(ForeignKey('skins.id'))
    purchased_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SpinClaim(Base):
    __tablename__ = 'spin_claims'
    profile_id: Mapped[int] = mapped_column(ForeignKey('game_profiles.id'), primary_key=True)
    place_id: Mapped[int] = mapped_column(ForeignKey('places.id'), primary_key=True)
    last_claim_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class GameOperation(Base):
    __tablename__ = 'game_operations'
    __table_args__ = (UniqueConstraint('profile_id', 'request_id', name='uq_game_operation_request'),)
    id: Mapped[int] = mapped_column(primary_key=True)
    profile_id: Mapped[int] = mapped_column(ForeignKey('game_profiles.id'))
    request_id: Mapped[str] = mapped_column(String(36))
    payload_hash: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(String(16))
    points_delta: Mapped[int] = mapped_column(Integer)
    place_id: Mapped[int | None] = mapped_column(ForeignKey('places.id'), nullable=True)
    skin_id: Mapped[str | None] = mapped_column(ForeignKey('skins.id'), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
