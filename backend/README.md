# Publiczne dane Krakowa i planowanie tras

## Uruchomienie

```sh
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Na Linux/macOS użyj `.venv/bin/python`. Można też uruchomić backend przez
Compose z głównego katalogu projektu. Baza danych nie jest potrzebna do tras.

`GET /city-data` zwraca status źródeł, aktualne roboty, liczbę odcinków
rowerowych i alerty. `POST /routes` przyjmuje JSON:

```json
{"origin":{"latitude":50.0679,"longitude":19.9454},"destination":{"latitude":50.06143,"longitude":19.93658},"mode":"bike"}
```

Tryby: `walk`, `bike`, `transit`, `car`, `wheelchair`. Odpowiedź zawiera
geometrię `[latitude, longitude]`, dystans, czas, wskazówki, ostrzeżenia i źródła
z datą pobrania/aktualizacji. Błąd dostawcy zwraca błąd, a nie fikcyjną trasę.

## Źródła i zakres oceny

- [ZTP – dane otwarte](https://ztp.krakow.pl/dane-otwarte):
  [warstwa ciągów rowerowych](https://services-eu1.arcgis.com/svTzSt3AvH7sK6q9/arcgis/rest/services/Ciagi_rowerowe/FeatureServer/0).
  Rzeczywiste odcinki i pole `nawierzchnia`; pobieramy obszar wokół trasy.
  Pokrycie to przybliżenie próbek trasy co 25 m w odległości do 12 m od odcinka.
  Nie dowodzi ciągłości ani bezpieczeństwa przejazdu. Przy braku pełnych danych
  procent nie jest pokazywany.
- [ZDMK – zestawienie prac](https://zdmk.krakow.pl/zestawienie-prac-w-miescie/):
  publiczny KML mapy osadzonej na stronie miasta. Wybieramy wpisy aktywne według
  dat `od`/`do`; pomijamy wpisy bez jednoznacznych dat. Punkt blisko trasy
  wpływa na wybór spośród alternatyw routera, ale nie jest uznawany za pełny
  zasięg zamknięcia. Archiwalny serwis `kzdwk.home.pl` nie jest używany.
- [ZTP – GTFS i GTFS-RT](https://gtfs.ztp.krakow.pl/): autobusy MPK/Mobilis
  i tramwaje. Wyszukujemy podróż na teraz, do 6 godzin, maksymalnie 2 przesiadki.
  Sprawdzamy dzień kursowania, wyjątki kalendarza, opóźnienia i odwołania;
  uwzględniamy aktualne alerty. Dane RT starsze niż 10 minut są oznaczone jako
  nieaktualne i zastąpione planowym rozkładem. Dojścia sprawdza router pieszy.
- Valhalla/OpenStreetMap dostarcza sieć dróg i osobne profile, nie miejskie
  dane o korkach. Rower preferuje łagodniejsze podjazdy. Profil dla wózka ma
  limit nachylenia 6% i preferencje ograniczające schody, lecz zależy od
  kompletności mapy. Nawierzchnie miejskie wpływają na wybór alternatywy.

Nie znaleziono pełnego publicznego miejskiego feedu prędkości/zatorów ani
zweryfikowanego wykazu wszystkich krawężników, schodów i szerokości chodników.
Aplikacja pokazuje te braki. Czas samochodu jest szacunkowy bez bieżących
korków. Dostępność całej trasy i wejścia do celu pozostaje niepotwierdzona.
Nie korzystamy z komercyjnego API korków. W centrum samochód może wymagać
ostatniego odcinka pieszo; trasa nie jest pozwoleniem na wjazd ani gwarancją parkingu.

## Konfiguracja

- `ROUTING_BASE_URL`: domyślnie publiczna instancja Valhalla, do lokalnego
  prototypu; limitujemy żądania do ok. 1/s. Produkcja wymaga własnej instancji
  lub uzgodnionego dostawcy. Dane miejskie są buforowane 5 min, GTFS 1 godzinę.
- `FRONTEND_ORIGINS`: dozwolone originy wdrożonego frontendu, rozdzielone
  przecinkiem. Localhost jest dopuszczony automatycznie.
- `CITY_ACCESSIBILITY_URL`: opcjonalny przyszły, zweryfikowany miejski GeoJSON.
  Domyślnie pusty. FeatureCollection musi mieć `updated_at` w ISO 8601 z UTC
  lub strefą (do 24 h). Aktywne Point `[longitude, latitude]` mają properties:
  `active: true`, `barrier`: `steps`, `high_kerb`, `narrow_passage` lub `closed`,
  opcjonalnie `name` i `modes` (domyślnie `["wheelchair"]`). Znane bariery są
  zgłaszane routerowi do ominięcia i sprawdzane po wyznaczeniu trasy.

Historia GPS nie jest utrwalana. Router otrzymuje współrzędne początku/celu.
Nagrody frontendu są lokalne i wymagają osobnej weryfikacji w wersji produkcyjnej.

## Testy

```sh
.venv/Scripts/python -m unittest discover -s tests -v
```

Testy sprawdzają daty robót, ocenę nawierzchni, profile, przesiadki,
kalendarze i odrzucanie nieprawidłowych żądań.
