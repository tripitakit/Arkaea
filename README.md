> 🇮🇹 Italiano (questa pagina) · [🇬🇧 English](README.en.md)

# Arkea

**Arkea è un sandbox evolutivo persistente di organismi proto-batterici.** Pubblico target: microbiologi, genetisti, biologi molecolari, ricercatori interessati a osservare evoluzione microbica come fenomeno emergente — non come animazione preconfezionata.

I player progettano un *Arkeon* (composizione cellulare + genoma generativo) e lo introducono in un biotopo che continua a evolvere 24/7 server-side. Il fenomeno osservabile è lo stesso che guarderesti al microscopio in un sistema microbico naturale: speciazione, coevoluzione ospite-fago, displacement plasmidico, error catastrophe, syntrophy, bacterial warfare. **Niente scoreboard, niente contest loop**: l'osservazione è il fine.

## Modello biologico

Il genoma è una sequenza di codoni parsata in **11 tipi di domini funzionali** (substrate-binding, catalytic, transmembrane, channel, energy-coupling, DNA-binding, regulator-output, ligand-sensor, structural-fold, surface-tag, repair-fidelity). Ogni capacità del lignaggio — uptake, catalisi, resistenza, comunicazione, difesa — emerge dalla composizione di domini, senza cataloghi finiti né special case hardcoded.

### Meccanismi simulati end-to-end

- **Metabolismo Michaelis-Menten** su 13 metaboliti, con cicli C/N/S/Fe/H₂ chiusi e syntrophy emergente da cross-feeding stechiometrico.
- **HGT su quattro canali**: coniugazione plasmidica con entry-exclusion via inc-group, trasformazione naturale (triade competence ComEC/ComEA/ComX-like), trasduzione laterale (Chen 2018), infezione fagica con receptor matching.
- **Difese Restriction-Modification** con bypass via metilazione host (Arber-Dussoix).
- **Ciclo fagico chiuso**: induction RecA-mediated da SOS → lytic burst → virion decay → re-infection con cI/cro switch derivato dai `:dna_binding` della cassetta.
- **Mutazione + SOS response**: damage accumulation, mutator strain emergente sotto stress, error catastrophe come *theoretical ceiling* Eigen `(1−µ/L)^L > 1/σ`.
- **Quorum sensing 4D**: receptor matching gaussiano LuxR/AHL-like, drift comunicativo come meccanismo di speciazione.
- **Bacteriocine**: kin-recognition warfare con coupling obbligato producer-immunity (auto-distruzione senza immunity tag).
- **Xenobiotici e RAS**: feedback β-lattamasi-driven su pool ambientale comune con MIC dinamica.
- **Biomassa continua** (membrane / wall / DNA progress) → lisi alla divisione → produce automaticamente l'arms race loss-of-receptor.
- **Phase model intra-biotopo**: surface, water column, sediment, biofilm — ognuno con chimica, ossigenazione e dilution propri; mixing events stocastici a cadenza Poissoniana.

Ogni costante numerica è ancorata alla letteratura primaria con range biologico esplicito (vedi [`devel-docs/04-CALIBRATION.md`](devel-docs/04-CALIBRATION.md)).

## Architettura

- **Elixir + Phoenix LiveView**: rendering 100% server-authoritative, zero framework JS, zero build SPA.
- **BEAM single-node**: ogni biotopo è un processo `Arkea.Sim.Biotope.Server` con tick puro-funzionale, deterministicamente riproducibile dal seed RNG.
- **PostgreSQL via Ecto** per persistenza biotopi, lineage, audit log append-only e accounts player.
- **SVG nativo** per cromosoma circolare, scena biotope e world graph. Bundle JS ≈ 50 KB.

## Avvio locale

```bash
cd arkea
mix setup
mix ecto.migrate
mix phx.server
```

Apri [`localhost:4000`](http://localhost:4000) e crea un player dalla route `/`.

Requisiti: Erlang 28.x · Elixir 1.19.x · PostgreSQL ≥14.

## Licenza

[GNU General Public License v3.0](LICENSE) (GPL-3.0).
