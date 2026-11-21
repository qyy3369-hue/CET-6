export function cleanWord(raw) {
  const word = raw.toLowerCase().replace(/[‘’]/gu, "'").replace(/[‐‑–]/gu, '-')
    .replace(/^[^a-z]+|[^a-z]+$/gu, '');
  return /^[a-z]+(?:['-][a-z]+)*$/u.test(word) && word.length >= 2 && word.length <= 60 ? word : null;
}

export async function imageCanvas(file) {
  if (!file || !file.type.startsWith('image/') || file.size > 25 * 1024 * 1024) {
    throw new Error('请选择不大于 25 MB 的图片。');
  }
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 2048 / Math.max(bitmap.width,bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1,Math.round(bitmap.width * scale));
  canvas.height = Math.max(1,Math.round(bitmap.height * scale));
  const context = canvas.getContext('2d',{willReadFrequently:true});
  context.fillStyle = '#fff';
  context.fillRect(0,0,canvas.width,canvas.height);
  context.drawImage(bitmap,0,0,canvas.width,canvas.height);
  bitmap.close();
  return canvas;
}

function annotationMask(pixels, size) {
  let bright = 0;
  let samples = 0;
  for (let i = 0; i < size; i += 101) {
    bright += Number(pixels[4 * i + 1] > 145);
    samples++;
  }
  const light = bright * 2 >= samples;
  const mask = new Uint8Array(size);
  for (let i = 0; i < size; i++) {
    const [red,green,blue] = [pixels[4*i],pixels[4*i+1],pixels[4*i+2]];
    const maximum = Math.max(red,green,blue);
    const minimum = Math.min(red,green,blue);
    if (maximum > 80 && maximum - minimum > 40 && (maximum - minimum) / maximum > .17) mask[i] = 1;
    else if (light ? maximum < 95 : minimum > 175) mask[i] = 2;
  }
  return mask;
}

export function detectMarks(canvas) {
  const {width,height} = canvas;
  const size = width * height;
  const pixels = canvas.getContext('2d').getImageData(0,0,width,height).data;
  const mask = annotationMask(pixels,size);
  const queue = new Int32Array(size);
  const marks = [];
  for (let index = 0; index < size; index++) {
    const ink = mask[index];
    if (!ink) continue;
    let tail = 1;
    let left = width;
    let right = 0;
    let top = height;
    let bottom = 0;
    mask[index] = 0;
    queue[0] = index;
    for (let head = 0; head < tail; head++) {
      const value = queue[head];
      const x = value % width;
      const y = Math.floor(value / width);
      left = Math.min(left,x); right = Math.max(right,x);
      top = Math.min(top,y); bottom = Math.max(bottom,y);
      for (let dy = -1; dy <= 1; dy++) {
        const yy = y + dy;
        if (yy < 0 || yy >= height) continue;
        for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx;
          if (xx < 0 || xx >= width) continue;
          const next = yy * width + xx;
          if (mask[next] !== ink) continue;
          mask[next] = 0;
          queue[tail++] = next;
        }
      }
    }
    if (tail < 18) continue;
    right++; bottom++;
    const w = right-left, h = bottom-top;
    const fill = tail / (w*h);
    const kinds = [];
    if (w >= 13 && h <= w/2.75 && fill >= .38 && (ink === 1 || (h >= 2 && tail/w >= 1.9))) kinds.push('underline');
    if (ink === 1 && h >= 7 && w >= h*.7 && fill >= .45) kinds.push('highlight');
    if (h >= 12 && w >= 14 && fill < .55 && (ink === 1 || tail/(2*(w+h)) >= 1.4)) {
      const edges = [0,0,0,0];
      let middle = 0;
      for (let i = 0; i < tail; i++) {
        const point = queue[i];
        const x = (point%width-left)/w, y = (Math.floor(point/width)-top)/h;
        if (x > .22 && x < .78) {
          if (y < .24) edges[0]++;
          if (y > .76) edges[1]++;
          if (x > .3 && x < .7 && y > .3 && y < .7) middle++;
        }
        if (y > .22 && y < .78) {
          if (x < .24) edges[2]++;
          if (x > .76) edges[3]++;
        }
      }
      if (Math.min(edges[0],edges[1]) >= w*.16 && Math.min(edges[2],edges[3]) >= h*.16 && middle < w*h*.05) kinds.push('outline');
    }
    if (kinds.length) marks.push({left,right,top,bottom,kinds});
  }
  return marks;
}

export function isMarked(box, marks) {
  const {x0,y0,x1,y1} = box;
  const width = x1-x0, height = y1-y0;
  if (width <= 0 || height <= 0) return false;
  const midX = (x0+x1)/2, midY = (y0+y1)/2;
  return marks.some(mark => {
    const cover = Math.max(0,Math.min(mark.right,x1)-Math.max(mark.left,x0))/width;
    const gap = (mark.top+mark.bottom)/2-y1;
    const overlapY = Math.min(mark.bottom,y1)-Math.max(mark.top,y0);
    const h = mark.bottom-mark.top;
    return mark.kinds.some(kind => {
      if (kind === 'underline') return cover >= .55 && gap >= -height*.22 && gap <= Math.max(5,height*.66);
      if (kind === 'highlight') return cover >= .56 && overlapY >= height*.36 && h <= Math.max(12,height*2.6);
      return cover >= .78 && midX >= mark.left && midX <= mark.right && midY >= mark.top && midY <= mark.bottom
        && h >= height*1.17 && mark.right-mark.left >= width*1.02;
    });
  });
}

function readingCanvas(canvas) {
  const {width,height} = canvas;
  const source = canvas.getContext('2d').getImageData(0,0,width,height);
  const pixels = source.data;
  const ink = annotationMask(pixels,width*height);
  let light = 0;
  let samples = 0;
  for (let offset=0;offset<pixels.length;offset+=404) {
    light += Number(pixels[offset+1]>145);
    samples++;
  }
  const darkPage = light*2 < samples;
  for (let index=0;index<ink.length;index++) {
    const offset=index*4;
    const luminance=Math.round(.2126*pixels[offset]+.7152*pixels[offset+1]+.0722*pixels[offset+2]);
    const gray=ink[index]===1 ? 255 : darkPage ? 255-luminance : luminance;
    pixels[offset]=pixels[offset+1]=pixels[offset+2]=gray;
  }
  const cleaned=document.createElement('canvas');
  cleaned.width=width;
  cleaned.height=height;
  cleaned.getContext('2d').putImageData(source,0,0);
  return cleaned;
}

let engine;
function ocrEngine() {
  if (!engine) engine = new Promise((resolve,reject) => {
    const script = document.createElement('script');
    script.src = new URL('./ocr/tesseract.min.js',import.meta.url).href;
    script.onload = () => resolve(window.Tesseract);
    script.onerror = () => { engine = null; reject(new Error('本地识别组件加载失败，请重试。')); };
    document.head.append(script);
  });
  return engine;
}

export async function recognizeImage(canvas, signal) {
  const tesseract = await ocrEngine();
  signal.throwIfAborted();
  const path = name => new URL('./ocr/' + name,import.meta.url).href;
  const worker = await tesseract.createWorker('eng',1,{
    workerPath:path('worker.min.js'),
    corePath:path('tesseract-core-lstm.wasm.js'),
    langPath:path('').replace(/\/$/u,''),
    workerBlobURL:false,
  });
  let stop;
  try {
    signal.throwIfAborted();
    const aborted = new Promise((_,reject) => {
      stop = () => reject(signal.reason);
      signal.addEventListener('abort',stop,{once:true});
    });
    const result = await Promise.race([worker.recognize(readingCanvas(canvas),{}, {blocks:true}),aborted]);
    const marks = detectMarks(canvas);
    const detected = [];
    for (const block of result.data.blocks ?? []) {
      for (const paragraph of block.paragraphs ?? []) {
        for (const line of paragraph.lines ?? []) {
          for (const hit of line.words ?? []) {
            const text = cleanWord(hit.text);
            if (text && hit.confidence >= 28) {
              detected.push({text,box:hit.bbox,marked:isMarked(hit.bbox,marks)});
            }
          }
        }
      }
    }
    return detected;
  } finally {
    if (stop) signal.removeEventListener('abort',stop);
    await worker.terminate();
  }
}
