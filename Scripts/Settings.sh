#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE
#修改默认时区为北京时间(Asia/Shanghai, POSIX写法 CST-8; 默认是 timezone='GMT0' zonename='UTC')
sed -i "s/timezone='GMT0'/timezone='CST-8'/g" $CFG_FILE
sed -i "s/zonename='UTC'/zonename='Asia\\/Shanghai'/g" $CFG_FILE
echo "default timezone set to Asia/Shanghai (CST-8)!"

#修改默认root密码为 password (默认为空, 写 /etc/shadow, MD5crypt 哈希)
echo 'root:$1$4C5K7.$KQSzgarR6TWvov9ZTlKPS0:0:0:99999:7:::' > ./package/base-files/files/etc/shadow
echo "default root password set to 'password'!"

#首启脚本: 修 iStore/taskd + 清理无效 apk 源
#1) /var/log/tasks 目录: taskd(iStore 装包执行器) 日志目录, /var 是 tmpfs 重启清空.
#   缺失时 task_add 写日志失败 → iStore 装包卡死(用户实测装包把系统搞挂的根因).
#2) 删掉 snapshots 官方不存在的 video 源(404), 避免 apk update 每次对它空等超时.
UDIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UDIR"
cat > "$UDIR/99-fix-istore-taskd" <<'EOF'
#!/bin/sh
# 每次首启确保 taskd 日志目录存在(iStore 装包依赖)
mkdir -p /var/log/tasks
# 删掉 apk 源里 404 的 video feed(官方 snapshots 无此目录, 留着只会让 update 空等)
sed -i '\#/aarch64_generic/video/packages.adb#d' /etc/apk/repositories.d/distfeeds.list 2>/dev/null
exit 0
EOF
chmod +x "$UDIR/99-fix-istore-taskd"
echo "uci-defaults 99-fix-istore-taskd installed!"

#首启脚本: IPv6 relay 模式(逐字照抄 OpenWrt 官方 wiki 的 "IPv6 relay" 配置)
#背景: 上级光猫是 ISP 桥接 ONT, 只给 WAN 单个 /64、不下发 DHCPv6-PD 前缀.
#   官方默认 RA server 模式靠 PD 分前缀, 此光猫下 LAN 拿不到公网 v6.
#   正确解 = relay 模式(odhcpd 把上游 RA/NDP/DHCPv6 转发到 LAN, 客户端直接从上游拿公网 v6).
#★三个坑(血泪教训): 别加 ra_flags/ra_management(官方 relay 配置没有, 加了反而干扰);
#   network.wan6 没有 "option relay" 这个有效选项(netifd 不认); 改完只重启 odhcpd 别 network restart.
cat > "$UDIR/98-ipv6-relay" <<'EOF'
#!/bin/sh
# 仅当 wan6 存在且 lan 尚未配成 relay 时写入(幂等, 避免覆盖用户后续手改)
if uci -q get network.wan6 >/dev/null && [ "$(uci -q get dhcp.lan.ra)" != "relay" ]; then
	# lan: 保留 dhcpv4=server(IPv4 DHCP 照常), 只把 v6 三项切到 relay
	uci set dhcp.lan.dhcpv6='relay'
	uci set dhcp.lan.ra='relay'
	uci set dhcp.lan.ndp='relay'
	# 清掉默认 RA server 模式带的 ra_flags(relay 模式不需要)
	uci -q delete dhcp.lan.ra_flags
	# wan6: relay + master(官方 wiki 逐字)
	uci set dhcp.wan6='dhcp'
	uci set dhcp.wan6.interface='wan6'
	uci set dhcp.wan6.master='1'
	uci set dhcp.wan6.ra='relay'
	uci set dhcp.wan6.dhcpv6='relay'
	uci set dhcp.wan6.ndp='relay'
	uci commit dhcp
fi
exit 0
EOF
chmod +x "$UDIR/98-ipv6-relay"
echo "uci-defaults 98-ipv6-relay installed!"

