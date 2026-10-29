# BetterGlide

Aplikacja macOS działająca w pasku menu. Przełącza **zwykłe okna** (niezmaksymalizowane) gestem 3 lub 4 palców, w stałej, przestrzennej kolejności od lewej do prawej, tak jakby każde okno było osobnym pulpitem. Dodatkowo zapamiętuje układ okien osobno dla każdej konfiguracji monitorów i przywraca go po podłączeniu lub odłączeniu ekranu.

- Swift, AppKit (pasek menu, nakładki) + SwiftUI (ustawienia, onboarding, aktualizacje)
- Wygląd Liquid Glass na macOS 26+ (szklane panele i przyciski `glassEffect`, systemowe kontrolki z SDK 26); na macOS 14–15 materiały (`regularMaterial`)
- macOS 14 Sonoma lub nowszy, Apple Silicon i Intel (CI buduje na macOS 26 z Xcode 26)
- Bez ikony w Docku (`LSUIElement`), bez sandboxa, dystrybucja poza App Store

## Instalacja (DMG)

1. Pobierz **[BetterGlide.dmg](https://github.com/KubaCh7/Better_glide/releases/latest/download/BetterGlide.dmg)** (zawsze najnowszy build; lista wersji: [Releases](https://github.com/KubaCh7/Better_glide/releases)).
2. Otwórz plik i przeciągnij **BetterGlide** na skrót **Applications**.
3. Aplikacja nie jest jeszcze podpisana certyfikatem Developer ID ani notaryzowana, więc macOS zablokuje pierwsze uruchomienie. Zdejmij blokadę w Terminalu:

   ```bash
   xattr -dr com.apple.quarantine /Applications/BetterGlide.app
   ```

   Alternatywnie spróbuj ją otworzyć, a potem wybierz *Ustawienia systemowe → Prywatność i ochrona → Otwórz mimo to*.
4. Uruchom BetterGlide z Aplikacji. Ikona pojawi się w pasku menu (nie w Docku), a okno konfiguracji poprowadzi przez nadanie uprawnienia Dostępności.

### Aktualizacje w aplikacji

BetterGlide sam sprawdza aktualizacje: 15 s po uruchomieniu, a potem raz dziennie (jedno zapytanie do GitHub Releases). Możesz to wyłączyć w *Ustawienia → Aktualizacje*. Gdy pojawi się nowy build, otworzy się okno z listą zmian i przyciskiem **Zainstaluj i uruchom ponownie**. Ręcznie: menu w pasku → *Sprawdź aktualizacje…*

Instalacja przebiega tak:

1. Pobierany jest `BetterGlide.dmg` z najnowszego release'u.
2. Aplikacja ze środka jest sprawdzana: zgodny identyfikator i poprawny podpis.
3. Stara wersja jest podmieniana w tym samym miejscu (np. `/Applications`), a nowa uruchamia się sama. Jeśli kopiowanie się nie uda, wraca poprzednia wersja.
4. Plik pobrany przez aplikację nie dostaje flagi kwarantanny, więc `xattr` nie jest już potrzebne.

### Jednorazowo: stały podpis, żeby aktualizacje nie kasowały uprawnień

macOS przypisuje zgody na *Dostępność* i *Nagrywanie ekranu* do podpisu aplikacji. Buildy podpisane ad hoc mają za każdym razem inny podpis, więc **po każdej aktualizacji trzeba by nadawać uprawnienia od nowa**. Rozwiązanie bez płatnego konta Apple Developer to własny certyfikat. Na Macu, w katalogu repozytorium, uruchom:

```bash
scripts/create-signing-certificate.sh
```

Skrypt tworzy certyfikat w `~/BetterGlide-signing` i zapisuje go w GitHubie jako sekrety `SIGNING_CERT_P12` i `SIGNING_CERT_PASSWORD`. Jeśli masz zalogowane `gh`, robi to sam; jeśli nie, otwiera stronę sekretów i kopiuje wartość do schowka. Od następnego builda CI podpisuje aplikację tym certyfikatem. Po pierwszej instalacji takiego builda nadaj uprawnienia jeszcze raz (zmienia się podpis); kolejne aktualizacje już ich nie ruszą.

Bez sekretów wszystko działa, tylko po każdej aktualizacji trzeba ponownie włączyć BetterGlide w *Prywatność i ochrona → Dostępność* oraz *Nagrywanie ekranu* (albo uruchomić `tccutil reset Accessibility com.betterglide.BetterGlide`).

## Budowanie ze źródeł

Wymagania: Xcode 26+ (SDK z Liquid Glass) oraz [XcodeGen](https://github.com/yonaskolb/XcodeGen). Projekt `.xcodeproj` jest generowany z pliku `project.yml` i nie trafia do repozytorium.

```bash
brew install xcodegen
```

```bash
make build     # Debug → build/Build/Products/Debug/BetterGlide.app
```

```bash
make test      # testy jednostkowe logiki (detektor gestu, kolejność okien, dopasowanie układu)
```

```bash
make probe     # prototyp: loguje palce i swipe'y w Terminalu (FINGERS=4 dla 4 palców)
```

```bash
make install   # Release → /Applications/BetterGlide.app i uruchomienie
```

```bash
make dmg       # Release → build/BetterGlide.dmg
```

Możesz też uruchomić `xcodegen generate` i otworzyć `BetterGlide.xcodeproj` w Xcode (schematy `BetterGlide` i `SwipeProbe`).

Każdy push buduje projekt na GitHub Actions (`.github/workflows/build.yml`): prototyp, testy, uniwersalny build Release (Apple Silicon + Intel) oraz sprawdzenie, czy symbole MultitouchSupport ładują się na danej wersji macOS. Na końcu `BetterGlide.dmg` jest publikowany jako release `latest-build`, który zastępuje poprzedni. Dlatego link z sekcji *Instalacja* zawsze wskazuje najnowszą wersję.

## Uprawnienia

| Uprawnienie | Po co | Wymagane |
|---|---|---|
| **Dostępność** (Prywatność i ochrona → Dostępność) | lista okien, podnoszenie i fokus, ustawianie pozycji i rozmiaru | tak |
| **Nagrywanie ekranu** (Prywatność i ochrona → Nagrywanie ekranu) | animacja przesuwania: na czas gestu robiony jest zrzut ekranu, który przesuwa się pod palcami. Nic nie jest zapisywane. Po nadaniu trzeba uruchomić aplikację ponownie | tylko do animacji |
| **Monitorowanie wprowadzania** | MultitouchSupport zwykle go nie potrzebuje; nadaj tylko, jeśli test gestu nic nie wykrywa | nie |

Przy pierwszym uruchomieniu (oraz zawsze, gdy brakuje uprawnienia Dostępności) otwiera się okno konfiguracji. Prowadzi ono do właściwych paneli Ustawień systemowych, sprawdza konflikt z gestem systemowym i ma pole do testowania gestu na żywo. Później otworzysz je z menu: *Uprawnienia i konfiguracja gestu…*

> **Uwaga przy developmencie:** build podpisany ad hoc dostaje nowy podpis przy każdej kompilacji, a macOS może wtedy „zapomnieć” zgodę na Dostępność (wpis na liście jest, ale nie działa). Rozwiązania: usuń BetterGlide z listy i dodaj ponownie, uruchom `tccutil reset Accessibility com.betterglide.BetterGlide`, albo podpisuj stałym certyfikatem (Apple Development lub self-signed).

### Konflikt z gestem systemowym

BetterGlide odczytuje surowe dotknięcia **obok** systemu i nie potrafi zablokować systemowego gestu. Jeśli systemowe „Przesuwanie między aplikacjami pełnoekranowymi” używa tej samej liczby palców, zadziałają oba gesty naraz. Dlatego:

- przy pierwszym uruchomieniu BetterGlide wybiera 3 palce, jeśli poziomy gest 3 palcami jest w systemie wolny, a w przeciwnym razie 4 palce,
- ustawienia i onboarding pokazują ostrzeżenie oraz instrukcję: *Ustawienia systemowe → Gładzik → Więcej gestów → Przesuwanie między aplikacjami pełnoekranowymi → czterema palcami* (dzięki temu 3 palce zostają dla BetterGlide),
- wykrywane jest też „Przeciąganie trzema palcami” (Dostępność), które koliduje z każdym gestem 3 palcami.

## Jak to działa (architektura)

```
BetterGlide/
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
│  └─ WindowSwitcher       sąsiedzi aktywnego okna w kolejności przestrzennej, fokus
├─ Transition/
│  ├─ SlideTransitionController  przebieg gestu: śledzenie palców, decyzja dokończ/cofnij, haptyka na krawędzi
│  ├─ SlideOverlay         warstwy Core Animation przesuwające „strony” jak Spaces
│  ├─ ScreenSnapshotter    zrzuty ekranu i okna docelowego (ScreenCaptureKit)
│  ├─ DisplayGeometry      obszar ekranu bez paska menu i Docka
│  └─ SlideMath            próg, flick, gumowe odbicie (czysta logika, testowana)
├─ Layout/
│  ├─ DisplayConfiguration odcisk konfiguracji: vendor/model/serial, rozdzielczość, ułożenie
│  ├─ DisplayConfigObserver CGDisplayRegisterReconfigurationCallback + didChangeScreenParameters
│  ├─ LayoutStore          JSON w ~/Library/Application Support/BetterGlide/layouts.json + LayoutMatcher
│  └─ LayoutManager        zapisy (zdarzeniowe) i przywracanie po zmianie monitorów
├─ Update/       ReleaseInfo (GitHub API), UpdateController (sprawdzanie), UpdateInstaller (pobranie, podmiana, restart)
├─ UI/           MenuBarController, SettingsView, OnboardingView, UpdateView, Glass (Liquid Glass + fallback), WindowPresenter
├─ Resources/    Assets.xcassets z ikoną (generuje ją scripts/make-icon.py)
└─ Settings/     AppSettings (UserDefaults), Permissions, LoginItem (SMAppService)
SwipeProbe/      prototyp CLI z etapu (a)
BetterGlideTests/   testy logiki (bez uruchamiania aplikacji)
```

### Kolejność przestrzenna

1. Ekrany od lewej do prawej (a przy równym X od góry do dołu), według globalnego układu z Ustawień → Wyświetlacze. Okno należy do ekranu, na którym ma największą część powierzchni.
2. Na danym ekranie okna są sortowane według lewej krawędzi. Okna, których lewe krawędzie różnią się o ≤ 12 pt, tworzą jedną „kolumnę”.
3. W obrębie kolumny decyduje kolejność **pierwszego zauważenia** okna. Przy starcie BetterGlide nadaje ją według z-order (najwyżej leżące okno jest pierwsze), a nowe okna trafiają na koniec swojej kolumny.

Dlaczego w punkcie 3 nie ma bieżącego z-order: każde przełączenie zmienia z-order. Dwa okna leżące jedno na drugim zamieniałyby się wtedy miejscami po każdym geście i kolejność przestałaby być przewidywalna. Kolejność zmienia się tylko wtedy, gdy przesuniesz okno.

Kierunek domyślny działa jak Spaces: palce w lewo przenoszą do okna po prawej. Można to odwrócić w ustawieniach. Na końcu listy ekran odbija się sprężyście i daje delikatny sygnał haptyczny; zawijanie (z ostatniego okna na pierwsze) można włączyć.

### Animacja przesuwania (jak przy pulpitach)

macOS nie pozwala użyć systemowej animacji Spaces dla zwykłych okien, więc BetterGlide ją odtwarza:

1. Gdy rozpoznany zostanie poziomy ruch palców, BetterGlide robi zrzut obszaru ekranu (bez paska menu i Docka, które zostają na miejscu) oraz obrazy sąsiednich okien. Zajmuje to kilkadziesiąt ms.
2. Na czas gestu nad ekranem pojawia się nakładka: bieżący „pulpit” przesuwa się za palcami 1:1, a z boku wjeżdża następny, czyli ten sam ekran z oknem docelowym na wierzchu (dokładnie tak będzie wyglądał po przełączeniu).
3. Po puszczeniu palców:
   - przesunięcie ponad ~35% szerokości albo szybki „flick” dokańcza przejście, a w tym czasie pod spodem wychodzi na wierzch prawdziwe okno i nakładka znika płynnym przenikaniem,
   - mniejszy ruch powoduje, że ekran wraca na miejsce.
4. Na końcu listy (bez zawijania) ekran stawia opór i odbija się jak gumka.

Suwak *Czułość* zmienia, jak szybko ekran przesuwa się względem palców. Bez uprawnienia *Nagrywanie ekranu* (albo po wyłączeniu animacji) zasady dokończenia są takie same, tylko bez przesuwania.

### Pamięć układu

- **Klucz konfiguracji** to posortowana lista ekranów: `vendor-model-serial@pikseleXpiksele[x,y,szer.×wys.]`. Ten sam monitor ustawiony po drugiej stronie laptopa daje więc inny układ.
- **Zapis (snapshot)** następuje przy przełączeniu aplikacji (najwyżej raz na 5 s), po każdym gestowym przełączeniu, przed uśpieniem, przy wyjściu z aplikacji, tuż przed zmianą ekranów (flaga *begin configuration*) oraz z zegara co 60 s jako zabezpieczenie. Aplikacje, które nie są uruchomione, zachowują swoje wpisy.
- **Przywracanie:** po ustabilizowaniu się zmiany (1,5 s) okna wracają na swoje miejsca w dwóch przebiegach (po 0,3 s i po 3 s), bo macOS i niektóre aplikacje same przesuwają okna chwilę po podłączeniu monitora. Na czas zmiany zapisy są wstrzymane, żeby tymczasowe „przetasowanie” nie nadpisało zapamiętanego układu.
- **Dopasowanie okien** (`LayoutMatcher`): w obrębie aplikacji najpierw po tytule, potem po indeksie okna w aplikacji, na końcu pozostałe wpisy po kolei.

### Zużycie CPU

Nic nie jest odpytywane w pętli. Zrzuty ekranu powstają wyłącznie wtedy, gdy zaczyna się poziomy gest. Callback MultitouchSupport jest wywoływany tylko wtedy, gdy palce dotykają gładzika, a obsługa jednej ramki to kilka dodawań. Lista okien jest budowana na żądanie: przy geście, przy otwarciu menu i przy zapisie układu, co kosztuje kilka ms zapytań Accessibility. Jedyny zegar (zapis co 60 s, tolerancja 20 s) pozwala systemowi łączyć wybudzenia z innymi timerami.

## Testowanie ręczne

**Etap (a), gest:** uruchom `make probe` i połóż 3 palce na gładziku. Powinna pojawić się linia `fingers: 3`, a po przesunięciu `>>> SWIPE LEFT/RIGHT`. Sprawdź też, że 2 i 4 palce oraz ruch pionowy nie wywołują swipe'a. Jeśli nic się nie loguje, nadaj Terminalowi „Monitorowanie wprowadzania” i spróbuj ponownie.

**Etap (b), przełączanie i animacja:** ułóż 3 okna obok siebie (np. Safari po lewej, Notatki pośrodku, Terminal po prawej). Przesuwaj powoli 3 palcami w lewo: ekran powinien jechać za palcami, a z prawej wjeżdżać następny widok. Puść w połowie, a przejście się dokończy; puść na początku, a ekran wróci. Kolejność to Safari → Notatki → Terminal, a na końcu ekran odbija się z lekkim „pukiem” haptycznym. Gest w prawo działa odwrotnie. Powtórz kilka razy: kolejność ma się nie zmieniać. Dwa okna tego samego programu (np. dwa okna Finder) też powinny się przełączać.

**Etap (c), menu bar:** ikona w pasku menu pokazuje `2/3`. Menu wyświetla okna w kolejności przestrzennej, a aktywne okno jest zaznaczone. Kliknięcie (albo klawisz 1–9 przy otwartym menu) aktywuje okno. W *Wykluczone aplikacje* zaznacz np. Terminal: zniknie z listy i z przełączania. Wyłącz *Przełączanie gestem*: ikona zmieni się, a gest przestanie działać.

**Etap (d), układ:** przy podłączonym monitorze rozmieść okna i wybierz *Zapisz układ teraz*. Odłącz monitor (okna przeskoczą na laptopa), ułóż je dowolnie na laptopie, a potem podłącz monitor ponownie. Po ok. 2 s okna powinny wrócić na zapamiętane miejsca. Zapisane dane są w `~/Library/Application Support/BetterGlide/layouts.json`. Logi zobaczysz w Console.app (filtr: `subsystem:com.betterglide.BetterGlide`) albo poleceniem:

```bash
log stream --predicate 'subsystem == "com.betterglide.BetterGlide"' --level debug
```

**Etap (e), ustawienia:** *Ustawienia…* (⌘, w menu). Zmień liczbę palców, a pole „Test” pokaże wykryty gest na żywo. Sprawdź suwak czułości, kierunek, zawijanie, włączanie/wyłączanie animacji i uruchamianie przy logowaniu (działa najlepiej z `/Applications`).

**CPU:** w Monitorze aktywności BetterGlide bez dotykania gładzika powinien pokazywać ~0,0% CPU.

## Znane ograniczenia

- **Animacja to nakładka ze zrzutów ekranu, nie systemowy Space.** Treść, która się zmienia (np. wideo), jest na czas gestu „zamrożona”. Przy przełączeniu na okno z innego monitora animacja odbywa się na tamtym monitorze.
- **Nagrywanie ekranu w macOS 15+:** system może co jakiś czas (np. raz w miesiącu) pytać, czy dalej pozwolić BetterGlide na nagrywanie ekranu, a podczas robienia zrzutu może na chwilę pokazać fioletowy wskaźnik nagrywania w pasku menu. Jeśli to przeszkadza, wyłącz animację w ustawieniach.

- **Prywatne API.** MultitouchSupport (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, …) i `_AXUIElementGetWindow` są nieudokumentowane. Ładujemy je dynamicznie: jeśli Apple je usunie, aplikacja wystartuje, ale bez gestów (onboarding to pokaże). Z tego powodu aplikacja nie może trafić do App Store.
- **Nie można „pochłonąć” gestu systemowego.** Patrz *Konflikt z gestem systemowym*.
- **Tylko bieżący Space.** Przełączane i zapisywane są okna widoczne na aktualnym pulpicie. Okna na innych Spaces i zminimalizowane są pomijane (prywatne API SkyLight do Spaces są znacznie mniej stabilne).
- **Aktywacja na macOS 14+.** System ogranicza „kradzież” fokusu przez aplikacje w tle. BetterGlide używa ścieżki Accessibility (`AXMain` + `AXFrontmost` + `AXRaise`), która działa niezależnie od tego ograniczenia, a `NSRunningApplication.activate()` jest tylko awaryjnym zapasem.
- **Dopasowanie okien po restarcie aplikacji** odbywa się według tytułu lub indeksu. Okna o identycznych, zmiennych tytułach mogą zamienić się miejscami.
- **Urządzenia multitouch** są wyliczane przy starcie i po wybudzeniu. Magic Trackpad podłączony w trakcie działania zacznie działać po ponownym uruchomieniu BetterGlide lub po uśpieniu i wybudzeniu.
- **Pełny ekran:** aplikacja pełnoekranowa jest jedynym oknem na swoim Space, więc tam gest BetterGlide nie ma między czym przełączać (tak ma być, to robi gest systemowy).

## Dalsze kroki

- Podpis Developer ID + Hardened Runtime + notaryzacja (`xcrun notarytool`). Usunie ostrzeżenie Gatekeepera przy pierwszej instalacji. Hardened Runtime nie blokuje `dlopen` frameworków systemowych.
- Ikona w formacie Icon Composer (`.icon`) z pełnym efektem Liquid Glass systemu; obecna to klasyczny PNG w stylu szkła.
- Lokalizacja EN.
- Opcjonalnie: przełączanie także między Spaces po dojściu do krawędzi listy.
