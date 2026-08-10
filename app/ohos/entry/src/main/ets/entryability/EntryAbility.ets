
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { Configuration } from '@ohos.app.ability.Configuration';
import resourceManager from '@ohos.resourceManager';
import I18n from '@ohos.i18n';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { PlatformBrightness } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/systemchannels/SettingsChannel';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

// 鸿蒙深色模式:应用须 setColorMode(NOT_SET) 才会跟随系统;再用 resourceManager
// 判定实际深浅色并推送到 Flutter SettingsChannel(比 matchMedia 更可靠,HarmonyOS 7)。
export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    this.syncPlatformBrightness();
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    // 未设置时应用可能固定浅色,Flutter 侧 platformBrightness 会一直为 light。
    this.context.getApplicationContext().setColorMode(
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    super.onCreate(want, launchParam);
    this.syncPlatformBrightness();
  }

  onConfigurationUpdate(config: Configuration) {
    super.onConfigurationUpdate(config);
    this.syncPlatformBrightness();
  }

  onForeground() {
    super.onForeground();
    // 用户在后台切换系统深浅色后,回到前台补推一次。
    this.syncPlatformBrightness();
  }

  private isSystemDarkMode(): boolean {
    try {
      const rmConfig = this.context.resourceManager.getConfigurationSync();
      if (rmConfig.colorMode === resourceManager.ColorMode.DARK) {
        return true;
      }
    } catch (_) {
      // resourceManager 不可用时回退 ability config。
    }
    return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private syncPlatformBrightness(): void {
    const channel = this.getFlutterEngine()?.getSettingsChannel();
    if (!channel) {
      return;
    }
    const isDark = this.isSystemDarkMode();
    const config = this.context.config;
    channel.startMessage()
      .setNativeSpellCheckServiceDefined(false)
      .setBrieflyShowPassword(false)
      .setAlwaysUse24HourFormat(I18n.System.is24HourClock())
      .setPlatformBrightness(isDark ? PlatformBrightness.DARK : PlatformBrightness.LIGHT)
      .setTextScaleFactor(config.fontSizeScale ?? 1.0)
      .send();
  }
}
