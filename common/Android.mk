# vendor/morphe — stock + patched prebuilts.
#
# Design: stock APKs are installed as regular product apps (valid stock
# signatures at install/scan time), patched APKs ship as inert data files
# under product/etc/rv, and init.morphe.rc bind-mounts the patched file
# over the stock path at boot. Because the swap happens below
# PackageManager, no re-signing or dexpreopt of the 100MB+ patched blobs
# is needed at build time. ETC class is deliberate: it installs the file
# byte-for-byte without APK processing.
LOCAL_PATH := $(call my-dir)

# Stock YouTube (install-time signature source)
include $(CLEAR_VARS)
LOCAL_MODULE := YouTube
LOCAL_SRC_FILES := product/app/YouTube/com.google.android.youtube.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/app/YouTube
LOCAL_INSTALLED_MODULE_STEM := com.google.android.youtube.apk
LOCAL_PRODUCT_MODULE := true
include $(BUILD_PREBUILT)

# Patched YouTube (bind-mounted over stock at boot, see init.morphe.rc)
include $(CLEAR_VARS)
LOCAL_MODULE := YTPatched
LOCAL_SRC_FILES := product/etc/rv/YTPatched.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/etc/rv
LOCAL_INSTALLED_MODULE_STEM := YTPatched.apk
include $(BUILD_PREBUILT)

# YouTube native libs (extracted from the stock APK by vendorsetup.sh;
# placeholder.txt keeps the dir tracked in git, *.so stays ignored)
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

# YT Music native libs (extracted from the stock APK by vendorsetup.sh)
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
