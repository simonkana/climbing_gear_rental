# Climbing Gear Rental

## 1. Zvolené téma

Jednoduchá MVP aplikace půjčovny lezeckého vybavení pro sportovní lezení (např. umělé stěny, boulder, lezení venku na skále). Aplikace je postavená na frameworku Ruby on Rails a vznikla jako testovací projekt pro seznámení se s Ruby on Rails.

## 2. Decisions

### Modely

Rozhodl jsem se pro dva modely: `Equipment` (vybavení) a `Reservation` (rezervace). V reálné aplikaci by dával smysl i model `Category` (např. lezečky, úvazky, lana, jistítka), ale tady mi nepřišel tak zajímavý a nutný. Dřív bych přidal třeba model `User` (viz bod 4).

Abych lépe nasimuloval reálný provoz půjčovny a navrhl aplikaci bezpečněji a víc „produkčně“, rozhodl jsem se ještě před sepsáním implementačního plánu (v konzultaci s agentem) pro následující:

- **Dual ID.** Číselné ID z databáze v URL adrese jde snadno uhodnout a postupně projít. To řeší UUID, které uhodnout prakticky nejde. Jako primární klíč ale UUID zvětšuje primární klíč, cizí klíče i indexy a náhodné UUID (v4) navíc fragmentují index při vkládání. Proto má každý záznam interní číselné `id` (primární klíč pro vazby v databázi) a automaticky generované `public_id` (UUIDv7, časově řazené, uložené jako `VARCHAR(36)`), které se používá v URL adresách. Na číselné `id` v URL aplikace odpoví stránkou 404.
- **Časový buffer po skončení rezervace (`turnaround_minutes`)**, tedy doba, po kterou je kus vybavení po vrácení ještě blokovaný. Výchozí hodnota je 60 minut, při vytvoření vybavení jde nastavit 0–1440 minut (lano má v seedech 2 hodiny). V praxi pokrývá kontrolu a vyčištění vráceného vybavení nebo menší zpoždění zákazníka při vracení. Vybavení nejde upravovat, takže se buffer nezmění pod už existujícími rezervacemi.
- **Lokalizace data a času a změna letního a zimního času.** Časy se ukládají v UTC a zobrazují v pásmu Europe/Prague v českém formátu `17. 11. 2026 14:30` (rozhraní je anglicky). Délka rezervace i buffer se počítají v absolutním čase, takže je změna času nerozhodí.
- **Algoritmus sweep line a zámek v databázové transakci**, aby se předešlo race conditions (viz bod 3).

Model `Equipment` je druh vybavení (např. „Rope 60 m“) a `capacity` je počet jeho fyzických kusů. Kromě systémových polí (`id`, `public_id`, timestamps) má povinná pole `name`, `capacity` a `turnaround_minutes` a volitelná `description` a `image_url`. Nejdůležitější validace platí i v databázi (CHECK): kladná kapacita, nezáporný buffer a `image_url` jen jako adresa `https://`.

Model `Reservation` má kromě systémových polí povinná pole `customer_name`, `customer_email`, `start_date`, `end_date` a `status` a volitelné `customer_phone`. Sloupce `start_date` a `end_date` jsou pojmenované podle zadání, ale obsahují datum i čas (po 15 minutách, délka 1 hodina až 30 dní, začátek v budoucnu a nejvýš rok dopředu). V databázi je navíc zajištěno, že konec je po začátku a že `status` je jen `active` nebo `cancelled`.

`Equipment` je ve vztahu `has_many` k `Reservation` a `Reservation` ve vztahu `belongs_to` k `Equipment` (cizí klíč v databázi). Jedna rezervace blokuje jeden kus daného vybavení. Velikosti (lezečky, úvazky) jsou samostatné záznamy, např. „Climbing shoes EU 42“.

### Validace a logika

Základní validace polí jsem nechal v modelech, což odpovídá Rails konvencím. Logiku kontroly kapacity jsem rozdělil do dvou tříd:

- `CapacityTimeline`: čistá Ruby třída bez databáze (PORO v `app/models`), která pro zadané časové okno spočítá nejvyšší počet současně blokovaných kusů (sweep line, viz bod 3).
- `ReservationBooking`: service objekt, jediná cesta, kudy se rezervace vytváří i upravuje. Zamkne vybavení, načte překrývající se rezervace, pomocí `CapacityTimeline` ověří kapacitu a rezervaci uloží, nebo vrátí chybu.

Service objekt jsem zvolil kvůli čistší architektuře, aby modely a kontrolery nebyly zahlcené touto business logikou. Kontrola kapacity záměrně není validace modelu: validace běží bez zámku, takže by ji dva souběžné požadavky mohly projít oba.

### Kontrolery

Kontroler pro vybavení má akce `index`, `show`, `new` a `create`, tedy pro vytvoření a zobrazení vybavení. Detail vybavení zobrazuje i jeho rezervace.

Kontroler pro rezervace má navíc akce `edit`, `update` a `cancel` pro úpravu a zrušení existující rezervace. Rezervace se nemaže, jen ruší: zůstane v historii a do kapacity se nepočítá. Při úpravě nejde změnit vybavení, protože by se musely zamykat dva řádky vybavení a hrozil by deadlock. Místo toho se rezervace zruší a vytvoří nová.

