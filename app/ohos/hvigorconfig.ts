import fs from 'fs'
import path from 'path'
import { injectNativeModules } from 'flutter-hvigor-plugin';

const appRoot = path.dirname(__dirname)
const pluginsDeps = path.join(appRoot, '.flutter-plugins-dependencies')
if (fs.existsSync(pluginsDeps)) {
  const parsed = JSON.parse(fs.readFileSync(pluginsDeps, 'utf-8'))
  if (!parsed.plugins?.ohos) {
    throw new Error(
      'HarmonyOS plugins are missing from .flutter-plugins-dependencies. ' +
      'Run `flutter pub get` with the OpenHarmony Flutter SDK ' +
      '(see ohos/local.properties → flutter.sdk), not the standard Flutter SDK.'
    )
  }
}

injectNativeModules(__dirname, appRoot)