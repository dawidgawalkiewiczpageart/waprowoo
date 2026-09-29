# WAPRO Mag: możliwości integracji, schemat bazy, wykrywanie zmian

> **Metodologia.** Część stron (wapro.pl, pomoc.wapro.pl, waproerp.blog, goldenline, docplayer) była dostępna tylko przez streszczenia wyszukiwarki. Najmocniejsze źródło to publiczny kod, który odpytuje bazę WAPRO: integracja YetiForce CRM oraz projekt `leerichie/strefaciszy`.
> - **[KOD]** potwierdzone działającym kodem SQL z GitHuba,
> - **[DOK]** potwierdzone w dokumentacji Asseco, na forum lub u integratora,
> - **[HIP]** hipoteza do weryfikacji na prawdziwej bazie (`sp_help`, `INFORMATION_SCHEMA`, SQL Profiler).

---

## 1. Możliwości integracji

### 1.1 Bezpośredni dostęp do MS SQL
- Dane w MS SQL Server, schemat `dbo` **[DOK][KOD]**. Instalacje często działają na **SQL Express** **[KOD]**.
- **Odczyt**: `SELECT` z `WITH (NOLOCK)` / `READ UNCOMMITTED` i `SET LOCK_TIMEOUT` (nie blokujemy operatorów). Tak robią YetiForce, strefaciszy i WfSync **[KOD][DOK]**.
- **Unikać surowych `INSERT`/`UPDATE`** na tabelach biznesowych. Program trzyma dane pochodne (rezerwacje, stany tymczasowe, numerację, sumy nagłówków). Znany błąd przy złym zapisie: „niezgodność pomiędzy stanem faktycznym a tymczasowym” **[DOK]**.
- Osobny login z minimalnymi uprawnieniami: `SELECT` i `EXECUTE` na wybranych procedurach **[dobra praktyka]**.

### 1.2 Procedury składowane Asseco (zalecana ścieżka zapisu)
- Źródło: dokument **„Procedury SQL obsługi dokumentów w WAPRO Mag. Poradnik wdrożeniowca”** **[DOK]**.
- Procedury z przyrostkiem **`_Server`** wykonują całą logikę po stronie SQL **[DOK]**.
- **Sekwencja zakładania ZO** **[DOK, forum]**:
  1. `RM_DodajZamowienie` (`@id_firmy, @id_kontrahenta, @id_magazynu, @typ, @data (int), @semafor, @trybrejestracji, @brutto_netto`) zwraca ID zamówienia.
  2. `RM_DodajPozycjeZamowienia` (`@id_pozycji_zamowienia OUTPUT, @id_zamowienia, @id_artykulu, @kod_vat, @zamowiono, @zrealizowano, @zarezerwowano, @do_rezerwacji, @cena_netto, @cena_brutto, @cena_netto_wal, …`).
  3. `JL_PobierzFormatNumeracji_Server` pobiera format numeracji.
  4. `RM_ZatwierdzZamowienie` zatwierdza zamówienie, usuwa pozycje z ilością 0 i przelicza nagłówek.
- **[HIP]** Pełne sygnatury różnią się między wersjami. Sprawdzić je na trzy sposoby:
  - aktualny Poradnik od partnera Asseco,
  - `sys.parameters` dla procedur `RM_%` i `JL_%`,
  - **SQL Profiler / Extended Events** podczas ręcznego zapisu ZO w programie.
- `@semafor` i `@trybrejestracji` to parametry techniczne. Wartości z forum (`3000001`, `0`) trzeba zweryfikować **[HIP]**.
- „Gniazda rozszerzeń” (procedury-hooki wywoływane przez program) są dostępne w wariancie **PRESTIŻ PLUS** **[DOK]**.

### 1.3 Bufor zamówień (BZO)
- Zamówienie w buforze to szkic bez rezerwacji. Operator zatwierdza je i przenosi do rejestru. Numeracja BZO/BZD **[DOK]**.
- **Rekomendacja:** zamówienia z Woo zapisywać do bufora (BZO), a tryb ZO lub ZO z rezerwacją zostawić jako opcję w panelu. Który parametr procedury steruje buforem, ustalimy Profilerem **[HIP]**.