## 3. Proč algoritmus kontroly kapacity funguje

Při vytvoření i úpravě rezervace se v jedné databázové transakci jako první zamkne řádek daného vybavení (`SELECT … FOR UPDATE`), takže se rezervace stejného vybavení zpracují jedna po druhé a každá vidí všechny dříve uložené. Pak algoritmus sweep line spočítá skutečné maximum současně blokovaných kusů (včetně nové rezervace) v jejím časovém okně, kde každá rezervace blokuje kus od začátku do konce plus buffer. Rezervace se uloží, jen pokud toto maximum nepřekročí kapacitu, takže aplikace nepřijme rezervaci, která by kapacitu v kterémkoli okamžiku překročila, a neodmítne žádnou, která by ji nepřekročila.

Po podrobnější rešerši různých možností jsem se rozhodl pro algoritmus **sweep line**. Vezmou se aktivní rezervace daného vybavení, které se překrývají s oknem nové rezervace (při úpravě bez ní samotné), a k nim nová rezervace. Každý interval se ořízne na okno a rozloží na dvě události: začátek (+1) a konec včetně bufferu (−1). Události se seřadí podle času a při stejném čase jde konec před začátek, takže na sebe navazující rezervace se nepřekrývají. Při průchodu seřazenými událostmi se počítá průběžný součet a jeho maximum je nejvyšší počet současně blokovaných kusů.

Prosté spočítání rezervací, které se s novou překrývají, by nestačilo, protože by odmítalo i platné rezervace. Např. lezečky s kapacitou 2 jsou rezervované 8:00–10:00 a 12:00–14:00. Nová rezervace 9:00–13:00 se překrývá s oběma, ale současně se nikdy nepoužívají víc než 2 kusy (scénář S4 v seedech). Sweep line je navíc efektivní: řazení událostí stojí O(n log n), kde n je počet rezervací v okně. Porovnávání každé rezervace s každou by bylo O(n²) a dělalo by zbytečné kontroly i u rezervací, které se nepřekrývají.

Zámek zajišťuje správnost při souběhu, např. když dva zákazníci současně rezervují poslední volný kus. Druhá transakce na zámek počká, a až první skončí, vidí už její rezervaci a kontrola kapacity ji odmítne. Zámek je prvním příkazem transakce záměrně: InnoDB (REPEATABLE READ) vytváří snapshot pro čtení až při prvním běžném čtení, tedy až po získání zámku. Rezervace různého vybavení na sebe nečekají. Ověřuje to test, ve kterém 8 vláken současně rezervuje poslední volný kus a uspěje právě jedno.

## 4. Co bych udělal jinak s více časem

Přidal bych víc „produkčních“ funkcí: model `User`, role (zákazník, správce), autentizaci a autorizaci, ověřování e-mailu a telefonního čísla a platby (např. zálohy nebo vratné kauce za vybavení). Teď bez přihlášení kdokoli uvidí seznam všech rezervací se jmény zákazníků a v detailu i jejich e-mail a telefon.

Umožnil bych rezervovat víc kusů vybavení v jedné rezervaci, což teď nejde (dva úvazky jsou dvě rezervace). Úpravy rezervací i kontrola kapacity by byly složitější, ale bylo by to užitečnější a bližší reálnému provozu. Přidal bych i úpravu vybavení s kontrolou, aby kapacita neklesla pod počet už rezervovaných kusů.

Dál bych přidal notifikace a obrázky vybavení bych místo odkazu na cizí web nahrával přes Active Storage (ideálně do S3 bucketu nebo na lokální disk v Dockeru). `public_id` bych ukládal úsporněji jako `BINARY(16)` místo čitelnějšího `VARCHAR(36)` a rezervace bych chránil rate limitingem (Rails 8 `rate_limit`). Aplikaci bych nasadil na VPS s doménou, abyste ji mohli rovnou vyzkoušet bez lokálního spouštění.

Také bych refaktoroval některé části kódu a prošel automatické testy, jestli jsou všechny dostatečně relevantní, protože u produkční aplikace by zbytečné testy stály výkon a minuty v CI/CD pipeline. A víc bych se zaměřil na UX, aby bylo používání aplikace co nejpřirozenější.

## Testy

Testy používají Minitest a fixtures (výchozí v Rails). `CapacityTimeline` má samostatné unit testy hraničních případů (navazující a vnořené intervaly, maximum mimo okno, protipříklad k prostému počítání překryvů). Testy `ReservationBooking` hlídají hranice kapacity a bufferu, zrušené rezervace, úpravy rezervací, změnu času i to, že zámek je opravdu první SQL příkaz transakce. Concurrency test běží bez testovacích transakcí (data se opravdu commitují): 8 vláken s vlastním spojením odstartuje bariéra najednou a uspět smí jen jedno. Další testy ověřují scénáře ze seedů a systémové testy v prohlížeči kontrolují rozložení na desktopu i mobilu (390 px) a celou rezervaci i zrušení.

