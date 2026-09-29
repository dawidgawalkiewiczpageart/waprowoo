# Panel administracyjny wtyczki WAPRO Mag ↔ WooCommerce: raport projektowy

Stan na wrzesień 2026. Środowisko docelowe: WordPress 7.0, WooCommerce 10.x/11.x, Action Scheduler 4.x.
Architektura: agent on-prem obok MS SQL Server (WAPRO Mag) plus wtyczka WP/WC, która daje REST API dla agenta i rozbudowany panel w wp-admin.

> Część faktów z developer.woocommerce.com i make.wordpress.org pochodzi z wyników wyszukiwarki (proxy blokowało pełną lekturę). Przed implementacją przeczytać linkowane strony, zwłaszcza Settings UI i DataViews.

---

## 0. Kluczowe fakty z ekosystemu na 2026

| Fakt | Konsekwencja |
|---|---|
| WP 7.0 przebudowuje listy w wp-admin na **DataViews** (`@wordpress/dataviews`). DataForm służy do formularzy i ustawień. | Panel budujemy na DataViews/DataForm. `WP_List_Table` to przestarzały wzorzec. |
| WC 10.9 ma flagę `settings-ui` (React dla ustawień rozszerzeń, `LegacySettingsPageAdapter`). Na razie to opt-in. | Nie wiążemy się teraz. Zostawiamy możliwość dodania zakładki później. |
| Beta blokowego edytora produktu została usunięta w WC 11.0. | Metabox produktu robimy klasycznie (`add_meta_box`, `woocommerce_product_data_tabs`). |
| HPOS jest domyślny. | Deklaracja `custom_order_tables` i wyłącznie CRUD zamówień. |
| Action Scheduler 4.0 czyści nieudane akcje po 3 miesiącach, a `$unique` uwzględnia argumenty. | Historię jobów trzymamy we własnej tabeli. AS służy tylko jako silnik wykonawczy. |
| WC 11.5 (01.2027) ma wymagać PHP 8.1 lub nowszego. | Celujemy w PHP 8.1+, WP 6.8+, WC 10.0+. |
| Notatki inboxa: `Automattic\WooCommerce\Admin\Notes\Note`. | Stare klasy `WC_Admin_Note(s)` są przestarzałe. |

---

## 1. Zakres funkcjonalny panelu

### 1.1 Benchmark
- **BaseLinker (`baselinker-woo`)**: mapowanie statusów, przełączniki pobierania zamówień i przesyłania statusów, tryb master/slave dla stanów i cen, harmonogram.
- **Sellintegro**: wybór cennika i magazynu, wybór pól do aktualizacji, zmiana statusu po utworzeniu dokumentu, filtr statusów zamówień.
- **WfSync, KID**: wybór typu dokumentu (ZO, ZO z rezerwacją, FS/PA, WZ), automatyczna realizacja ZO, dwukierunkowe produkty, zwrotne statusy.
- **WP All Import**: historia przebiegów z licznikami, pobieranie logu, „run now”, wznawianie przerwanego importu.

**Nasz wyróżnik:** widoczność kolejki, retry per rekord, **własność pól** (field ownership).

### 1.2 Moduły panelu
1. **Pulpit**
   - KPI: agent online/offline (heartbeat „32 s temu”, wersja, host), ostatnia synchronizacja per strumień, błędy 24 h i 7 dni, kolejka (pending, running, failed), zamówienia do eksportu i z błędem.
   - Wykres 7 dni i 10 ostatnich błędów.
   - Alerty: agent offline, niezmapowane VAT, statusy lub metody wysyłki, produkty bez mapowania.
   - Szybkie akcje: synchronizuj stany, pełny resync, **kill switch**.
2. **Ustawienia** (zakładki; pola w sekcji 3.3).
3. **Mapowania**
   - produkty,
   - kategorie,
   - klienci,
   - wysyłka i płatności,
   - statusy (dwukierunkowo),
   - VAT (w tym ZW i NP),
   - jednostki i cechy.
