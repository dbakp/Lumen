const { chromium } = require('playwright-core');
const path = require('path');
(async () => {
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  const page = await browser.newPage({viewport: {width: 1400, height: 1200}, deviceScaleFactor: 1});
  await page.goto('file://' + path.resolve('Design/mockup.html'));
  const icon = page.locator('.app-icon').first();
  await icon.evaluate(e => { e.style.setProperty('border-radius','0','important'); e.style.width='1024px'; e.style.height='1024px'; });
  for (const mode of ['default','dark','tinted']) {
    await icon.evaluate((e, mode) => e.dataset.mode = mode, mode);
    await icon.screenshot({path: '/tmp/lumen-icon-' + mode + '.png'});
  }
  await browser.close();
})();
