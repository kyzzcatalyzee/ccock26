ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCock26WiFi CCock26Cellular CCock26Bluetooth CCock26Hotspot

CCock26WiFi_FILES = PACCModule.m
CCock26WiFi_CFLAGS = -fobjc-arc -DPACC_KIND=0 -DPACC_MODULE=PACCWiFiModule -DPACC_VC_CLASS=PACCWiFiVC
CCock26WiFi_FRAMEWORKS = UIKit
CCock26WiFi_INSTALL_PATH = /Library/ControlCenter/Bundles
CCock26WiFi_RESOURCE_DIRS = Resources/WiFi

CCock26Cellular_FILES = PACCModule.m
CCock26Cellular_CFLAGS = -fobjc-arc -DPACC_KIND=1 -DPACC_MODULE=PACCCellularModule -DPACC_VC_CLASS=PACCCellularVC
CCock26Cellular_FRAMEWORKS = UIKit
CCock26Cellular_INSTALL_PATH = /Library/ControlCenter/Bundles
CCock26Cellular_RESOURCE_DIRS = Resources/Cellular

CCock26Bluetooth_FILES = PACCModule.m
CCock26Bluetooth_CFLAGS = -fobjc-arc -DPACC_KIND=2 -DPACC_MODULE=PACCBluetoothModule -DPACC_VC_CLASS=PACCBluetoothVC
CCock26Bluetooth_FRAMEWORKS = UIKit
CCock26Bluetooth_INSTALL_PATH = /Library/ControlCenter/Bundles
CCock26Bluetooth_RESOURCE_DIRS = Resources/Bluetooth

CCock26Hotspot_FILES = PACCModule.m
CCock26Hotspot_CFLAGS = -fobjc-arc -DPACC_KIND=3 -DPACC_MODULE=PACCHotspotModule -DPACC_VC_CLASS=PACCHotspotVC
CCock26Hotspot_FRAMEWORKS = UIKit
CCock26Hotspot_INSTALL_PATH = /Library/ControlCenter/Bundles
CCock26Hotspot_RESOURCE_DIRS = Resources/Hotspot

include $(THEOS_MAKE_PATH)/bundle.mk