4. **Logi**
   - filtry po poziomie, kanale, encji, dacie i `run_id`,
   - kontekst JSON,
   - eksport CSV lub NDJSON,
   - retencja.
5. **Kolejka / Zadania**
   - statusy: pending, running, done, failed, dead,
   - akcje: retry (też masowe), anuluj, dead-letter, podgląd payloadu i prób.
6. **Przebiegi (Runs)**: start i koniec, liczniki created/updated/skipped/failed.
7. **Narzędzia**
   - pełny resync (z dry-run),
   - synchronizacja SKU,
   - (ponowne) wysłanie zamówienia,
   - przebudowa mapowań,
   - test połączenia,
   - eksport i import konfiguracji,
   - raport diagnostyczny.
8. **Metabox produktu**
   - ID_ARTYKULU, indeks, EAN, stany per magazyn, ceny per poziom, ostatnia synchronizacja,
   - kłódki na polach należących do ERP,
   - przyciski: „Synchronizuj teraz”, „Odłącz”,
   - na liście produktów: kolumna „WAPRO” i akcja masowa.
9. **Metabox zamówienia (HPOS)**
   - status eksportu, numer dokumentu WAPRO, kontrahent, próby i błąd, oś czasu,
   - przyciski: „Wyślij” i „Wyślij ponownie”,
   - na liście zamówień: kolumna i filtr „błąd eksportu”.
10. **Powiadomienia**
    - e-mail: progi, agent offline, digest, throttling,
    - inbox WC i `admin_notices`,
    - opcjonalnie Slack/Teams.
11. **Uprawnienia**: własne capabilities (2.9).

---

## 2. Podejście techniczne

### 2.1 Menu
**Podmenu pod WooCommerce** („WooCommerce → WAPRO Sync”, `add_submenu_page('woocommerce', …)`): jedna strona SPA z zakładkami `?page=wapro-sync&tab=…`, do tego `wc_admin_connect_page()` dla nagłówka i breadcrumbs WC. Top-level menu tylko na życzenie klienta, jako flaga w kodzie.

### 2.2 React czy klasyczne PHP
**Nowoczesny React**:
- `@wordpress/scripts`, `@wordpress/components`,
- `@wordpress/dataviews` (DataViews i DataForm),
- `@wordpress/data`, `@wordpress/api-fetch`, `@wordpress/i18n`.

Uwagi:
- Klasycznie zostają tylko metaboxy i ewentualna zakładka w Ustawieniach WC.
- `@wordpress/dataviews` bundlujemy w paczce wtyczki i przypinamy wersję. `react` i `@wordpress/components` zostają jako zależności zewnętrzne (`index.asset.php`).
- Dane panelu idą wyłącznie przez REST `wapro-sync/v1/admin/*`, bez `admin-ajax`.

### 2.3 Integracja z WooCommerce Admin
- Nagłówek: `wc_admin_connect_page()` albo `wc_admin_register_page()`.
- Inbox: `Note` z `name` np. `wapro-sync-agent-offline`. Przed dodaniem sprawdzamy `Notes::get_note_by_name`.
- Kolumny zamówień przy HPOS: `manage_woocommerce_page_wc-orders_columns` i `..._custom_column`, dla trybu legacy `manage_edit-shop_order_columns`. Screen przez `wc_get_page_screen_id('shop-order')`.
- `woocommerce_system_status_report` i `woocommerce_debug_tools`.

### 2.4 HPOS
```php
add_action('before_woocommerce_init', static function () {
    if (class_exists(\Automattic\WooCommerce\Utilities\FeaturesUtil::class)) {
        \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility('custom_order_tables', WAPRO_SYNC_FILE, true);
        \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility('cart_checkout_blocks', WAPRO_SYNC_FILE, true);
    }
});
```
Meta zamówienia: `$order->update_meta_data(); $order->save();`. Wyszukiwanie przez własną tabelę mapowań. Callback metaboxa przyjmuje `WP_Post|WC_Order` i normalizuje przez `wc_get_order()`.