#首启脚本: IPTV 组播转单播(rtp2httpd)防火墙+路由+IGMP 一键就绪(2026-09-30 真机反复试错定案)
#适用场景: 双 WAN(上网 + IPTV 专网 iptv, 湖南电信), rtp2httpd 跑在路由器上, 组播从 iptv 口进.
#★根因与三要素(血泪):
#  1) 组播路由默认走上网口, IGMP 加组发错口 → 必须把组播路由指到 iptv 口;
#  2) 组播 UDP 会被 wan zone 的 fullcone NAT/conntrack 误处理, 且 wan 链 iifname 只绑上网设备
#     匹配不到 iptv 口 → 必须建独立 iptv zone(按接口匹配, 不开 masq), 让组播绕开 NAT 直接放行;
#  3) 运营商 IPTV 用 IGMPv2 → force_igmp_version=2(实测 v3/auto 收不到流).
#★为什么用 zone 而不是 IP 段规则: 不同运营商组播地址不一定是 224.0.0.0/4, 按接口匹配最通用.
#★对齐 JDC 8c5e81f 的「接口后建漏建」修复: zone 是防火墙规则容器, 建不建跟 iptv 接口存不存在、
#  up不up完全无关 → uci-defaults 无条件先建 zone(不等接口); 接口判断只用于组播路由/IGMP 这类
#  跟接口设备绑定的部分(交给 hotplug, 接口 up 时取到 DEV 再补).
cat > "$UDIR/97-iptv-multicast" <<'EOF'
#!/bin/sh
# 无条件先建 iptv zone(zone 是规则容器, 不依赖 iptv 接口存在/up; 幂等)
if ! uci -q get firewall.iptv >/dev/null; then
	uci set firewall.iptv='zone'
	uci set firewall.iptv.name='iptv'
	uci set firewall.iptv.network='iptv'
	uci set firewall.iptv.input='ACCEPT'
	uci set firewall.iptv.output='ACCEPT'
	uci set firewall.iptv.forward='DROP'
	uci set firewall.iptv.masq='0'
	uci set firewall.iptv.mtu_fix='0'
	uci commit firewall
fi
# IGMP v2 持久化(sysctl.conf, 每次 boot 生效; all/default 兜底, 具体接口由 hotplug 补)
echo 2 > /proc/sys/net/ipv4/conf/all/force_igmp_version 2>/dev/null
echo 2 > /proc/sys/net/ipv4/conf/default/force_igmp_version 2>/dev/null
grep -q 'force_igmp_version' /etc/sysctl.conf 2>/dev/null || cat >> /etc/sysctl.conf <<'SYSCTL'
net.ipv4.conf.all.force_igmp_version=2
net.ipv4.conf.default.force_igmp_version=2
SYSCTL
exit 0
EOF
chmod +x "$UDIR/97-iptv-multicast"
echo "uci-defaults 97-iptv-multicast installed!"

#配套: hotplug 脚本——iptv 接口 ifup/ifupdate/update 时: 先无条件建 zone, 再取 DEV 补组播路由+IGMP v2
#(uci-defaults 只首启跑一次且接口可能开机后才建; pppoe/dhcp 接口又是动态重建. 故 zone+路由+IGMP
# 全部由 hotplug 兜底: zone 不等接口 up, 路由/IGMP 需 DEV 才补, 取不到 DEV 跳过但 zone 照建.
# 触发放宽到 ifup|ifupdate|update, 覆盖「先建接口后 up」和「改接口」两种场景)
HOTDIR="./package/base-files/files/etc/hotplug.d/iface"
mkdir -p "$HOTDIR"
cat > "$HOTDIR/97-iptv-multicast" <<'EOF'
#!/bin/sh
# IPTV 组播三要素 hotplug 兜底: iptv 接口 up/更新 时补建 zone+组播路由+IGMPv2
case "$ACTION" in
	ifup|ifupdate|update) ;;
	*) exit 0 ;;
esac
[ "$INTERFACE" = "iptv" ] || exit 0

