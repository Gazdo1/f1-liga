# F1 Liga

Súkromná webová appka našej F1 ligy: poradie, výsledky pretekov, jazdci a sieň slávy.

**Odkaz:** https://gazdo1.github.io/f1-liga/

- Bez prihlásenia je vidno iba úvodnú stránku s prihlásením.
- Nový účet čaká na schválenie adminom, až potom vidí dáta.
- Roly: Člen (prezerá), Zapisovateľ (výsledky, kalendár, jazdci, odklady), Admin (navyše sezóny a ľudia).
- Prístup vynucuje databáza (Supabase, Row Level Security), nie iba stránka.

## Súbory
```
index.html                 – celá appka
config.js                  – URL a publishable key zo Supabase (verejný kľúč, to je v poriadku)
supabase/01_schema.sql     – kompletná schéma pre novú inštaláciu
supabase/03_migracia_z_pin.sql, 04_clenovia.sql – migrácie staršej verzie
```
Dáta ligy v repozitári nie sú.
