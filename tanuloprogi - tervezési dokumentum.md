# Degree Atlas – tervezési dokumentum

Nov 23, 2026 · @Tamasi Krisztian Erik

## Vízió

Nyílt forrású eszköz, amely bármely egyetemi szak tárgyaiból négy mélységi szinten (L0–L3) generál tananyagot, valós egyetemi tárgylisták alapján.

- **Kiindulópont:** az egyetemi tudás nyilvánosan elérhető (jegyzetek, előadások, cikkek, sok nyelven), de szét van szórva, és nincs szintekre bontva.
- **Cél:** bárki megismerhesse egy idegen szakma, alapjait, és ott mélyüljön tovább, ahol szüksége van rá.
- **Elv:** azt tanítja, amit a szakma valóban megkövetel, nem azt, ami érdekes. A kötelező tárgyak sorrendje dönt, a felhasználó csak a szakot és a célszintet választja meg.
- **Szerkezet:** a tárgyak a szakok között megosztottak. Egy tárgy egyszer készül el, és minden szak hivatkozik rá, amelyik tartalmazza. Így a szakok hálózattá állnak össze (DAG).
- **Működés:** a generálás terminálból, Claude Code-dal fut, a kimenet a `data/` mappába kerül, egy Flutter alkalmazás pedig megjeleníti.

A "Degree Atlas" munkanév. A "Learn Anything" név foglalt (lásd a következő szakaszt).

## Meglévő projektek

Ebben a kombinációban nem találtunk létező projektet: valós tantervekből indul, rögzített L0–L3 szintekkel dolgozik, és nyílt forrású agent generálja a tartalmat. Részek viszont léteznek.

