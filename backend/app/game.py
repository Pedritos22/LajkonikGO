"""Authoritative reward transactions. Precise location is checked, never stored."""
from datetime import datetime, timezone
import hashlib
import json
import secrets
from typing import Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.geo import meters
from app.models import GameOperation, GameProfile, GameSession, Place, Skin, SkinOwnership, SpinClaim, User, Visit

router = APIRouter(prefix='/game', tags=['game'])
bearer = HTTPBearer(auto_error=False)
COOLDOWN = 300


def user_id(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)):
    if not credentials or credentials.scheme.lower() != 'bearer':
        raise HTTPException(401, 'Brak sesji użytkownika.')
    digest = hashlib.sha256(credentials.credentials.encode()).hexdigest()
    session = db.scalar(select(GameSession).where(GameSession.token_hash == digest))
    if session is None:
        raise HTTPException(401, 'Sesja nie jest dostępna. Nie utworzono nowego konta, aby nie stracić Twoich punktów.')
    return session.user_id


def state(db, uid):
    profiles = {}
    for profile in db.scalars(select(GameProfile).where(GameProfile.user_id == uid).order_by(GameProfile.mode)):
        claims = db.execute(select(Place.adventure_key, SpinClaim.last_claim_at).join(SpinClaim, SpinClaim.place_id == Place.id).where(SpinClaim.profile_id == profile.id)).all()
        profiles[profile.mode] = dict(points=profile.points, selected_skin=profile.selected_skin,
            owned_skins=list(db.scalars(select(SkinOwnership.skin_id).where(SkinOwnership.profile_id == profile.id))),
            claims={key: date.isoformat() for key, date in claims})
    places = [dict(key=p.adventure_key, name=p.name, description=p.description, category=p.category,
                   latitude=p.latitude, longitude=p.longitude, radius_m=p.radius_meters, reward=p.points_reward)
              for p in db.scalars(select(Place).where(Place.adventure_key.is_not(None)).order_by(Place.id))]
    return dict(user_id=uid, profiles=profiles, places=places, server_time=datetime.now(timezone.utc).isoformat(),
                cooldown_s=COOLDOWN, skins=[dict(id=s.id, name=s.name, cost=s.cost_points) for s in db.scalars(select(Skin))])


@router.post('/sessions', status_code=201)
def create_session(db: Session = Depends(get_db)):
    token = secrets.token_urlsafe(32)
    user = User(username='guest_' + uuid4().hex, email=None, points=0)
    db.add(user)
    db.flush()
    db.add(GameSession(user_id=user.id, token_hash=hashlib.sha256(token.encode()).hexdigest()))
    db.add_all([GameProfile(user_id=user.id, mode=mode, points=0) for mode in ('gps', 'demo')])
    db.commit()
    return dict(token=token, state=state(db, user.id))


@router.get('/state')
def get_state(uid: int = Depends(user_id), db: Session = Depends(get_db)):
    return state(db, uid)


