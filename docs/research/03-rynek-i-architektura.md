# Integracja WAPRO Mag ↔ WooCommerce: rynek i architektura

*Raport badawczy, stan na 2026-09-29*

> **Uwaga metodologiczna:** proxy blokowało pobieranie pełnych treści z większości domen `.pl`. Informacje o produktach i cenach pochodzą z fragmentów wyników wyszukiwania i trzeba je sprawdzić u dostawców. Nazwy tabel i kolumn WAPRO niepotwierdzone w źródłach mają oznaczenie **[do weryfikacji]**.

---

## 1. Istniejące rozwiązania

### 1.1 Rozwiązania Asseco WAPRO (natywne)

| Rozwiązanie | Co robi | Uwagi |
|---|---|---|
| **Wapro Aukcje + integracja Base (BaseLinker)** (od 8.80.0) | WAPRO → Base: artykuły, ceny, stany, kategorie, VAT, statusy, zdjęcia. Base → WAPRO: zamówienia i kontrahenci. Łączenie po EAN lub SKU. Harmonogram od 30 min. | Wymaga wariantu BUSINESS Wapro Aukcje. WooCommerce łączy się przez Base, czyli pośrednio. |
| **Wapro Aukcje + Apilo** | Podobny zakres. Apilo ma integrację z WooCommerce. | Abonament Apilo. |
| **WebAPI Wapro Integrator (REST API)**, partner Aprosystem | Warstwa HTTP nad bazą MSSQL WAPRO: pełny odczyt i podstawowy zapis, reszta dopisywana na zamówienie. | **1990 zł netto + 490 zł instalacja**, licencja wieczysta, on-premise. Kandydat na oficjalną warstwę zapisu. |
| **Wapro B2B / B2C / Hybrid** | Własna platforma sklepowa Asseco. | Konkurencja dla WooCommerce, a nie integracja z nim. |
| **Import/eksport XML (ECOD)** w WAPRO Mag | Import zamówień i faktur z XML. | Wspierana ścieżka zapisu, ale import jest uruchamiany z UI. |
| **Procedury SQL obsługi dokumentów** („Poradnik wdrożeniowca”) | Oficjalne procedury składowane do tworzenia dokumentów, w tym zamówień. | Zalecana droga zapisu z własnego kodu. Aktualną wersję trzeba zdobyć od partnera lub Asseco. |

### 1.2 Integratory firm trzecich (bezpośrednio WAPRO ↔ WooCommerce)

| Produkt | Zakres | Cena | Model |
|---|---|---|---|
| **WfSync (Integratory.pl)** | Zamówienia jako ZO, ZO z rezerwacją, FS/PAi lub WZ. Dwukierunkowe produkty (ceny, stany, opisy, zdjęcia, kategorie, producenci, flaga sprzedaży). Statusy z mailem. | ok. **1180 zł**, licencja na NIP | Aplikacja Windows on-prem |
| **Rovens** | Stany i ceny (ok. co 1 h), zamówienia, produkty. | deklarowane „za darmo” | Konektor + chmura |
| **KID (wf-mag.com.pl)** | Artykuły, ceny, stany, kategorie, VAT, statusy, zamówienia. | licencja roczna, cena na zapytanie | On-prem |
| **Sellasist** | Dwukierunkowe produkty, stany i ceny z cennika, zamówienia. | abonament | Chmura |
| **SellIntegro** | Ponad 20 wtyczek dla WAPRO Mag. | od **89 zł/mies.** | Chmura + agent |
| **iVend, Orbis, IMAG, xc.com.pl** | Wdrożenia partnerskie, często przez Base. | na zapytanie | Mieszany |

### 1.3 Base.com (dawniej BaseLinker)
Freemium do 100 zamówień/mies. Plan Business: 279 zł netto/mies. + 0,99 zł za zamówienie. Do tego licencja łącznika WAPRO↔Base.

