# Integracja WAPRO Mag ↔ WooCommerce: raport o stronie WooCommerce (stan na 09.2026)

> Zakres: tylko strona WooCommerce (REST API `wc/v3`, webhooki, HPOS, wydajność, biblioteki klienckie).
> Źródła: dokumentacja REST API v3 (pliki źródłowe repozytorium `woocommerce-rest-api-docs`), blog deweloperski WooCommerce, rejestry PyPI, npm i Packagist.

---

## 1. REST API `wc/v3`: podstawy

### 1.1 Wersje i przestrzenie nazw
- **`/wp-json/wc/v3/`** to wersja stabilna i produkcyjna. Wszystkie opisane dalej endpointy dotyczą v3.
- **`wc/v4`** jest w statusie „Development”. Pierwszy nowy endpoint to Customers v4. **Nie używać produkcyjnie.** Warstwę klienta API trzymamy w osobnym module, żeby łatwo było ją później wymienić.
- Starsze wersje API są utrzymywane przez 2 lata po wydaniu następcy.
- **Legacy REST API** (`/wc-api/v1-v3`) zostało usunięte z rdzenia w WC 9.0 i **nie działa z HPOS**. Nie używać.

### 1.2 Uwierzytelnianie
| Metoda | Kiedy | Uwagi |
|---|---|---|
| **Consumer Key/Secret + HTTP Basic Auth przez HTTPS** | **Rekomendowana** | Klucze z *WooCommerce → Ustawienia → Zaawansowane → REST API* (Read, Write lub Read/Write). |
| Klucz i sekret w query string | Gdy serwer gubi nagłówek `Authorization` (Apache/CGI) | Lepiej naprawić serwer: `SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1`. Sekret w URL trafia do logów. |
| OAuth 1.0a „one-legged” | Tylko bez HTTPS | Niepotrzebna komplikacja, lepiej wymusić HTTPS. |
| **Application Passwords** (WP 5.6+) | Alternatywa | Uprawnienia wynikają z roli użytkownika WP. Łatwe odwoływanie, ale nie da się zawęzić uprawnień do samego odczytu. |

**Rekomendacje:** dedykowany użytkownik `wapro-sync` (rola Shop Manager) z kluczem Read/Write. Połączenie tylko przez HTTPS. Klucz w sejfie lub zmiennej środowiskowej. Wyjątki WAF (Cloudflare, Wordfence) dla adresu IP agenta.

### 1.3 Limity żądań i wydajność
- **`wc/v3` nie ma domyślnego limitu żądań.** Ograniczają go PHP, MySQL, hosting i WAF. Po stronie klienta potrzebny jest throttling: 2–5 równoległych żądań, backoff przy 429/502/503/504 i obsługa `Retry-After`.
- Rate limiting Store API (25 żądań na 10 s) dotyczy tylko Store API.
- Zmiany w nowszych wersjach:
  - **WC 10.4**: leniwe ładowanie przestrzeni `wc-admin` i `wc-analytics`, czyli 30–60 ms mniej TTFB na żądaniu REST.
  - **WC 10.5**: eksperymentalny cache odpowiedzi REST. Wymaga Redis lub Memcached i dotyczy tylko GET.
  - **WC 10.7**: synchronizacja HPOS przy odczycie (sync-on-read) jest domyślnie wyłączona.
- **`_fields`** (np. `?_fields=id,sku,stock_quantity,date_modified_gmt`) wyraźnie przyspiesza pobieranie list.

### 1.4 Paginacja
- `page`, `per_page` (domyślnie 10, **maksymalnie 100**), `offset`. Nagłówki odpowiedzi: `X-WP-Total`, `X-WP-TotalPages`, `Link`.
- Przy pełnym skanie sortować `orderby=id&order=asc`. Przy synchronizacji przyrostowej używać `modified_after` zamiast głębokiej paginacji.

