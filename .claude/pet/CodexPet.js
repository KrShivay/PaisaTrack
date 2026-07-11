ObjC.import("AppKit");

const app = $.NSApplication.sharedApplication;
app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

const width = 136;
const height = 104;
const frame = $.NSMakeRect(0, 0, width, height);
const panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
  frame,
  $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
  $.NSBackingStoreBuffered,
  false,
);

panel.level = $.NSFloatingWindowLevel;
panel.opaque = false;
panel.backgroundColor = $.NSColor.clearColor;
panel.hasShadow = true;
panel.movableByWindowBackground = true;
panel.hidesOnDeactivate = false;
panel.collectionBehavior =
  $.NSWindowCollectionBehaviorCanJoinAllSpaces |
  $.NSWindowCollectionBehaviorFullScreenAuxiliary;

const imageView = $.NSImageView.alloc.initWithFrame(frame);
imageView.enabled = false;
imageView.imageScaling = $.NSImageScaleProportionallyUpOrDown;
imageView.image = $.NSImage.alloc.initWithContentsOfFile(
  $.NSProcessInfo.processInfo.environment.objectForKey("CODEX_PET_IMAGE"),
);
panel.contentView = imageView;

const screen = $.NSScreen.mainScreen.visibleFrame;
panel.setFrameOrigin(
  $.NSMakePoint(
    screen.origin.x + screen.size.width - width - 28,
    screen.origin.y + 44,
  ),
);
panel.orderFrontRegardless;

app.run;