class Operation(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    request_id: UUID
    profile: Literal['gps', 'demo']


class Spin(Operation):
    place_key: str = Field(min_length=1, max_length=60)
    latitude: float = Field(ge=49.8, le=50.3)
    longitude: float = Field(ge=19.5, le=20.4)
    accuracy: float = Field(ge=0, le=25)
    recorded_at: datetime


class Purchase(Operation):
    skin_id: Literal['lajkonik']


class Selection(Operation):
    skin_id: Literal['lajkonik', 'default']


def locked_profile(db, uid, payload, kind):
    # Every state mutation locks the same row, so concurrent spins/purchases serialize.
    profile = db.scalar(select(GameProfile).where(GameProfile.user_id == uid, GameProfile.mode == payload.profile).with_for_update())
    if profile is None:
        raise HTTPException(404, 'Profil nagród nie istnieje.')
    digest = hashlib.sha256(json.dumps(dict(kind=kind, **payload.model_dump(mode='json')), sort_keys=True).encode()).hexdigest()
    prior = db.scalar(select(GameOperation).where(GameOperation.profile_id == profile.id, GameOperation.request_id == str(payload.request_id)))
    if prior and prior.payload_hash != digest:
        raise HTTPException(409, 'Identyfikator operacji został już użyty do innego żądania.')
    return profile, digest, prior


def finish(db, uid, profile, payload, digest, kind, delta=0, place_id=None, skin_id=None):
    db.add(GameOperation(profile_id=profile.id, request_id=str(payload.request_id), payload_hash=digest,
                         kind=kind, points_delta=delta, place_id=place_id, skin_id=skin_id))
    if profile.mode == 'gps':
        db.get(User, uid).points = profile.points
    db.commit()
    return dict(state=state(db, uid), points_delta=delta, replayed=False)


def replay(db, uid, operation):
    # Release the lock before reading the current authoritative state.
    delta = operation.points_delta
    db.commit()
    return dict(state=state(db, uid), points_delta=delta, replayed=True)


@router.post('/spins')
def spin(payload: Spin, uid: int = Depends(user_id), db: Session = Depends(get_db)):
    profile, digest, prior = locked_profile(db, uid, payload, 'spin')
    if prior:
        return replay(db, uid, prior)
    now = datetime.now(timezone.utc)
    if payload.recorded_at.tzinfo is None or not -5 <= (now - payload.recorded_at).total_seconds() <= 30:
        raise HTTPException(422, 'Odśwież pozycję GPS przed obrotem.')
    place = db.scalar(select(Place).where(Place.adventure_key == payload.place_key))
    if place is None:
        raise HTTPException(404, 'Punkt przygody nie istnieje.')
    if meters([payload.latitude, payload.longitude], [place.latitude, place.longitude]) + payload.accuracy > place.radius_meters:
        raise HTTPException(422, 'Podejdź bliżej punktu przygody.')
    claim = db.get(SpinClaim, (profile.id, place.id))
    if claim and (now - claim.last_claim_at).total_seconds() < COOLDOWN:
        raise HTTPException(409, 'Ten punkt można obrócić ponownie po 5 minutach.')
    if claim:
        claim.last_claim_at = now
    else:
        db.add(SpinClaim(profile_id=profile.id, place_id=place.id, last_claim_at=now))
    profile.points += place.points_reward
    if profile.mode == 'gps':
        db.add(Visit(user_id=uid, place_id=place.id, points_earned=place.points_reward, visited_at=now))
    return finish(db, uid, profile, payload, digest, 'spin', place.points_reward, place_id=place.id)


@router.post('/skins/purchase')
def purchase(payload: Purchase, uid: int = Depends(user_id), db: Session = Depends(get_db)):
    profile, digest, prior = locked_profile(db, uid, payload, 'purchase')
    if prior:
        return replay(db, uid, prior)
    skin = db.get(Skin, payload.skin_id)
    if skin is None:
        raise HTTPException(404, 'Wygląd nie istnieje.')
    owned = db.scalar(select(SkinOwnership).where(SkinOwnership.profile_id == profile.id, SkinOwnership.skin_id == skin.id))
    delta = 0
    if owned is None:
        if profile.points < skin.cost_points:
            raise HTTPException(409, 'Za mało punktów na ten wygląd.')
        delta = -skin.cost_points
        profile.points += delta
        db.add(SkinOwnership(profile_id=profile.id, skin_id=skin.id))
    profile.selected_skin = skin.id
    return finish(db, uid, profile, payload, digest, 'purchase', delta, skin_id=skin.id)


@router.post('/skins/select')
def select_skin(payload: Selection, uid: int = Depends(user_id), db: Session = Depends(get_db)):
    profile, digest, prior = locked_profile(db, uid, payload, 'select')
    if prior:
        return replay(db, uid, prior)
    if payload.skin_id != 'default' and not db.scalar(select(SkinOwnership.id).where(SkinOwnership.profile_id == profile.id, SkinOwnership.skin_id == payload.skin_id)):
        raise HTTPException(409, 'Najpierw odblokuj ten wygląd.')
    profile.selected_skin = None if payload.skin_id == 'default' else payload.skin_id
    return finish(db, uid, profile, payload, digest, 'select', skin_id=profile.selected_skin)
