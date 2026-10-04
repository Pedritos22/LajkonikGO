"""Server-owned points, skins, guest sessions and idempotent operations."""
from alembic import op
import sqlalchemy as sa

revision = 'ab7409c82e11'
down_revision = '59603852cabe'
branch_labels = depends_on = None


def upgrade():
    op.alter_column('users', 'email', existing_type=sa.String(120), nullable=True)
    op.add_column('places', sa.Column('adventure_key', sa.String(60), nullable=True))
    op.create_unique_constraint('uq_places_adventure_key', 'places', ['adventure_key'])
    op.create_table('game_sessions',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('token_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))
    op.create_index('ix_game_sessions_user_id', 'game_sessions', ['user_id'])
    op.create_table('skins',
        sa.Column('id', sa.String(40), primary_key=True),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('cost_points', sa.Integer(), nullable=False),
        sa.CheckConstraint('cost_points >= 0', name='ck_skin_cost'))
    op.create_table('game_profiles',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('mode', sa.String(8), nullable=False),
        sa.Column('points', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('selected_skin', sa.String(40), sa.ForeignKey('skins.id'), nullable=True),
        sa.UniqueConstraint('user_id', 'mode', name='uq_game_profile_user_mode'),
        sa.CheckConstraint("mode IN ('gps', 'demo')", name='ck_game_profile_mode'),
        sa.CheckConstraint('points >= 0', name='ck_game_profile_points'))
    op.create_table('skin_ownerships',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('profile_id', sa.Integer(), sa.ForeignKey('game_profiles.id'), nullable=False),
        sa.Column('skin_id', sa.String(40), sa.ForeignKey('skins.id'), nullable=False),
        sa.Column('purchased_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('profile_id', 'skin_id', name='uq_skin_ownership'))
    op.create_table('spin_claims',
        sa.Column('profile_id', sa.Integer(), sa.ForeignKey('game_profiles.id'), primary_key=True),
        sa.Column('place_id', sa.Integer(), sa.ForeignKey('places.id'), primary_key=True),
        sa.Column('last_claim_at', sa.DateTime(timezone=True), nullable=False))
    op.create_table('game_operations',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('profile_id', sa.Integer(), sa.ForeignKey('game_profiles.id'), nullable=False),
        sa.Column('request_id', sa.String(36), nullable=False),
        sa.Column('payload_hash', sa.String(64), nullable=False),
        sa.Column('kind', sa.String(16), nullable=False),
        sa.Column('points_delta', sa.Integer(), nullable=False),
        sa.Column('place_id', sa.Integer(), sa.ForeignKey('places.id'), nullable=True),
        sa.Column('skin_id', sa.String(40), sa.ForeignKey('skins.id'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('profile_id', 'request_id', name='uq_game_operation_request'))
    # Preserve balances of existing database users; local browser balances are not trusted.
    op.execute("INSERT INTO game_profiles (user_id, mode, points) SELECT id, 'gps', points FROM users")
    op.execute("INSERT INTO game_profiles (user_id, mode, points) SELECT id, 'demo', 0 FROM users")
    skins = sa.table('skins', sa.column('id', sa.String), sa.column('name', sa.String), sa.column('cost_points', sa.Integer))
    op.bulk_insert(skins, [dict(id='lajkonik', name='Lajkonik', cost_points=50)])
    op.execute("INSERT INTO cities (name, latitude, longitude) SELECT 'Kraków', 50.06143, 19.93658 WHERE NOT EXISTS (SELECT 1 FROM cities WHERE name IN ('Kraków', 'Krakow'))")
    places = [('sukiennice', 'Sukiennice', 50.06143, 19.93658),
              ('brama-florianska', 'Brama Floriańska', 50.0649, 19.9411),
              ('planty', 'Planty', 50.0620, 19.9410),
              ('wawel', 'Wawel', 50.0544, 19.9354)]
    for key, name, lat, lon in places:
        # These fixed, curated adventure points are distinct from other city POIs.
        op.execute(sa.text("INSERT INTO places (adventure_key, city_id, name, category, latitude, longitude, radius_meters, points_reward, source) SELECT :key, min(id), :name, 'adventure', :lat, :lon, 45, 50, 'LajkonikGO' FROM cities WHERE name IN ('Kraków', 'Krakow')").bindparams(key=key, name=name, lat=lat, lon=lon))


def downgrade():
    for table in ('game_operations', 'spin_claims', 'skin_ownerships', 'game_profiles', 'skins', 'game_sessions'):
        op.drop_table(table)
    # Keep seeded places and guest users; preserve visits and avoid deleting user data.
    op.drop_constraint('uq_places_adventure_key', 'places', type_='unique')
    op.drop_column('places', 'adventure_key')
    # email remains nullable because guest users do not have an email address.
