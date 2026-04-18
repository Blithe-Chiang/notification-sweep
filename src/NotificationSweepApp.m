#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <string.h>

#import "NotificationSweepEngine.h"

static void ShowAlertAndTerminate(NSString *message, BOOL offerSettings) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Notification Sweep";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    if (offerSettings) {
        [alert addButtonWithTitle:@"Open Settings"];
    }

    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (offerSettings && response == NSAlertSecondButtonReturn) {
        NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }

    [NSApp terminate:nil];
}

@interface NotificationSweepAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation NotificationSweepAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        ShowAlertAndTerminate(@"请在“系统设置 > 隐私与安全性 > 辅助功能”里允许 Notification Sweep.app，然后再次点击 Dock 图标。", YES);
        return;
    }

    NSError *error = nil;
    (void)NotificationSweepPerformMatchingActions(NotificationSweepActionKindClearAll, &error);
    if (error != nil) {
        ShowAlertAndTerminate(error.localizedDescription, NO);
        return;
    }

    (void)NotificationSweepPerformMatchingActions(NotificationSweepActionKindClose, &error);
    if (error != nil) {
        ShowAlertAndTerminate(error.localizedDescription, NO);
        return;
    }

    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
            return NotificationSweepRunSelfTests();
        }

        if (argc > 1 && strcmp(argv[1], "--count-candidates") == 0) {
            return NotificationSweepPrintCandidateCounts();
        }

        if (argc > 2 && strcmp(argv[1], "--contains-text") == 0) {
            return NotificationSweepPrintContainsText([NSString stringWithUTF8String:argv[2]]);
        }

        [NSApplication sharedApplication];
        NotificationSweepAppDelegate *delegate = [[NotificationSweepAppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
