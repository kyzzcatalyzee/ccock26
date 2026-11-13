ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCOCK26Prefs

CCOCK26Prefs_FILES = CCOCK26RootListController.m
CCOCK26Prefs_FRAMEWORKS = UIKit
CCOCK26Prefs_PRIVATE_FRAMEWORKS = Preferences
CCOCK26Prefs_INSTALL_PATH = /Library/PreferenceBundles
CCOCK26Prefs_CFLAGS = -fobjc-arc
CCOCK26Prefs_RESOURCE_DIRS = Resources


include $(THEOS_MAKE_PATH)/bundle.mk

after-CCOCK26Prefs-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp "Resources/CCOCK26Prefs.plist" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CCOCK26Prefs.plist"