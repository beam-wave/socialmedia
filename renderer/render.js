// Render one post's slides as JPEGs plus its caption.
// Usage: node render.js <channel-template-dir> <out-dir> < data.json
// Prints JSON to stdout: {"slides": ["<abs path>", ...], "captions": [{"id", "text"}]}
// Setup once: npm install && npx playwright install chromium
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path'), url = require('url');

const readStdin = () => new Promise(res => {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', c => (buf += c));
  process.stdin.on('end', () => res(buf));
});

(async () => {
  const [dirArg, outArg] = process.argv.slice(2);
  if (!dirArg || !outArg) { console.error('Usage: node render.js <channel-dir> <out-dir> < data.json'); process.exit(2); }
  const dir = path.resolve(dirArg), out = path.resolve(outArg);
  const data = JSON.parse(await readStdin());
  fs.mkdirSync(out, { recursive: true });

  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
    if (process.env.NO_FONTS) await page.route(/fonts\.(googleapis|gstatic)/, r => r.abort());
    page.on('pageerror', e => console.error('Page error:', e.message));
    await page.goto(url.pathToFileURL(path.join(dir, 'template.html')).href, { waitUntil: 'load', timeout: 30000 }).catch(() => {});
    await page.waitForFunction(() => window.Studio && window.Studio.data, null, { timeout: 15000 });
    await page.evaluate(() => document.body.classList.add('render'));
    await page.evaluate(d => window.Studio.render(d), data);
    await page.evaluate(() => Promise.all([...document.images].map(i => i.complete ? null : new Promise(r => { i.onload = i.onerror = r; }))));

    const slides = [];
    for (const f of await page.$$('.frame')) {
      const file = path.join(out, `${await f.getAttribute('data-file')}.jpg`);
      // Highest JPEG quality (Instagram's API only takes JPEG); bytes go to S3 untouched
      await f.screenshot({ path: file, type: 'jpeg', quality: 100 });
      slides.push(file);
    }
    const captions = await page.evaluate(() => window.Studio.captions());
    process.stdout.write(JSON.stringify({ slides, captions }));
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e.stack || String(e)); process.exit(1); });
