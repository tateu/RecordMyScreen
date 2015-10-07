TARGET=:clang
GO_EASY_ON_ME = 1
SDKVERSION = 7.0
ARCHS = armv7 arm64
PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)
include $(THEOS)/makefiles/common.mk
_THEOS_INTERNAL_CFLAGS += -w

TWEAK_NAME = RecordMyScreenTweak
RecordMyScreenTweak_FILES = ActivatorListener.mm ../RecordMyScreen/CSScreenRecorder.m CSWindow.m CSRecordQueryWindow.m CSRecordCompletionAlert.m
RecordMyScreenTweak_FRAMEWORKS = CoreGraphics QuartzCore UIKit AVFoundation CoreVideo CoreMedia
RecordMyScreenTweak_PRIVATE_FRAMEWORKS = IOSurface
RecordMyScreenTweak_CFLAGS = -I../RecordMyScreen/headers/ -I../RecordMyScreen/headers/IOSurface
RecordMyScreenTweak_LDFLAGS = -lactivator
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 backboardd"
