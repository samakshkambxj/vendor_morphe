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

# Boot-time bind-mount script (applies patched APKs over stock paths)
PRODUCT_COPY_FILES += \
    vendor/morphe/common/product/etc/init/init.morphe.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/init.morphe.rc

# Mod enabled by default; MorpheManager flips this (reboot to apply)
PRODUCT_PRODUCT_PROPERTIES += \
    persist.sys.morphe.mod=true
