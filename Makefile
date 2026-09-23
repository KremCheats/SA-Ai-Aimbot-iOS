ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = KremAimbot

KremAimbot_FILES = Tweak.mm
KremAimbot_CFLAGS = -fobjc-arc -I$(THEOS)/include
KremAimbot_CCFLAGS = -std=c++17
KremAimbot_FRAMEWORKS = Foundation UIKit QuartzCore CoreML Vision
KremAimbot_PRIVATE_FRAMEWORKS = IOKit
KremAimbot_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk
