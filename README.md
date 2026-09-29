# waprowoo: integracja WAPRO Mag ↔ WooCommerce

Dedykowana integracja systemu **WAPRO Mag** (Asseco, MS SQL Server, on-prem) ze sklepem **WooCommerce**, z rozbudowanym panelem w **wp-admin**.

> Status: **faza 0, przygotowanie.** Repozytorium zawiera research, architekturę i skrypt rozpoznania bazy. Kodu jeszcze nie ma.

## Co będzie synchronizowane
| Kierunek | Dane |
|---|---|
| WAPRO → Woo | stany (dostępne, z wybranych magazynów), ceny (wybrany cennik), produkty (według własności pól), kategorie, EAN, statusy realizacji zamówień |
| Woo → WAPRO | zamówienia (bufor BZO / ZO / …), kontrahenci (NIP / e-mail / detaliczny) |

## Komponenty (planowane)
```
agent/              .NET Worker Service (Windows) – czyta WAPRO, zapisuje zamówienia procedurami Asseco
plugin/wapro-sync/  wtyczka WP/WC – REST dla agenta (HMAC), kolejka, logi, mapowania, panel wp-admin (React + DataViews)
sql/                skrypty SQL (rozpoznanie schematu, docelowo widoki read-only)
docs/               architektura, research, pytania do klienta
```

## Dokumentacja
- [docs/ARCHITEKTURA.md](docs/ARCHITEKTURA.md): architektura, decyzje, roadmapa, ryzyka
- [docs/PYTANIA-DO-KLIENTA.md](docs/PYTANIA-DO-KLIENTA.md): lista pytań przed startem
- Research:
  - [01 – WAPRO Mag: integracja, schemat bazy, wykrywanie zmian](docs/research/01-wapro-mag.md)
  - [02 – WooCommerce REST API, HPOS, batch, webhooki](docs/research/02-woocommerce-api.md)
  - [03 – Rynek (gotowe integratory) i architektura](docs/research/03-rynek-i-architektura.md)
  - [04 – Projekt panelu wp-admin](docs/research/04-panel-wp-admin.md)
- [sql/discovery.sql](sql/discovery.sql): skrypt rozpoznania schematu (tylko odczyt), do uruchomienia na kopii bazy klienta

## Następne kroki
1. Odpowiedzi klienta na [pytania](docs/PYTANIA-DO-KLIENTA.md), kopia bazy WAPRO, staging WooCommerce.
2. `sql/discovery.sql` + nagranie SQL Profilerem ręcznego zapisu zamówienia (sygnatury `RM_*`).
3. Faza 1: szkielet wtyczki (tabele, REST HMAC, Pulpit/Logi/Kolejka/Ustawienia) + agent (heartbeat, stany, ceny).
