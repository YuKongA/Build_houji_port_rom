#!/bin/bash

sudo timedatectl set-timezone Asia/Shanghai
sudo apt-get remove -y firefox zstd
sudo apt-get install python3 aria2

URL="$1"              # 移植包下载地址
VENDOR_URL="$2"       # 底包下载地址
GITHUB_ENV="$3"       # 输出环境变量
GITHUB_WORKSPACE="$4" # 工作目录

device=houji # 设备代号

Red='\033[1;31m'    # 粗体红色
Yellow='\033[1;33m' # 粗体黄色
Blue='\033[1;34m'   # 粗体蓝色
Green='\033[1;32m'  # 粗体绿色

port_os_version=$(echo ${URL} | cut -d"/" -f4)                   # 移植包的 OS 版本号, 例: OS1.0.7.0.UNACNXM
port_version=$(echo ${port_os_version} | sed 's/OS1/V816/g')     # 移植包的实际版本号, 例: V816.0.7.0.UNACNXM
port_zip_name=$(echo ${URL} | cut -d"/" -f5)                     # 移植包的 zip 名称, 例: miui_AURORA_OS1.0.7.0.UNACNXM_81a48e3c20_14.0.zip
vendor_os_version=$(echo ${VENDOR_URL} | cut -d"/" -f4)          # 底包的 OS 版本号, 例: OS1.0.32.0.UNCCNXM
vendor_version=$(echo ${vendor_os_version} | sed 's/OS1/V816/g') # 底包的实际版本号, 例: V816.0.32.0.UNCCNXM
vendor_zip_name=$(echo ${VENDOR_URL} | cut -d"/" -f5)            # 底包的 zip 名称, 例: miui_HOUJI_OS1.0.32.0.UNCCNXM_4fd0e15877_14.0.zip

android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1) # Android 版本号, 例: 14
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)   # 构建时间

sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools
magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
ksud="$GITHUB_WORKSPACE"/tools/ksud
a7z="$GITHUB_WORKSPACE"/tools/7zzs
zstd="$GITHUB_WORKSPACE"/tools/zstd
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
apktool_jar="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"

Start_Time() {
  Start_s=$(date +%s)
  Start_ns=$(date +%N)
}

End_Time() {
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi

  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))

  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒"
  fi
}

### 系统包下载
echo -e "${Red}- 开始下载系统包"
echo -e "${Yellow}- 开始下载移植包"
Start_Time
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$URL"
End_Time 下载移植包
Start_Time
echo -e "${Yellow}- 开始下载底包"
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$VENDOR_URL"
End_Time 下载底包
### 系统包下载结束

### 解包
echo -e "${Red}- 开始解压系统包"
mkdir -p "$GITHUB_WORKSPACE"/Third_Party
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip

echo -e "${Yellow}- 开始解压移植包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/$port_zip_name -r -o"$GITHUB_WORKSPACE"/Third_Party >/dev/null
rm -rf "$GITHUB_WORKSPACE"/$port_zip_name
End_Time 解压移植包
echo -e "${Yellow}- 开始解压底包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${vendor_zip_name} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${vendor_zip_name}
End_Time 解压底包
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
echo -e "${Red}- 开始解底包payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir/ -i "$GITHUB_WORKSPACE"/"${device}"/payload.bin -X system,system_ext,product -e -T0
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin
echo -e "${Red}- 开始分解底包image"
for i in mi_ext odm system_dlkm vendor vendor_dlkm; do
  echo -e "${Yellow}- 正在分解底包: $i.img"
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
done
sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
cd "$GITHUB_WORKSPACE"/images
echo -e "${Red}- 开始解移植包payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/images/ -i "$GITHUB_WORKSPACE"/Third_Party/payload.bin -X product,system,system_ext -T0
echo -e "${Red}- 开始分解移植包image"
for i in product system system_ext; do
  echo -e "${Yellow}- 正在分解移植包: $i"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/images/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/Third_Party
### 解包结束