### 1.4 Open source
- **przemo420/WooCommerce-WFMAG-Stock-Update**: tylko stany, zapis bezpośrednio do bazy WP. Przy HPOS to zła praktyka.
- **Wiktor10993/wapro-sync-agent**: Electron + Node (`mssql`). Na tabelach produkcyjnych robi tylko SELECT, a zamówienia zapisuje jako XML ECOD albo do osobnego schematu `integracja`. **Wzorzec do skopiowania:** staging w osobnym schemacie i zero zapisu do tabel WAPRO.

### 1.5 Kupić czy budować
- **Kupić**, gdy potrzeby są standardowe. WfSync albo Rovens kosztują mniej niż kilka dni pracy.
- **Budować**, gdy potrzebne są niestandardowe mapowania (warianty z cech, wiele cenników lub magazynów, pakiety), własna logika, pełna kontrola i audyt, brak abonamentów, **rozbudowany panel w wp-admin**.
- **Funkcje do skopiowania z rynku:**
  - wybór typu dokumentu (ZO, ZO z rezerwacją, FS, PA, WZ),
  - wybór magazynu i cennika,
  - łączenie produktów po EAN lub SKU,
  - produkty złożone (min lub suma),
  - interwały synchronizacji,
  - statusy zwrotne z mailem,
  - flaga „w sklepie” z WAPRO.

---

## 2. Rekomendowana architektura konektora

### 2.1 Topologia (wersja pierwotna raportu)

```
[Serwer Windows u klienta]                          [Hosting]
 MS SQL Server (WAPRO Mag)                           WordPress + WooCommerce
      ▲  SELECT (read-only login)                         ▲
      │  EXEC procedur / XML (zapis zamówień)             │ HTTPS
 ┌────┴──────────────────────────┐   wychodzące HTTPS     │
 │ Agent synchronizacji          │ ───────────────────────┘
 │ (Windows Service)             │
 │  - scheduler zadań            │
 │  - SQLite: mapowania, kolejka │
 │  - logi plikowe + Event Log   │
 └───────────────────────────────┘
```

- Agent działa **on-prem**. SQL nie jest wystawiony do internetu, a ruch idzie tylko wychodzącym HTTPS 443.
- Zamówienia pobiera **polling**, bo webhooki wymagałyby publicznego endpointu u klienta.
- Wyjątek: przy WAPRO Anywhere Online / WAPRO Online agent instaluje się w chmurze Asseco.

> Ta topologia została zaktualizowana w [`../ARCHITEKTURA.md`](../ARCHITEKTURA.md) o wtyczkę WordPress z panelem admina. Mapowania, logi i kolejka trafiają wtedy (także) do WP.

### 2.2 Forma uruchomienia
| Opcja | Ocena |
|---|---|
| **Windows Service** (.NET Worker + `UseWindowsService()`, albo Python przez NSSM/WinSW) | **Rekomendowane** |
| Task Scheduler + CLI | Na prototyp |
| Docker | Niezalecany na serwerach WAPRO |

### 2.3 Magazyn stanu agenta
SQLite obok agenta. Tabele: `product_map`, `order_map`, `customer_map`, `outbox`, `sync_cursor`. **Nie zapisujemy stanu w bazie WAPRO**, ewentualnie tylko w osobnym schemacie `integracja` po zgodzie klienta.

### 2.4 Wykrywanie zmian w WAPRO
- **Hash-diff** co N minut na potrzebnych polach, wysyłka tylko różnic.
- Opcjonalnie daty modyfikacji **[do weryfikacji]**. Change Tracking wymaga zmian w bazie klienta.
- Wysyłka przez `products/batch` (≤ 100 elementów).

### 2.5 Niezawodność
- Retry z backoffem i jitterem przy 5xx, 429 i timeoutach. Błędy 4xx trafiają do dead letter z alertem.
- Idempotencja zamówień:
  - najpierw sprawdzenie `order_map`,
  - numer Woo zapisany w polu dokumentu WAPRO („numer obcy” **[do weryfikacji]**),
  - meta `_wapro_zo_id` w Woo.
