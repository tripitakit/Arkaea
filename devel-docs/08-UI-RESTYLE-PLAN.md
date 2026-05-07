# Restyling rigoroso UI Arkea

## Context

L'app è funzionalmente ricca ma visivamente disordinata: la lamentela è "troppo fancy / poco professionale / disordinata". L'audit ha confermato cause concrete:

- **Border-radius caotico**: 21 valori distinti, con picchi a `999px` (12 occ.) e `1rem` (11 occ.) — il "troppo rotondo".
- **Zero feedback su 38 `phx-click`**: nessun `phx-disable-with`, nessuno spinner, nessun focus ring (`ring-*` = 0 occorrenze).
- **Effetti "fancy"**: `radial-gradient` decorativi, `backdrop-filter: blur`, doppi `box-shadow`, `translateY(-2px)` su hover.
- **Doppia fonte di verità**: tokens arkea (radius 6/10/14) ↔ daisyUI (radius 4/8) ↔ legacy `--sim-*`.
- **Body monospace** (IBM Plex Mono) → identità "retro-tech" che oggi pesa contro il "professionale".
- **Bottoni eterogenei**: `.arkea-action-button`, `.arkea-button`, `.arkea-button--secondary`, `.arkea-world__filter`, `.arkea-biotope__header-btn`, e bottoni nudi senza classe (6+ occ.).

Decisioni utente già prese (sessione di pianificazione 2026-05-05):
1. Body **sans-serif moderno** (system-ui) — monospace solo per ID/dati tabulari/metric value.
2. **Rimuovere DaisyUI** ora.
3. **Solo dark mode**, ottimizzato.
4. **Sistema feedback bottoni completo** (phx-disable-with + spinner + focus ring + stati).

Outcome atteso: UI compatta, sobria, coerente, accessibile, senza decorazioni superflue, con feedback visivo robusto su ogni interazione.

---

## 1. Design tokens consolidati

File: `arkea/assets/css/arkea/tokens.css`

### 1.1 Border-radius scale (definitiva, applicata ovunque)

```
--arkea-radius-xs:   2px   /* chip, badge, metric */
--arkea-radius-sm:   4px   /* bottone, input, select, panel, tab */
--arkea-radius-md:   6px   /* card, modal, drawer */
--arkea-radius-pill: 999px /* SOLO status dot semantici */
```

**Eliminare** ogni occorrenza di `border-radius: 1rem`, `0.95rem`, `0.9rem`, `0.45rem`, `0.6rem`, `0.75rem`, `1.6rem`, `50%` (eccetto status dot `pill`). `999px` ammesso solo per indicatori di stato circolari (es. `.arkea-shell__brand-dot`, status dot in metric_chip se necessario).

### 1.2 Tipografia

```
--arkea-font-sans: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--arkea-font-mono: "IBM Plex Mono", "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;

--arkea-text-xs:   11px
--arkea-text-sm:   12px
--arkea-text-base: 13px   /* default body */
--arkea-text-md:   14px
--arkea-text-lg:   16px
--arkea-text-xl:   18px

--arkea-fw-regular: 400  /* body */
--arkea-fw-medium:  500  /* label, button text */
--arkea-fw-semi:    600  /* heading section */
```

`body` passa a `font-family: var(--arkea-font-sans)`. Monospace applicato solo via classe utility `.arkea-mono` o tramite `font-feature-settings: "tnum"` su selettori specifici (`.arkea-metric-chip__value`, `.arkea-table td.num`, `<code>`, lineage ID).

### 1.3 Spacing — confermato (già coerente)

`--space-1`..`--space-6` (0.25→1.5rem). Usare SOLO questi token. Vietato 0.6/0.7/0.8rem custom.

### 1.4 Surfaces (semplificate)

```
--arkea-bg          /* main */
--arkea-surface     /* panel/card */
--arkea-surface-2   /* header/footer del panel, hover row tabella */
--arkea-surface-3   /* hover/active state controlli */
--arkea-border      /* 1px solido, alpha bassa eliminata */
--arkea-border-strong  /* divisori, scrollbar */
```

### 1.5 Effetti rimossi

- Eliminare `radial-gradient` da: `world.css`, `inner.css` (access shell), `shell.css` (brand-dot resta semplice colore solido o gradient minimale `2-color`).
- Eliminare `backdrop-filter: blur` da: access page, `arkea-old-nav`.
- Doppi `box-shadow`: ridurre a singolo livello. Rimosso del tutto su hover stati (`arkea-card-link`, `arkea-access-hero`).
- `translateY(-2px)` su hover: sostituire con cambio `border-color` o `background-color`.

---

## 2. Button system unificato

### 2.1 Nuovo componente Phoenix

File NUOVO: `arkea/lib/arkea_web/components/button.ex`