### 1.5 Endpointy wsadowe (batch)
- `POST /products/batch`, `/products/<id>/variations/batch`, `/products/categories/batch`, `/orders/batch`, `/customers/batch`, `/taxes/batch` itd.
- Treść żądania: `{ "create": [...], "update": [...], "delete": [ids] }`.
- **Limit: 100 obiektów na żądanie łącznie** (filtr `woocommerce_rest_batch_items_limit`). Gdy w paczce są obrazy lub kategorie, bezpieczny zakres to 25–50.
- Błąd jednego elementu nie przerywa paczki: element dostaje obiekt `error`. **Paczka nie jest transakcyjna**, więc operacje muszą być idempotentne.
- Warianty mają batch tylko w obrębie jednego produktu nadrzędnego.

---

## 2. Endpointy i pola istotne dla synchronizacji

### 2.1 Produkty `/products`
- **Identyfikacja**: `id`, `sku` (unikalny w sklepie), `global_unique_id` (GTIN/EAN, od WC 9.2, dobre miejsce na EAN z WAPRO), `type`, `status`.
- **Ceny**: `regular_price`, `sale_price`, `date_on_sale_from/to`. Ceny przekazuje się **jako string**. To, czy są brutto czy netto, zależy od ustawienia `woocommerce_prices_include_tax`.
- **Magazyn**: `manage_stock`, `stock_quantity`, `stock_status`, `backorders`, `low_stock_amount`.
- **Podatek**: `tax_status`, `tax_class` (pusty string oznacza stawkę Standard; własne klasy dla 8%, 5% i 0%).
- **Taksonomie i atrybuty**: `categories`, `tags`, `attributes`, `default_attributes`.
- **Obrazy**: `images: [{id} | {src}]`. Podanie `src` oznacza kosztowny sideload.
- **Pozostałe**: `weight`, `dimensions`, `shipping_class`, `description`, `short_description`, `meta_data`.
- **Filtry**: `sku` (kilka SKU po przecinku), `modified_after/before`, `dates_are_gmt`, `status`, `stock_status`, `type`, `category`, `include`, `orderby`.
- `GET /products?sku=XYZ` zwraca również warianty (z `parent_id`). Sprawdzić na docelowej wersji WC.

### 2.2 Warianty `/products/<id>/variations`
- Pola jak w produkcie plus `attributes: [{id|name, option}]` i jeden `image`.
- Stan magazynowy ustawiać na **wariancie**.
- WC ≥ 10.5 zawiera poprawki dla atrybutów ze znakami specjalnymi, w tym polskimi.

### 2.3 Kategorie i atrybuty
- `/products/categories` (z batchem), `/products/attributes` i `/terms`.
- Grupy towarowe WAPRO mapować tabelą `ID_GRUPY_WAPRO → term_id`, nie po slugach.

### 2.4 Zamówienia `/orders`
- **Statusy**: `pending`, `processing`, `on-hold`, `completed`, `cancelled`, `refunded`, `failed`, `trash`, `checkout-draft` i statusy własne. Do WAPRO importujemy zwykle `processing` i `on-hold`.
- **Nagłówek**: `id`, `number`, `status`, `currency`, `prices_include_tax`, `date_*_gmt`, `payment_method(_title)`, `transaction_id`, `customer_id`, `customer_note`, `total`, `total_tax`, `shipping_total`, `discount_total`.
- **`billing` i `shipping`**: pełne dane adresowe.
- **`line_items[]`**: `product_id`, `variation_id`, `sku`, `quantity`, `subtotal`, `total`, `total_tax`, `taxes[]`, `price`, `meta_data`. Pozycje w WAPRO wiązać **po SKU**, z fallbackiem przez mapowanie ID.
- **Pozostałe**: `shipping_lines[]`, `fee_lines[]`, `coupon_lines[]`, `tax_lines[]`, `refunds[]`.
- **Zapis zwrotny**: `PUT /orders/<id>` (status, meta `_wapro_doc_no`, numer przesyłki) oraz `POST /orders/<id>/notes`.
- **NIP**: WooCommerce **nie ma natywnego pola NIP**. Klucz meta zależy od wtyczki (`_billing_nip`, `billing_nip`, `_billing_vat_number`, `_wc_other/<ns>/nip` itd.), dlatego musi być **konfigurowalny w panelu**. Podobnie flaga „chcę fakturę”.

