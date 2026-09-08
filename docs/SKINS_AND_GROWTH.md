# Skins, sprites e crescimento — guia prático

Este doc é o ponto de verdade para **criar arte nova** e para o sistema de **fases de crescimento**.  
Foco: você não precisa ser designer — precisa de um pipeline claro.

---

## Skins ativas (pack completo)

12 skins no `catalog.json`, todas `unlock: starter`.

No quiz: **personalidade/arquétipo** vem das respostas; a **skin é sorteada** entre as 12.

| ID | Nome |
|---|---|
| `dino-doux` | Doux |
| `dino-vita` | Vita |
| `dino-olaf` | Olaf |
| `dino-mort` | Mort |
| `dino-kuro` | Kuro |
| `dino-cole` | Cole |
| `dino-kira` | Kira |
| `dino-loki` | Loki |
| `dino-mono` | Mono |
| `dino-nico` | Nico |
| `dino-sena` | Sena |
| `dino-tard` | Tard |

Contact sheet: `docs/all-dinos-sheet.png`.

---

## 1. O que o app espera hoje

### Formato do sprite sheet (obrigatório)

- PNG horizontal (strip)
- Altura = tamanho de **1 frame**
- Largura = `altura × número_de_frames`
- Exemplo real do Mort idle: **72×24** → 3 frames de 24×24
- Fundo transparente
- Pixel art (nearest neighbor; sem blur)

Clips usados:

```
idle, move, jump, dash, hurt, kick, bite, scan, avoid
eggMove, crack, hatch   # ciclo do ovo
```

### Pastas

**Desktop**

```
apps/desktop/renderer/assets/dinos/<folder>/<stage>/<clip>.png
```

Stages: `baby` | `teen` | `adult` (com fallback para `base/` = arte Arks atual).  
Ovos: `egg/`. Evolves: `evolve-baby-teen.png`, `evolve-teen-adult.png` na pasta da skin.

**iOS**

```
apps/ios/Shared/Media.xcassets/Sheet{Name}{Clip}.imageset/          # baby / base
apps/ios/Shared/Media.xcassets/Sheet{Name}Teen{Clip}.imageset/      # teen (Mort)
apps/ios/Shared/Media.xcassets/Sheet{Name}Adult{Clip}.imageset/     # adult (Mort)
```

Naming: `SheetMortIdle`, `SheetMortTeenIdle`, `SheetMortAdultSleep`, `SheetMortEvolveBabyTeen`.

Ver implementação: `docs/GROWTH_IMPLEMENTATION.md`.

---

## 2. Dois sistemas separados (não misturar)

| Conceito | O que é | Exemplo |
|---|---|---|
| **Skin** | Quem é o companion | `dino-mort` |
| **Variant** | Cor / estilo visual | Mort gold, Mort anime |
| **Stage** | Fase de crescimento | `baby` → `teen` → `adult` (`base`) |

- Variante nova = novo ID **ou** pasta alternativa
- Crescimento = **mesma skin**, pasta de estágio diferente

---

## 3. Onde criar a arte (se você não desenha)

Escolha **uma** trilha. Da mais fácil à mais artesanal:

### A) Mais fácil — recolor / remix do pack atual (recomendado primeiro)

