# Lajkonik GO

Frontend Flutter z mapą OpenStreetMap, pozycją GPS na żywo i śladem spaceru.

## Uruchomienie

```sh
flutter pub get
flutter run -d chrome --web-port 5174
```

Wybierz **Włącz lokalizację** i zezwól przeglądarce na odczyt lokalizacji.
Wersja web wymaga HTTPS lub localhost. Dokładność zależy od urządzenia;
komputer może zwracać przybliżoną pozycję zamiast GPS.

- Mapa płynnie podąża za kolejnymi odczytami pozycji.
- Ręczne przesunięcie mapy wyłącza podążanie; celownik je przywraca.
- Dziennik pokazuje czas, dystans oraz ostatnie 20 punktów trasy.
- Zakończenie spaceru zatrzymuje odczyt, zachowując trasę do końca sesji.
- Każdy nowy spacer rozpoczyna nową trasę. Odświeżenie usuwa dane sesji.
- Odczyty o dokładności gorszej niż 100 m nie zwiększają dystansu.
- **Spacer demo** symuluje przejście po Krakowie. Punkty i nagrody demo są
  oddzielone od nagród zdobytych z GPS.
- Punkt przygody można obrócić gestem lub przyciskiem, aby dostać 50 punktów.
  Pozycja musi być świeża (30 s), mieć dokładność do 25 m, a odległość wraz
  z marginesem dokładności mieścić się w 45 m. Kolejny obrót po 5 minutach.
- Nagrody, historia obrotów, saldo oraz zakup i wybór wyglądu zapisują się
  w PostgreSQL przez backend. Serwer sprawdza lokalizację, czas między obrotami
  i koszt; żądania mają identyfikatory zapobiegające podwójnemu naliczeniu.
- W **Kolekcji** można za 50 punktów odblokować na stałe znacznik Lajkonika.
  Zakup od razu wybiera nowy wygląd. Powrót do zwykłego znacznika i ponowny
  wybór Lajkonika są darmowe. Wyglądy demo i GPS są oddzielne; konto na serwerze
  zachowuje zakup, wybór oraz pozostałe punkty po odświeżeniu.
- Automatycznie tworzymy konto gościa. W przeglądarce pozostaje tylko klucz
  sesji, osobny dla adresu API. Usunięcie danych przeglądarki oznacza utratę
  dostępu do tego konta, nie usunięcie jego danych w bazie. Na tym etapie
  nie ma logowania na innych urządzeniach ani odzyskiwania konta.
- Kliknięcie salda lub powrót do aplikacji odświeża stan z backendu.
  Brak połączenia nie przyznaje lokalnych punktów ani wyglądów.
- Dawny zapis `lajkonik.rewards.v1` pozostaje nietknięty jako dane prototypu,
  ale nie jest używany ani automatycznie importowany do salda serwerowego.
- Z punktu wybierz **Zaplanuj trasę**, następnie pieszo, rower, komunikację,
  samochód albo profil dla wózka. Bez GPS początek to jawnie oznaczony podgląd
  z Dworca Głównego. Wybrana trasa pojawia się na mapie.
- Przy aktywnej lokalizacji trasa odświeża się po zejściu z niej i okresowo.
  Planowanie wymaga uruchomionego backendu (opis w `../backend/README.md`).
  Inny adres: `--dart-define=API_BASE_URL=http://localhost:8000`.

Ślad spaceru pozostaje w pamięci aplikacji. Przy planowaniu trasy aplikacja
przekazuje początek i cel do backendu, a backend do routera Valhalla/OSM.
Backend nie zapisuje śladu ani współrzędnych odczytów GPS. Dla nagrody sprawdza
przesłaną pozycję i zapisuje odwiedzony punkt oraz czas obrotu.
Publiczne dane Krakowa dostarczają
infrastruktury rowerowej, nawierzchni, prac drogowych i rozkładów ZTP.
Dostępność dla wózka nie jest gwarantowana: brak pełnego miejskiego wykazu
barier. Dane prac drogowych nie są danymi o aktualnych korkach.
Dostawca kafelków OpenStreetMap otrzymuje żądania dla oglądanego obszaru.
Sesja działa podczas otwarcia aplikacji; nie jest to śledzenie w tle.

## Weryfikacja

Mapa i kolekcja pobierają katalog punktów z `/game/state`. Katalog zawiera 20
miejsc w Krakowie, także na Kazimierzu, w Podgórzu i Nowej Hucie. Przycisk
„Pokaż wszystkie punkty” dopasowuje widok do całej listy; „Podążaj za mną”
przywraca śledzenie pozycji. Nowe wpisy w backendzie pojawiają się po odświeżeniu
stanu konta, bez dopisywania znaczników w aplikacji.

```sh
flutter analyze
flutter test
```

Pełny test z uruchomionym backendem i bazą (tworzy osobne konto gościa z nagrodą
demo, nie modyfikuje kont użytkowników):

```sh
flutter test --dart-define=RUN_LIVE_GAME_TEST=true test/live_game_test.dart
```

Testy obejmują aktualizacje GPS, filtrowanie niedokładnych odczytów, uprawnienia,
zatrzymanie demo, nagrody, czas między obrotami, rozdzielenie demo/GPS,
obsługę błędów planowania i układ na telefonie.

Repozytorium zawiera obecnie komplet platformy web. Przed uruchomieniem wersji
Android/iOS należy uzupełnić projekty natywne oraz deklaracje uprawnień lokalizacji.