- Mutex na zadania.
- Logi rotowane dziennie, krytyczne błędy do Windows Event Log.
- Sekrety zaszyfrowane przez DPAPI lub Credential Manager.

### 2.6 Źródło prawdy dla każdego pola
| Dane | Źródło prawdy | Kierunek |
|---|---|---|
| Nazwa, EAN/SKU, VAT, cena, stan, kategoria | **WAPRO** | WAPRO → Woo |
| Opisy, SEO, zdjęcia | do ustalenia, często **Woo** | konfigurowalnie (np. tylko przy tworzeniu) |
| Zamówienia, klient, dostawa, płatność | **Woo** | Woo → WAPRO (tylko tworzenie) |
| Status realizacji, numer faktury | **WAPRO** | WAPRO → Woo |

Stan wysyłany do Woo = stan − rezerwacje − bufor bezpieczeństwa. Zamówienia pobierane co 1–5 min.

### 2.7 Dostęp do bazy WAPRO
- **Odczyt:** login tylko z SELECT, najlepiej przez własne widoki w osobnym schemacie.
- **Zapis zamówień:** (1) procedury Asseco, (2) WebAPI Wapro Integrator, (3) XML ECOD.
- **Nigdy surowe INSERT-y** do `ZAMOWIENIE` / `POZYCJA_ZAMOWIENIA`. Logika WAPRO siedzi w triggerach i procedurach.

---

## 3. Stos technologiczny agenta

