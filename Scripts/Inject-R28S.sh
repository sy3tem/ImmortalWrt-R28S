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
# ★compatible 前缀必须与 dts 一致 = "friendlyelec,nanopi-r28s"(不是 friendlyarm!)★
# 之前错写成 friendlyarm,nanopi-r28s 挂到 r3s 组, board_detect 用 dts compatible
# (friendlyelec,nanopi-r28s) 匹配 -> 永远匹配不到 -> 网口映射失效只剩默认单口.
# 按官方 friendlywrt 02_network 原版: wan=eth0 lan=eth1(独立 case),
# 并在 MAC 段补 wan_mac/lan_mac(官方从 mmc cid 生成, lan=wan+1).
NET="$BOARD_D/02_network"
if [ -f "$NET" ] && ! grep -q "friendlyelec,nanopi-r28s" "$NET"; then
	# 网口映射: 在 ucidef_set_interfaces_lan_wan 主 case 末尾(board_config_update 前)插入独立分支
	sed -i "/ucidef_set_interface_wan 'eth0'/i\\
friendlyelec,nanopi-r28s)\\
	ucidef_set_interface_wan 'eth0'\\
	ucidef_set_interface \"lan\" device \"eth1\" protocol \"static\" ipaddr \"192.168.10.1\"\\
	;;\\
" "$NET"
	# MAC 生成: 在 wan_mac=...mmcblk* 的 case 组里补 r28s(跟在 nanopi-r3s 同组写法)
	sed -i 's/friendlyelec,nanopi-r3s|\\/friendlyelec,nanopi-r3s|\\\n\tfriendlyelec,nanopi-r28s|\\/' "$NET"
	echo "[3] 02_network mapping added"
else
	echo "[3] 02_network already has r28s or file missing, skip"
fi

# ---- 4) board.d LED 映射 ----
# 按官方 friendlywrt 01_leds 原版写法(friendlyelec,nanopi-r28s 段):
#   ucidef_set_led_netdev "wan" "WAN" "wan_led" "eth0"
#   ucidef_set_led_netdev "lan" "LAN" "lan_led" "eth1"
# LED 名必须用 dts 的 label 名(wan_led/lan_led/sys_led), 与官方 LuCI 网口图标一致.
# 主线 6.18 led_compose_name 有 label 属性即以其为 LED 名, 与官方完全对上.
# 注意: 只 sed 追加 case 分支, 不整文件覆盖(覆盖会丢上游 base-files 开头的 include).
LEDS="$BOARD_D/01_leds"
if [ -f "$LEDS" ] && ! grep -q "friendlyelec,nanopi-r28s" "$LEDS"; then
	sed -i "/board_config_update/i\\
friendlyelec,nanopi-r28s)\\
	ucidef_set_led_netdev \"wan\" \"WAN\" \"wan_led\" \"eth0\"\\
	ucidef_set_led_netdev \"lan\" \"LAN\" \"lan_led\" \"eth1\" ;;\\
" "$LEDS"
	echo "[4] 01_leds mapping added"
else
	echo "[4] 01_leds already has r28s or file missing, skip"
fi

echo "===== Inject done ====="
