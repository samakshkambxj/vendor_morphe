# vendor/morphe/products/morphe.mk — entry point.
# Inherit from your device or ROM product makefile:
#   $(call inherit-product, vendor/morphe/products/morphe.mk)
#
# Master switch for the patched apps (default on). Set BEFORE inheriting:
#   MORPHE_INCLUDE_APPS := false

MORPHE_INCLUDE_APPS ?= true

# Toggle app (privileged, platform-signed). It only controls the boot
# bind-mount, so stockless builds (patched installed directly) don't need
# it. Opt out in your device.mk BEFORE inheriting this file:
#   MORPHE_INCLUDE_MANAGER := false
MORPHE_INCLUDE_MANAGER ?= true
ifeq ($(MORPHE_INCLUDE_MANAGER),true)
PRODUCT_PACKAGES += \
    MorpheManager
endif

# Stock + patched prebuilts
$(call inherit-product, vendor/morphe/common/common-vendor.mk)

# Sepolicy (init mount rules, manager domain, property type)
include vendor/morphe/sepolicy/SEPolicy.mk

# Boot-time bind-mount scripts (one per app), shipped only for apps that have
# a stock base to mount over — and only when the apps are enabled at all.
# Stockless apps install patched directly and need no mount.
ifeq ($(MORPHE_INCLUDE_APPS),true)
ifneq ($(wildcard vendor/morphe/common/product/app/YouTube/com.google.android.youtube.apk),)
PRODUCT_COPY_FILES += \
    vendor/morphe/common/product/etc/init/init.morphe.yt.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/init.morphe.yt.rc
endif
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk),)
PRODUCT_COPY_FILES += \
    vendor/morphe/common/product/etc/init/init.morphe.music.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/init.morphe.music.rc
endif
endif

# Mod enabled by default; MorpheManager flips this (reboot to apply)
PRODUCT_PRODUCT_PROPERTIES += \
    persist.sys.morphe.mod=true
