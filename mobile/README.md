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
- Nagrody zapisują się lokalnie. Nie są zabezpieczonym systemem rankingowym;
  produkcyjne nagrody wymagają kont i weryfikacji po stronie serwera.
- Z punktu wybierz **Zaplanuj trasę**, następnie pieszo, rower, komunikację,
  samochód albo profil dla wózka. Bez GPS początek to jawnie oznaczony podgląd
  z Dworca Głównego. Wybrana trasa pojawia się na mapie.
- Przy aktywnej lokalizacji trasa odświeża się po zejściu z niej i okresowo.
  Planowanie wymaga uruchomionego backendu (opis w `../backend/README.md`).
  Inny adres: `--dart-define=API_BASE_URL=http://localhost:8000`.

Ślad spaceru pozostaje w pamięci aplikacji. Przy planowaniu trasy aplikacja
przekazuje początek i cel do backendu, a backend do routera Valhalla/OSM.
Backend nie zapisuje historii lokalizacji. Publiczne dane Krakowa dostarczają
infrastruktury rowerowej, nawierzchni, prac drogowych i rozkładów ZTP.
Dostępność dla wózka nie jest gwarantowana: brak pełnego miejskiego wykazu
barier. Dane prac drogowych nie są danymi o aktualnych korkach.
Dostawca kafelków OpenStreetMap otrzymuje żądania dla oglądanego obszaru.
Sesja działa podczas otwarcia aplikacji; nie jest to śledzenie w tle.

## Weryfikacja

```sh
flutter analyze
flutter test
```

Testy obejmują aktualizacje GPS, filtrowanie niedokładnych odczytów, uprawnienia,
zatrzymanie demo, nagrody, czas między obrotami, rozdzielenie demo/GPS,
obsługę błędów planowania i układ na telefonie.

Repozytorium zawiera obecnie komplet platformy web. Przed uruchomieniem wersji
Android/iOS należy uzupełnić projekty natywne oraz deklaracje uprawnień lokalizacji.