### 2.5 Klienci `/customers`
- Zamówienia gości mają `customer_id = 0`. Kontrahenta w WAPRO dopasowywać z `billing`: po NIP (firma) albo po e-mailu (osoba prywatna).

### 2.6 Podatki
- `/taxes/classes` i `/taxes`. Stawkę VAT w WAPRO mapować na `tax_class`. Przy imporcie weryfikować przez `tax_lines[].rate_percent`.

---

## 3. Webhooki i polling

### 3.1 Webhooki
- Tematy: `order.created`, `order.updated`, `order.deleted`, `product.*`, `customer.*`, `action.<hook>`.
- Podpis: `X-WC-Webhook-Signature = base64(HMAC-SHA256(surowe_body, secret))`. Porównywać funkcją stałoczasową. Ping przy zapisie webhooka (`webhook_id=N`) musi dostać odpowiedź 200.
- **Niezawodność**:
  - Dostarczanie idzie przez Action Scheduler, więc opóźnienia rzędu minut są normalne.
  - **Brak retry.** Po 5 kolejnych nieudanych dostawach webhook dostaje status `disabled`.
  - `order.updated` odpala się często, a kolejność dostaw nie jest gwarantowana.
- **Wniosek**: webhook traktować jako sygnał do kolejki i przetwarzać go idempotentnie, uzupełniając go pollingiem. Monitorować `GET /webhooks?status=disabled`.

### 3.2 Polling
- `GET /orders?modified_after=…&dates_are_gmt=true&orderby=modified&order=asc&per_page=100`.
- Zakładka 5 minut wstecz. Zapisywać `date_modified_gmt` ostatniego przetworzonego rekordu.
- **Model hybrydowy**: webhook daje niską latencję, a polling co 5–15 minut zapewnia kompletność.

> Uwaga dla naszej architektury: ponieważ i tak piszemy wtyczkę WP, webhooki na zewnątrz są zbędne. Wtyczka może sama zapisywać zdarzenia zamówień do własnej kolejki, np. przez hook `woocommerce_order_status_changed`, a agent on-prem odbiera je pollingiem z endpointu wtyczki. Agent stojący za NAT-em nie musi wtedy przyjmować ruchu przychodzącego.

---

## 4. HPOS, Store API, nowości
- HPOS jest domyślny od WC 8.2 (`wp_wc_orders*`). `wc/v3` jest w pełni zgodne z HPOS.
- **Nigdy nie czytać ani nie zapisywać zamówień bezpośrednio w MySQL.** Od WC 10.7 sync-on-read jest wyłączony, więc bezpośrednie zapisy do `wp_postmeta` prowadzą do niespójności.
- Wtyczka musi używać CRUD (`wc_get_orders`, `WC_Order::update_meta_data`) i deklarować zgodność: `FeaturesUtil::declare_compatibility('custom_order_tables', __FILE__, true)`.
- Store API (`wc/store/v1`) służy frontendowi i **nie nadaje się do integracji**.
- `global_unique_id` (GTIN) jest natywny od WC 9.2.

---

