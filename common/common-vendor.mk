# vendor/morphe/common/common-vendor.mk — prebuilt module list.

PRODUCT_SOONG_NAMESPACES += \
    vendor/morphe/morphemanager

# YouTube/YTMusic modules always exist: stock install in stock mode,
# patched-direct install in stockless mode (see common/Android.mk).
PRODUCT_PACKAGES += \
    YouTube \
    YTMusic

# Mount-only modules exist only when the matching stock APK is supplied.
ifneq ($(wildcard vendor/morphe/common/product/app/YouTube/com.google.android.youtube.apk),)
PRODUCT_PACKAGES += \
    YTPatched
endif
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk),)
PRODUCT_PACKAGES += \
    YTMusicPatched
endif

# Lib dirs exist whenever the lib set does, in either mode (vendorsetup.sh
# extracts it from stock when present, else from the patched APK itself —
# module APKs ship Deflated libs with extraction disabled, so without this
# the app dies at startup with UnsatisfiedLinkError).
ifneq ($(wildcard vendor/morphe/common/product/app/YouTube/lib/arm64/*.so),)
PRODUCT_PACKAGES += \
    YouTube_libdir
endif
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/lib/arm64/*.so),)
PRODUCT_PACKAGES += \
    YTMusic_libdir
endif