```elixir
attr :variant, :string, default: "primary",
  values: ~w(primary secondary ghost danger)
attr :size, :string, default: "md", values: ~w(sm md)
attr :type, :string, default: "button"
attr :loading, :boolean, default: false
attr :icon, :string, default: nil   # heroicon name
attr :rest, :global, include: ~w(disabled form name value
                                 phx-click phx-disable-with
                                 phx-target phx-value-id)
slot :inner_block, required: true
def arkea_button(assigns)
```

Comportamento:
- Inietta automaticamente `phx-disable-with` con il testo del bottone + ellipsis se `phx-click` è presente e `phx-disable-with` non è già stato passato.
- `loading=true` o `disabled` → mostra spinner inline (`.arkea-spinner` già esistente in `tokens.css`), nasconde icona.
- Markup: `<button class="arkea-button arkea-button--{variant} arkea-button--{size}">…</button>`.

### 2.2 CSS — file NUOVO `arkea/assets/css/arkea/button.css`

Stati obbligatori, tutti visibili:

```
.arkea-button {
  /* base */
  display: inline-flex; align-items: center; gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  font-family: var(--arkea-font-sans);
  font-size: var(--arkea-text-sm);
  font-weight: var(--arkea-fw-medium);
  line-height: 1;
  border: 1px solid transparent;
  border-radius: var(--arkea-radius-sm);    /* 4px */
  cursor: pointer;
  transition: background-color 120ms, border-color 120ms, color 120ms;
  user-select: none;
}

/* hover  : surface o accent attenuato */
/* active : surface scuro / press inset 0 0 0 1px borderColor */
/* focus-visible : outline 2px solid accent; outline-offset 1px;  NO glow */
/* disabled / aria-busy : opacity .55; cursor not-allowed; */
```

Varianti:
- `--primary`: bg accent (teal), text scuro, border accent.
- `--secondary`: bg surface-2, text fg, border `--arkea-border`.
- `--ghost`: bg transparent, hover surface-2.
- `--danger`: bg accent stress, text scuro.

Sizes:
- `--sm`: padding `var(--space-1) var(--space-2)`, text-xs.
- `--md` (default).

Stato loading: aggiunge spinner via `::before`, `aria-busy="true"`, disabilita pointer.

### 2.3 Migrazione dei bottoni esistenti

Elenco file e occorrenze da convertire a `<.arkea_button>` o classe `.arkea-button`:

- `lib/arkea_web/live/audit_live.ex` (linee 67, 92, 112, 122) — refresh, filter tab, pager.
- `lib/arkea_web/live/seed_lab_live.ex` (linee 621, 665, 728, 828, 953+, 1199, 1213, 1250, 1262, 1274, 1340, 1363, 1384+).
- `lib/arkea_web/live/sim_live.ex` (linee 277, 329, 427, 498, 576, 741, 769, 805, 815, 825, 929–944).
- `lib/arkea_web/live/world_live.ex` (~79+, filter tabs).
- `lib/arkea_web/live/community_live.ex` (linea 38).
- `lib/arkea_web/live/dashboard_live.ex` (CTA card-link → diventa `.arkea-button--ghost` con icona).
- `lib/arkea_web/controllers/player_access_html/new.html.heex` (login/register).

Le **tab di filtro** (`arkea-world__filter`, audit filter) NON diventano bottoni primari: ottengono una variante dedicata `.arkea-tab` con stato `aria-selected` (border-bottom 2px accent) — vedi §4.

I bottoni "icon-only" (✕ modal close, ✕ remove) usano `.arkea-button--ghost.arkea-button--icon` (square `28×28px`, no padding lateral).

Eliminare classi obsolete: `.arkea-action-button`, `.arkea-biotope__header-btn`, `.arkea-button--secondary` (ridotto a variant del nuovo sistema), `.arkea-old-nav__link` (legacy splash → `.arkea-button--ghost`).

---

## 3. Form & input system

File NUOVO (split da `inner.css`): `arkea/assets/css/arkea/form.css`.

- `.arkea-input`, `.arkea-select`, `.arkea-textarea`, `.arkea-checkbox`: padding token-based, border 1px solido, radius 4px.
- Focus: `border-color: var(--arkea-accent-teal)`; **outline 2px** offset 1px su focus-visible. NIENTE doppio box-shadow glow attualmente in `inner.css` per `.arkea-access-form .input` (linee da identificare).
- Error: aggiunge classe `.is-invalid` → border accent stress + `<p class="arkea-form__error">` sotto.
- Label: `.arkea-form__label` text-xs, fw-medium, **non uppercase, no letter-spacing 0.1em** (rimossi gli "eyebrow" verbose).
- Fieldset: rimuovere `border-radius: 0.95rem`, sostituire con 4px o nessun border.

Aggiornare `core_components.ex` `input/1` (linee 160–297) a renderizzare i markup `.arkea-*` invece di classi daisyUI (`input input-error select select-error textarea fieldset`).