### 2.5 Action Scheduler
- Grupa `wapro-sync`. Hooki:
  - `wapro_sync/process_job` (argument: tylko `job_id`),
  - `wapro_sync/export_order`,
  - `wapro_sync/cleanup`,
  - `wapro_sync/heartbeat_check`,
  - `wapro_sync/digest_email`.
- Zdarzenie zapisuje rekord w `wapro_jobs`, potem `as_enqueue_async_action(..., 'wapro-sync', true)`.
- Batch od agenta dzielimy na chunki po 100–200, każdy chunk to jedna akcja AS. Endpoint odpowiada `202 Accepted` z `run_id`.
- Zadania cykliczne: cleanup (codziennie), kontrola heartbeatu (co 5 min), digest.
- Retry z backoffem 1, 5, 15, 60 min. Po `max_attempts` status `dead` i alert.
- Blokada współbieżności per encja (`locked_until` albo `GET_LOCK`).

### 2.6 Własne tabele i migracje
Tworzymy je przez `dbDelta()` w klasie `Schema`. Wersja w opcji `wapro_sync_db_version`, sprawdzana na `plugins_loaded`. Migracje to klasy `Migration_000N_*`.

| Tabela | Kluczowe kolumny |
|---|---|
| `wapro_map` | `id`, `entity`, `wc_id`, `wapro_id`, `wapro_code`, `hash`, `last_sync_at`, `last_direction`, `state`; UNIQUE(entity, wc_id), UNIQUE(entity, wapro_id) |
| `wapro_jobs` | `id`, `run_id`, `type`, `direction`, `entity`, `entity_ref`, `status`, `priority`, `attempts`, `max_attempts`, `available_at`, `locked_until`, `payload` (JSON), `last_error`, `created_at`, `updated_at`; KEY(status, available_at) |
| `wapro_runs` | `id`, `source`, `stream`, `started_at`, `finished_at`, `status`, `counts` (JSON), `initiated_by` |
| `wapro_log` | `id`, `ts`, `level`, `channel`, `run_id`, `job_id`, `entity`, `entity_ref`, `message`, `context` (JSON); KEY(ts), KEY(level, ts), KEY(entity, entity_ref) |
| `wapro_agent_nonces` | `nonce`, `ts` (ochrona przed replay) |

Stan agenta trzymamy w opcji `wapro_sync_agent_state` (autoload false). Retencja: np. 30 dni, dla błędów 90. Czyszczenie przez AS w paczkach. Opcjonalny mostek do `wc_get_logger()`.

### 2.7 REST API dla agenta (`wapro-sync/v1`)
Połączenie zawsze inicjuje agent (NAT).

| Endpoint | Metoda | Opis |
|---|---|---|
| `/agent/heartbeat` | POST | wersja, host, stan SQL, backlog; w odpowiedzi komendy (resync, sync SKU, ping) i wersja configu |
| `/agent/config` | GET | ustawienia i mapowania dla agenta (ETag) |
| `/agent/catalog` | POST | słowniki z WAPRO: magazyny, cenniki, stawki VAT, formy płatności, statusy, grupy |
| `/products/batch` | POST | upsert produktów według własności pól, `Idempotency-Key` |
| `/stock/batch`, `/prices/batch` | POST | lekkie delty |
| `/orders/pending` | GET | zamówienia do eksportu (kursor, limit) |
| `/orders/{id}/ack` | POST | numer dokumentu WAPRO albo błąd |
| `/orders/{id}/status` | POST | status zwrotny, numer listu |
| `/runs` | POST/PATCH | otwarcie i zamknięcie przebiegu |
| `/admin/*` | różne | endpointy panelu (cookie + nonce `wp_rest` + capabilities) |

