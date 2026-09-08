# Implementação de crescimento (growth) — sem quebrar o app atual

## Status atual

**Growth visual / evolve DESLIGADO** (`GROWTH_ENABLED = false` em `src/growth.ts`, `Growth.isEnabled = false` no iOS).

Motivo: arte teen/adult Gemini ficou escura demais e as strips de evolve estão estranhas.  
O app usa só **`base/` (Arks)** — cores normais. Código e assets ficam no repo para religar depois.

Para religar: `GROWTH_ENABLED = true` + `Growth.isEnabled = true` + desktop `GROWTH_VISUALS = true` em `clipCandidates`.

---

## Ideia (quando religar)

- **Skin** = quem é o dino; **`growthStage`** = baby → teen → adult.
- **`growthStageAt`**: relógio de permanência na fase.
- Sprite: `…/<stage>/<clip>.png` → fallback `base/`.
- Escala: baby `0.88`, teen `1.0`, adult `1.14`.
- Evolve one-shot + voz por fase (limites de palavras).

## Progressão planejada

| De → Para | Dias na fase | Affection |
|---|---|---|
| baby → teen | 7 | 55 |
| teen → adult | 14 | 70 |

## Voz por fase (código pronto; com flag off fica em “baby”)

| Stage | Tom | Máx. palavras |
|---|---|---|
| baby | simples, grudento | 10 |
| teen | mais atitude | 16 |
| adult | mais maduro | 22 |

## Arte

| O quê | Pasta |
|---|---|
| Masters | `art/growth/` |
| Desktop Mort | `apps/desktop/renderer/assets/dinos/mort/{baby,teen,adult}/` |
| Preview FPS | `docs/mort-anim-preview.html` |

## Migrações

`growthStage` + `growthStageAt` já no schema — ok manter mesmo com feature off.