---

## 4. Tabs, tabelle, liste

### 4.1 Tabs (filtri)

File NUOVO o estensione di `button.css`: `.arkea-tab`, `.arkea-tab[aria-selected="true"]`. Border-bottom 2px accent, hover bg surface-2. Sostituisce `.arkea-world__filter` e i tab nudi in `audit_live.ex`, `sim_live.ex` (805/815/825).

### 4.2 Tabelle

In `audit.css` e `inner.css`:
- Aggiungere hover row: `tr:hover { background: var(--arkea-surface-2) }`.
- Sticky header già presente in `.arkea-audit__table`: estendere alle altre tabelle.
- Numeri allineati a destra con `font-feature-settings: "tnum"` e `font-family: var(--arkea-font-mono)`.
- Densità: padding `var(--space-2) var(--space-3)` uniforme.

### 4.3 Liste compatte (lineages, biotopes)

Riga selezionabile: stato `aria-selected="true"` con border-left 2px accent. Hover `surface-2`. No `transform: translate*` su hover.

---

## 5. Flash / notifiche

Sostituire daisyUI `alert/toast` in `core_components.ex` (linee 51–81) con CSS arkea custom:

- File NUOVO: `arkea/assets/css/arkea/flash.css`.
- Posizione: top-right, larghezza fissa 360px, max 4 visibili.
- Variants: info (border accent sky), success (growth), warning (signal/gold), error (stress/rust).
- Border 1px + bordo sinistro 3px nella tonalità del variant. **Nessun blur**, nessuna ombra drammatica.
- Heroicon a sinistra, testo, close button (ghost icon).
- Animazione: `opacity` + `translateX(8px)` 200ms — niente scale.

---

## 6. Rimozione DaisyUI

File: `arkea/assets/css/app.css`.

1. Rimuovere `@plugin "../vendor/daisyui"` e `@plugin "../vendor/daisyui-theme"`.
2. Spostare i pochi token utili (palette OKLch del tema dark) nei `:root` di `tokens.css`.
3. Rimuovere file vendor `arkea/assets/vendor/daisyui.js` e `daisyui-theme.js` (verificarne effettiva non-dipendenza).
4. In `core_components.ex`:
   - `flash/1` (51–81): markup arkea (vedi §5).
   - `button/1` (84–118): rimpiazza con delega a `Arkea.Button` o emette `<button class="arkea-button arkea-button--primary">`.
   - `input/1` (160–297): rimuove classi `input/select/textarea/checkbox/fieldset` daisyUI.
   - `header/1`, `table/1`, `list/1`, `icon/1`: verificare e portare a classi arkea.
5. In `mix.exs` e `package.json`: confermare assenza dipendenze a daisyUI residue.
6. `mix assets.build` deve passare; `priv/static/assets/css/app.css` non contiene più stringhe `daisy`.

---

## 7. Cleanup `inner.css` (1.368 righe legacy)

Split in moduli e migrazione token:

| Da `inner.css` | A | Note |
|---|---|---|
| login/access page styles | NUOVO `arkea/assets/css/arkea/access.css` | Rimuovere gradient radiali, blur, border-radius 1rem. |
| seed-lab form chrome | merge in `seed_lab.css` | |
| event-entry styles | NUOVO `arkea/assets/css/arkea/event.css` | |
| `.arkea-table` shared | NUOVO `arkea/assets/css/arkea/table.css` | unifica con `.arkea-audit__table`. |
| restanti utility (button vecchi, card) | dissolvere in `button.css` / `panel.css` | |

Tutti i `--sim-*` e `--bio-*` rimanenti → mappare su `--arkea-*`.

`app.css`: aggiornare `@import` (o lasciare al bundler) per includere i nuovi file.

---

## 8. Layout & shell — tweak puntuali

File: `shell.css`, `dashboard.css`, `world.css`, `panel.css`.

- `.arkea-shell__brand-dot`: gradient 2-colori → colore solido `--arkea-accent-teal` (più sobrio).
- `.arkea-card-link` (dashboard hover): rimuovere `box-shadow: 0 8px 24px ...` e `translateY(-2px)`. Sostituire con `border-color: var(--arkea-border-strong)` e leggero `background-color: var(--arkea-surface-2)` su hover.
- `.arkea-world__canvas`: rimuovere radial gradient di sfondo; sostituire con `background: var(--arkea-bg)` + griglia sottile via SVG pattern (1px dot, opacity 0.05).
- Eyebrow text: rimuovere `text-transform: uppercase` + `letter-spacing: 0.1em` da panel header. Mantenere font-weight 600, dimensione text-xs/sm, colore `--arkea-fg-muted`.
- `.arkea-panel`: radius da `var(--arkea-radius-md)` (10px) → `var(--arkea-radius-md)` ricalibrato a 6px (consistente con scala §1.1).

