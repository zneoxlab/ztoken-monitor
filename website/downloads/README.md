# Android 正式版安装包

部署网站时，请将 Android 安装包放在此目录，并保持文件名为：

`ZT-Monitor-Android.apk`

网站会根据当前部署地址自动生成下载二维码。生产环境固定地址为：

`https://zt.zneox.com/downloads/ZT-Monitor-Android.apk`

应用更新策略固定地址为：

`https://zt.zneox.com/app-update.json`

更换 APK 时必须使用同一 Android Release 签名，递增构建号，并将新文件的 SHA-256 同步写入 `website/app-update.json`。
