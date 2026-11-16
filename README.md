# F1 Liga

Webová appka na sledovanie našej F1 ligy: poradie, výsledky pretekov, štatistiky hráčov a sieň slávy.
Dáta sú uložené v Supabase. Stránka je jeden statický HTML súbor, takže sa dá hostovať kdekoľvek (GitHub Pages, Netlify, …).

## Čo appka vie
- **Poradie**: líder, odjazdené preteky, ďalší závod, tabuľka s výhrami, pódiami a priemernou pozíciou a graf vývoja bodov.
- **Preteky**: karty s pódiom pre každý závod alebo tabuľka „ako v Exceli“ (hráči × preteky).
- **Hráči**: profil hráča so štatistikami po sezónach, poslednými pretekmi a vzájomnými súbojmi (head-to-head).
- **Sieň slávy**: šampióni sezón a historické rebríčky.
- **Správa (iba pre prihlásených s právami)**: zápis výsledkov ťukaním na hráčov v poradí dojazdu, úprava poradia potiahnutím, najrýchlejšie kolo, kalendár, hráči a odklady. Admin navyše spravuje sezóny a role.

## Odkaz
**https://gazdo1.github.io/f1-liga/** (GitHub Pages z vetvy `main`)

## Najrýchlejšie kolá
Pri zápise výsledkov sa dá označiť „NK“. Najrýchlejšie kolá sa evidujú v štatistikách (poradie, profil hráča, sieň slávy), ale body nepridávajú. Ak by ste ich niekedy chceli bodovať, nastavíš to v Admin → Sezóny.

## Štruktúra
```
index.html          – celá appka
config.js           – URL a publishable key zo Supabase
supabase/01_schema.sql – tabuľky, zabezpečenie (RLS) a funkcie
supabase/02_data.sql   – dáta prenesené z pôvodného Excelu
```

## Databáza
Databáza už beží v Supabase projekte „F1 tabulka“ a `web/config.js` je naň nastavený. Postup nižšie je iba pre prípad, že by si ju niekedy zakladal znova.

## Inštalácia od nuly
1. Supabase: SQL Editor → spusti `01_schema.sql` a potom `02_data.sql`. (`03_migracia_z_pin.sql` je iba pre staršiu verziu s PIN-om.)
2. Supabase → Project Settings → API Keys: skopíruj Project URL a Publishable key do `config.js`.
3. Nahraj `index.html` a `config.js` na hosting (tu GitHub Pages: Settings → Pages → Deploy from branch `main`).

## Účty a role
- **Bez prihlásenia** môže každý všetko prezerať.
- **Divák**: každý nový účet. Môže iba prezerať, rovnako ako bez prihlásenia.
- **Zapisovateľ**: zapisuje výsledky, upravuje kalendár, hráčov a odklady.
- **Admin**: všetko, plus sezóny a role. Prvý zaregistrovaný účet sa stane adminom automaticky.

Kamarát sa zaregistruje cez ikonu účtu vpravo hore. Admin mu potom v Správe → Používatelia a role nastaví rolu Zapisovateľ.

## Bezpečnosť
- Čítať môže ktokoľvek s linkom. Zapisovať sa dá iba cez databázové funkcie, ktoré overujú rolu prihláseného používateľa.
- Publishable key je verejný kľúč, je v poriadku, že je v stránke.

## Supabase free plán
Projekt na free pláne sa pozastaví po 7 dňoch bez aktivity. Každé otvorenie appky sa počíta ako aktivita. Ak sa projekt predsa pozastaví, obnovíš ho v Supabase dashboarde jedným klikom („Restore project“).