Base: [Arks — Dino Characters](https://arks.itch.io/dino-characters) (já no projeto).

Ferramentas:

1. **Aseprite** (pago, padrão da indústria pixel) ou **LibreSprite** (grátis)
2. Abra `idle.png` / `move.png` existentes
3. Recolor por camada/palette (rosa → dourado, etc.)
4. Exporte no **mesmo tamanho de frame**

Bom para: variantes de cor rápidas (`dino-mort-gold`).

### B) IA pixel — gerar sheets novos

Ferramentas boas para sprite sheet:

- [PixelLab](https://www.pixellab.ai/) — pensado em game sprites / animações
- [Scenario](https://www.scenario.com/) — style lock (treina no visual dos seus dinos)
- ChatGPT / Gemini / Figma AI — só se você **forçar** pixel + sheet strip; costuma precisar de limpeza no Aseprite

Prompt base (cole e ajuste a cor/fase):

```text
Pixel art dinosaur companion sprite sheet, side view, cute chibi dino,
transparent background, 24x24 pixels per frame, horizontal strip,
exactly 4 frames, thick dark outline, limited palette, clean pixels,
no anti-aliasing, no blur, no text, no shadow under character.
Animation: idle breathing loop.
Character: pink Mort-like dino, round snout, simple limbs.
```

Para **baby**:

```text
... same style ... smaller body, bigger head (chibi baby proportions),
shorter legs, same color identity as adult Mort.
```

Para **teen**:

```text
... same style ... between baby and adult, slightly taller, same silhouette language.
```

Depois: abrir no Aseprite → alinhar baseline → garantir frame size idêntico → exportar PNG.

### C) Figma (melhor para idle “bonito”, pior para animações pixel)

Use se quiser visual **anime/HQ** (não pixel).  
Doc antigo de blob: `apps/desktop/docs/FIGMA_SKINS.md`.

Para o app atual (dinos pixel), Figma é secundário — só se mudarmos `artStyle` para um renderer não-pixel.

### D) Contratar / comprar pack

- itch.io: “dino pixel sprite sheet”, “creature evolution sprite”
- Fiverr / vitrine de pixel artist: pedir **3 stages × clips mínimos**

Clips mínimos pra MVP de crescimento:

```
idle, move, jump, hurt, hatch
```

O resto pode reusar do adulto no começo (fallback no código).

---

## 4. Pipeline sugerido (do zero até no app)

```
1. Definir brief
   - skin base (ex: Mort)
   - stage (baby/teen/adult)
   - variant (opcional: gold)

2. Gerar ou recolor
   - PixelLab / Aseprite

3. Normalizar
   - frame = 24×24 (ou 32×32, mas consistente na skin)
   - strip horizontal
   - pés alinhados na mesma linha (baseline)

4. Colocar arquivos
   Desktop:
     assets/dinos/mort/baby/idle.png
     assets/dinos/mort/baby/move.png
     ...
   iOS:
     SheetMortBabyIdle.imageset/...

5. Registrar
   - catalog.json (se for skin/variant nova)
   - mapping em DinoSpriteView / skinCatalog

6. Testar
   - desktop popup + iOS widget + Live Activity
```

### Checklist de qualidade (obrigatório)

- [ ] Todos os frames da skin têm a **mesma altura**
- [ ] Personagem não “pula” entre frames (baseline fixa)
- [ ] Fundo 100% transparente
- [ ] Legível em ~64–88px na tela
- [ ] Paleta curta (≤ 8–12 cores por personagem)
- [ ] `idle` com 3–6 frames; `move` com 4–8

---

## 5. Crescimento — especificação de produto

### Stages

| Stage | Pasta | Quando |
|---|---|---|
| `egg` | `egg/` | pré-hatch (já existe) |
| `baby` | `baby/` | pós-hatch |
| `teen` | `teen/` | após tempo + cuidado |
| `adult` | `base/` | estágio final (já existe) |

### Regra inicial (simples)

- Tempo abre a oportunidade de evoluir
- Affection / missões / energia decidem se evolui “bem”
- Neglect atrasa (não mata o companion no MVP)

Sugestão numérica (ajustável):

| Transição | Tempo mínimo | Condição extra |
|---|---|---|
| egg → baby | hatch | já existe |
| baby → teen | 24–48h | affection ≥ 40 |
| teen → adult | +3–5 dias | affection ≥ 60 e missões ok |

Persistir depois: `growthStage` no Prisma + snapshot iOS (widgets).

### Resolução de arte

```
resolveSprite(skin, stage, clip):
  tenta   dinos/<folder>/<stage>/<clip>.png
  senão   dinos/<folder>/base/<clip>.png      # fallback adulto
```

Assim dá para lançar baby só com `idle`+`move` e ir completando.

---

## 6. Onde NÃO criar

- Não redesenhar no Procreate/Photoshop sem sheet strip — o player só lê strip horizontal
- Não gerar 3D / realista — o app é 2D pixel (por enquanto)
- Não criar um personagem completamente diferente por estágio (quebra o vínculo quiz → arquétipo)
- Não colocar chaves/API de IA de arte no git; só assets finais PNG

---

## 7. Ordem de trabalho recomendada

1. **Prova de conceito:** só Mort em `baby` (idle + move), fallback no resto
2. Ligar `growthStage` no código (desktop + iOS)
3. Completar `teen` do Mort
4. Replicar baby/teen para as outras 4 skins (recolor + proporção)
5. Variantes de cor (gold/neon/etc.) como unlock

---

## 8. Briefs prontos para colar na IA

### Baby Mort

```text
Create a pixel art sprite sheet for a baby pink dinosaur companion named Mort.
Transparent background. Each frame exactly 24x24 pixels.
Horizontal strip with 4 frames. Idle breathing animation.
Chibi baby proportions: big head, small body, short legs.
Same character identity as a pink cute dino mascot.
Thick outline, limited palette, no anti-aliasing, no text, no drop shadow.
```

### Teen Mort

```text
Same style and palette as baby Mort pixel dino, but teenage proportions:
slightly taller body, head still large, growing limbs.
24x24 frames, horizontal strip, 4 idle frames, transparent background,
clean pixel art, thick outline, no blur.
```

### Variant Mort Gold (adulto)

```text
Recolor this pink pixel dino adult into a gold/amber luxury palette.
Keep identical silhouette, outlines, and frame size.
Horizontal sprite sheet, transparent background, no new details that break 24x24 readability.
```

---

## 9. Decisões em aberto (vamos fechando juntos)

- [ ] Frame size oficial: manter **24×24** ou subir para **32×32**?
- [ ] Crescimento por tempo puro, por affection, ou híbrido?
- [ ] Variantes são skins novas (`dino-mort-gold`) ou campo `variant`?
- [ ] Estilo futuro anime/HQ vira `artStyle` paralelo ou substitui pixel?

Quando fecharmos isso, o próximo passo de código é: campo `growthStage` + resolver pasta `baby|teen|base` nos players de sprite.
