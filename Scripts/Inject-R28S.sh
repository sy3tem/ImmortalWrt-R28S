#!/bin/bash
# SPDX-License-Identifier: MIT
# 把 NanoPi R28S (RK3528A) 支持注入到 ImmortalWrt 主线源码树
# 注入内容:
#   1) 内核设备树 rk3528-nanopi-r28s.dts -> target/linux/rockchip/files/.../dts/rockchip/
#   2) 设备定义追加到 target/linux/rockchip/image/armv8.mk
#   3) board.d/02_network 增加网口映射, board.d/01_leds 增加 LED 映射
# 调用时机: WRT-CORE 的 "Custom Packages" 阶段, 在源码树根目录执行
set -e

PATCH_DIR="$GITHUB_WORKSPACE/target-patch"
RK_DIR="./target/linux/rockchip"
DTS_DIR="$RK_DIR/files/arch/arm64/boot/dts/rockchip"
IMG_MK="$RK_DIR/image/armv8.mk"
BOARD_D="$RK_DIR/armv8/base-files/etc/board.d"

echo "===== Inject NanoPi R28S support ====="

# ---- 1) 注入内核设备树 ----
mkdir -p "$DTS_DIR"
cp -f "$PATCH_DIR/rk3528-nanopi-r28s.dts" "$DTS_DIR/rk3528-nanopi-r28s.dts"
echo "[1] dts installed -> $DTS_DIR/rk3528-nanopi-r28s.dts"

# ---- 2) 追加设备定义到 armv8.mk ----
if ! grep -q "friendlyarm_nanopi-r28s" "$IMG_MK"; then
	cat "$PATCH_DIR/armv8-device-r28s.mk" >> "$IMG_MK"
	echo "[2] device def appended -> $IMG_MK"
else
	echo "[2] device def already present, skip"
fi

# ---- 2.5) 让 r28s 触发编译 zero2 的 U-Boot ----
# 现象: pine64-img 打包时 dd 找不到 nanopi-zero2-rk3528-u-boot-rockchip.bin
# 根因: uboot-rockchip/Makefile 里 U-Boot/nanopi-zero2-rk3528 的 BUILD_DEVICES 只含
#       friendlyarm_nanopi-zero2, 不含新增的 friendlyarm_nanopi-r28s, 故编 r28s 时不编该 U-Boot
# 修法: 把 r28s 追加进该 target 的 BUILD_DEVICES 列表
UBOOT_MK="./package/boot/uboot-rockchip/Makefile"
if [ -f "$UBOOT_MK" ] && ! grep -A3 "define U-Boot/nanopi-zero2-rk3528" "$UBOOT_MK" | grep -q "friendlyarm_nanopi-r28s"; then
	sed -i '/define U-Boot\/nanopi-zero2-rk3528/,/endef/ s/friendlyarm_nanopi-zero2$/friendlyarm_nanopi-zero2 \\\n    friendlyarm_nanopi-r28s/' "$UBOOT_MK"
	echo "[2.5] nanopi-zero2-rk3528 U-Boot BUILD_DEVICES += r28s"
	grep -A5 "define U-Boot/nanopi-zero2-rk3528" "$UBOOT_MK" | head -8
else
	echo "[2.5] zero2 U-Boot already covers r28s or mk missing, skip"
fi

# ---- 3) board.d 网口映射 ----
NET="$BOARD_D/02_network"
if [ -f "$NET" ] && ! grep -q "friendlyarm,nanopi-r28s" "$NET"; then
	# 在 friendlyarm,nanopi-r3s 所在 case 组(lan=eth1, wan=eth0)后插入 r28s
	# R28S: gmac1(eth?) + RTL8111H PCIe(eth?), 枚举顺序 PCIe 通常靠前,
	# 采用与 R3S 相同映射: lan=eth1 wan=eth0; 首刷后用 dmesg 核对再微调
	sed -i 's/friendlyarm,nanopi-r3s|\\/friendlyarm,nanopi-r3s|\\\n\tfriendlyarm,nanopi-r28s|\\/' "$NET"
	echo "[3] 02_network mapping added"
else
	echo "[3] 02_network already has r28s or file missing, skip"
fi

# ---- 4) board.d LED 映射 ----
# 注意: 不能整文件覆盖 01_leds(会丢上游 base-files 开头的 . /lib/functions include,
# 导致 ucidef_set_led_default: not found). 只能 sed 在 case 里追加分支.
# LED 名必须写 dts 主线全名 "颜色:功能"(sysfs 名), 不能写官方旧 label(sys_led 找不到).
# R28S dts: sys=green:status / led1=green:lan / led2=green:wan.
LEDS="$BOARD_D/01_leds"
if [ -f "$LEDS" ] && ! grep -q "friendlyarm,nanopi-r28s" "$LEDS"; then
	sed -i "/board_config_update/i\\
friendlyarm,nanopi-r28s)\\
	ucidef_set_led_default \"status\" \"status\" \"green:status\" \"1\" ;;\\
" "$LEDS"
	echo "[4] 01_leds mapping added"
else
	echo "[4] 01_leds already has r28s or file missing, skip"
fi

echo "===== Inject done ====="
