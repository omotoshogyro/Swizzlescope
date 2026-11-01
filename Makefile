APP      := Swizzlescope
BUILD    := build
CC       := clang
MIN      := -mmacosx-version-min=13.0
CFLAGS   := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O1 -g $(MIN) -ICore -MMD -MP
LDFLAGS  := $(MIN)

CORE_SRC := $(wildcard Core/*.m)
APP_SRC  := $(wildcard App/*.m)
CLI_SRC  := CLI/main.m
FIX_SRC  := Fixture/FixtureClasses.m

CORE_OBJ := $(patsubst %.m,$(BUILD)/obj/%.o,$(CORE_SRC))
APP_OBJ  := $(patsubst %.m,$(BUILD)/obj/%.o,$(APP_SRC))
CLI_OBJ  := $(patsubst %.m,$(BUILD)/obj/%.o,$(CLI_SRC))

APP_BUNDLE := $(BUILD)/$(APP).app
APP_BIN    := $(APP_BUNDLE)/Contents/MacOS/$(APP)
CLI_BIN    := $(BUILD)/swizzlescope
FIX_BUNDLE := $(BUILD)/Fixture.bundle
FIX_BIN    := $(FIX_BUNDLE)/Contents/MacOS/Fixture

.PHONY: all app cli fixture test run clean

all: $(APP_BIN) $(CLI_BIN) $(FIX_BIN)
app: $(APP_BIN)
cli: $(CLI_BIN)
fixture: $(FIX_BIN)

$(BUILD)/obj/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(APP_BIN): $(CORE_OBJ) $(APP_OBJ) Resources/Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	$(CC) $(LDFLAGS) -framework Foundation -framework AppKit -framework UniformTypeIdentifiers $(CORE_OBJ) $(APP_OBJ) -o $@
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo
	codesign --force --sign - $(APP_BUNDLE)

$(CLI_BIN): $(CORE_OBJ) $(CLI_OBJ)
	$(CC) $(LDFLAGS) -framework Foundation $(CORE_OBJ) $(CLI_OBJ) -o $@
	codesign --force --sign - $@

$(FIX_BIN): $(FIX_SRC) Resources/Fixture-Info.plist
	@mkdir -p $(FIX_BUNDLE)/Contents/MacOS
	$(CC) $(CFLAGS) $(LDFLAGS) -bundle -framework Foundation -framework CoreGraphics $(FIX_SRC) -o $@
	cp Resources/Fixture-Info.plist $(FIX_BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(FIX_BUNDLE)

test: all
	Tests/run.sh

run: $(APP_BIN)
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD)

-include $(CORE_OBJ:.o=.d) $(APP_OBJ:.o=.d) $(CLI_OBJ:.o=.d)
