# Architektura: WAPRO Mag ↔ WooCommerce

Dokument decyzyjny. Wyrósł z raportów w [`research/`](research/). Nazwy tabel i procedur WAPRO oznaczone **[HIP]** wymagają weryfikacji na bazie klienta (skrypt: [`../sql/discovery.sql`](../sql/discovery.sql)).

## 1. Założenia
- WAPRO Mag stoi on-prem na MS SQL Server (często Express). Serwer SQL **nie jest** wystawiony do internetu.
- WooCommerce działa na zewnętrznym hostingu, HPOS włączony, WC ≥ 10.5.
- Klient wymaga **rozbudowanego panelu w wp-admin**. Konfiguracja, podgląd, logi, kolejka i akcje ręczne odbywają się w WordPressie.
- Źródło prawdy:
  - WAPRO: produkty, ceny, stany, VAT, statusy realizacji,
  - WooCommerce: zamówienia, dane klientów, opisy i zdjęcia (konfigurowalne per pole).

## 2. Komponenty

```
┌──────────── sieć klienta (LAN) ─────────────┐            ┌──────────── hosting ────────────────────────┐
│                                             │            │ WordPress + WooCommerce                     │
│  MS SQL Server ── WAPRO Mag (dbo)           │            │                                             │
│      ▲ SELECT (login read-only)             │   HTTPS    │  Wtyczka  wapro-sync                        │
│      │ EXEC RM_* (zapis zamówień)           │  (tylko    │   ├─ REST  wapro-sync/v1  (HMAC)            │
│  ┌───┴──────────────────────────┐           │  wychodzą- │   ├─ Kolejka jobów + Action Scheduler       │
│  │ Agent  (Windows Service)     │───────────┼──  ce z ──►│   ├─ Tabele: map / jobs / runs / log        │
│  │  .NET Worker, jeden .exe     │           │  agenta)   │   ├─ Panel wp-admin (React + DataViews)     │
│  │  SQLite: hash cache, kursory │◄──────────┼────────────│   └─ Metaboxy produktu i zamówienia (HPOS)  │
│  └──────────────────────────────┘ odpowiedzi│            │                                             │
└─────────────────────────────────────────────┘            └─────────────────────────────────────────────┘
```

### 2.1 Agent (on-prem): `agent/`
- **.NET 8 LTS (lub 10) Worker Service** z `UseWindowsService()`, publikowany jako jeden plik `.exe` self-contained.
- `Microsoft.Data.SqlClient`, zapytania przez Dapper, `HttpClient` z Polly (retry, backoff, jitter), Serilog (pliki + Event Log), `Microsoft.Data.Sqlite`.
- **Tylko połączenia wychodzące** HTTPS do wtyczki. Agent nie nasłuchuje na żadnym porcie.
- **Konfiguracja biznesowa** (magazyny, cennik, VAT, typ dokumentu, interwały) pochodzi z panelu WP przez `GET /agent/config`. Lokalnie są tylko: connection string SQL, URL sklepu, klucz HMAC (DPAPI).
- **Zadania:**

  | Zadanie | Interwał (domyślny) | Opis |
  |---|---|---|
  | heartbeat | 60 s | status, wersja, stan SQL; w odpowiedzi komendy z panelu |
  | catalog | 1 h / na żądanie | słowniki z WAPRO: magazyny, cenniki, stawki VAT, formy płatności, statusy, grupy |
  | stock | 2–5 min | snapshot stanu dostępnego → hash-diff → `/stock/batch` |
  | prices | 15 min | cena z wybranego cennika → hash-diff → `/prices/batch` |
  | products | nocą + na żądanie | pełne dane artykułów według własności pól → `/products/batch` |
  | orders | 1–2 min | `GET /orders/pending` → zapis w WAPRO → `/orders/{id}/ack` |
  | order-status | 5–15 min | statusy ZO/FS/WZ z WAPRO → `/orders/{id}/status` |

- **Odczyt WAPRO** tylko przez nasze zapytania SQL z `READ UNCOMMITTED` i `LOCK_TIMEOUT`. Docelowo przez widoki w osobnym schemacie (np. `wsync`), po zgodzie klienta.
- **Zapis zamówień** przez adapter `IOrderWriter` z trzema implementacjami do wyboru:
  1. `StoredProcOrderWriter`: `RM_DodajZamowienie` → `RM_DodajPozycjeZamowienia` → `RM_ZatwierdzZamowienie` **[HIP: sygnatury]**. Domyślnie do bufora BZO.
  2. `WebApiOrderWriter`: WebAPI Wapro Integrator (Aprosystem), jeśli klient go kupi.
  3. `XmlOrderWriter`: plik EDI XML do półautomatycznego importu (fallback).
- **Nigdy** surowe `INSERT`/`UPDATE` do tabel WAPRO.

