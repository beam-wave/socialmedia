// Record a post's animated slide (format "reel") as an MP4, frame by frame.
// Usage: node record.js <channel-template-dir> <out-dir> < data.json
// Prints JSON: {"videos": ["<abs path>.mp4", ...], "covers": ["<abs path>.jpg", ...], "captions": [{"id","text"}]}
// Every CSS animation is paused and stepped with currentTime, so frames are exact
// and the speed of the machine doesn't matter. Needs ffmpeg on PATH.
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url'), os = require('os');

const FPS = +(process.env.FPS || 30);
const readStdin = () => new Promise(res => {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', c => (buf += c));
  process.stdin.on('end', () => res(buf));
});

(async () => {
  const [dirArg, outArg] = process.argv.slice(2);
  if (!dirArg || !outArg) { console.error('Usage: node record.js <channel-dir> <out-dir> < data.json'); process.exit(2); }
  const dir = path.resolve(dirArg), out = path.resolve(outArg);
  const data = JSON.parse(await readStdin());
  fs.mkdirSync(out, { recursive: true });

  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
    page.on('pageerror', e => console.error('Page error:', e.message));
    await page.goto(url.pathToFileURL(path.join(dir, 'template.html')).href, { waitUntil: 'load', timeout: 30000 }).catch(() => {});
    await page.waitForFunction(() => window.Studio && window.Studio.data, null, { timeout: 15000 });
    await page.evaluate(() => document.body.classList.add('render'));
    await page.evaluate(d => window.Studio.render(d), data);
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate(() => Promise.all([...document.images].map(i => i.complete ? null : new Promise(r => { i.onload = i.onerror = r; }))));

    const seconds = +(data.video_seconds || 12);
    const videos = [], covers = [];
    for (const f of await page.$$('.frame')) {
      const name = await f.getAttribute('data-file');
      const frames = fs.mkdtempSync(path.join(os.tmpdir(), 'reel-'));
      const total = Math.round(seconds * FPS);
      for (let i = 0; i < total; i++) {
        const ms = (i * 1000) / FPS;
        await page.evaluate(t => document.getAnimations().forEach(a => { a.pause(); a.currentTime = t; }), ms);
        await f.screenshot({ path: path.join(frames, `${String(i).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 92 });
      }
      // Cover: the finished card, just before the end card fades in
      const cover = path.join(out, `${name}-cover.jpg`);
      await page.evaluate(() => document.getAnimations().forEach(a => { a.currentTime = 8500; }));
      await f.screenshot({ path: cover, type: 'jpeg', quality: 95 });

      const mp4 = path.join(out, `${name}.mp4`);
      // H.264 + a silent AAC track: what Instagram Reels expects (music is attached by the API)
      execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', path.join(frames, '%05d.jpg'),
        '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
        '-shortest', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
        '-r', String(FPS), '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', mp4]);
      for (const file of fs.readdirSync(frames)) fs.unlinkSync(path.join(frames, file));
      fs.rmdirSync(frames);
      videos.push(mp4); covers.push(cover);
    }
    const captions = await page.evaluate(() => window.Studio.captions());
    process.stdout.write(JSON.stringify({ videos, covers, captions }));
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e.stack || String(e)); process.exit(1); });
