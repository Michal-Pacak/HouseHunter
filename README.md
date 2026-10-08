# HouseHunter

Narzędzie monitorujące ogłoszenia sprzedaży mieszkań (na start: OLX i Otodom), które:

- filtruje ogłoszenia wg sztywnych parametrów (miasto, budżet, stan) zanim cokolwiek trafi do AI,
- analizuje dopasowanie do swobodnych kryteriów (tekst + zdjęcia) modelem Claude — tylko dla nowych ogłoszeń albo takich, w których coś realnie się zmieniło,
- wykrywa samą zmianę ceny bez ponownego uruchamiania AI,
- łączy ogłoszenia tej samej nieruchomości z różnych portali w jeden byt (`Property`),
- pokazuje wynik w prostym panelu webowym.

Zobacz plan/architekturę: `C:\Users\Michal\.claude\plans\potrzebuj-narz-dzia-kt-re-bedzie-toasty-bunny.md`.

## Uruchomienie

Są dwa tryby analizy AI, sterowane `ANALYSIS_BACKEND` w `.env`:

### Tryb `claude_cli` (domyślny) — analiza w ramach subskrypcji Claude, bez klucza API

Zamiast płatnego Anthropic API, `app/analysis/claude_cli_client.py` odpala lokalnie zainstalowane i zalogowane (kontem Pro/Max) Claude Code CLI (`claude -p ...` w trybie headless, ze structured output przez `--json-schema`). Zużycie liczy się do limitów subskrypcji, nie do $/token — nie trzeba doładowywać konta w konsoli Anthropic.

**Ograniczenie: apka (uvicorn/CLI) musi wtedy działać na tej samej maszynie, na której `claude` jest zalogowany — nie w kontenerze Dockera** (kontener nie ma dostępu do danych logowania subskrypcji na hoście). Postgres może zostać w Dockerze, port 5432 jest wystawiony na `localhost`.

```bash
cp .env.example .env    # domyślnie ANALYSIS_BACKEND=claude_cli, ANTHROPIC_API_KEY nie jest potrzebny
docker compose up -d db
pip install -r requirements.txt
python -m alembic upgrade head
python -m app.cli set-criteria --city Warszawa --max-budget 900000 --condition po_remoncie --free-text "..."
python -m uvicorn app.api.main:app --host 0.0.0.0 --port 8000
# w drugim terminalu, ręcznie lub wg harmonogramu:
python -m app.cli scrape
```

Uwaga na zużycie limitu: model Claude Code (`CLAUDE_CLI_MODEL`, domyślnie `sonnet`) rozumuje (extended thinking), więc jedno ogłoszenie ze zdjęciami to zwykle >1000 tokenów wyjściowych — przy dużej liczbie nowych ogłoszeń w cyklu może to zauważalnie nadgryzać dzienny/tygodniowy limit subskrypcji, współdzielony ze zwykłą pracą w Claude Code. Zweryfikowane działanie: analiza tekstowa bez zdjęć oraz analiza realnego ogłoszenia z 8 zdjęciami (poprawnie oceniło brak balkonu/widoku na park na podstawie zdjęć).

### Tryb `anthropic_api` — pełna konteneryzacja, płatne API

Docelowy tryb produkcyjny/komercyjny (przyszła wersja wieloosobowa musi i tak rozliczać każdego klienta przez API — subskrypcja jednej osoby nie może obsłużyć innych użytkowników).

```bash
cp .env.example .env
# w .env: ANALYSIS_BACKEND=anthropic_api, ANTHROPIC_API_KEY=<prawdziwy klucz>,
# DATABASE_URL=postgresql+psycopg://househunter:househunter@db:5432/househunter
docker compose up --build
```

Migracje (`alembic upgrade head`) odpalają się automatycznie przy starcie kontenera `app`.

Panel webowy: http://localhost:8000 — lista dopasowań pod `/`, ustawienia kryteriów pod `/criteria`.

## Ustawienie pierwszych kryteriów

Panel `/criteria` jest najwygodniejszy, ale na start (albo do testów) można też użyć CLI w kontenerze:

```bash
docker compose exec app python -m app.cli set-criteria --city Warszawa --max-budget 900000 --condition po_remoncie --free-text "Chcę balkon i widok na park, unikam parteru"
```

## Ręczne odpalenie cyklu (weryfikacja)

```bash
docker compose exec app python -m app.cli scrape --portal olx
docker compose exec app python -m app.cli scrape --portal otodom
# albo oba na raz:
docker compose exec app python -m app.cli scrape
```

Odpal drugi raz bez zmian w danych źródłowych — w logach nie powinno pojawić się żadne wywołanie Anthropic API (to jest test kluczowego wymogu: brak ponownej analizy niezmienionych ogłoszeń).

## Testy jednostkowe

```bash
pip install -r requirements.txt
pytest
```

Obejmują hashowanie treści (wykrywanie zmian) i pomocnicze parsowanie tekstu. Nie uruchamiałem ich lokalnie — na tej maszynie nie było zainstalowanego Pythona. Warto odpalić przed pierwszym prawdziwym cyklem scrapingu.

## Status weryfikacji

