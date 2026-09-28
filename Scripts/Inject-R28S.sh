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
# 实测 ImmortalWrt 02_network 结构: 两个 case "$board" in ——
#   rockchip_setup_interfaces(){ case "$board" in ... }  <- 网口映射(要插这里)
#   rockchip_setup_macs(){ case "$board" in ... }        <- MAC 地址(不能插这)
# 所以必须【只在第一个 case "$board" in 之后插入一次】, 用 done 标志防止二次插入
# (设备端血泪教训: 无标志会双插入, 还需额外去重).
# R28S = 双口(非switch): lan=eth1 wan=eth0, 与上游 friendlyarm,nanopi-r3s 等同组写法.
NET="$BOARD_D/02_network"
if [ -f "$NET" ] && ! grep -q "friendlyelec,nanopi-r28s" "$NET"; then
	awk '!done && /case "\$board" in/ {
		print;
		print "\tfriendlyelec,nanopi-r28s)";
		print "\t\tucidef_set_interfaces_lan_wan \x27eth1\x27 \x27eth0\x27";
		print "\t\t;;";
		done=1;
		next
	} 1' "$NET" > "$NET.tmp" && mv "$NET.tmp" "$NET"
	# 校验: 只插入一次(出现 1 次 r28s), 且在 interfaces 函数内
	cnt=$(grep -c "friendlyelec,nanopi-r28s" "$NET")
	echo "[3] 02_network mapping added (r28s count=$cnt, expect 1)"
else
	echo "[3] 02_network already has r28s or file missing, skip"
fi

# ---- 4) board.d LED 映射 ----
# 按官方 friendlywrt 01_leds 原版写法(friendlyelec,nanopi-r28s 段):
#   ucidef_set_led_netdev "wan" "WAN" "wan_led" "eth0" / "lan" "LAN" "lan_led" "eth1"
# LED 名必须用 dts 的 label 名(wan_led/lan_led/sys_led), 与官方 LuCI 网口图标一致.
# 主线 6.18 led_compose_name 有 label 属性即以其为 LED 名, 与官方完全对上.
# ★在 'case $board in' 之【后】插入(分支进 case 内部)★
#   之前插在 board_config_update 前 -> 跑到 case 语句外 -> "syntax error: unexpected )".
LEDS="$BOARD_D/01_leds"
if [ -f "$LEDS" ] && ! grep -q "friendlyelec,nanopi-r28s" "$LEDS"; then
	awk '!done && /^case \$board in/ {
		print;
		print "friendlyelec,nanopi-r28s)";
		print "\tucidef_set_led_netdev \"wan\" \"WAN\" \"wan_led\" \"eth0\"";
		print "\tucidef_set_led_netdev \"lan\" \"LAN\" \"lan_led\" \"eth1\" ;;";
		done=1;
		next
	} 1' "$LEDS" > "$LEDS.tmp" && mv "$LEDS.tmp" "$LEDS"
	cnt=$(grep -c "friendlyelec,nanopi-r28s" "$LEDS")
	echo "[4] 01_leds mapping added (r28s count=$cnt, expect 1)"
else
	echo "[4] 01_leds already has r28s or file missing, skip"
fi

# ---- 5) 首启清理 boot 分区自动挂载(对齐官方干净挂载点) ----
# 官方 friendlywrt 在 setup.sh 的 clean_fstab() 里首启删掉除 /opt 外所有 mount 项,
# 所以官方挂载点干净, 没有 /mnt/mmcblk0p1. 我们照搬: uci-defaults 首启脚本把
# block detect 自动生成的 mmcblk0p1(boot 分区, 128MB 装 kernel/dtb)挂载项删掉.
# boot 分区系统启动用不到(内核/dtb 由 u-boot 直接读), 挂出来纯属碍眼.
UDIR="$RK_DIR/armv8/base-files/etc/uci-defaults"
mkdir -p "$UDIR"
cat > "$UDIR/99-r28s-clean-mount" <<'EOF'
#!/bin/sh
# R28S: 删掉 block-mount 自动挂载的 eMMC boot 分区(/mnt/mmcblk0p1), 对齐官方干净挂载点
index=0
while uci -q get fstab.@mount[$index]; do
	target=$(uci -q get fstab.@mount[$index].target)
	uuid_dev=$(uci -q get fstab.@mount[$index].device)
	case "$target" in
	/mnt/mmcblk0p1|/mnt/mmcblk2p1)
		uci -q del fstab.@mount[$index] ;;
	*)
		index=$((index + 1)) ;;
	esac
done
uci commit fstab
# 顺手卸载已挂上的(若本次已挂)
umount /mnt/mmcblk0p1 2>/dev/null
exit 0
EOF
chmod +x "$UDIR/99-r28s-clean-mount"
echo "[5] uci-defaults clean-mount installed"

# ---- 6) 移植官方 eMMC Tools (LuCI 应用) ----
# 官方 friendlyarm/friendlywrt_device_common/emmc-tools/ 只有预编译 apk(无源码).
# 官方用 install.sh 在构建时 apk --root add 离线装进 rootfs.
# 我们把 apk 拷进固件 /root/, 首刷后用户手动 apk add --allow-untrusted 试装,
# 验证与 ImmortalWrt APK 兼容后再固化(避免不兼容把构建搞挂).
EMMC_SRC="$PATCH_DIR/emmc-tools"
ROOT_FILES="$RK_DIR/armv8/base-files/root"
if [ -f "$EMMC_SRC/luci-app-emmc-tools.apk" ]; then
	mkdir -p "$ROOT_FILES/emmc-tools"
	cp -f "$EMMC_SRC/luci-app-emmc-tools.apk" "$ROOT_FILES/emmc-tools/"
	cp -f "$EMMC_SRC/luci-i18n-emmc-tools-zh-cn.apk" "$ROOT_FILES/emmc-tools/" 2>/dev/null || true
	echo "[6] emmc-tools apk -> /root/emmc-tools/ (手动试装)"
else
	echo "[6] emmc-tools apk not found, skip"
fi

echo "===== Inject done ====="
