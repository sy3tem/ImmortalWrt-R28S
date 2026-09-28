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
# R28S: 清理 block-mount 自动挂载, 对齐官方干净挂载点
# 1) 关掉匿名挂载(anon_mount/anon_swap): 这是 /opt 大分区被重复挂到 /mnt/mmcblk0p3 的
#    元凶 —— block-mount 早期 anon_mount 会把没在 fstab 显式占位的分区自动挂 /mnt/<dev>.
#    官方 friendlywrt 没关它(靠 /opt 项占位屏蔽), 但我们的 /opt 项是 init.d 后写的,
#    早期 block-mount 读不到 → anon_mount 兜底挂 /mnt. 关掉它最干净(副作用: 插U盘不自动挂/mnt).
uci set fstab.@global[0].anon_mount='0'
uci set fstab.@global[0].anon_swap='0'
# 2) 删掉非 /opt 的自动挂载项(boot 分区 /mnt/mmcblk0p1 等), 保留 /opt
index=0
while uci -q get fstab.@mount[$index]; do
	target=$(uci -q get fstab.@mount[$index].target)
	case "$target" in
	/opt)
		index=$((index + 1)) ;;
	*)
		uci -q del fstab.@mount[$index] ;;
	esac
done
uci commit fstab
# 3) 卸载已挂上的多余挂载 + 删掉残留空目录
for m in /mnt/mmcblk0p1 /mnt/mmcblk0p3 /mnt/mmcblk2p1 /mnt/mmcblk2p3; do
	umount "$m" 2>/dev/null
	findmnt -n "$m" >/dev/null 2>&1 || rmdir "$m" 2>/dev/null
done
exit 0
EOF
chmod +x "$UDIR/99-r28s-clean-mount"
echo "[5] uci-defaults clean-mount installed"

# ---- 5b) /opt 大分区(剩余空间) init.d 服务 ----
# 照搬官方 friendlywrt 的 /opt 大分区行为. 官方是编译期预建 opt:grow 分区(sd-fuse 打包),
# 我们 ImmortalWrt 不走那套, 改方案B: 首启新建分区占满剩余空间 + ext4 + 挂 /opt.
# 运行中的系统盘新建分区后内核拒读分区表须 reboot, 故用 init.d 两段式(非 uci-defaults).
# 脚本本体在 target-patch/opt-partition/r28s-opt-partition.init, 已在真机验证通过.
OPT_INIT_SRC="$PATCH_DIR/opt-partition/r28s-opt-partition.init"
INITD="$RK_DIR/armv8/base-files/etc/init.d"
RCD="$RK_DIR/armv8/base-files/etc/rc.d"
if [ -f "$OPT_INIT_SRC" ]; then
	mkdir -p "$INITD" "$RCD"
	cp -f "$OPT_INIT_SRC" "$INITD/r28s-opt-partition"
	chmod +x "$INITD/r28s-opt-partition"
	# 开机自启软链
	ln -sf ../init.d/r28s-opt-partition "$RCD/S99r28s-opt-partition"
	echo "[5b] /opt big-partition init.d service installed"
else
	echo "[5b] opt-partition init script not found, skip"
fi

# 注: eMMC Tools 已移除(2026-09-28). 实测在 R28S 上无法正常使用——
# 它是"从 SD 卡启动 → 烧录到板载 eMMC"的工具, 而 R28S 无 SD 卡槽使用场景
# (系统直接在 116.5G 板载 eMMC 上跑), 页面提示"请改用 SD 卡烧录", 功能不适用.

echo "===== Inject done ====="
