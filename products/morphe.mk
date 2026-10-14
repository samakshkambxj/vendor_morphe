# vendor/morphe/products/morphe.mk — entry point.
# Inherit from your device or ROM product makefile:
#   $(call inherit-product, vendor/morphe/products/morphe.mk)

# Toggle app (privileged, platform-signed)
PRODUCT_PACKAGES += \
    MorpheManager

# Stock + patched prebuilts
$(call inherit-product, vendor/morphe/common/common-vendor.mk)

# Sepolicy (init mount rules, manager domain, property type)
include vendor/morphe/sepolicy/SEPolicy.mk

# Boot-time bind-mount scripts (one per app), shipped only for apps that have
# a stock base to mount over. Stockless apps install patched directly and
# need no mount.
ifneq ($(wildcard vendor/morphe/common/product/app/YouTube/com.google.android.youtube.apk),)
PRODUCT_COPY_FILES += \
    vendor/morphe/common/product/etc/init/init.morphe.yt.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/init.morphe.yt.rc
endif
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk),)
PRODUCT_COPY_FILES += \
    vendor/morphe/common/product/etc/init/init.morphe.music.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/init.morphe.music.rc
endif

# Mod enabled by default; MorpheManager flips this (reboot to apply)
PRODUCT_PRODUCT_PROPERTIES += \
    persist.sys.morphe.mod=true
