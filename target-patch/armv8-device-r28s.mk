define Device/friendlyarm_nanopi-r28s
  $(Device/rk3528)
  DEVICE_VENDOR := FriendlyARM
  DEVICE_MODEL := NanoPi R28S
  DEVICE_DTS := rk3528-nanopi-r28s
  UBOOT_DEVICE_NAME := nanopi-zero2-rk3528
  DEVICE_PACKAGES := kmod-r8169 kmod-aic8800-sdio aic8800-sdio-firmware kmod-bluetooth wpad-openssl
  # sysupgrade 平台校验: 运行时 board_name 来自 dts compatible(friendlyelec,...),
  # 而镜像元数据默认用 DEVICE_NAME(friendlyarm,...), 两套命名独立. 不加这行 sysupgrade -T 会报
  # "Device friendlyelec,nanopi-r28s not supported by this image". 加上后正常刷写.
  SUPPORTED_DEVICES += friendlyelec,nanopi-r28s
endef
TARGET_DEVICES += friendlyarm_nanopi-r28s