### 1.4 Oficjalne API i moduły
- **WebAPI Wapro Integrator** (Aprosystem): REST, JSON/XML, klucz API. Jest nakładką na tabele i procedury. Licencja ok. **1990 zł netto** plus wdrożenie **[DOK]**. Alternatywa, jeśli klient nie zgodzi się na bezpośredni dostęp do SQL.
- **Wapro Aukcje**: Allegro i BaseLinker. Przy równoległym imporcie grozi **duplikacja zamówień** **[DOK]**. Tabele mają prawdopodobnie prefiks `AUK_` **[HIP]**.
- **Gotowi integratorzy dla Woo**: WfSync, Rovens, Sellasist, SellIntegro, KID. Szczegóły w [03-rynek-i-architektura.md](03-rynek-i-architektura.md).

### 1.5 Import i eksport plików
- Wymiana danych między bazami. Grupy tabel **[DOK]**:
  - kontrahenci: `FIRMA, KONTRAHENT, KONTAKT, …`,
  - artykuły: `KATEGORIA_ARTYKULU, JEDNOSTKA, ARTYKUL, DEFINICJA_PRODUKTU, KOD_KRESKOWY, ZAMIENNIK, CENA`.
- Import/eksport TXT/CSV/XML z procedurą przed i po operacji **[DOK]**.
- **EDI XML** `ORDER v2.4` / `ORDERRSP v1.5`: wspierana ścieżka importu zamówień, ale wymaga modułu EDI i jest półautomatyczna **[DOK]**.
- XML WAPRO (Mag → Kaper/Fakir) służy do księgowania, nie do sklepu. Natywny import EPP **raczej nie istnieje** **[HIP]**.

### 1.6 Licencje i wsparcie
- Oficjalnie wspierane są: procedury z poradnika, WebAPI, moduły Aukcje i EDI. Bezpośredni zapis do tabel nie jest wspierany.
- **Aktualizacje WAPRO usuwają obce triggery** (WfSync każe je reinstalować) **[DOK]**. Aktualizacje mogą też zmienić schemat lub sygnatury, więc integracja musi sprawdzać wersję bazy.
- SQL Express: limit 10 GB, brak SQL Agenta, więc **CDC nie działa**. Change Tracking działa **[HIP: sprawdzić]**.

---

## 2. Schemat bazy

### 2.1 Artykuły
**`dbo.ARTYKUL`** **[KOD]**:
- identyfikacja: `ID_ARTYKULU` (PK), `NAZWA`, `INDEKS_KATALOGOWY`, `INDEKS_HANDLOWY`, `INDEKS_PRODUCENTA`, `KOD_KRESKOWY`, `OPIS`, `WAGA`,
- stany: `STAN`, `STAN_MINIMALNY`, `STAN_MAKSYMALNY`, `ZAREZERWOWANO`,
- ceny i VAT: `VAT_SPRZEDAZY`, `CENA_ZAKUPU_BRUTTO`, `ID_CENY_DOM`,
- powiązania: `ID_KATEGORII_TREE`, `ID_JEDNOSTKI`.

Uwagi:
- **Kartoteka jest osobna dla każdego magazynu** (`ID_MAGAZYNU`) **[DOK]**. Ten sam towar w dwóch magazynach to dwa rekordy. Łączy je **`INDEKS_KATALOGOWY`**.
- `STAN` i `ZAREZERWOWANO` to prawdopodobnie wartości zdenormalizowane. **Nigdy ich nie zapisywać** **[HIP]**.
- Pola dodatkowe artykułu istnieją, ale nazw kolumn nie potwierdziłem **[HIP]**.

Pozostałe tabele i widoki:
- **`dbo.CENA_ARTYKULU`** **[KOD]**: `ID_ARTYKULU`, `ID_CENY`, `CENA_NETTO`, `CENA_BRUTTO`.
- **`dbo.CENA`**: definicje rodzajów cen **[DOK]**. Kolumny **[HIP]**.
- **`dbo.KATEGORIA_ARTYKULU_TREE`**: `ID_KATEGORII_TREE`, `NAZWA` **[KOD]**. Obok niej `KATEGORIA_ARTYKULU` **[DOK]**.
- **`dbo.JEDNOSTKA`**: `ID_JEDNOSTKI`, `SKROT` **[KOD]**.
- **`dbo.KOD_KRESKOWY`**: dodatkowe EAN-y **[DOK]**.
- Widoki **[KOD]**:
  - `ART_ECR_MAG_V` (`ID_ARTYKULU`, `KOD_KRESKOWY`),
  - `WIDOK_ARTYKUL` (`IdArtykulu`, `JednostkaSprzedazy`),
  - **`JLVIEW_STANMAGAZYNU_RAP`** (`id_artykulu`, `stan`, `skrot`).
