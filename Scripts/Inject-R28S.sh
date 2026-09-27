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
LEDS="$BOARD_D/01_leds"
if [ -f "$LEDS" ] && ! grep -q "friendlyarm,nanopi-r28s" "$LEDS"; then
	# 参照其它设备格式, 把 r28s 的 sys_led 设为 status LED
	# 直接在该文件的 case 里追加一个分支(放在 board_config_update 之前的 case 内)
	# 采用最简单的 uci 写法, 与 openwrt rockchip 01_leds 兼容
	sed -i "/board_config_update/i\\
	friendlyarm,nanopi-r28s)\\
		ucidef_set_led_default \"status\" \"status\" \"sys_led\" \"1\" ;;\\
" "$LEDS" 2>/dev/null || echo "[4] 01_leds patch skipped (format varies, non-fatal)"
	echo "[4] 01_leds mapping attempted"
else
	echo "[4] 01_leds already has r28s or file missing, skip"
fi

echo "===== Inject done ====="