# 1) zone 无条件建(不等接口 up/取 DEV; 幂等)
if ! uci -q get firewall.iptv >/dev/null; then
	uci set firewall.iptv='zone'
	uci set firewall.iptv.name='iptv'
	uci set firewall.iptv.network='iptv'
	uci set firewall.iptv.input='ACCEPT'
	uci set firewall.iptv.output='ACCEPT'
	uci set firewall.iptv.forward='DROP'
	uci set firewall.iptv.masq='0'
	uci set firewall.iptv.mtu_fix='0'
	uci commit firewall
	/etc/init.d/firewall reload >/dev/null 2>&1
fi

# 2) 取接口实际设备 DEV(双路径): 优先 ubus 运行时 l3_device, 取不到退 uci 配置的 device
DEV=$(ubus call network.interface.iptv status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
[ -z "$DEV" ] && DEV=$(uci -q get network.iptv.device 2>/dev/null)
[ -z "$DEV" ] && exit 0   # 取不到 DEV 则跳过路由/IGMP, 但 zone 已在上面建好

# 3) 组播路由指向 iptv 口(否则走上网口, IGMP 发错口) + IGMP v2(运营商 IPTV 只认 v2)
ip route replace 224.0.0.0/4 dev "$DEV" 2>/dev/null
ip route replace 239.0.0.0/8 dev "$DEV" 2>/dev/null
echo 2 > /proc/sys/net/ipv4/conf/"$DEV"/force_igmp_version 2>/dev/null
exit 0
EOF
chmod +x "$HOTDIR/97-iptv-multicast"
echo "hotplug.d/iface/97-iptv-multicast installed!"

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#注: 不装 luci-app-$WRT_THEME-config(主题配置器), 用主题原始状态(用户要求删除 argon-config)

#apk软件源(snapshots 滚动版)
#★2026-09-28 实测: 国内镜像对 snapshots 全部不可用——清华/USTC/阿里/腾讯 404,
#  SJTU 有但把 packages.adb 302 重定向到 mirrors.zju.edu.cn(浙大), 而浙大仅 ~6KB/s 巨慢,
#  GNU wget 跟随重定向后卡死(每源等 60s 超时), 导致 apk update/iStore 装包巨慢甚至卡死.
#  反而官方源 downloads.immortalwrt.org 走 Cloudflare CDN 最快(148KB/s, update 15 秒).
#  故 snapshots 直接用官方源, 不用国内镜像.
#VERSION_REPO 是编译变量, 写进 /etc/apk/repositories.d/distfeeds.list
#坑: 依赖链 CONFIG_IMAGEOPT -> CONFIG_VERSIONOPT -> CONFIG_VERSION_REPO, 三级都要=y
#    VERSION_REPO 在 image-config.in 里被 "if VERSIONOPT" 包裹, 而 VERSIONOPT 又是 "if IMAGEOPT" 的 menuconfig(default n)
#    少开任何一个, kconfig(olddefconfig) 都会把下级的 REPO 丢弃, 源静默不生效(25ebdcf/d1ea589/2f8abc2 三批都因此白改)
echo 'CONFIG_IMAGEOPT=y' >> ./.config
echo 'CONFIG_VERSIONOPT=y' >> ./.config
echo 'CONFIG_VERSION_REPO="https://downloads.immortalwrt.org/snapshots"' >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#Rockchip 平台调整 (NanoPi R28S)
if [[ "${WRT_TARGET^^}" == *"ROCKCHIP"* ]]; then
	#注入 R28S 设备树/设备定义/board.d 映射
	if [ -f "$GITHUB_WORKSPACE/Scripts/Inject-R28S.sh" ]; then
		bash "$GITHUB_WORKSPACE/Scripts/Inject-R28S.sh"
	fi
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
	#其他调整
	echo "CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y" >> ./.config
fi


#注：FULL 版代理核心已由 sing-box(homeproxy) 换成 xray-core(passwall)，
#原先"固定 sing-box 到 1.14.1"的段落已移除——保留它会误改 passwall 自带的 sing-box Makefile。
