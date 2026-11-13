THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCOCK26
CCOCK26_FILES = tweak.xm PACC.x PAnim.x PACCIndicator.x PACCMedia.x PACCCoordinator.x PACCDesign.x PACCEdit.xm PACCLIQ.x PACCBig.x PACCCrash.x

CCOCK26_CFLAGS = -fobjc-arc 
CCOCK26_FRAMEWORKS = UIKit CFNetwork
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs modules

include $(THEOS_MAKE_PATH)/aggregate.mk
after-install::
	install.exec "sbreload"