- **`dbo.ARTYKUL_BLOB`**: zdjęcia w bazie albo na udziale sieciowym **[DOK]**.
- `ZAMIENNIK`, `DEFINICJA_PRODUKTU` (komplety) **[DOK]**.
- **Cechy**: nazwa tabeli niepotwierdzona **[HIP]**.
- **Warianty**: brak natywnego modelu. Grupowanie według cechy, pola dodatkowego albo wzorca indeksu **[DOK]**.

### 2.2 Kontrahenci
- **`dbo.KONTRAHENT`** **[KOD]**:
  - `ID_KONTRAHENTA`, `ID_FIRMY`, `NAZWA`, `NIP`, `REGON`, `UWAGI`, `ADRES_WWW`, `DOMYSLNY_RABAT`, `ADRES_EMAIL`, `TELEFON_FIRMOWY`,
  - adres: `SYM_KRAJU`, `WOJEWODZTWO`, `POWIAT`, `MIEJSCOWOSC`, `KOD_POCZTOWY`, `ULICA_LOKAL`,
  - adres korespondencyjny: te same kolumny z przyrostkiem `_KOR`.
- **`dbo.KONTAKT`**: `ID_KONTAKTU`, `ID_KONTRAHENTA`, `IMIE`, `NAZWISKO`, `TEL`, `TEL_KOM`, `E_MAIL`, … **[KOD]**
- **`dbo.FIRMA`** (wielofirmowość), `ADRESY_FIRMY` **[KOD]**.
- `GRUPA_KONTRAHENTA`, `KLASYFIKACJA_KONTRAHENTA`, `RACHUNEK_KONTRAHENTA` **[DOK]**.
- **`dbo.MIEJSCE_DOSTAWY`**: `ID_MIEJSCA_DOSTAWY`, `FIRMA`, `ODBIORCA`, adres, `TEL`. **`dbo.DOSTAWA`**: `ID_DOKUMENTU_HANDLOWEGO`, `ID_MIEJSCA_DOSTAWY` **[KOD]**.

### 2.3 Dokumenty i zamówienia
- **`dbo.DOKUMENT_HANDLOWY`** **[KOD]**:
  - `ID_DOKUMENTU_HANDLOWEGO`, `ID_FIRMY`, `ID_KONTRAHENTA`, `ID_TYPU` (1 = FS, 3 = korekta), `NUMER`,
  - `FORMA_PLATNOSCI` (tekst), `WARTOSC_NETTO`, `WARTOSC_BRUTTO`,
  - daty: `DATA_WYSTAWIENIA`, `DATA_SPRZEDAZY`, `TERMIN_PLAT`,
  - waluta: `DOK_WAL`, `SYM_WAL`, `PRZELICZNIK_WAL`.
- **`dbo.POZYCJA_DOKUMENTU_MAGAZYNOWEGO`** **[KOD]**: `ID_DOK_HANDLOWEGO`, `ID_ARTYKULU`, `ILOSC`, `KOD_VAT`, `CENA_NETTO`, `JEDNOSTKA`, `OPIS`, `RABAT`, `RABAT2`, `FLAGA_STANU`.
- **`dbo.ZAMOWIENIE`** **[DOK]**. Kolumny `ID_ZAMOWIENIA`, `ID_KONTRAHENTA`, `ID_MAGAZYNU`, `ID_FIRMY`, `TYP`, `DATA`, `NUMER`, `BRUTTO_NETTO` wywnioskowane z procedur **[HIP]**.
- **`POZYCJA_ZAMOWIENIA`** (`ZAMOWIONO`, `ZREALIZOWANO`, `ZAREZERWOWANO`, `DO_REZERWACJI`, `CENA_NETTO`, `CENA_BRUTTO`, `KOD_VAT`) **[HIP]**.
- `DOKUMENT_MAGAZYNOWY`, `MAGAZYN` (`ID_MAGAZYNU`, `SYMBOL`, `NAZWA`) **[HIP]**.
- VAT: `KOD_VAT` w pozycji i `VAT_SPRZEDAZY` w artykule **[KOD]**. Uwaga na kody nienumeryczne (zw, np, oo) **[HIP]**.
- `WALUTA_BAZOWA_V`, `RACHUNEK_FIRMY`, `BANKI` **[KOD]**.

