# vendor/morphe/common/common-vendor.mk — prebuilt module list.
# MORPHE_INCLUDE_APPS (default true) is the master switch; MORPHE_INCLUDE_{YOUTUBE,MUSIC,REDDIT}
# (default true) are per-app switches. Effective inclusion is master AND per-app.
# All flags must be set before inheriting products/morphe.mk.

PRODUCT_SOONG_NAMESPACES += \
    vendor/morphe/morphemanager

ifeq ($(MORPHE_INCLUDE_APPS),true)

# App modules always exist when enabled: stock install in stock mode,
# patched-direct install in stockless mode (see common/Android.mk).
ifeq ($(MORPHE_INCLUDE_YOUTUBE),true)
PRODUCT_PACKAGES += \
    YouTube
endif
ifeq ($(MORPHE_INCLUDE_MUSIC),true)
PRODUCT_PACKAGES += \
    YTMusic
endif
ifeq ($(MORPHE_INCLUDE_REDDIT),true)
PRODUCT_PACKAGES += \
    Reddit
endif

# Mount-only modules exist only when the matching stock APK is supplied.
ifeq ($(MORPHE_INCLUDE_YOUTUBE),true)
ifneq ($(wildcard vendor/morphe/common/product/app/YouTube/com.google.android.youtube.apk),)
PRODUCT_PACKAGES += \
    YTPatched
endif
endif
ifeq ($(MORPHE_INCLUDE_MUSIC),true)
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk),)
PRODUCT_PACKAGES += \
    YTMusicPatched
endif
endif
ifeq ($(MORPHE_INCLUDE_REDDIT),true)
ifneq ($(wildcard vendor/morphe/common/product/app/Reddit/com.reddit.frontpage.apk),)
PRODUCT_PACKAGES += \
    RedditPatched
endif
endif

# Lib dirs exist whenever the lib set does, in either mode (vendorsetup.sh
# extracts it from stock when present, else from the patched APK itself —
# module APKs ship Deflated libs with extraction disabled, so without this
# the app dies at startup with UnsatisfiedLinkError).
ifeq ($(MORPHE_INCLUDE_YOUTUBE),true)
ifneq ($(wildcard vendor/morphe/common/product/app/YouTube/lib/arm64/*.so),)
PRODUCT_PACKAGES += \
    YouTube_libdir
endif
endif
ifeq ($(MORPHE_INCLUDE_MUSIC),true)
ifneq ($(wildcard vendor/morphe/common/product/app/YTMusic/lib/arm64/*.so),)
PRODUCT_PACKAGES += \
    YTMusic_libdir
endif
endif
ifeq ($(MORPHE_INCLUDE_REDDIT),true)
ifneq ($(wildcard vendor/morphe/common/product/app/Reddit/lib/arm64/*.so),)
PRODUCT_PACKAGES += \
    Reddit_libdir
endif
endif

endif # MORPHE_INCLUDE_APPS
