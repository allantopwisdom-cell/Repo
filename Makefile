TARGET := iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide

TWEAK_NAME = Powercuff
Powercuff_FILES = Powercuff.x
Powercuff_FRAMEWORKS = Foundation
Powercuff_CFLAGS = -fobjc-arc
Powercuff_EXTRA_CFLAGS = -Wno-error=unused-parameter

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/prerm $(THEOS_STAGING_DIR)/DEBIAN/postrm
