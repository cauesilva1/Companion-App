# Skins no Figma (originais opcionais)

Use isto só se quiser criar um personagem **seu**. Os packs Kenney/itch cobrem a coleção principal.

## Passos

1. Frame `512×512`, fundo transparente, nome `skin-idle`
2. Camadas (de baixo pra cima): `body`, `face-plate`, `eye-L`, `eye-R`, `pupil-L`, `pupil-R`, `mouth`, `blush-L`, `blush-R`, `accessory`
3. Estilo ooi: olhos grandes, outline 6–8px, poucas cores, legível em ~88px
4. Export PNG `@1x` → `idle.png`
5. Coloque em `renderer/assets/skins/<id>/idle.png` e adicione no `skins/catalog.json`

## Prompt para o Agent do Figma

```text
Create a companion character face sheet for a desktop widget (ooi / Tamagotchi style).

Canvas:
- One Frame named "skin-idle", exactly 512×512 px
- Transparent background (no solid backdrop rectangle)
- Center the character; leave ~10% padding from edges

Character design:
- Cute collectible mascot, simple silhouette readable at 88px
- Big round eyes with colored iris + black pupils + small white shine
- Soft blush cheeks, simple mouth
- Thick outline 6–8px, flat colors, max 5 colors
- No text, no UI chrome, no shadow under the whole frame
- Style: modern kawaii blob/creature (NOT realistic, NOT 3D render)

Layer structure (rename layers exactly):
1. body
2. face-plate (optional oval)
3. eye-L, eye-R
4. iris-L, iris-R
5. pupil-L, pupil-R
6. shine-L, shine-R
7. mouth
8. blush-L, blush-R
9. accessory (optional — keep small)

Constraints:
- Keep eye positions identical across variants (same rig)
- Export-ready transparent PNG named idle.png
```

## Prompt curto

```text
512×512 transparent frame. Cute ooi-style mascot, big eyes, thick outline, flat colors. Layers: body, eye-L, eye-R, pupil-L, pupil-R, mouth, blush-L, blush-R, accessory. No background, no text. Export-ready PNG.
```