| Kryterium | **.NET 8/10 (C#)** | **Python 3.12+** | **Node.js (TS)** |
|---|---|---|---|
| Sterownik MSSQL | `Microsoft.Data.SqlClient` (first-party, obsługuje Windows auth) | `pyodbc` + ODBC 18 albo **`mssql-python`** (samo `pip`) | `mssql`/`tedious`, a do Windows auth `msnodesqlv8` |
| TLS | `Encrypt=true` domyślnie | `Encrypt=yes` domyślnie | jak wyżej |
| Usługa Windows | natywnie (`UseWindowsService()`) | NSSM/pywin32/WinSW | node-windows/WinSW |
| Dystrybucja | jeden plik `.exe` | PyInstaller (+ ODBC) | pkg/nexe |
| Klient Woo | HttpClient + Polly | httpx + tenacity | oficjalny |
| SQLite | `Microsoft.Data.Sqlite` | wbudowany | `better-sqlite3` |
| Ekosystem WAPRO | partnerzy piszą w .NET/Delphi | — | — |

**Rekomendacja: .NET (C#) Worker Service.** Alternatywa: Python z `mssql-python` + PyInstaller + WinSW.

---

## 4. MVP i roadmapa

- **Faza 0: rozpoznanie (1–3 dni).** Kopia bazy WAPRO i wersja programu, mapa tabel, dokumentacja procedur, staging Woo, klucze REST.
- **Faza 1 (MVP): WAPRO → Woo.** Produkty, stany i ceny:
  - łączenie produktów po SKU lub EAN z raportem niedopasowań,
  - stan liczony jako magazyny − rezerwacje − bufor, cena z wybranego cennika,
  - opcjonalnie nowe produkty jako `draft`,
  - hash-diff, batch, retry, logi, usługa Windows, `--dry-run`.
  - Kryterium odbioru: zgodność ≤ 15 min.
- **Faza 2: zamówienia Woo → WAPRO (ZO).**
  - Kontrahent dopasowany po NIP, potem po e-mailu, w ostateczności kontrahent detaliczny.
  - Dostawa jako usługa, rabaty uwzględnione.
  - Zapis przez procedury, WebAPI albo XML.
  - Idempotencja, kwarantanna dla niezmapowanych produktów.
- **Faza 3: rozszerzenia.**
  - statusy zwrotne i numery przesyłek,
  - faktury (numer, PDF, **KSeF obowiązkowy od 2026**),
  - kontrahenci B2B i cenniki indywidualne,
  - zdjęcia, warianty, drzewo kategorii.

---

## 5. Ryzyka i pytania do klienta

### 5.1 Ryzyka
| Ryzyko | Mitygacja |
|---|---|
| Zmiany schematu po aktualizacjach WAPRO | Własne widoki, test „smoke” przy starcie, zapis tylko oficjalnymi ścieżkami, test po każdej aktualizacji |
| Licencjonowanie i wsparcie Asseco | Potwierdzić z partnerem. Rozważyć WebAPI. |
| Spójność przy zapisie | Tylko procedury lub XML, transakcje, test na kopii bazy, minimalne uprawnienia |
| Wydajność SQL | Tylko potrzebne kolumny, rozsądny interwał, pełny resync nocą |
| Wydajność Woo | Konfigurowalny batch (20–50), throttling |
| Overselling | Krótki interwał zamówień, rezerwacje, bufor |
| Jakość danych (SKU/EAN) | Raport niedopasowań przed startem |
| Wiele kanałów sprzedaży (Allegro) | Jedno źródło stanów, bez dwóch integratorów na tych samych polach |
| Utrzymanie agenta u klienta | Instalator, autoaktualizacja, heartbeat widoczny w panelu WP |
| Bezpieczeństwo | DPAPI, konto usługi z minimalnymi prawami, tylko HTTPS |

### 5.2 Pytania do klienta
Pełna lista: [`../PYTANIA-DO-KLIENTA.md`](../PYTANIA-DO-KLIENTA.md).

---

## 6. Źródła
**Asseco WAPRO**
- https://wapro.pl/dokumentacja-erp/desktop/docs/aukcje-internetowe/integracja-baselinker/
- https://wapro.pl/dokumentacja-erp/desktop/docs/aukcje-internetowe/modele-integracji/
- https://wapro.pl/dokumentacja-erp/anywhere/docs/aukcje-internetowe/integracja/apilo/
- https://pomoc.wapro.pl/menedzer-radzi/porozmawiajmy-o-e-commerce-7-integracja-hybrydowa-wapro-mag-baselinker-i-sklep-internetowy/
- https://wapro.pl/rozwiazania-branzowe/webapi-wapro-integrator-rest-api/
- https://wapro.pl/dokumentacja-erp/anywhere/docs/sprzedaz-i-magazyn/menu-inne/wymiana-danych/eksport-import-mag/
- https://www.waproerp.blog/wapro-mag-elektroniczna-wymiana-danych-xml-konfiguracja/
- https://docplayer.pl/106232407-Procedury-sql-obslugi-dokumentow-w-wapro-mag-poradnik-wdrozeniowca.html

**Integratory i platformy pośrednie**
- https://www.aprosystem.pl/dedykowane-rozwiazania/webapi-wapro/
- https://www.aprosystem.pl/webapi/docs/intro/
- https://integratory.pl/produkt/wfsync-integrator-woocommerce-i-wf-mag-wapro/
- https://rovens.pl/integracja-wapro/woocommerce/
- https://wf-mag.com.pl/integrator/130-integrator-woo-commerce-wapro-mag
- https://sellasist.pl/integracja/woocommerce/wapro-wf-mag
- https://www.sellintegro.pl/systemy/wapro-mag
- https://apilo.com/pl/integracje/wapro-wf-mag/
- https://base.com/pl-PL/blog/nowy-cennik-baselinker/

**GitHub**
- https://github.com/Wiktor10993/wapro-sync-agent
- https://github.com/topics/wapro-mag

**Stos**
- https://learn.microsoft.com/en-us/dotnet/core/extensions/windows-service
- https://pypi.org/project/mssql-python/
- https://learn.microsoft.com/en-us/sql/connect/odbc/connection-troubleshooting?view=sql-server-ver17
