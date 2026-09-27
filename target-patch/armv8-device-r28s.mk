define Device/friendlyarm_nanopi-r28s
  $(Device/rk3528)
  DEVICE_VENDOR := FriendlyARM
  DEVICE_MODEL := NanoPi R28S
  DEVICE_DTS := rk3528-nanopi-r28s
  UBOOT_DEVICE_NAME := nanopi-zero2-rk3528
  DEVICE_PACKAGES := kmod-r8169 kmod-aic8800-sdio wpad-openssl
endef
TARGET_DEVICES += friendlyarm_nanopi-r28s