### 2.4 Format dat (ważne)
Daty to **int** w formacie Clarion: `CAST(kol - 36163 AS datetime)`, a w drugą stronę `DATEDIFF(day,'1900-01-01',@d) + 36163` **[KOD+DOK]**. Czas bywa osobną kolumną w setnych sekundy **[HIP]**.

### 2.5 Skrypt weryfikacji na prawdziwej bazie
Patrz [`../../sql/discovery.sql`](../../sql/discovery.sql). Poza nim: nagrać Profilerem ręczne utworzenie ZO/BZO, zmianę ceny i zmianę statusu.

---

## 3. Mapowanie WAPRO ↔ WooCommerce

| Obszar | WAPRO Mag | WooCommerce | Uwagi |
|---|---|---|---|
| Identyfikator | `INDEKS_KATALOGOWY`, `ID_ARTYKULU` (per magazyn) | `sku`, mapa ID | SKU = indeks katalogowy. `ID_ARTYKULU` per magazyn w tabeli mapującej |
| EAN | `ARTYKUL.KOD_KRESKOWY` + tabela `KOD_KRESKOWY` | `global_unique_id` | kod główny |
| Cena | `CENA_ARTYKULU` × `CENA`, `ID_CENY_DOM` | `regular_price`, `sale_price` | rodzaj ceny konfigurowalny. Promocje i cenniki indywidualne WAPRO → B2B później |
| Netto/brutto | `CENA_NETTO`, `CENA_BRUTTO` | `prices_include_tax` | B2C: brutto, bez błędów zaokrągleń |
| VAT | `VAT_SPRZEDAZY`, `KOD_VAT` | tax classes | tabela mapowania |
| Magazyny | kartoteki per `ID_MAGAZYNU` | jeden stan | lista magazynów sklepowych, suma po `INDEKS_KATALOGOWY` |
| Stan | `STAN`, `ZAREZERWOWANO`, `JLVIEW_STANMAGAZYNU_RAP` | `stock_quantity` | dostępny = STAN − ZAREZERWOWANO **[HIP]** − bufor − niezaimportowane zamówienia |
| Jednostki | `JEDNOSTKA.SKROT` + przeliczniki | brak | ilości ułamkowe wymagają wtyczki |
| Kategorie | `KATEGORIA_ARTYKULU_TREE` | product_cat | drzewo |
| Zdjęcia | `ARTYKUL_BLOB` / udział sieciowy | media | zwykle tylko w Woo |
| Warianty | brak natywnych | variable | reguła grupowania |
| Klient | `KONTRAHENT`, `MIEJSCE_DOSTAWY` | billing/shipping | B2B: dopasowanie po NIP. B2C: kontrahent zbiorczy albo dopasowanie po e-mailu |
| Zamówienie | `RM_DodajZamowienie` + pozycje + `RM_ZatwierdzZamowienie` | order | numer Woo w uwagach lub numerze obcym, wysyłka jako artykuł-usługa, mapa form płatności |
| Statusy | automatyczne + ręczne (słownik statusów zamówień) | order status | mapowanie konfigurowalne |
| Waluta | `DOK_WAL`, `SYM_WAL`, `PRZELICZNIK_WAL` | currency | tylko przy sprzedaży w walutach |
| Firma | `ID_FIRMY` | — | stała w konfiguracji |

---

## 4. Wykrywanie zmian w MS SQL

1. **Polling po ID lub dacie**: wykrywa tylko nowe rekordy (YetiForce) **[KOD]**. Kolumna daty modyfikacji niepotwierdzona **[HIP]**.
2. **`rowversion`**: sprawdzić, czy istnieje. **Nie dodawać kolumn** do tabel producenta.
3. **SQL Server Change Tracking**: lekki, zwraca PK zmienionych wierszy, bez zmian schematu tabel, działa w Express.
   - Tabele: `ARTYKUL`, `CENA_ARTYKULU`, `ZAMOWIENIE`, `KONTRAHENT`, `KOD_KRESKOWY`.
   - Ryzyko: aktualizacja WAPRO może go wyłączyć (sprawdzać `sys.change_tracking_tables` przy starcie). Gdy wersja wyjdzie poza okno retencji, trzeba zrobić pełny resync.
   - **Kandydat na główny mechanizm, wymaga zgody klienta i admina SQL.**
