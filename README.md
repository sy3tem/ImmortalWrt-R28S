# ImmortalWrt-R28S

NanoPi R28S（RK3528A）的 ImmortalWrt 主线云编译仓库，GitHub Actions 驱动。

## 设备

- **NanoPi R28S**：SoC RK3528A（四核 A53 + Mali-450），1GB LPDDR4，eMMC + microSD
- **网口**：双千兆 = gmac1（RGMII→RTL8211F）+ RTL8111H（PCIe），无 2.5G/RTL8125
- **WiFi/BT**：AIC8800（SDIO0 + UART2），WiFi6 + BT5.3
- **LED**：SYS / LED1 / LED2（GPIO4 PB0/PB1/PB3）
- **按键**：USER(C) 键（GPIO4 PB2）、MASK 键（救砖进 Maskrom）

## 方案

- **源码**：ImmortalWrt 主线 `immortalwrt/immortalwrt` master（内核 6.18）
- **U-Boot**：复用主线已验证的 `nanopi-zero2-rk3528`（同 SoC RK3528A，DDR/TPL 初始化与板无关）
- **设备树**：`target-patch/rk3528-nanopi-r28s.dts`（按主线 Zero2 模板 + 官方 rev03 硬件定义），编译时经 `Scripts/Inject-R28S.sh` 注入源码树
- **代理**：passwall + xray-core（参照 JDC NO-FULL），其余 PassWall 组件全关
- **附加**：argon 主题、iStore 商店、rtp2httpd、dockerman、ttyd 等（见 `Config/GENERAL.txt`）

## 编译

手动触发 `R28S-ALL` workflow（Actions → R28S-ALL → Run workflow）：

- `CONFIGS`：JSON 数组，默认 `["RK3528-R28S-FULL"]`
- `TEST=true`：仅输出 `.config` 不编译（约 5 分钟，用于验证配置）
- 产物自动传到 Releases

## 刷机（防变砖）

- 第一版**先刷 microSD 卡**验证启动、双网口、WiFi，确认无误再考虑写 eMMC
- 任何情况下变砖都可用 **MASK 键进 Maskrom 模式 + RKDevTool** 重刷救回
- 默认登录：`192.168.10.1` / root / `password`

## 参考

- 设备树/结构复刻自 [sy3tem/ImmortalWrt-JDC](https://github.com/sy3tem/ImmortalWrt-JDC)
- 官方规格：https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R28S/zh
- 官方云编译参考：https://github.com/friendlyarm/Actions-FriendlyWrt