---

## 9. Feedback runtime (LiveView)

Convenzioni da applicare nei template, in coppia col nuovo `<.arkea_button>`:

- Ogni `phx-click` che fa I/O (DB, simulation step, export) → automatico `phx-disable-with="…"` con testo "Caricamento…" o testo del bottone seguito da `…`.
- Bottoni "refresh" (audit `↻`): durante il refresh mostrano spinner inline via `loading={@refreshing}` assign.
- `<.flash_group>`: animazione slide-in verificata cross-route.
- Aggiungere `:focus-visible` polyfill non necessario (browser target moderni).

---

## 10. File da creare / modificare (sintesi)

**Nuovi**:
- `arkea/lib/arkea_web/components/button.ex`
- `arkea/assets/css/arkea/button.css`
- `arkea/assets/css/arkea/form.css`
- `arkea/assets/css/arkea/flash.css`
- `arkea/assets/css/arkea/table.css`
- `arkea/assets/css/arkea/access.css`
- `arkea/assets/css/arkea/event.css`

**Modificati**:
- `arkea/assets/css/app.css` — rimozione daisyUI, body font, import nuovi moduli.
- `arkea/assets/css/arkea/tokens.css` — radius scale, tipografia, surfaces.
- `arkea/assets/css/arkea/inner.css` — svuotato/splittato (target: file eliminato).
- `arkea/assets/css/arkea/{shell,panel,dashboard,world,scene,biotope,seed_lab,audit,help,chart,phylogeny,metric}.css` — sostituire radius hardcoded, gradient, shadow, eyebrow uppercase.
- `arkea/lib/arkea_web/components/core_components.ex` — flash, button, input, header, table, list a markup arkea.
- Tutti i 9 LiveView in `arkea/lib/arkea_web/live/*.ex` — bottoni nudi → `<.arkea_button>` o classe; rimuovere classi obsolete.
- `arkea/lib/arkea_web/controllers/player_access_html/new.html.heex` — login/register stile sobrio.

**Eliminati** (dopo verifica):
- `arkea/assets/vendor/daisyui.js`
- `arkea/assets/vendor/daisyui-theme.js`
- `arkea/assets/css/arkea/inner.css` (a fine split)

---

## 11. Verifica end-to-end

1. **Build**: `cd arkea && mix assets.build` — nessun errore, nessun riferimento a `daisy*` nell'output.
2. **Test suite**: `mix test` — i test sui core_components e LiveView passano (focus su flash, button, input render).
3. **Compilazione**: `mix compile --warnings-as-errors`.
4. **Server manuale**: `mix phx.server` su `:4000`, percorrere ogni route:
   - `/` (access page) — niente glow/blur, login/register sobri.
   - `/dashboard` — 6 panel grid, hover senza translateY.
   - `/world` — filter tab funzionanti con stato aria-selected, sfondo SVG senza radial gradient.
   - `/seed-lab` — bottoni di palette domini con classe coerente, focus ring visibile in tab navigation.
   - `/biotopes/:id` — bottoni intervention con `phx-disable-with` attivo durante click; modal close icon-only ghost.
   - `/biotopes/:id/hgt-ledger`, `/audit` — tabelle con hover row, sticky header, allineamento numerico monospace.
   - `/help`, `/community`, `/search` — chrome coerente.
5. **A11y check manuale**: navigare con `Tab` ovunque, ogni elemento interattivo mostra outline 2px; nessun bottone senza nome accessibile (icon-only ha `aria-label`).
6. **Audit visivo**: `rg "border-radius: (1rem|0\.95rem|0\.9rem|999px|50%)" arkea/assets/css` ritorna solo le 1–2 occorrenze ammesse (status dot semantici).
7. **Audit feedback**: `rg "phx-click" arkea/lib/arkea_web/live` confronta con `rg "phx-disable-with"` — il rapporto deve essere ~1:1 sulle azioni async (le tab di filtro client-only sono esenti).
8. **Smoke biologico**: una run di `mix sim.demo` (se esiste) o creazione + tick di un biotope dalla UI: verificare che metric_chip, scene SVG, lineage drawer rendano correttamente con la nuova tipografia/scale.

---

## 12. Sequenza di esecuzione consigliata

1. **Tokens** (§1) — base di tutto.
2. **Button system** + componente `Arkea.Button` (§2).
3. **Form** (§3) e **Flash** (§5).
4. **Rimozione DaisyUI** (§6) + sostituzione `core_components.ex`.
5. **Migrazione bottoni nei LiveView** (§2.3).
6. **Cleanup `inner.css`** + tweak shell/dashboard/world/panel (§7, §8).
7. **Verifica** (§11).

Ogni passo è indipendente e ispezionabile via `mix phx.server`, così l'utente può approvare incrementalmente.