4. **Triggery do własnej kolejki** (jak WfSync): aktualizacje je usuwają, a błąd triggera blokuje operatorów. Tylko minimalne i z kontrolą obecności.
5. **CDC**: nie działa w Express, niezalecane.
6. **Stany**: **okresowy snapshot** stanu dostępnego (co 1–5 min) plus hash-diff i wysyłka tylko różnic (jak `APP_PRODUCTS_SNAPSHOT` w strefaciszy) **[KOD]**.
7. **Woo → WAPRO**: polling zamówień z wtyczki i mapa `woo_order_id ↔ ID_ZAMOWIENIA` (idempotencja).

**Wniosek:**
- MVP: **hash-diff/snapshot** (zero zmian w bazie klienta).
- Później: Change Tracking jako przyspieszenie, jeśli klient się zgodzi.
- Tabele pomocnicze agenta **poza bazą WAPRO** (SQLite lokalnie albo osobna baza).

---

## 5. Najważniejsze niewiadome
1. Dokładne sygnatury `RM_DodajZamowienie` / `RM_DodajPozycjeZamowienia` / `RM_ZatwierdzZamowienie` i sposób zapisu do BZO.
2. Prawdziwe kolumny `ZAMOWIENIE`, `POZYCJA_ZAMOWIENIA`, `MAGAZYN`, `CENA` i tabel cech.
3. Wzór stanu dostępnego zgodny z tym, co pokazuje program.
4. Wersja i wydanie SQL Server (Express?).
5. Wariant licencji WAPRO Mag.

---

## 6. Źródła
**Kod**
- https://github.com/YetiForceCompany/YetiForceCRM/tree/developer/app/Integrations/Wapro
- https://github.com/leerichie/strefaciszy/tree/main/lib/API

**Asseco / WAPRO**
- https://wapro.pl/dokumentacja-erp/desktop/docs/sprzedaz-i-magazyn/wymiana-danych/mg-eksport-import-mag/
- https://wapro.pl/dokumentacja-erp/desktop/docs/aukcje-internetowe/modele-integracji/
- https://assecobs.pl/blog/jakie-integracje-e-commerce-obsluguje-wapro-mag-od-asseco/
- https://wapro.pl/rozwiazania-branzowe/webapi-wapro-integrator-rest-api/
- https://www.aprosystem.pl/webapi/docs/intro/
- https://wapro.pl/rozwiazania-branzowe/import-export-w-wapro-mag/
- https://www.waproerp.blog/wapro-mag-elektroniczna-wymiana-danych-xml/
- https://pomoc.wapro.pl/menedzer-radzi/statusy-zamowien-w-wapro-mag/
- https://www.waproerp.blog/numeracja-zamowien-z-bufora-w-wapro-mag/
- https://www.waproerp.blog/wapro-mag-import-zdjec-do-bazy/
- https://www.waproerp.blog/wapro-mag-gniazda-rozszerzen-dodatkowy-filtr/
- https://pomoc.wapro.pl/menedzer-radzi/poznaj-mozliwosci-wykorzystania-cen-i-cennikow-w-wapro-mag-czesc-ii/

**Poradnik i forum**
- https://docplayer.pl/106232407-Procedury-sql-obslugi-dokumentow-w-wapro-mag-poradnik-wdrozeniowca.html
- https://www.goldenline.pl/grupy/Komputery_Internet/wfmag-forum-uzytkownikow-oprogramowania-wfmag/tworzenie-zamowienia-zapytaniami-sql,2972358/
- https://www.goldenline.pl/grupy/Komputery_Internet/wfmag-forum-uzytkownikow-oprogramowania-wfmag/stan-faktyczny-a-tymczasowy-blad-dodawania-pozycji-zamowienia,3496563/
- https://www.elektroda.pl/rtvforum/topic3646817.html

**Integratory**
- https://pomoc.integratory.pl/wfsync-integracja-z-wapro-mag/praca-z-programem/sledzenie-zmian/
- https://pomoc.integratory.pl/technikalia/manipulacja-stanem-magazynowym-przesylanym-przez-wfsync-do-sklepu-internetowego/

**Microsoft**
- https://learn.microsoft.com/sql/relational-databases/track-changes/about-change-tracking-sql-server
- https://learn.microsoft.com/sql/t-sql/data-types/rowversion-transact-sql
