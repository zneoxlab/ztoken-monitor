#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "用法: $0 <项目外的签名备份目录>" >&2
  exit 2
fi

signing_dir=$1
keystore_path="$signing_dir/zt-monitor-release.jks"
password_path="$signing_dir/zt-monitor-release.password"

if [ -e "$keystore_path" ] || [ -e "$password_path" ]; then
  echo "拒绝覆盖已有的 Android Release 签名文件" >&2
  exit 1
fi

umask 077
mkdir -p "$signing_dir"
openssl rand -hex -out "$password_path" 32
keytool -genkeypair \
  -alias zt-monitor \
  -keyalg RSA \
  -keysize 4096 \
  -sigalg SHA256withRSA \
  -validity 36500 \
  -dname "CN=ZT Monitor, OU=Mobile, O=Zneox, C=CN" \
  -keystore "$keystore_path" \
  -storetype JKS \
  -storepass:file "$password_path" \
  -keypass:file "$password_path" \
  -noprompt
chmod 600 "$keystore_path" "$password_path"

echo "Android Release 签名已创建：$keystore_path"
echo "请将整个目录备份到受保护的离线位置。"
