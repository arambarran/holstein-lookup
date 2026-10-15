// Run against a local app. Only uploads and fictional results; no live lookups.
const { chromium, expect } = require(process.env.PLAYWRIGHT_MODULE || '@playwright/test');
const fs = require('node:fs');

async function dropFiles(page, selector, files) {
  await page.locator(selector).evaluate((target, entries) => {
    const transfer = new DataTransfer();
    entries.forEach(entry => transfer.items.add(new File(
      [entry.content || 'animal_id\n001\n'], entry.name, { type: 'text/csv' }
    )));
    target.dispatchEvent(new DragEvent('drop', { bubbles: true, dataTransfer: transfer }));
  }, files);
}

async function downloadText(page, selector) {
  const [download] = await Promise.all([
    page.waitForEvent('download'), page.locator(selector).click()
  ]);
  return fs.readFileSync(await download.path(), 'utf8');
}

async function checkBrowser() {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined, headless: true
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    // Old, unversioned URLs can still be cached after an app upgrade.
    // Serve stale content at those URLs; current HTML must request new URLs.
    let staleAssets = 0;
    await page.route(/\/app\.(css|js)$/, route => {
      staleAssets += 1;
      const css = route.request().url().endsWith('.css');
      return route.fulfill({
        contentType: css ? 'text/css' : 'application/javascript',
        body: css ? '.app-header { display: grid; grid-template-columns: 110px 1fr 110px; }' : ''
      });
    });
    const errors = [];
    let uploads = 0;
    page.on('pageerror', error => errors.push(error.message));
    page.on('websocket', socket => socket.on('framesent', ({ payload }) => {
      try { if (JSON.parse(payload).method === 'uploadInit') uploads += 1; } catch (_) { /* Non-JSON frames. */ }
    }));
    page.setDefaultTimeout(15000);
    await page.goto(process.env.LOOKUP_URL || 'http://127.0.0.1:4876');
    await expect(page.locator('#empty_state')).toContainText('No results yet');
    await page.waitForFunction(() => document.querySelector('#results').classList.contains('shiny-bound-output') && Boolean(document.querySelector('#columns').selectize));
    await expect(page.locator('#run')).toBeDisabled();
    await expect(page.locator('.btn-file')).toHaveText('Choose file');
    await expect(page.locator('#id_column')).toBeDisabled();
    expect(staleAssets).toBe(0);
    await expect(page.locator('link[href^="app.css"]')).toHaveAttribute('href', /\?v=[a-f0-9]{32}$/);
    await expect(page.locator('script[src^="app.js"]')).toHaveAttribute('src', /\?v=[a-f0-9]{32}$/);
    await expect(page.locator('.header-inner')).toHaveCSS('display', 'grid');
    const title = await page.locator('h1').boundingBox();
    expect(Math.abs(title.x + title.width / 2 - 720)).toBeLessThan(2);
    for (const icon of await page.locator('.lookup-icon').all()) {
      const bounds = await icon.boundingBox();
      expect(bounds.width).toBeLessThanOrEqual(32);
      expect(bounds.height).toBeLessThanOrEqual(32);
    }
    // Icons retain their intrinsic size even if the custom stylesheet fails.
    await page.evaluate(() => { document.querySelector('link[href^="app.css"]').sheet.disabled = true; });
    for (const icon of await page.locator('.lookup-icon').all()) {
      const bounds = await icon.boundingBox();
      expect(bounds.width).toBe(28);
      expect(bounds.height).toBe(28);
    }
    await page.evaluate(() => { document.querySelector('link[href^="app.css"]').sheet.disabled = false; });
    await page.screenshot({ path: '/tmp/holstein-empty.png', fullPage: true });

    // Keyboard access to the native file picker.
    await page.locator('.btn-file').focus();
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'), page.locator('.btn-file').press('Enter')
    ]);
    await chooser.setFiles({ name: 'first.csv', mimeType: 'text/csv', buffer: Buffer.from('animal_id\n0001\n') });
    await expect(page.locator('#upload_info')).toContainText('1 rows / 1 unique IDs');
    await expect(page.locator('#run')).toBeEnabled();

    // Drop on the nested native control: formerly this started two uploads.
    const beforeDrop = uploads;
    await dropFiles(page, '.upload-area .form-control', [{
      name: 'herd.csv', content: 'tag,notes\n004464,a\n004464,b\n2034,c\n'
    }]);
    await expect(page.locator('#upload_info')).toContainText('3 rows / 2 unique IDs');
    await expect(page.locator('#run')).toBeEnabled();
    expect(uploads - beforeDrop).toBe(1);
    await page.locator('#prefix').fill('COLLEGE');
    await expect(page.locator('#search_preview')).toContainText('COLLEGE 004464');
    await page.locator('.input-preview summary').click();
    await expect(page.locator('#preview')).toContainText('004464');

    // Rejected drops keep the selected file and do not start another transport.
    const beforeInvalid = uploads;
    await dropFiles(page, '.upload-area', [{ name: 'notes.txt' }]);
    await expect(page.locator('#upload-error')).toHaveText('Please choose a .csv file.');
    await dropFiles(page, '.upload-area', [{ name: 'one.csv' }, { name: 'two.csv' }]);
    await expect(page.locator('#upload-error')).toHaveText('Choose one CSV file at a time.');
    expect(uploads).toBe(beforeInvalid);
    await expect(page.locator('.upload-area .form-control')).toHaveValue('herd.csv');
    await page.locator('#setup-fields').evaluate(fields => { fields.disabled = true; });
    await dropFiles(page, '.upload-area .form-control', [{ name: 'busy.csv' }]);
    expect(uploads).toBe(beforeInvalid);
    await page.locator('#setup-fields').evaluate(fields => { fields.disabled = false; });

    // A parse error must clear the preceding valid upload and disable Start.
    await page.locator('#csv').setInputFiles({ name: 'empty.csv', mimeType: 'text/csv', buffer: Buffer.from('animal_id\n') });
    await expect(page.locator('#upload_info')).toContainText('at least one data row');
    await expect(page.locator('#run')).toBeDisabled();
    await dropFiles(page, '.upload-area', [{ name: 'herd.csv', content: 'animal_id,notes\n004464,a\n2034,b\n' }]);
    await expect(page.locator('#upload_info')).toContainText('2 rows / 2 unique IDs');
    await expect(page.locator('#upload-error')).toBeEmpty();
    await expect(page.locator('#run')).toBeEnabled();

    await page.locator('#example').click();
    await expect(page.locator('#results_caption')).toContainText('7 records from 6 animal IDs');
    await expect(page.locator('#results')).toContainText('EXAMPLE MAPLE');
    await page.locator('#search').fill('maple');
    await expect(page.locator('#exports')).toContainText('1 record in this view');
    await page.locator('#search').fill('[');
    await expect(page.locator('#results')).toContainText('No records match these filters.');
    await page.locator('#search').fill('');
    await page.evaluate(() => document.querySelector('#status').selectize.setValue('multiple'));
    await expect(page.locator('#exports')).toContainText('2 records in this view');
    await page.locator('.column-picker summary').click();
    await expect(page.locator('.column-menu')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('.column-menu')).not.toBeVisible();
    await page.evaluate(() => document.querySelector('#columns').selectize.setValue(['animal_id', 'Name']));
    await expect(page.locator('#results .rt-th')).toHaveCount(2);
    await page.locator('#results .rt-th').nth(1).click();
    await page.locator('#results .rt-th').nth(1).click();
    await expect(page.locator('#results .rt-tbody .rt-tr').first()).toContainText('WILLOW B');
    await page.waitForFunction(() => Shiny.shinyapp.$inputValues.results__reactable__sorted?.Name === 'desc');
    const view = await downloadText(page, '#export_view');
    expect(view.trim().split('\n')).toHaveLength(3);
    expect(view).toMatch(/^animal_id,Name\n/);
    expect(view.split('\n')[1]).toContain('WILLOW B');
    expect((await downloadText(page, '#export_all')).trim().split('\n')).toHaveLength(8);
    expect(await downloadText(page, '#export_errors')).toContain('timed out');
    await page.evaluate(() => document.querySelector('#columns').selectize.clear());
    await expect(page.getByText('Choose at least one column to display results.', { exact: true })).toBeVisible();
    await page.evaluate(() => {
      document.querySelector('#columns').selectize.setValue(['animal_id', 'Name', 'match_status', 'birth_codes', 'genotyping_code']);
      document.querySelector('#status').selectize.setValue('all');
    });
    await expect(page.locator('#results')).toContainText('EXAMPLE MAPLE');
    await page.screenshot({ path: '/tmp/holstein-example.png', fullPage: true });
    for (const width of [768, 390]) {
      await page.setViewportSize({ width, height: 844 });
      await page.locator('.column-picker summary').click();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      await page.keyboard.press('Escape');
      await page.screenshot({ path: `/tmp/holstein-${width}.png`, fullPage: true });
    }
    const second = await browser.newPage();
    await second.goto(process.env.LOOKUP_URL || 'http://127.0.0.1:4876');
    await expect(second.locator('#empty_state')).toContainText('No results yet');
    expect(errors).toEqual([]);
    console.log('Browser checks passed: upload, single drop transport, validation, keyboard access, filters, columns, sorting, CSV exports, responsive layout, session isolation.');
  } finally {
    await browser.close();
  }
}

checkBrowser().catch(error => { console.error(error); process.exitCode = 1; });
