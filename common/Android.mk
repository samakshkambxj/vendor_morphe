# vendor/morphe — stock + patched prebuilts.
#
# Per-app mode selection: when the stock APK is supplied it is installed as
# the signature source and the patched build mounts over it at boot; when it
# is absent (stockless ROMs ship no Google apps) the patched build IS the
# installed app. Module names stay identical across modes; only the
# mount-only modules (YTPatched/YTMusicPatched) exist in stock mode, while
# the libdirs exist in both modes whenever the lib set is present
# (see common-vendor.mk). ETC class installs files byte-for-byte with no
# re-signing or dexpreopt either way.
LOCAL_PATH := $(call my-dir)

# ---- YouTube ----
ifneq ($(wildcard $(LOCAL_PATH)/product/app/YouTube/com.google.android.youtube.apk),)

# Stock YouTube (install-time signature source)
include $(CLEAR_VARS)
LOCAL_MODULE := YouTube
LOCAL_SRC_FILES := product/app/YouTube/com.google.android.youtube.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YouTube
LOCAL_INSTALLED_MODULE_STEM := com.google.android.youtube.apk
LOCAL_PRODUCT_MODULE := true
include $(BUILD_PREBUILT)

# Patched YouTube (bind-mounted over stock at boot, see init.morphe.yt.rc)
include $(CLEAR_VARS)
LOCAL_MODULE := YTPatched
LOCAL_SRC_FILES := product/etc/rv/YTPatched.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/etc/rv
LOCAL_INSTALLED_MODULE_STEM := YTPatched.apk
include $(BUILD_PREBUILT)

else

# Stockless: patched build installed directly as the YouTube app.
include $(CLEAR_VARS)
LOCAL_MODULE := YouTube
LOCAL_SRC_FILES := product/etc/rv/YTPatched.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YouTube
LOCAL_INSTALLED_MODULE_STEM := com.google.android.youtube.apk
LOCAL_PRODUCT_MODULE := true
include $(BUILD_PREBUILT)

endif

# ---- YT Music ----
ifneq ($(wildcard $(LOCAL_PATH)/product/app/YTMusic/com.google.android.apps.youtube.music.apk),)

# Stock YT Music (install-time signature source)
include $(CLEAR_VARS)
LOCAL_MODULE := YTMusic
LOCAL_SRC_FILES := product/app/YTMusic/com.google.android.apps.youtube.music.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YTMusic
LOCAL_INSTALLED_MODULE_STEM := com.google.android.apps.youtube.music.apk
LOCAL_PRODUCT_MODULE := true
include $(BUILD_PREBUILT)

# Patched YT Music (bind-mounted over stock at boot)
include $(CLEAR_VARS)
LOCAL_MODULE := YTMusicPatched
LOCAL_SRC_FILES := product/etc/rv/YTMusicPatched.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/etc/rv
LOCAL_INSTALLED_MODULE_STEM := YTMusicPatched.apk
include $(BUILD_PREBUILT)

else

# Stockless: patched build installed directly as the YT Music app.
include $(CLEAR_VARS)
LOCAL_MODULE := YTMusic
LOCAL_SRC_FILES := product/etc/rv/YTMusicPatched.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YTMusic
LOCAL_INSTALLED_MODULE_STEM := com.google.android.apps.youtube.music.apk
LOCAL_PRODUCT_MODULE := true
include $(BUILD_PREBUILT)

endif

# ---- Native lib dirs (both modes) ----
# Module APKs keep their .so files Deflated with extraction disabled, so
# PackageManager never materializes them and startup dies with
# UnsatisfiedLinkError (libelements.so) without these. Defined whenever the
# lib set exists, however it got there: vendorsetup.sh extracts it from the
# stock APK when present, else from the patched APK itself.
# placeholder.txt keeps the dir tracked in git, *.so stays ignored.
ifneq ($(wildcard $(LOCAL_PATH)/product/app/YouTube/lib/arm64/*.so),)
include $(CLEAR_VARS)
LOCAL_MODULE := YouTube_libdir
LOCAL_MODULE_CLASS := ETC
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YouTube/lib
LOCAL_PREBUILT_MODULE_FILE := $(LOCAL_PATH)/product/app/YouTube/lib/placeholder.txt
LOCAL_POST_INSTALL_CMD := \
    mkdir -p $(LOCAL_MODULE_PATH); \
    cp -rf $(LOCAL_PATH)/product/app/YouTube/lib/* $(LOCAL_MODULE_PATH)/
include $(BUILD_PREBUILT)
endif

ifneq ($(wildcard $(LOCAL_PATH)/product/app/YTMusic/lib/arm64/*.so),)
include $(CLEAR_VARS)
LOCAL_MODULE := YTMusic_libdir
LOCAL_MODULE_CLASS := ETC
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YTMusic/lib
LOCAL_PREBUILT_MODULE_FILE := $(LOCAL_PATH)/product/app/YTMusic/lib/placeholder.txt
LOCAL_POST_INSTALL_CMD := \
    mkdir -p $(LOCAL_MODULE_PATH); \
    cp -rf $(LOCAL_PATH)/product/app/YTMusic/lib/* $(LOCAL_MODULE_PATH)/
include $(BUILD_PREBUILT)
endif
