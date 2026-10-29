# SnapBack

Aplikacja macOS działająca w pasku menu. Przełącza **zwykłe okna** (niezmaksymalizowane) gestem 3 lub 4 palców, w stałej, przestrzennej kolejności od lewej do prawej, tak jakby każde okno było osobnym pulpitem. Dodatkowo zapamiętuje układ okien osobno dla każdej konfiguracji monitorów i przywraca go po podłączeniu lub odłączeniu ekranu.

- Swift, AppKit (pasek menu, nakładki) + SwiftUI (ustawienia, onboarding)
- macOS 13 Ventura lub nowszy (CI: macOS 15.7, Xcode 16.4)
- Bez ikony w Docku (`LSUIElement`), bez sandboxa, dystrybucja poza App Store

## Budowanie

Wymagania: Xcode 15+ oraz [XcodeGen](https://github.com/yonaskolb/XcodeGen). Projekt `.xcodeproj` jest generowany z pliku `project.yml` i nie trafia do repozytorium.

```bash
brew install xcodegen
```

```bash
make build     # Debug → build/Build/Products/Debug/SnapBack.app
```

```bash
make test      # testy jednostkowe logiki (detektor gestu, kolejność okien, dopasowanie układu)
```

```bash
make probe     # prototyp: loguje palce i swipe'y w Terminalu (FINGERS=4 dla 4 palców)
```

```bash
make install   # Release → /Applications/SnapBack.app i uruchomienie
```

Możesz też uruchomić `xcodegen generate` i otworzyć `SnapBack.xcodeproj` w Xcode (schematy `SnapBack` i `SwipeProbe`).

Każdy push buduje projekt na GitHub Actions (`.github/workflows/build.yml`): prototyp, testy, build Release oraz sprawdzenie, czy symbole MultitouchSupport ładują się na danej wersji macOS. Paczki `SnapBack.zip` i `SwipeProbe` są dostępne jako artefakt każdego przebiegu. Są podpisane ad hoc, więc po pobraniu trzeba zdjąć kwarantannę:

```bash
xattr -dr com.apple.quarantine SnapBack.app
```

## Uprawnienia

| Uprawnienie | Po co | Wymagane |
|---|---|---|
| **Dostępność** (Prywatność i ochrona → Dostępność) | lista okien, podnoszenie i fokus, ustawianie pozycji i rozmiaru | tak |
| **Monitorowanie wprowadzania** | MultitouchSupport zwykle go nie potrzebuje; nadaj tylko, jeśli test gestu nic nie wykrywa | nie |

Przy pierwszym uruchomieniu (oraz zawsze, gdy brakuje uprawnienia Dostępności) otwiera się okno konfiguracji. Prowadzi ono do właściwych paneli Ustawień systemowych, sprawdza konflikt z gestem systemowym i ma pole do testowania gestu na żywo. Później otworzysz je z menu: *Uprawnienia i konfiguracja gestu…*

> **Uwaga przy developmencie:** build podpisany ad hoc dostaje nowy podpis przy każdej kompilacji, a macOS może wtedy „zapomnieć” zgodę na Dostępność (wpis na liście jest, ale nie działa). Rozwiązania: usuń SnapBack z listy i dodaj ponownie, uruchom `tccutil reset Accessibility com.snapback.SnapBack`, albo podpisuj stałym certyfikatem (Apple Development lub self-signed).

### Konflikt z gestem systemowym

SnapBack odczytuje surowe dotknięcia **obok** systemu i nie potrafi zablokować systemowego gestu. Jeśli systemowe „Przesuwanie między aplikacjami pełnoekranowymi” używa tej samej liczby palców, zadziałają oba gesty naraz. Dlatego:

- przy pierwszym uruchomieniu SnapBack wybiera 3 palce, jeśli poziomy gest 3 palcami jest w systemie wolny, a w przeciwnym razie 4 palce,
- ustawienia i onboarding pokazują ostrzeżenie oraz instrukcję: *Ustawienia systemowe → Gładzik → Więcej gestów → Przesuwanie między aplikacjami pełnoekranowymi → czterema palcami* (dzięki temu 3 palce zostają dla SnapBack),
- wykrywane jest też „Przeciąganie trzema palcami” (Dostępność), które koliduje z każdym gestem 3 palcami.

## Jak to działa (architektura)

```
SnapBack/
├─ App/          main.swift, AppDelegate: łączy moduły
├─ Gesture/
│  ├─ MultitouchBridge     dlopen/dlsym do prywatnego MultitouchSupport.framework
│  ├─ SwipeDetector        czysta maszyna stanów: N palców → swipe w lewo/prawo (próg, kierunek, debounce)
│  ├─ GestureMonitor       wątek multitouch → zdarzenia na main thread, restart po wybudzeniu
│  └─ TrackpadPreferences  odczyt ustawień gestów systemowych (wykrywanie konfliktu)
├─ Windows/
│  ├─ AXHelpers            typowane wrappery Accessibility + prywatne _AXUIElementGetWindow
│  ├─ WindowTracker        okna z AX ∩ CGWindowList (tylko widoczne, standardowe, bieżący Space)
│  ├─ WindowOrdering       stała kolejność przestrzenna (czysta logika, testowana)
│  ├─ WindowSwitcher       swipe → następne/poprzednie okno → fokus, podświetlenie, haptyka
│  └─ HighlightOverlay     animowana ramka wokół okna docelowego
├─ Layout/
│  ├─ DisplayConfiguration odcisk konfiguracji: vendor/model/serial, rozdzielczość, ułożenie
│  ├─ DisplayConfigObserver CGDisplayRegisterReconfigurationCallback + didChangeScreenParameters
│  ├─ LayoutStore          JSON w ~/Library/Application Support/SnapBack/layouts.json + LayoutMatcher
│  └─ LayoutManager        zapisy (zdarzeniowe) i przywracanie po zmianie monitorów
├─ UI/           MenuBarController, SettingsView, OnboardingView, WindowPresenter
└─ Settings/     AppSettings (UserDefaults), Permissions, LoginItem (SMAppService)
SwipeProbe/      prototyp CLI z etapu (a)
SnapBackTests/   testy logiki (bez uruchamiania aplikacji)
```

### Kolejność przestrzenna

1. Ekrany od lewej do prawej (a przy równym X od góry do dołu), według globalnego układu z Ustawień → Wyświetlacze. Okno należy do ekranu, na którym ma największą część powierzchni.
2. Na danym ekranie okna są sortowane według lewej krawędzi. Okna, których lewe krawędzie różnią się o ≤ 12 pt, tworzą jedną „kolumnę”.
3. W obrębie kolumny decyduje kolejność **pierwszego zauważenia** okna. Przy starcie SnapBack nadaje ją według z-order (najwyżej leżące okno jest pierwsze), a nowe okna trafiają na koniec swojej kolumny.

Dlaczego w punkcie 3 nie ma bieżącego z-order: każde przełączenie zmienia z-order. Dwa okna leżące jedno na drugim zamieniałyby się wtedy miejscami po każdym geście i kolejność przestałaby być przewidywalna. Kolejność zmienia się tylko wtedy, gdy przesuniesz okno.

Kierunek domyślny działa jak Spaces: palce w lewo przenoszą do okna po prawej. Można to odwrócić w ustawieniach. Na końcu listy gest się zatrzymuje i daje delikatny sygnał haptyczny; zawijanie (z ostatniego okna na pierwsze) można włączyć.

### Pamięć układu

- **Klucz konfiguracji** to posortowana lista ekranów: `vendor-model-serial@pikseleXpiksele[x,y,szer.×wys.]`. Ten sam monitor ustawiony po drugiej stronie laptopa daje więc inny układ.
- **Zapis (snapshot)** następuje przy przełączeniu aplikacji (najwyżej raz na 5 s), po każdym gestowym przełączeniu, przed uśpieniem, przy wyjściu z aplikacji, tuż przed zmianą ekranów (flaga *begin configuration*) oraz z zegara co 60 s jako zabezpieczenie. Aplikacje, które nie są uruchomione, zachowują swoje wpisy.
- **Przywracanie:** po ustabilizowaniu się zmiany (1,5 s) okna wracają na swoje miejsca w dwóch przebiegach (po 0,3 s i po 3 s), bo macOS i niektóre aplikacje same przesuwają okna chwilę po podłączeniu monitora. Na czas zmiany zapisy są wstrzymane, żeby tymczasowe „przetasowanie” nie nadpisało zapamiętanego układu.
- **Dopasowanie okien** (`LayoutMatcher`): w obrębie aplikacji najpierw po tytule, potem po indeksie okna w aplikacji, na końcu pozostałe wpisy po kolei.

### Zużycie CPU

Nic nie jest odpytywane w pętli. Callback MultitouchSupport jest wywoływany tylko wtedy, gdy palce dotykają gładzika, a obsługa jednej ramki to kilka dodawań. Lista okien jest budowana na żądanie: przy geście, przy otwarciu menu i przy zapisie układu, co kosztuje kilka ms zapytań Accessibility. Jedyny zegar (zapis co 60 s, tolerancja 20 s) pozwala systemowi łączyć wybudzenia z innymi timerami.

## Testowanie ręczne

**Etap (a), gest:** uruchom `make probe` i połóż 3 palce na gładziku. Powinna pojawić się linia `fingers: 3`, a po przesunięciu `>>> SWIPE LEFT/RIGHT`. Sprawdź też, że 2 i 4 palce oraz ruch pionowy nie wywołują swipe'a. Jeśli nic się nie loguje, nadaj Terminalowi „Monitorowanie wprowadzania” i spróbuj ponownie.

**Etap (b), przełączanie:** ułóż 3 okna obok siebie (np. Safari po lewej, Notatki pośrodku, Terminal po prawej). Gest 3 palcami w lewo powinien przenosić fokus Safari → Notatki → Terminal, a na końcu dawać lekki „puk” haptyczny. Gest w prawo działa odwrotnie. Powtórz kilka razy: kolejność ma się nie zmieniać. Dwa okna tego samego programu (np. dwa okna Finder) też powinny się przełączać.

**Etap (c), menu bar:** ikona w pasku menu pokazuje `2/3`. Menu wyświetla okna w kolejności przestrzennej, a aktywne okno jest zaznaczone. Kliknięcie (albo klawisz 1–9 przy otwartym menu) aktywuje okno. W *Wykluczone aplikacje* zaznacz np. Terminal: zniknie z listy i z przełączania. Wyłącz *Przełączanie gestem*: ikona zmieni się, a gest przestanie działać.

**Etap (d), układ:** przy podłączonym monitorze rozmieść okna i wybierz *Zapisz układ teraz*. Odłącz monitor (okna przeskoczą na laptopa), ułóż je dowolnie na laptopie, a potem podłącz monitor ponownie. Po ok. 2 s okna powinny wrócić na zapamiętane miejsca. Zapisane dane są w `~/Library/Application Support/SnapBack/layouts.json`. Logi zobaczysz w Console.app (filtr: `subsystem:com.snapback.SnapBack`) albo poleceniem:

```bash
log stream --predicate 'subsystem == "com.snapback.SnapBack"' --level debug
```

**Etap (e), ustawienia:** *Ustawienia…* (⌘, w menu). Zmień liczbę palców, a pole „Test” pokaże wykryty gest na żywo. Sprawdź suwak czułości, kierunek, zawijanie, podświetlenie i uruchamianie przy logowaniu (działa najlepiej z `/Applications`).

**CPU:** w Monitorze aktywności SnapBack bez dotykania gładzika powinien pokazywać ~0,0% CPU.

## Znane ograniczenia

- **Prywatne API.** MultitouchSupport (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, …) i `_AXUIElementGetWindow` są nieudokumentowane. Ładujemy je dynamicznie: jeśli Apple je usunie, aplikacja wystartuje, ale bez gestów (onboarding to pokaże). Z tego powodu aplikacja nie może trafić do App Store.
- **Nie można „pochłonąć” gestu systemowego.** Patrz *Konflikt z gestem systemowym*.
- **Tylko bieżący Space.** Przełączane i zapisywane są okna widoczne na aktualnym pulpicie. Okna na innych Spaces i zminimalizowane są pomijane (prywatne API SkyLight do Spaces są znacznie mniej stabilne).
- **Aktywacja na macOS 14+.** System ogranicza „kradzież” fokusu przez aplikacje w tle. SnapBack używa ścieżki Accessibility (`AXMain` + `AXFrontmost` + `AXRaise`), która działa niezależnie od tego ograniczenia, a `NSRunningApplication.activate()` jest tylko awaryjnym zapasem.
- **Dopasowanie okien po restarcie aplikacji** odbywa się według tytułu lub indeksu. Okna o identycznych, zmiennych tytułach mogą zamienić się miejscami.
- **Urządzenia multitouch** są wyliczane przy starcie i po wybudzeniu. Magic Trackpad podłączony w trakcie działania zacznie działać po ponownym uruchomieniu SnapBack lub po uśpieniu i wybudzeniu.
- **Pełny ekran:** aplikacja pełnoekranowa jest jedynym oknem na swoim Space, więc tam gest SnapBack nie ma między czym przełączać (tak ma być, to robi gest systemowy).

## Dalsze kroki

- Podpis Developer ID + Hardened Runtime + notaryzacja (`xcrun notarytool`). Hardened Runtime nie blokuje `dlopen` frameworków systemowych.
- Ikona aplikacji, lokalizacja EN.
- Opcjonalnie: przełączanie także między Spaces po dojściu do krawędzi listy.
