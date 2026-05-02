# Arkea Phoenix app

Applicazione Phoenix del prototipo Arkea.

## Avvio locale

```bash
mix setup
mix ecto.migrate
mix phx.server
```

Apri poi [`localhost:4000`](http://localhost:4000).

## Flusso corrente

- `/` — crea un player o riprendi un player esistente via email
- `/world` — overview condivisa del network di biotopi
- `/seed-lab` — costruzione del seed e provisioning del primo home biotope
- `/biotopes/:id` — viewport realtime del biotopo controllato

## Comandi utili

```bash
mix test
mix assets.build
mix format --check-formatted
```