**Uwierzytelnianie agenta: HMAC-SHA256**
- Nagłówki `X-Wapro-Key`, `X-Wapro-Timestamp`, `X-Wapro-Nonce` oraz `X-Wapro-Signature = base64(HMAC_SHA256(secret, METHOD\nPATH\nQUERY\nTIMESTAMP\nNONCE\nSHA256(body)))`.
- Okno czasowe ±300 s, jednorazowy nonce, porównanie przez `hash_equals`, wiele kluczy dla rotacji.
- Sekret szyfrowany libsodium (klucz z `WAPRO_SYNC_ENC_KEY` albo `AUTH_KEY`), pokazywany w panelu tylko raz.
- Fallback: Application Passwords z rolą `wapro_agent`.
- `permission_callback` jest zawsze jawny. Nigdy `__return_true`.

### 2.8 Wydajność i spójność
- Stany przez `wc_update_product_stock()`, przy dużych batchach odroczona synchronizacja lookup tables.
- Hash w `wapro_map` pozwala pomijać rekordy bez zmian.
- **Pętle zwrotne**: flaga `SyncContext::$fromWapro`, żeby hooki WC nie odpalały eksportu z powrotem.
- **Własność pól**: pola ERP w edytorze tylko do odczytu (kłódka), a przy zapisie ręcznym ignorowane.

### 2.9 Uprawnienia
| Capability | Domyślnie | Zakres |
|---|---|---|
| `wapro_sync_view` | administrator, shop_manager | pulpit, logi, kolejka (odczyt), metaboxy |
| `wapro_sync_operate` | administrator, shop_manager | retry, sync pojedynczego produktu, wysłanie zamówienia |
| `wapro_sync_manage` | administrator | ustawienia, mapowania, pełny resync, klucze agenta |
| `wapro_sync_agent` | rola `wapro_agent` | tylko REST agenta |

Capabilities dodajemy przy aktywacji, a w `uninstall.php` sprzątamy tylko przy opcji „usuń dane”. Filtr `wapro_sync_capability_map` pozwala zmienić przypisania.

### 2.10 i18n
- Text Domain `wapro-sync`. `load_plugin_textdomain()` na `init`, bez `__()` przy bootstrapie (od WP 6.7 daje to notice).
- W JS `wp_set_script_translations`. Tłumaczenia generujemy przez `wp i18n make-pot`, `make-json` i `make-php`.
- Kod po angielsku, dostarczamy `pl_PL`.

### 2.11 Checklist bezpieczeństwa
- [ ] Jawny `permission_callback` wszędzie: panel przez nonce i capability, agent przez HMAC.
- [ ] Walidacja `args` i `schema`, odrzucanie nieznanych pól.
- [ ] `$wpdb->prepare()`, kolumny sortowania tylko z allowlisty.
- [ ] Escaping na wyjściu, brak `dangerouslySetInnerHTML` dla treści logów.
- [ ] Sekrety szyfrowane i maskowane, redakcja w logach.
- [ ] RODO: retencja, anonimizacja, eksportery i erasery danych osobowych.
- [ ] Ochrona przed replay, limity body i batcha, rate limiting.
- [ ] `Idempotency-Key`.
- [ ] Potwierdzenia i log audytu dla akcji destrukcyjnych.
- [ ] `defined('ABSPATH') || exit;`, tylko JSON (bez `unserialize` danych z zewnątrz).
- [ ] Wymuszony HTTPS dla REST agenta.
- [ ] Prefiksowanie zależności Composera (Strauss lub PHP-Scoper).

---

## 3. Struktura wtyczki i ekrany

