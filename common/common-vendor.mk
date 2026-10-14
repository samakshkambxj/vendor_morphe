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
    YTPatched \
    YouTube_libdir
endif
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk),)
PRODUCT_PACKAGES += \
    YTMusicPatched \
    YTMusic_libdir
endif