## Práce s AI

Aplikaci jsem vyvíjel s Claude Code. Rozhodnutí označená 🧑 v `IMPLEMENTATION_PLAN.md` (§2) jsem udělal sám, ostatní navrhl agent a já je zkontroloval a potvrdil. Agent se řídil pravidly v `AGENTS.md` a `GUARDRAILS.md` (např. zámek musí zůstat prvním příkazem transakce, concurrency test nesmí být nahrazen sekvenčním): každá fáze začínala plánem ke schválení a před každým commitem proběhly testy, RuboCop a Brakeman. Commity jsem dělal sám a podíl AI je vidět v `Co-Authored-By`. Ručně jsem schvaloval plány, procházel kód před commitem, kontroloval vzhled a mobilní zobrazení (původní návrh vzhledu jsem po review nechal předělat) a proklikával aplikaci. Tak jsem našel např. chybu, kdy odkaz v chybové hlášce smazal vyplněný formulář.

## Lokální spuštění a testy

Požadavky: Ruby 3.4.10 (viz `.ruby-version`) a MySQL 8.4. Gem `mysql2` potřebuje klientské knihovny MySQL (na Ubuntu balíček `libmysqlclient-dev`).

Databázový uživatel podle `config/database.yml` (spustit jako root MySQL, např. `sudo mysql`):

```sql
CREATE USER 'climbing_gear_rental'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON `climbing_gear_rental_development`.* TO 'climbing_gear_rental'@'localhost';
GRANT ALL PRIVILEGES ON `climbing_gear_rental_test`.* TO 'climbing_gear_rental'@'localhost';
GRANT ALL PRIVILEGES ON `climbing_gear_rental_test_%`.* TO 'climbing_gear_rental'@'localhost';
```

Poslední řádek je pro paralelní běh testů (Rails pro každý proces vytvoří databázi `climbing_gear_rental_test_0`, `_1`, …). Aplikace se k MySQL připojuje přes socket `/var/run/mysqld/mysqld.sock` (Ubuntu/Debian), jinde je potřeba upravit `socket` v `config/database.yml`.

```bash
bundle install
bin/rails db:setup     # vytvoří databáze, načte schéma a seedy, vypíše scénáře k vyzkoušení
bin/rails server       # http://localhost:3000
```

Seedy vytvoří 7 druhů vybavení a 15 rezervací. Scénáře jsou vždy týden ode dne spuštění seedů (`bin/rails db:seed` jde spustit znovu, smaže všechna data a scénáře posune):

- **S1 Crashpad** (kapacita 1, buffer 60 min): rezervace 10:00–18:00. Rezervace od 18:30 se odmítne (buffer), od 19:00 projde.
- **S2 GriGri** (kapacita 2): rezervace 9:00–17:00 a 13:00–20:00. Termín 15:00–16:00 se odmítne, 10:00–12:00 projde.
- **S3 Rope 60 m** (kapacita 3, buffer 2 h): téměř plné, 13:00–14:00 jsou obsazené všechny 3 kusy. Termín 12:00–15:00 se odmítne, 9:00–11:00 projde.
- **S4 Climbing shoes EU 42** (kapacita 2): rezervace 8:00–10:00 a 12:00–14:00. Termín 9:00–13:00 projde, i když se překrývá s oběma.
- **S5 Harness M** (kapacita 4): 4 rezervace 10:00–14:00, jedna zrušená, takže další 10:00–14:00 projde.
- **S6 Helmet**: dvě proběhlé rezervace, které už nejdou upravit.

```bash
bin/rails test          # 165 testů (modely, service, kontrolery, seedy, souběh)
bin/rails test:system   # 10 testů v headless Chrome (desktop a mobil 390 px)
bin/ci                  # RuboCop, bezpečnostní audity, Brakeman, všechny testy a seedy
```

Systémové testy nepotřebují ručně instalovaný prohlížeč: Selenium Manager při prvním spuštění stáhne Chrome for Testing 157 a chromedriver (potřebuje internet). Verze je zafixovaná, protože Chrome 158 odmítá reset úložiště, který mezi testy posílá Capybara 3.40.

## Zdroje

Fotky vybavení jsou odkazované z Wikimedia Commons (`https://commons.wikimedia.org/wiki/File:<název souboru>`):

- Rope: „Climbing Rope.jpg“, Climber.Ben.Johnson, CC BY-SA 4.0
- Harness: „Baudrier.jpg“, Savant-fou, CC BY-SA 3.0
- GriGri: „Petzl Grigri 2.jpg“, Climber.Ben.Johnson, CC BY-SA 4.0
- Shoes: „Climbing shoes Rockempire.jpg“, Malis, public domain
- Quickdraws: „Quickdraw Singingrock 1.jpg“, Malis, public domain
- Helmet: „Climbing helmet Petzl Meteor - 1.jpg“, Malis, public domain
- Crashpad: „Bouldering Crash Pad.jpg“, Mark Donoher, CC BY 2.0

Font Figtree (The Figtree Project Authors), SIL Open Font License 1.1, licence v `app/assets/fonts/OFL.txt`.