### 3.1 Drzewo katalogów
```
wapro-sync/
├── wapro-sync.php                # nagłówek, stałe, autoload, Plugin::boot(), deklaracje HPOS
├── uninstall.php
├── composer.json                 # PSR-4: "WaproSync\\": "src/"; strauss; phpcs (WPCS), phpstan
├── package.json                  # @wordpress/scripts
├── languages/
├── assets/src/
│   ├── admin/index.tsx           # SPA: router zakładek
│   ├── admin/store/              # @wordpress/data store 'wapro-sync/admin'
│   ├── admin/screens/            # Dashboard, Settings/*, Mappings/*, Logs, Jobs, Runs, Tools
│   ├── admin/components/         # KpiCard, AgentStatus, MappingTable, JsonViewer, ConfirmDialog
│   └── metabox/{product,order}.ts
├── build/
├── src/
│   ├── Plugin.php
│   ├── Infrastructure/
│   │   ├── Database/{Schema.php, Migrator.php, Migrations/}
│   │   ├── Repository/{MapRepository, JobRepository, RunRepository, LogRepository}.php
│   │   ├── Crypto/SecretBox.php
│   │   └── Settings/{Settings.php, SettingsSchema.php}
│   ├── Rest/
│   │   ├── Auth/{HmacAuthenticator.php, AgentPermission.php}
│   │   ├── Agent/{Heartbeat, Config, Catalog, Products, Stock, Prices, Orders, Runs}Controller.php
│   │   └── Admin/{Dashboard, Logs, Jobs, Mappings, Settings, Tools}Controller.php
│   ├── Sync/
│   │   ├── Queue/{JobDispatcher.php, JobWorker.php, RetryPolicy.php, Lock.php}
│   │   ├── Handlers/{ProductUpsert, StockUpdate, PriceUpdate, OrderExport, OrderStatusImport, CustomerMatch}.php
│   │   ├── Mapping/{FieldOwnership.php, TaxMapper.php, StatusMapper.php, ...}
│   │   └── SyncContext.php
│   ├── Admin/
│   │   ├── Menu.php, Assets.php
│   │   ├── ProductMetabox.php, ProductListColumns.php, ProductFieldLock.php
│   │   ├── OrderMetabox.php, OrderListColumns.php
│   │   └── Notices/{AdminNotices.php, WcInboxNotes.php}
│   ├── Notifications/{Mailer.php, Digest.php, Throttle.php}
│   ├── Security/{Capabilities.php, Redactor.php}
│   ├── Compat/{Hpos.php, SystemStatus.php, DebugTools.php}
│   └── Logging/{Logger.php, WcLoggerBridge.php}
└── tests/ (PHPUnit + wp-env, Playwright)
```
Nagłówek wtyczki: `Requires at least: 6.8`, `Requires PHP: 8.1`, `Requires Plugins: woocommerce`, `WC requires at least: 10.0`.

### 3.2 Nawigacja
`WooCommerce → WAPRO Sync` z zakładkami **Pulpit | Kolejka | Logi | Przebiegi | Mapowania | Ustawienia | Narzędzia**. Stan filtrów trzymamy w URL (linki z e-maili).

### 3.3 Ekrany i pola
- **Pulpit**
  - KPI, wykres 7 dni, ostatnie błędy,
  - alerty konfiguracyjne,
  - szybkie akcje, przełącznik „wstrzymane”.
- **Ustawienia → Połączenie**
  - klucze agenta (nazwa, ID, utworzono, ostatnie użycie, IP; generuj lub unieważnij),
  - tryb autoryzacji,
  - allowlista IP,
  - próg „offline”,
  - URL endpointu,
  - przycisk „Testuj”.
- **Ustawienia → Magazyny**
  - magazyny WAPRO (lista od agenta, checkboxy),
  - sposób liczenia stanu (suma, pojedynczy, dostępny = stan − rezerwacje),
  - bufor (szt. lub %),
  - zachowanie przy stanie ≤ 0,
  - magazyn dla dokumentów zamówień.
- **Ustawienia → Ceny**
  - poziom ceny → regularna, opcjonalnie poziom → promocyjna,
  - brutto lub netto,
  - zaokrąglenie,
  - „nie nadpisuj aktywnej promocji WC”.
- **Ustawienia → VAT**: stawka WAPRO (23, 8, 5, 0, ZW, NP) ↔ klasa podatkowa WC, z walidacją kompletności.
- **Ustawienia → Zamówienia**
  - typ dokumentu (ZO, ZO z rezerwacją, FS, PA, WZ), seria,
  - statusy kwalifikujące do eksportu, status po eksporcie i po błędzie,
  - „dopiero po opłaceniu”, automatyczna realizacja ZO,
  - artykuł transportu,
  - statusy zwrotne,
  - tworzenie kontrahenta, meta key NIP.
