# Pytania do klienta przed startem

## WAPRO i infrastruktura
1. Wersja i wariant WAPRO Mag (Start / Biznes / Prestiż / Prestiż Plus)? Desktop on-prem czy WAPRO Anywhere / Online?
2. Wersja i wydanie SQL Server (Express / Standard)? Kto administruje serwerem?
3. Czy agent może działać jako usługa Windows na serwerze SQL albo innym Windows w LAN? Czy jest wychodzący HTTPS? Zdalny dostęp dla wsparcia?
4. Kto jest partnerem WAPRO klienta? Czy zgadza się na integrację (odczyt SQL, wywołania procedur `RM_*`)? Czy ma aktualny „Poradnik wdrożeniowca”?
5. Czy możemy dostać **kopię bazy WAPRO** na środowisko testowe?
6. Czy klient używa Wapro Aukcje, Base (BaseLinker), Apilo lub innego integratora? (ryzyko duplikacji zamówień i stanów)
7. Czy dopuszczalne są zmiany w bazie: osobny schemat z widokami albo włączenie Change Tracking?

## Produkty, stany, ceny
8. Liczba artykułów ogółem i w sklepie? Jak oznaczane są artykuły „do sklepu” (grupa, pole dodatkowe, cecha)?
9. Czy produkty w Woo już istnieją? Łączymy je po SKU = indeks katalogowy czy po EAN?
10. Z których magazynów liczyć stan? Odejmować rezerwacje? Bufor bezpieczeństwa?
11. Częstotliwość aktualizacji stanów (np. co 5 min)?
12. Który rodzaj ceny (cennik) dla sklepu? Ceny brutto czy netto? Promocje prowadzone w WAPRO czy w Woo?
13. Warianty (rozmiar, kolor): jak są zapisane w WAPRO?
14. Opisy, zdjęcia, kategorie: gdzie są prowadzone, kto jest ich właścicielem?
15. Jednostki ułamkowe (kg, m)?

## Zamówienia i klienci
16. Jaki dokument ma powstać z zamówienia: bufor (BZO), ZO, ZO z rezerwacją, FS / PA, WZ? Seria numeracji? Magazyn?
17. Od jakiego statusu Woo przenosić zamówienie (np. `processing` po opłaceniu, `on-hold` dla przelewu / pobrania)?
18. Klienci: jeden kontrahent „detaliczny” dla osób prywatnych czy zakładanie nowych? Dopasowanie firm po NIP?
19. Jaka wtyczka dodaje pole NIP i „chcę fakturę” w checkoutcie (klucz meta)?
20. Mapowanie metod dostawy (usługa lub artykuł „transport” w WAPRO) i płatności (formy płatności WAPRO)?
21. Które zdarzenia w WAPRO mają zmieniać status w Woo (realizacja ZO, wystawienie FS, WZ)? Numery przesyłek: skąd?
22. Faktury: kto wystawia (WAPRO czy wtyczka sklepu)? KSeF? Udostępniać PDF w koncie klienta?

## WooCommerce i panel
23. Wersja WP i WooCommerce, HPOS, hosting (limity PHP, WAF / Cloudflare, Redis)? Czy jest staging?
24. Panel: podmenu „WooCommerce → WAPRO Sync” czy osobna pozycja w menu? Kto ma dostęp (administrator, shop manager)?
25. Powiadomienia: kto dostaje alerty (e-mail, Slack / Teams), jakie progi?
26. Wymagania RODO dotyczące retencji logów z danymi klientów?
27. SLA: kto reaguje na błędy integracji?

## Biznes
28. Czy rozważano gotowe integratory (WfSync ok. 1,2 tys. zł, Rovens, Sellasist)? Co przesądziło o rozwiązaniu dedykowanym?