| Projekt | Mit csinál | Miben más |
| --- | --- | --- |
| [Learn Anything](https://github.com/nikitavoloboev/learn-anything) | Nyílt forrású (MIT), mind mapek és közösségi tanulási utak, kb. 16 ezer csillag | Linkeket gyűjt, tartalmat nem generál, nem tanterv alapú. A név foglalt. |
| [Oboe](https://techcrunch.com/?p=3044797) | Egy promptból kurzust generál, agentek auditálják a pontosságot | Zárt, kereskedelmi. Témákra épít, nem egész szakokra. |
| [Metacademy](https://foldl.me/2014/metacademy) | Nyílt forrású fogalmi függőségi gráf forrásokkal | 2014 körüli projekt, AI és generálás nélkül. |
| OSSU-szerű tantervek | Kézzel összeállított "ingyenes szak" listák | Kevés szak, csak linkek, saját tartalom nincs. |
| [Open Syllabus](https://docs.opensyllabus.org/) | Kb. 33 millió szillabusz kb. 11 000 intézményből | Adatforrás, nem tanulóeszköz. Nem szabadon letölthető, ezért nem építünk rá. |

A különbségünk: egyetemi tantárgyakból indulunk, több mélységi szint van, a projekt nyílt forrású, és helyi fájlokkal dolgozik.

## Szintek

Minden tárgy négy szinten készülhet el. Egy szint csak akkor generálódik, ha az előtte lévő már kész van.

| Szint | Cél | Terjedelem | Forrás | Gyakorlás |
| --- | --- | --- | --- | --- |
| L0 – ELI5 | A tárgy koncepciója, fő módszerei és tanulságai érthetően | kb. 1 oldal | Egyetemi tárgyleírás, jegyzet | Nincs |
| L1 – Alapok | A fő gondolatok koherensen, a kulcsfogalmakkal | 3–4 oldal | Egyetemi jegyzetek, OCW-anyagok | Ellenőrző kérdések |
| L2 – Mester szintű gyorstalpaló | Módszerek, levezetések, tipikus problémák | Kb. egy jegyzet terjedelme | Jegyzetek, tankönyvi források | Megoldott feladatok |
| L3 – Kutatási front | Hol tart ma a szakma, nyitott irányok | Változó | Friss review-k, arXiv, konferenciák | Nyitott kérdések |

- **Forráskötelezettség:** L1-től felfelé minden állításnak forrása van. L3-nál jelölni kell, ha egy forrás preprint, és még nem esett át szakmai lektoráláson.
- **Képlet:** LaTeX, a megjelenítő kirajzolja.
- **Fogalmi zártság:** egy szint csak olyan fogalmat használhat, amit az előfeltétel-tárgyak az adott szinten már bevezettek. Ezt a verifier ellenőrzi.
- **Frissesség:** az L0–L2 szint stabil. Az L3 elavul, ezért dátummal készül, és újragenerálható.

## Seed adat

Az alap hálózat három egyetem összes szakából és tárgylistájából épül fel, minden képzési szinten (BSc, MSc, PhD). Kontinensenként egy egyetemet választottunk, és mindhárom jól feldolgozható.

| Egyetem | Miért | Forrás |
| --- | --- | --- |
| MIT | Strukturált OpenCourseWare, sok tárgyhoz teljes jegyzettel, ez az L1–L2 forrása | OCW és a tárgykatalógus |
| ETH Zürich | Erős mérnöki és természettudományos kínálat, nyilvános tárgykatalógus | Tárgykatalógus |
| NUS (Szingapúr) | Nyilvános JSON API, az előfeltételek és/vagy fában vannak benne | [NUSMods API](https://apis.io/apis/nus/nus-modules-api/) |

### Összepárosítás tartalom alapján

A cél nem a hivatalos tantervek pontos másolása. Annyi kell, hogy ami tartalomban nagyjából ugyanaz, az egy tárgy legyen.

1. Minden tárgyból megvan a cím, a leírás és a témakörök, nyelvtől függetlenül.
2. A mapper agent a tartalom alapján dönti el, hogy két tárgy ugyanaz-e. Például a "Control Systems", a "Regelungstechnik" és a "Feedback Control" egyetlen tárgy lesz.
3. Az összevont tárgy kanonikus azonosítót kap, a különböző nevek aliasként maradnak meg.
4. Ha az egyik egyetem két tárgyban tanítja azt, amit a másik egyben, a tartalmi átfedés dönti el, hogy összevonja-e őket.
5. A szakok csak tárgylisták. Ha egy tárgy több szakban is szerepel, az a közös pont a hálózatban.

A seed után a hálózat bővíthető új egyetemekkel és szakokkal, a meglévő tárgyak újragenerálása nélkül.

## Pipeline és agentek

Négy agent dolgozik egymás után. A scout és a mapper egyszer fut a seedre, utána új egyetemek és szakok hozzáadásakor. A writer és a verifier tárgyanként és szintenként fut.

&#91;embedded content: pipeline · 4 agent, 1 ellenőrző hurok\]

Ha a verifier hibát talál, a writer újraírja az anyagot. A `data/` mappába csak elfogadott anyag kerül, és az app ezt jeleníti meg.

### Bővítési sorrend

A sorrendet a tanterv határozza meg, nem az érdeklődés. A felhasználó a szakot és a célszintet adja meg, a harness pedig kitölti a hiányokat.

1. A szak minden kötelező tárgyából L0.
2. Utána L1, félévsorrendben, mindig az előfeltételek után.
3. Ugyanígy L2, majd L3, a célszintig.
4. Választható tárgyhoz csak külön kérésre nyúl.
5. Már elkészült tárgyat, ha másik szakban is szerepel, nem generál újra.

## Modellválasztás

Minden szerephez és szinthez a legolcsóbb modell kell, amelyik még megbízhatóan elvégzi a feladatot. Mivel a legtöbb tartalom L0, a költség nagy része Haikun fut.

| Szerep | Modell | Indoklás |
| --- | --- | --- |
| Scout: nyers tárgylisták szűrése | Haiku 5.5 | Mechanikus kinyerés, nagy mennyiségben |
| Writer L0, L1 | Haiku 5.5 | Forrásból tömörít, a feladat nem igényel mély következtetést |
| Mapper: tárgyak összepárosítása, előfeltételek | Sonnet 5.5 | Ha itt hibázik, az egész hálózat elromlik |
| Writer L2 | Sonnet 5.5 | Levezetések és feladatok kellenek hozzá |
| Writer L3 | Opus 5.5 | Friss kutatások szintézise |
| Verifier | Opus 5.5 | Legalább olyan erős legyen, mint az író modell, különben a hibákat is jóváhagyja |

A modell agentenként a `.claude/agents/` fájlokban állítható be. A Mythos-tier modellek ehhez a feladathoz feleslegesek.

## A data/ mappa sémája

Minden adat sima fájlban van a `data/` mappában, git alatt. A pipeline írja, a Flutter alkalmazás csak olvassa. Adatbázis nincs.

```text
data/
├── universities/
│   └── <egyetem>.json         nyers tárgylisták, ahogy a scout kinyerte
├── domains/
│   └── <domain>.json          pl. engineering, finance: szakok csoportosítása
├── degrees/
│   └── <szak>.json            képzési szint + tárgyak félévsorrendben
└── subjects/
    └── <tárgy>/
        ├── meta.json          azonosító, aliasok, előfeltételek, állapot
        ├── L0.md … L3.md      a tananyag szintenként
        ├── figures/           SVG ábrák
        └── sources.json       a felhasznált források
```

### A meta.json mezői

| Mező | Tartalom |
| --- | --- |
| id | Kanonikus azonosító, pl. control-theory |
| title | Megjelenített név |
| aliases | Az egyetemek elnevezései, egyetemmel és tárgykóddal együtt |
| summary | Pár mondatos tartalmi leírás, erre épül az összepárosítás |
| prerequisites | Más tárgyak azonosítói |
| degrees | Mely szakokban szerepel, kötelezőként vagy választhatóként |
| levels | Szintenként: állapot (nincs, kész, ellenőrizve), dátum, modell |

A degree fájl a tárgyakat félévsorrendben és kötelező/választható jelöléssel sorolja fel. Ebből jön a bővítési sorrend. A sémákat JSON Schema írja le, és minden írás után ellenőrizzük őket.

## Stack

Három réteg van: terminálból futó pipeline, fájlalapú adat és egy Flutter alkalmazás, ami csak megjelenít. Kiválasztott elemek: flutter\_markdown\_plus + LaTeX, re\_highlight, Riverpod, Syncthing.

| Réteg | Elem | Választott | Alternatíva | Szerep |
| --- | --- | --- | --- | --- |
| Pipeline | Agent futtatás | Claude Code, `.claude/agents/` | – | Agentek, agentenként beállított modellel |
| Pipeline | Batch futás | Headless mód (`claude -p`) | – | Egy egész szak generálása felügyelet nélkül |
| Pipeline | Webes források | emaf MCP | – | search, scrape, crawl, research |
| Pipeline | PDF-jegyzetek | Docling | Marker | Képletek és táblázatok kinyerése |
| Pipeline | Ábrák | matplotlib, Mermaid CLI | Graphviz | SVG-ként kerülnek a `figures/` mappába |
| Pipeline | Validálás | JSON Schema | – | Az írások szerkezeti ellenőrzése |
| Adat | Tárolás | Fájlok + git | – | Előzmények, a verifier módosításai visszakövethetők |
| Adat | Szinkron mobilra | Syncthing | git pull | A `data/` mappa átvitele a telefonra |
| App | Keretrendszer | Flutter | – | Desktop és mobil egy kódbázisból |
| App | Markdown + LaTeX | [flutter\_markdown\_plus](https://pub.dev/documentation/flutter_markdown_plus/latest/) + flutter\_markdown\_plus\_latex | [gpt\_markdown](https://pub.dev/packages/gpt_markdown) | Megjelenítés. A régi flutter\_markdown discontinued. |
| App | Képletrenderelés | flutter\_math\_fork | – | A LaTeX csomagok erre épülnek |
| App | Kódkiemelés | [re\_highlight](https://pub.dev/packages/re_highlight) | syntax\_highlight | highlight.js Dart port |
| App | SVG | flutter\_svg | – | Az ábrák megjelenítése |
| App | Fájlfigyelés | watcher (dart-lang) | `Directory.watch` | Új fájlra az app azonnal frissít |
| App | State | Riverpod | Bloc | Állapotkezelés |
| App | Navigáció | go\_router | – | Útvonalak |
| App | Ablak | window\_manager | – | Keret nélküli desktop ablak |
| App | Betűtípus | google\_fonts (Noto Serif, Noto Sans) | – | Minimalista tipográfia |

### Az alkalmazás kinézete

Notebook-szerű felület: egy tárgy egy oldal, az L0–L3 szintek összecsukható cellákban egymás alatt. Minimalista stílus: sok üres tér, törtfehér háttér, egyetlen piros akcentusszín, vékony serif címek. A szakok és tárgyak hálózata külön nézetben látható.

## Roadmap

Először egyetlen szakra kell működnie terminálból. A GUI csak akkor jön, ha a tananyag minősége már megfelel. Minden fázisnak van kilépési feltétele.

1. **Váz:** CLAUDE.md a szintdefiníciókkal, a négy agent fájl, JSON Schemák.
   - Kilépés: a sémák validálnak egy kézzel írt mintatárgyat.
2. **Egy szak, L0:** pl. Material Science a három egyetemről, scout + mapper + L0 writer.
   - Kilépés: egy tárgy sem generálódik kétszer, és az L0-k szakmailag helytállók.
3. **Mélység:** L1 és L2 ugyanerre a szakra, verifierrel és feladatokkal.
   - Kilépés: a verifier által jelzett hibák aránya elfogadható, a források ellenőrizhetők.
4. **Seed:** a három egyetem összes szaka, minden tárgyból L0.
   - Kilépés: a domain- és degree-fájlok teljesek, a közös tárgyak össze vannak kapcsolva.
5. **Flutter megjelenítő:** notebook nézet, fájlfigyelés, LaTeX, SVG.