- **Ustawienia → Produkty i własność pól**
  - tabela pól ze źródłem prawdy (WAPRO, Woo albo tylko przy tworzeniu),
  - tworzenie produktów (draft lub publish),
  - klucz dopasowania,
  - warianty,
  - filtr „flaga e-sklep”.
- **Ustawienia → Harmonogramy**
  - interwały agenta (stany 1–15 min, ceny, pełne produkty nocą, statusy),
  - okno ciszy,
  - rozmiar batcha,
  - liczba prób i backoff.
- **Ustawienia → Powiadomienia**
  - adresy e-mail i zdarzenia,
  - digest,
  - inbox WC,
  - Slack/Teams.
- **Ustawienia → Zaawansowane**
  - retencja logów,
  - poziom logowania,
  - logowanie payloadów z redakcją,
  - usuwanie danych przy odinstalowaniu,
  - eksport i import konfiguracji.
- **Mapowania → Produkty** (DataViews)
  - kolumny: miniatura, nazwa, SKU, ID_ARTYKULU, indeks, EAN, status, ostatnia synchronizacja,
  - akcje: auto-dopasuj, powiąż ręcznie (modal z wyszukiwarką po cache'u katalogu WAPRO), odłącz, sync, import CSV.
- **Mapowania → Kategorie, Płatności, Wysyłka, Statusy, Klienci**: dwukolumnowe formularze z `ComboboxControl` i walidacją kompletności.
- **Kolejka**
  - kolumny: ID, typ, kierunek, encja, status, próby, następna próba, błąd,
  - akcje: retry, anuluj, dead-letter, podgląd.
- **Logi**
  - kolumny: czas, poziom, kanał, encja, komunikat, run,
  - filtry i wyszukiwanie,
  - kontekst JSON, eksport CSV.
- **Przebiegi**
  - kolumny: źródło, strumień, czas trwania, liczniki, status,
  - kliknięcie otwiera logi i joby tego przebiegu.
- **Narzędzia**
  - resync z dry-run,
  - sync SKU, wysłanie zamówienia,
  - przebudowa mapowań,
  - czyszczenie kolejki,
  - raport diagnostyczny,
  - reset kluczy.
- **Metaboxy** pobierają dane z `/admin/entity/{type}/{id}`, a przyciski wołają `/admin/tools/*`.

---

## 4. Źródła
- https://developer.woocommerce.com/docs/extensions/settings-and-config/working-with-woocommerce-admin-pages/
- https://github.com/woocommerce/woocommerce-admin/blob/main/docs/page-controller.md
- https://developer.woocommerce.com/2026/07/08/settings-ui/
- https://developer.woocommerce.com/2026/07/08/unifying-extension-settings-in-woocommerce/
- https://developer.woocommerce.com/docs/features/orders/high-performance-order-storage/recipe-book/
- https://developer.woocommerce.com/2026/06/02/product-editor-beta-retiring/
- https://actionscheduler.org/api/
- https://developer.woocommerce.com/2026/06/17/changes-to-action-scheduler/
- https://developer.woocommerce.com/2026/09/08/from-php-7-4-to-8-1/
- https://woocommerce.github.io/code-reference/classes/Automattic-WooCommerce-Admin-Notes-Notes.html
- https://developer.wordpress.org/block-editor/reference-guides/packages/packages-dataviews/
- https://developer.wordpress.org/news/2026/01/how-to-use-dataform-to-create-plugin-settings-pages/
- https://make.wordpress.org/core/2026/03/04/dataviews-dataform-et-al-in-wordpress-7-0/
- https://github.com/juanma-wp/dataviews-dataform-examples
- https://developer.wordpress.org/rest-api/using-the-rest-api/authentication/
- https://wordpress.org/plugins/baselinker-woo/
- https://integratory.pl/produkt/wfsync-wapro-mag-woocommerce/
- https://wf-mag.com.pl/integrator/130-integrator-woo-commerce-wapro-mag
