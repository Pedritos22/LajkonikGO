"""Expand the curated Krakow adventure catalog to twenty places."""
from alembic import op
import sqlalchemy as sa

revision = 'c291bd804ef6'
down_revision = 'ab7409c82e11'
branch_labels = depends_on = None

# Curated waypoints, not an import of verified municipal accessibility data.
POINTS = [
    ('bazylika-mariacka', 'Bazylika Mariacka', 'Hejnał i gotyckie wieże przy Rynku', 'culture', 50.06165, 19.93920),
    ('barbakan', 'Barbakan', 'Okrągła forteca na skraju Plant', 'monument', 50.06555, 19.94195),
    ('collegium-maius', 'Collegium Maius', 'Najstarsze kolegium Uniwersytetu Jagiellońskiego', 'culture', 50.06160, 19.93365),
    ('teatr-slowackiego', 'Teatr Słowackiego', 'Teatralny Kraków przy placu Świętego Ducha', 'culture', 50.06404, 19.94312),
    ('smok-wawelski', 'Smok Wawelski', 'Spotkanie ze smokiem nad Wisłą', 'monument', 50.05305, 19.93499),
    ('plac-nowy', 'Plac Nowy', 'Kazimierz wokół słynnego Okrąglaka', 'square', 50.05171, 19.94467),
    ('stara-synagoga', 'Stara Synagoga', 'Historia Kazimierza przy ulicy Szerokiej', 'culture', 50.05120, 19.94896),
    ('kladka-bernatka', 'Kładka Bernatka', 'Spacer między Kazimierzem a Podgórzem', 'bridge', 50.04697, 19.94737),
    ('rynek-podgorski', 'Rynek Podgórski', 'Podgórze u stóp kościoła św. Józefa', 'square', 50.04456, 19.94962),
    ('plac-bohaterow-getta', 'Plac Bohaterów Getta', 'Miejsce pamięci z pomnikiem krzeseł', 'square', 50.04687, 19.95433),
    ('cricoteka', 'Cricoteka', 'Sztuka Tadeusza Kantora nad Wisłą', 'culture', 50.04748, 19.95286),
    ('manggha', 'Manggha', 'Japońska sztuka z widokiem na Wawel', 'culture', 50.05115, 19.93185),
    ('park-jordana', 'Park Jordana', 'Zielona przerwa przy parkowych alejkach', 'nature', 50.06400, 19.91390),
    ('blonia', 'Błonia', 'Otwarta przestrzeń przy alei Focha', 'nature', 50.05860, 19.91350),
    ('kopiec-krakusa', 'Kopiec Krakusa', 'Panorama miasta z legendarnego kopca', 'nature', 50.03810, 19.95848),
    ('plac-centralny', 'Plac Centralny', 'Początek odkrywania Nowej Huty', 'square', 50.07205, 20.03785),
]


def upgrade():
    query = sa.text("""
        INSERT INTO places (adventure_key, city_id, name, description, category,
                            latitude, longitude, radius_meters, points_reward, source)
        SELECT :key, min(id), :name, :description, :category, :lat, :lon, 45, 50, 'LajkonikGO'
        FROM cities WHERE name IN ('Kraków', 'Krakow')
        ON CONFLICT (adventure_key) DO NOTHING
    """)
    for key, name, description, category, lat, lon in POINTS:
        op.execute(query.bindparams(key=key, name=name, description=description,
                                    category=category, lat=lat, lon=lon))


def downgrade():
    # Deactivate the catalog entries but preserve visits, claims and point ledgers.
    query = sa.text("UPDATE places SET adventure_key = NULL WHERE adventure_key = :key AND source = 'LajkonikGO'")
    for key, *_ in POINTS:
        op.execute(query.bindparams(key=key))