### 2.2 Wtyczka WordPress: `plugin/wapro-sync/`
- PHP 8.1+, WP 6.8+, WC 10.0+, PSR-4 `WaproSync\`, Composer (prefiksowanie przez Strauss).
- **Centrum sterowania.** Tu mieszkają:
  - konfiguracja,
  - mapowania (`wapro_map`),
  - kolejka (`wapro_jobs`),
  - historia (`wapro_runs`),
  - logi (`wapro_log`).
- Zapisy do WooCommerce idą wyłącznie przez CRUD WC (`wc_get_product`, `wc_update_product_stock`, `WC_Order`). Przy HPOS nigdy nie używamy SQL do tabel WC.
- Paczki od agenta: endpoint zapisuje joby i odpowiada `202 + run_id`, a przetwarza je Action Scheduler w chunkach po 100–200.
- Zamówienia: hook `woocommerce_order_status_changed` → job `order_export` → agent odbiera go pollingiem `GET /orders/pending`. Webhooki WC są niepotrzebne (agent stoi za NAT-em).
- Pętle zwrotne blokuje `SyncContext::$fromWapro`.
- Panel: szczegóły w [research/04-panel-wp-admin.md](research/04-panel-wp-admin.md).

### 2.3 Kontrakt REST `wapro-sync/v1`
| Endpoint | Metoda | Kierunek |
|---|---|---|
| `/agent/heartbeat` | POST | agent → WP (odpowiedź: komendy, wersja configu) |
| `/agent/config` | GET | WP → agent (ETag) |
| `/agent/catalog` | POST | słowniki WAPRO → WP (do selectów w panelu) |
| `/stock/batch`, `/prices/batch` | POST | delty `{wapro_id, sku, value, changed_at}` |
| `/products/batch` | POST | upsert według własności pól, `Idempotency-Key` |
| `/orders/pending` | GET | zamówienia do eksportu (kursor, limit) |
| `/orders/{id}/ack` | POST | numer dokumentu WAPRO / błąd |
| `/orders/{id}/status` | POST | status zwrotny, numer przesyłki |
| `/runs`, `/runs/{id}` | POST/PATCH | przebiegi z licznikami |
| `/admin/*` | — | panel (cookie + nonce + capabilities) |

Autoryzacja agenta: **HMAC-SHA256**.
- Podpisywane pola: `METHOD\nPATH\nQUERY\nTIMESTAMP\nNONCE\nSHA256(body)`.
- Nagłówki `X-Wapro-Key`, `-Timestamp`, `-Nonce`, `-Signature`.
- Okno ±300 s, jednorazowy nonce.
- Wiele kluczy (rotacja).

Pełną specyfikację OpenAPI tworzymy w fazie 1: `docs/api/openapi.yaml`.

## 3. Kluczowe decyzje (ADR skrót)
| # | Decyzja | Uzasadnienie |
|---|---|---|
| 1 | Agent on-prem + wtyczka WP, bez chmury pośredniej | SQL nie wychodzi na świat, brak abonamentów, panel tam, gdzie chce klient |
| 2 | Agent w .NET (C#) | natywny sterownik SQL i Windows Service, jeden `.exe`, ekosystem partnerów WAPRO |
| 3 | Własny REST wtyczki zamiast bezpośrednio `wc/v3` | lżejsze aktualizacje stanów, jedno miejsce logów i kolejki, widoczność w panelu, HMAC |
| 4 | Panel: React + `@wordpress/dataviews`, podmenu WooCommerce | kierunek WP 7.0, gotowe filtry i akcje masowe |
| 5 | Wykrywanie zmian: snapshot + hash-diff (MVP), Change Tracking opcjonalnie | zero zmian w bazie klienta. Triggery usuwane przez aktualizacje WAPRO |
| 6 | Zamówienia do bufora BZO przez procedury Asseco | wspierana ścieżka, operator zatwierdza, brak ryzyka dla stanów |
| 7 | Klucz produktu: SKU = `INDEKS_KATALOGOWY` | unikalny między magazynami (`ID_ARTYKULU` jest per magazyn) |
| 8 | Własna historia jobów i logów w tabelach WP | Action Scheduler czyści historię po 3 mies. |

## 4. Roadmapa
| Faza | Zakres | Kryterium odbioru |
|---|---|---|
| **0: Rozpoznanie** | kopia bazy WAPRO, `discovery.sql`, Profiler zapisu ZO, staging Woo, odpowiedzi na [pytania](PYTANIA-DO-KLIENTA.md) | zweryfikowane nazwy tabel, wzór stanu dostępnego, sygnatury procedur |
| **1: Szkielet + stany/ceny** | wtyczka: tabele, REST agenta (HMAC), Pulpit, Logi, Kolejka, Ustawienia (połączenie, magazyny, ceny, VAT), Mapowania produktów. Agent: heartbeat, catalog, stock, prices, usługa Windows, `--dry-run` | stan i cena w Woo zgodne z WAPRO ≤ 5 min, widoczne w panelu |
| **2: Zamówienia** | eksport zamówień do BZO/ZO, dopasowanie kontrahenta (NIP/e-mail/detaliczny), wysyłka jako usługa, mapa płatności, metabox zamówienia, retry, kwarantanna niezmapowanych produktów, powiadomienia e-mail | 100% zamówień w WAPRO bez duplikatów, błędy widoczne i ponawialne |
| **3: Produkty pełne + statusy** | tworzenie i aktualizacja produktów według własności pól, kategorie, EAN, statusy zwrotne, numer przesyłki, metabox produktu z kłódkami | — |
| **4: Rozszerzenia** | warianty (reguła grupowania), zdjęcia, cenniki B2B, faktury (numer/PDF, KSeF), Change Tracking, autoaktualizacja agenta | — |

## 5. Ryzyka (skrót)
- **Aktualizacje WAPRO zmieniają schemat lub procedury.** Mitygacja: test „smoke” zapytań przy starcie agenta, wersja bazy w heartbeat, alert w panelu.
- **Licencja i wsparcie Asseco.** Mitygacja: zapis tylko przez procedury lub WebAPI, uzgodnione z partnerem WAPRO klienta.
- **Overselling między cyklami.** Mitygacja: stan = dostępny − bufor − zamówienia Woo nieprzeniesione, krótki interwał.
- **Kilka integratorów naraz** (Wapro Aukcje, Base). Mitygacja: jedno źródło stanów, wykrywanie duplikatów zamówień.
- **Słaby hosting Woo.** Mitygacja: konfigurowalny rozmiar chunku, Action Scheduler, Redis.
- **RODO w logach.** Mitygacja: redakcja, retencja, eksporter i eraser danych.
