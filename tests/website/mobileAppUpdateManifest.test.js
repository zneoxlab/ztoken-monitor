'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const rootDir = path.join(__dirname, '..', '..');
const read = (file) => fs.readFileSync(path.join(rootDir, file), 'utf8');

test('mobile update manifest declares the formal v1.0.0 baseline', () => {
  const manifest = JSON.parse(read('website/app-update.json'));

  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.ios.latestVersion, '1.0.0');
  assert.equal(manifest.ios.latestBuild, 2002);
  assert.equal(manifest.android.latestVersion, '1.0.0');
  assert.equal(manifest.android.latestBuild, 2003);
  assert.equal(manifest.ohos.latestVersion, '1.0.0');
  assert.equal(manifest.ohos.latestBuild, 1000000);
  assert.equal(manifest.ohos.enabled, true);
  assert.equal(manifest.ohos.updateUrl, 'https://zt.zneox.com/#download');
});

test('Android direct update points at the website APK', () => {
  const manifest = JSON.parse(read('website/app-update.json'));
  const updatePath = path.normalize(path.join('website', manifest.android.updateUrl));

  assert.equal(updatePath, path.join('website', 'downloads', 'ZT-Monitor-Android.apk'));
  assert.ok(fs.existsSync(path.join(rootDir, updatePath)));
});

test('Android policy SHA-256 matches the published release APK', () => {
  const manifest = JSON.parse(read('website/app-update.json'));
  const apk = fs.readFileSync(
    path.join(rootDir, 'website', manifest.android.updateUrl),
  );
  const digest = crypto.createHash('sha256').update(apk).digest('hex');

  assert.match(manifest.android.sha256, /^[0-9a-f]{64}$/);
  assert.equal(manifest.android.sha256, digest);
});

test('website presents Android as a formal release', () => {
  const content = `${read('website/index.html')}\n${read('website/app.js')}`;

  assert.doesNotMatch(content, /Android 内测版/);
  assert.doesNotMatch(content, /Android beta/);
  assert.match(content, /Android 正式版/);
});