## 5. Dobre praktyki dla dużych katalogów
1. **SKU jako klucz biznesowy** plus lokalna mapa `wapro_id ↔ wc_id ↔ wc_parent_id ↔ sku ↔ hash`.
2. **Delta przez hash**: osobny lekki strumień ceny i stanu, osobny strumień pełnych danych produktu.
3. **Batch po 50–100** dla ceny i stanu, po 10–25 przy tworzeniu produktów. Jednocześnie 2–4 paczki.
4. **Idempotencja**: `update` po `id` jest idempotentny. Przy `create` najpierw sprawdzić SKU, a przy błędzie „SKU exists” przełączyć się na `update`. Zamówienia importować do WAPRO z zapisem `wc_order_id` i sprawdzać go przed utworzeniem dokumentu.
5. **Timeouty**: obrazy wysyłać osobno i asynchronicznie (`/wp/v2/media`). Nie wysyłać niezmienionych atrybutów. Włączyć Redis. Sprawdzić timeouty nginx i Cloudflare (100 s). Nie ponawiać paczek w ciemno.
6. **Własny endpoint we wtyczce** (np. `POST /wp-json/wapro-sync/v1/stock`) z `wc_update_product_stock()`, gdy batch `wc/v3` okaże się za wolny. Ponieważ i tak powstaje wtyczka z panelem, jest to naturalna ścieżka.
7. **Źródłem prawdy o stanie jest WAPRO** (stan dostępny = stan − rezerwacje). Trzeba uwzględniać zamówienia jeszcze niezaimportowane.

---

## 6. Biblioteki klienckie (09.2026)
| Język | Pakiet | Wersja | Status |
|---|---|---|---|
| Python | `WooCommerce` | 3.0.0 (03.2021) | Oficjalny, nierozwijany. Wystarczy własny klient na `httpx` z `tenacity`. |
| PHP | `automattic/woocommerce` | 3.1.1 (01.2026) | Oficjalny, aktywnie utrzymywany. |
| Node | `@woocommerce/woocommerce-rest-api` | 1.0.2 (07.2025) | Oficjalny, rozwój minimalny. |
| .NET | brak oficjalnego | n/d | `WooCommerceNET` (społecznościowy) albo własny `HttpClient`. |

---

## 7. Do potwierdzenia na docelowym sklepie
- wersja WooCommerce (zalecane ≥ 10.5) i to, czy HPOS jest włączony,
- czy `GET /products?sku=` zwraca warianty,
- klucz meta NIP i wtyczka checkoutu,
- czy ceny w sklepie są wprowadzane brutto czy netto,
- limity hostingu, WAF i object cache.

## 8. Źródła
- https://woocommerce.github.io/woocommerce-rest-api-docs/
- https://github.com/woocommerce/woocommerce-rest-api-docs/tree/trunk/source/includes/wp-api-v3
- https://developer.woocommerce.com/docs/apis/rest-api/
- https://developer.woocommerce.com/docs/apis/store-api/
- https://developer.woocommerce.com/docs/best-practices/urls-and-routing/webhooks/
- https://developer.woocommerce.com/2024/05/14/goodbye-legacy-rest-api/
- https://developer.woocommerce.com/2026/01/23/call-for-testing-experimental-rest-api-caching-in-woocommerce-10-5/
- https://developer.woocommerce.com/2026/01/14/wc-rest-api-fixes-for-product-variation-attributes-with-special-characters-in-woocommerce-10-5/
- https://developer.woocommerce.com/2026/04/15/woocommerce-10-7/
- https://yoohooplugins.com/woocommerce-hpos-migration-developer-guide-2026/
- https://www.businessbloomer.com/woocommerce-order-meta-with-hpos-and-api/
- https://make.wordpress.org/core/2020/11/05/application-passwords-integration-guide/
- https://hookdeck.com/webhooks/platforms/how-to-solve-woocommerce-5-delivery-failure-webhook-disabling
- https://github.com/woocommerce/woocommerce/issues/61312
- https://www.wpdesk.pl/blog/pole-nip-woocommerce/
- https://pypi.org/project/WooCommerce/
- https://packagist.org/packages/automattic/woocommerce
- https://www.npmjs.com/package/@woocommerce/woocommerce-rest-api