### 写入变量
echo -e "${Red}- 开始写入变量"
# 构建日期
echo "build_time=$build_time" >>$GITHUB_ENV
echo -e "${Blue}- 构建日期: $build_time"
# 移植包版本
echo "port_os_version=$port_os_version" >>$GITHUB_ENV
echo -e "${Blue}- 移植包版本: $port_os_version"
# 底包版本
echo "vendor_os_version=$vendor_os_version" >>$GITHUB_ENV
echo -e "${Blue}- 底包版本: $vendor_os_version"
# 移植包安全补丁
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
port_security_patch=$(grep "ro.build.version.security_patch=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 移植包安全补丁版本: $port_security_patch"
echo "port_security_patch=$port_security_patch" >>$GITHUB_ENV
# 底包安全补丁
vendor_build_prop=$GITHUB_WORKSPACE/${device}/vendor/build.prop
vendor_security_patch=$(grep "ro.vendor.build.security_patch=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 底包安全补丁版本: $vendor_security_patch"
echo "vendor_security_patch=$vendor_security_patch" >>$GITHUB_ENV
# 移植包基线版本
port_base_line=$(grep "ro.system.build.id=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 移植包基线版本: $port_base_line"
echo "port_base_line=$port_base_line" >>$GITHUB_ENV
# 底包基线版本
vendor_base_line=$(grep "ro.vendor.build.id=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 底包基线版本: $vendor_base_line"
echo "vendor_base_line=$vendor_base_line" >>$GITHUB_ENV
### 写入变量结束

### 功能修复
echo -e "${Red}- 开始功能修复"
Start_Time
# 添加 KernelSU 支持 (可选择)
echo -e "${Red}- 添加 KernelSU 支持 (可选择)"
mkdir -p "$GITHUB_WORKSPACE"/init_boot
cd "$GITHUB_WORKSPACE"/init_boot
cp -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/init_boot.img "$GITHUB_WORKSPACE"/init_boot
$ksud boot-patch -b "$GITHUB_WORKSPACE"/init_boot/init_boot.img --magiskboot $magiskboot --kmi android14-6.1
mv -f "$GITHUB_WORKSPACE"/init_boot/kernelsu_*.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/init_boot-kernelsu.img
rm -rf "$GITHUB_WORKSPACE"/init_boot
# 替换 vendor_boot 的 fstab
echo -e "${Red}- 替换 Vendor Boot 的 fstab"
mkdir -p "$GITHUB_WORKSPACE"/vendor_boot
cd "$GITHUB_WORKSPACE"/vendor_boot
mv -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img "$GITHUB_WORKSPACE"/vendor_boot
$magiskboot unpack -h "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img 2>&1
if [ -f ramdisk.cpio ]; then
  comp=$($magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp
    $magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
    fi
  fi
  mkdir -p ramdisk
  chmod 755 ramdisk
  cd ramdisk
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i 2>&1
fi
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
cd "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/
find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio
cd ..
if [ "$comp" ]; then
  $magiskboot compress=$comp ramdisk_new.cpio 2>&1
  if [ $? != 0 ] && $comp --help 2>/dev/null; then
    $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
  fi
fi
ramdisk=$(ls ramdisk_new.cpio* 2>/dev/null | tail -n1)
if [ "$ramdisk" ]; then
  cp -f $ramdisk ramdisk.cpio
  case $comp in
  cpio) nocompflag="-n" ;;
  esac
  $magiskboot repack $nocompflag "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img 2>&1
fi
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_boot
# 替换 vendor 的 fstab
echo -e "${Red}- 替换 vendor 的 fstab"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom
# 替换 Product 的叠加层
echo -e "${Red}- 替换 product 的叠加层"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
# 替换 device_features 文件
echo -e "${Red}- 替换 device_features 文件"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/device_features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/
# 替换 displayconfig 文件
echo -e "${Red}- 替换 displayconfig 文件"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/displayconfig.zip -d "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/
# 修复精准电量 (亮屏可用时长)
echo -e "${Red}- 修复精准电量 (亮屏可用时长)"
sudo rm -rf "$GITHUB_WORKSPACE"/images/system/system/app/PowerKeeper/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/PowerKeeper.zip -d "$GITHUB_WORKSPACE"/images/system/system/app/PowerKeeper/
# 修复注视感知
echo -e "${Red}- 修复注视感知"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MiAONService*
mkdir "$GITHUB_WORKSPACE"/images/product/app/MiAONService
sudo cp "$GITHUB_WORKSPACE"/"${device}"_files/MiAONService.apk "$GITHUB_WORKSPACE"/images/product/app/MiAONService
# 统一 build.prop
echo -e "${Red}- 统一 build.prop"
sudo sed -i 's/ro.build.user=[^*]*/ro.build.user=YuKongA/' "$GITHUB_WORKSPACE"/images/system/system/build.prop
for port_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name "build.prop"); do
  sudo sed -i 's/build.date=[^*]*/build.date='"${build_time}"'/' "${port_build_prop}"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"${build_utc}"'/' "${port_build_prop}"
  sudo sed -i 's/'"${port_os_version}"'/'"${vendor_os_version}"'/g' "${port_build_prop}"
  sudo sed -i 's/'"${port_version}"'/'"${vendor_version}"'/g' "${port_build_prop}"
  sudo sed -i 's/'"${port_base_line}"'/'"${vendor_base_line}"'/g' "${port_build_prop}"
  sudo sed -i 's/ro.product.product.name=[^*]*/ro.product.product.name='"${device}"'/' "${port_build_prop}"
done
for vendor_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/build.date=[^*]*/build.date='"${build_time}"'/' "${vendor_build_prop}"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"${build_utc}"'/' "${vendor_build_prop}"
  sudo sed -i 's/ro.mi.os.version.incremental=[^*]*/ro.mi.os.version.incremental='"${port_os_version}"'/' "${vendor_build_prop}"
done
# 精简部分应用
echo -e "${Red}- 精简部分应用"
apps=("MIGalleryLockscreen" "MIUIDriveMode" "MIUIDuokanReader" "MIUIGameCenter" "MIUINewHome" "MIUIYoupin" "MIUIHuanJi" "MIUIMiDrive" "MIUIVirtualSim" "ThirdAppAssistant" "XMRemoteController" "MIUIVipAccount" "MiuiScanner" "Xinre" "SmartHome" "MiShop" "MiRadio" "MIUICompass" "MediaEditor" "BaiduIME" "iflytek.inputmethod" "MIService" "MIUIEmail" "MIUIVideo" "MIUIMusicT")
for app in "${apps[@]}"; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${app}*")
  if [[ -n $appsui ]]; then
    echo -e "${Yellow}- 找到精简目录: $appsui"
    sudo rm -rf "$appsui"
  fi
done
# 分辨率修改
echo -e "${Red}- 分辨率修改"
sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=480/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
# Add aptX Lossless
echo -e "${Red}- Add aptX Lossless"
sudo sed -i '/# end of file/i persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
# 替换相机
echo -e "${Red}- 替换相机"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/*
sudo cat "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.1 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.2 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.3 >"$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/
# 替换相机标定
echo -e "${Red}- 替换相机标定"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/CameraTools_beta.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 占位广告应用
echo -e "${Red}- 占位广告应用"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA
# 替换开机动画
echo -e "${Red}- 替换开机动画"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/bootanimation.zip "$GITHUB_WORKSPACE"/images/product/media/bootanimation.zip
# 替换完美图标
echo -e "${Red}- 替换完美图标"
cd "$GITHUB_WORKSPACE"
git clone --depth=1 https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons &>/dev/null
for pkg in "$GITHUB_WORKSPACE"/images/product/media/theme/miui_mod_icons/dynamic/*; do
  if [[ -d "$GITHUB_WORKSPACE"/icons/icons/$pkg ]]; then
    rm -rf "$GITHUB_WORKSPACE"/icons/icons/$pkg
  fi
done
rm -rf "$GITHUB_WORKSPACE"/icons/icons/com.xiaomi.scanner
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip
rm -rf "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
mkdir -p "$GITHUB_WORKSPACE"/icons/res
mv "$GITHUB_WORKSPACE"/icons/icons "$GITHUB_WORKSPACE"/icons/res/drawable-xxhdpi
cd "$GITHUB_WORKSPACE"/icons
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip res
cd "$GITHUB_WORKSPACE"/icons/themes/Hyper/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd "$GITHUB_WORKSPACE"/icons/themes/common/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
rm -rf "$GITHUB_WORKSPACE"/icons
# 常规修改
echo -e "${Red}- 常规修改"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh
# 修复 init 崩溃
echo -e "${Red}- 修复 init 崩溃"
sudo sed -i "/start qti-testscripts/d" "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/init/hw/init.qcom.rc
# 内置 TWRP
echo -e "${Red}- 内置 TWRP"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/recovery.zip -d "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
# 添加刷机脚本
echo -e "${Red}- 添加刷机脚本"
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
echo -e "${Red}- 移除 Android 签名校验"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
cd "$GITHUB_WORKSPACE"/apk
sudo $apktool_jar d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read -r i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "${Yellow}- ${i} 修改成功"
done
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $apktool_jar b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar
# 替换更改文件/删除多余文件
echo -e "${Red}- 替换更改文件/删除多余文件"
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img
echo -e "${Red}- 开始打包super.img"
Start_Time
partitions=("mi_ext" "odm" "product" "system" "system_ext" "system_dlkm" "vendor" "vendor_dlkm")
for partition in "${partitions[@]}"; do
  echo -e "${Red}- 正在生成: $partition"
  sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
  sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts
  sudo $erofs_mkfs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$partition --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts "$GITHUB_WORKSPACE"/images/$partition.img "$GITHUB_WORKSPACE"/images/$partition
  eval "${partition}_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk '{print $1}')"
  sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
done
sudo rm -rf "$GITHUB_WORKSPACE"/images/config
$lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$GITHUB_WORKSPACE"/images/system_dlkm.img --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:8321499136 --metadata-slots 3 --group qti_dynamic_partitions_a:8321499136 --group qti_dynamic_partitions_b:8321499136 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
End_Time 打包super
for i in mi_ext odm product system system_ext system_dlkm vendor vendor_dlkm; do
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
### 生成 super.img 结束

### 输出卡刷包
echo -e "${Red}- 开始生成卡刷包"
echo -e "${Red}- 开始压缩super.zst"
Start_Time
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -12 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
End_Time 压缩super.zst
# 生成卡刷包
echo -e "${Red}- 生成卡刷包"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/miui_${device}_${port_os_version}.zip "$GITHUB_WORKSPACE"/images/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time 压缩卡刷包
# 定制 ROM 包名
echo -e "${Red}- 定制 ROM 包名"
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_${device}_${port_os_version}.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="miui_HOUJI_${port_os_version}_${zip_md5}_${android_version}.0_YuKongA.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/miui_${device}_${port_os_version}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
### 输出卡刷包结束
