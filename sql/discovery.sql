/*
  WAPRO Mag – rozpoznanie schematu (TYLKO ODCZYT).
  Uruchomić na KOPII bazy WAPRO (SSMS / sqlcmd), wynik zapisać do docs/research/wyniki-discovery/.
  Nie modyfikuje danych.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- 0. Wersja serwera i bazy
SELECT @@VERSION AS sql_version, SERVERPROPERTY('Edition') AS edition, DB_NAME() AS db_name;

-- 1. Kolumny kluczowych tabel
SELECT t.name AS tabela, c.column_id, c.name AS kolumna, ty.name AS typ, c.max_length, c.is_nullable
FROM sys.tables t
JOIN sys.columns c  ON c.object_id = t.object_id
JOIN sys.types  ty  ON ty.user_type_id = c.user_type_id
WHERE t.name IN ('ARTYKUL','CENA','CENA_ARTYKULU','MAGAZYN','JEDNOSTKA','KOD_KRESKOWY','ARTYKUL_BLOB',
                 'KATEGORIA_ARTYKULU','KATEGORIA_ARTYKULU_TREE','KONTRAHENT','KONTAKT','MIEJSCE_DOSTAWY',
                 'ZAMOWIENIE','POZYCJA_ZAMOWIENIA','DOKUMENT_HANDLOWY','DOKUMENT_MAGAZYNOWY',
                 'POZYCJA_DOKUMENTU_MAGAZYNOWEGO','FIRMA')
ORDER BY t.name, c.column_id;

-- 2. Tabele pomocnicze: cechy, statusy, VAT, Aukcje, pola dodatkowe
SELECT name FROM sys.tables
WHERE name LIKE '%CECH%' OR name LIKE '%STATUS%' OR name LIKE '%VAT%' OR name LIKE 'AUK[_]%'
   OR name LIKE '%POLA%DODATK%' OR name LIKE '%FORMA%PLAT%'
ORDER BY name;

-- 3. Kolumny rowversion/timestamp (wykrywanie zmian)
SELECT t.name AS tabela, c.name AS kolumna
FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE ty.name = 'timestamp';

-- 4. Procedury zamówień i procedury _Server + ich parametry
SELECT p.name AS procedura, pr.parameter_id, pr.name AS parametr, TYPE_NAME(pr.user_type_id) AS typ, pr.is_output
FROM sys.procedures p
LEFT JOIN sys.parameters pr ON pr.object_id = p.object_id
WHERE p.name LIKE 'RM[_]%Zamow%' OR p.name LIKE 'JL[_]PobierzFormatNumeracji%'
ORDER BY p.name, pr.parameter_id;

SELECT name FROM sys.procedures WHERE name LIKE '%[_]Server' ORDER BY name;

-- 5. Triggery (WAPRO i obce – np. po innych integratorach)
SELECT tr.name AS trigger_name, OBJECT_NAME(tr.parent_id) AS tabela, tr.is_disabled
FROM sys.triggers tr ORDER BY tabela;

-- 6. Change Tracking – czy włączony
SELECT DB_NAME(database_id) AS db, retention_period, retention_period_units_desc
FROM sys.change_tracking_databases;
SELECT OBJECT_NAME(object_id) AS tabela FROM sys.change_tracking_tables;

-- 7. Słowniki (podgląd)
SELECT TOP 50 * FROM dbo.MAGAZYN;
SELECT TOP 50 * FROM dbo.CENA;
SELECT TOP 50 * FROM dbo.JEDNOSTKA;

-- 8. Artykuły: unikalność indeksu katalogowego między magazynami
SELECT TOP 20 INDEKS_KATALOGOWY, COUNT(*) AS ile_kartotek
FROM dbo.ARTYKUL GROUP BY INDEKS_KATALOGOWY HAVING COUNT(*) > 1 ORDER BY ile_kartotek DESC;

SELECT COUNT(*) AS artykuly, COUNT(DISTINCT INDEKS_KATALOGOWY) AS indeksy,
       SUM(CASE WHEN ISNULL(KOD_KRESKOWY,'') = '' THEN 1 ELSE 0 END) AS bez_ean
FROM dbo.ARTYKUL;

-- 9. Próbka: stan vs rezerwacje vs widok raportowy (do ustalenia wzoru stanu dostępnego)
SELECT TOP 20 a.ID_ARTYKULU, a.INDEKS_KATALOGOWY, a.NAZWA, a.STAN, a.ZAREZERWOWANO, v.stan AS stan_widok
FROM dbo.ARTYKUL a
LEFT JOIN dbo.JLVIEW_STANMAGAZYNU_RAP v ON v.id_artykulu = a.ID_ARTYKULU
WHERE a.STAN <> 0;

-- 10. Próbka cen (detaliczna/domyślna)
SELECT TOP 20 a.INDEKS_KATALOGOWY, ca.ID_CENY, ca.CENA_NETTO, ca.CENA_BRUTTO, a.VAT_SPRZEDAZY
FROM dbo.ARTYKUL a JOIN dbo.CENA_ARTYKULU ca ON ca.ID_ARTYKULU = a.ID_ARTYKULU;