Zainstalowałem Pythona, Dockera i uruchomiłem cały stos (`docker compose up --build`) — migracje przechodzą, panel webowy działa, a `python -m app.cli scrape` faktycznie pobrał i zapisał **150 ogłoszeń z OLX i 103 z Otodom** (Warszawa), z poprawnie wypełnionymi cenami, metrażem, opisami i dedupem. Analiza AI kończy się kontrolowanym błędem 401 (bo w `.env` jest tylko placeholder klucza) — pipeline łapie ten błąd i jedzie dalej, zgodnie z założeniem.

Po drodze wypłynął jeden realny problem: **OLX blokuje zwykłego httpx-a/requests zwracając 403**, mimo poprawnego, przeglądarkowego User-Agenta — to blokada na poziomie fingerprintu TLS/HTTP, nie nagłówków (ten sam request przez `curl` przechodzi bez problemu). Naprawione przez `curl_cffi` z impersonacją Chrome (`app/adapters/browser_client.py`) — biblioteka stworzona dokładnie do tego przypadku, używana standardowo w narzędziach do web scrapingu. Zdjęcia (CDN) i Otodom nie miały tego problemu, ale dla spójności obie strony korzystają teraz z tego samego klienta.

**Analiza AI z prawdziwym werdyktem — zweryfikowane w trybie `claude_cli`.** Po przełączeniu backendu analizy na headless Claude Code CLI (subskrypcja Pro/Max zamiast płatnego klucza API — patrz sekcja „Uruchomienie") odpaliłem realny cykl na próbce ogłoszeń: **41 analiz, 8 dopasowań**, z poprawnym rozumowaniem odwołującym się do faktycznej treści zdjęć (piętro, balkon, widok) i opisu. Po drodze wyszedł drugi problem specyficzny dla uruchamiania na hoście Windows (ten backend nie działa w kontenerze): `curl_cffi` nie widział jakiegoś lokalnie zainstalowanego głównego urzędu certyfikacji (prawdopodobnie antywirus/proxy firmowe skanujące HTTPS) i rzucał błędem `unable to get local issuer certificate`, mimo że PowerShell/przeglądarka łączyły się bez problemu (bo korzystają z magazynu certyfikatów Windows, a `curl_cffi` nie). Naprawione w `app/adapters/browser_client.py` przez zbudowanie własnej paczki CA łączącej `certifi` z zawartością magazynu certyfikatów Windows (`ssl.enum_certificates`).

## Jak zweryfikowałem parsery OLX/Otodom

Obu portali nie da się bezpiecznie parsować "na czuja" z CSS-selektorów — obie strony renderują wyniki wyszukiwania z osadzonego w HTML-u obiektu JSON (`window.__PRERENDERED_STATE__` na OLX, standardowy Next.js `__NEXT_DATA__` na Otodom). Pobrałem realne strony wyników (Warszawa) i stronę pojedynczego ogłoszenia Otodom, i zweryfikowałem dokładne ścieżki pól (`listing.listing.ads[]` / `props.pageProps.data.searchAds.items[]` / `props.pageProps.ad`) użyte w `app/adapters/olx.py` i `app/adapters/otodom.py` względem rzeczywistej struktury. To realne, działające parsery, nie zgadywanka — ale portale zmieniają swoje frontendy bez ostrzeżenia, więc jeśli po jakimś czasie przestaną działać, pierwsze co sprawdzić to czy te ścieżki JSON się nie zmieniły.

## Znane ograniczenia etapu 1 (celowo odłożone na etap 2)

- **Tylko OLX i Otodom.** Morizon i Nieruchomości-online/Gratka mają być dodane wg tego samego interfejsu `PortalAdapter` (`app/adapters/base.py`) — nie badałem jeszcze ich struktury HTML.
- **Otodom wymaga znanego miasta.** URL wyszukiwania Otodom koduje hierarchię województwo/powiat/gmina/miasto; działa automatycznie tylko dla dużych miast na prawach powiatu z listy w `app/adapters/otodom.py` (`_CITY_VOIVODESHIP`). Dla innych miast trzeba będzie samodzielnie skopiować segment URL-a z otodom.pl i przekazać go przez `SearchFilters.portal_search_paths["otodom"]`.
- **Dedup bez AI tie-breaka.** `app/dedup/matcher.py` łączy ogłoszenia na podstawie bloku (miasto/metraż) + score tekstowy/phash zdjęć; przypadki niejednoznaczne (score 0.55–0.80) są rozstrzygane tylko przez porównanie zdjęć (perceptual hash), bez wywołania Claude jako tie-breakera, i bez ręcznego scalania/rozdzielania w panelu.
- **Zmiana kryteriów działa "na następne zobaczenie".** Nowa wersja kryteriów wymusza ponowną analizę ogłoszenia dopiero, gdy pojawi się ono ponownie w wynikach wyszukiwania danego cyklu — nie ma osobnego joba, który od razu przeanalizuje wszystkie już zapisane, aktywne ogłoszenia pod nowe kryteria.
- **Wysyłka e-mail** to celowo tylko nieaktywny przycisk w UI — infrastruktura pod maile (SendGrid/SES) to etap 2/komercjalizacja.
