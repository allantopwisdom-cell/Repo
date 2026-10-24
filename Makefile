TARGET := iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide

DEBUG = 0
FINALPACKAGE = 1

TWEAK_NAME = PowercuffBaldaranTrusted
PowercuffBaldaranTrusted_FILES = Powercuff.x
PowercuffBaldaranTrusted_FRAMEWORKS = Foundation
PowercuffBaldaranTrusted_CFLAGS = -fobjc-arc -Wall

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/prerm $(THEOS_STAGING_DIR)/DEBIAN/postrm
