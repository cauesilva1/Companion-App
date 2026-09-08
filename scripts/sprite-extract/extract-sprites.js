/**
 * extract-sprites.js
 *
 * Importante: teen-grid.png NÃO está alinhado em células 32×32 limpas.
 * Os sprites da 3ª fila visual começam ~y=59 (não y=64). Por isso um
 * extract fixo left:0,top:64 corta o dino ao meio.
 *
 * Este script:
 *  - Adult: crop fixo 32×32 (grid limpa)
 *  - Teen: deteta bounding boxes por conteúdo e recentra em células 32×32
 *
 * Uso: node scripts/sprite-extract/extract-sprites.js
 */
const path = require("path");
const fs = require("fs");

let sharp;
try {
  sharp = require("sharp");
} catch {
  sharp = null;
}

const DIR = __dirname;
const FRAME = 32;
const STRIP_W = FRAME * 4;

function mustExist(file) {
  if (!fs.existsSync(file)) throw new Error(`Missing ${file}`);
}

async function extractAdultWithSharp() {
  const adult = path.join(DIR, "adult-grid.png");
  mustExist(adult);

  await sharp(adult)
    .extract({ left: 0, top: 0, width: STRIP_W, height: FRAME })
    .png()
    .toFile(path.join(DIR, "adult-move.png"));
  console.log("✓ adult-move.png (grid 32 @ y=0)");

  // Real idle from row 6 (y=160) — melhor que fake
  await sharp(adult)
    .extract({ left: 0, top: 160, width: STRIP_W, height: FRAME })
    .png()
    .toFile(path.join(DIR, "adult-idle.png"));
  console.log("✓ adult-idle.png (grid 32 @ y=160 breathing)");
}

/**
 * Teen: use content-aware crop via raw pixels + sharp.
 * Walk band ≈ y 58–78; take first 4 sprites, center into 32×32, feet-aligned.
 */
async function extractTeenContentAware() {
  const teenPath = path.join(DIR, "teen-grid.png");
  mustExist(teenPath);

  const { data, info } = await sharp(teenPath).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const w = info.width;
  const h = info.height;

  const isContent = (x, y) => {
    const i = (y * w + x) * 4;
    const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
    return a > 200 && !(r < 30 && g < 30 && b < 30);
  };

  function findBoxes(y0, y1, minW = 12, maxN = 4) {
    const colDens = new Array(w).fill(0);
    for (let y = y0; y < y1; y++) {
      for (let x = 0; x < w; x++) if (isContent(x, y)) colDens[x]++;
    }
    const bands = [];
    let inB = false, s = 0;
    for (let x = 0; x < w; x++) {
      if (colDens[x] > 2 && !inB) {
        inB = true;
        s = x;
      } else if (colDens[x] <= 2 && inB) {
        inB = false;
        if (x - 1 - s + 1 >= minW) bands.push([s, x - 1]);
      }
    }
    if (inB && w - s >= minW) bands.push([s, w - 1]);

    const boxes = [];
    for (const [a, b] of bands.slice(0, maxN)) {
      let minY = y1, maxY = y0;
      for (let y = y0; y < y1; y++) {
        for (let x = a; x <= b; x++) {
          if (isContent(x, y)) {
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      boxes.push({ left: a, top: minY, right: b, bottom: maxY });
    }
    return boxes;
  }

  async function boxesToStrip(boxes, outName) {
    const frames = [];
    for (const box of boxes) {
      const pad = 1;
      const left = Math.max(0, box.left - pad);
      const top = Math.max(0, box.top - pad);
      const width = Math.min(w, box.right + pad + 1) - left;
      const height = Math.min(h, box.bottom + pad + 1) - top;
      const sprite = await sharp(teenPath).extract({ left, top, width, height }).png().toBuffer();
      // Place feet-aligned / horizontally centered on transparent 32×32
      const meta = await sharp(sprite).metadata();
      const sw = meta.width;
      const sh = meta.height;
      const ox = Math.floor((FRAME - sw) / 2);
      const oy = Math.max(0, FRAME - sh - 1);
      const cell = await sharp({
        create: { width: FRAME, height: FRAME, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
      })
        .composite([{ input: sprite, left: Math.max(0, ox), top: oy }])
        .png()
        .toBuffer();
      frames.push(cell);
    }

    // If fewer than 4, pad by repeating last
    while (frames.length < 4 && frames.length > 0) frames.push(frames[frames.length - 1]);

    const composites = frames.slice(0, 4).map((input, i) => ({ input, left: i * FRAME, top: 0 }));
    await sharp({
      create: { width: STRIP_W, height: FRAME, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
    })
      .composite(composites)
      .png()
      .toFile(path.join(DIR, outName));
    console.log(`✓ ${outName} (${frames.length} content boxes → 4 frames)`);
  }

  const moveBoxes = findBoxes(58, 78, 12, 4);
  console.log("teen move boxes", moveBoxes);
  await boxesToStrip(moveBoxes, "teen-move.png");

  // Idle: bob artificial a partir do frame 0 do move (respiração real da linha 6
  // nesta grid teen misturava frentes estreitas e cortava mal).
  const frame0 = await sharp(path.join(DIR, "teen-move.png"))
    .extract({ left: 0, top: 0, width: FRAME, height: FRAME })
    .png()
    .toBuffer();
  const bob = [];
  for (const dy of [0, -1, 0, 1]) {
    const cell = await sharp({
      create: { width: FRAME, height: FRAME, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
    })
      .composite([{ input: frame0, left: 0, top: dy }])
      .png()
      .toBuffer();
    bob.push(cell);
  }
  await sharp({
    create: { width: STRIP_W, height: FRAME, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .composite(bob.map((input, i) => ({ input, left: i * FRAME, top: 0 })))
    .png()
    .toFile(path.join(DIR, "teen-idle.png"));
  console.log("✓ teen-idle.png (bob a partir do frame 0 do move)");
}

async function main() {
  if (!sharp) {
    console.error("sharp não encontrado. Corre: npm install sharp --save-dev");
    process.exit(1);
  }
  // Sequencial
  await extractTeenContentAware();
  await extractAdultWithSharp();
  console.log("\nDone →", DIR);
  console.log("Abre preview.html ou os GIFs teen-move.gif / teen-idle.gif");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
