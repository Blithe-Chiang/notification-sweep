#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString *const kNotificationSweepBundleIdentifier = @"local.notification-sweep.app";
static NSString *const kNotificationCenterBundleIdentifier = @"com.apple.notificationcenterui";

typedef NS_ENUM(NSInteger, NotificationSweepActionKind) {
    NotificationSweepActionKindClearAll,
    NotificationSweepActionKindClose,
};

@interface NotificationSweepCandidate : NSObject
@property (nonatomic) AXUIElementRef element;
@property (nonatomic, copy) NSString *windowName;
@property (nonatomic, copy) NSString *actionName;
@property (nonatomic) NotificationSweepActionKind actionKind;
- (instancetype)initWithElement:(AXUIElementRef)element
                     windowName:(NSString *)windowName
                     actionName:(NSString *)actionName
                     actionKind:(NotificationSweepActionKind)actionKind;
@end

@implementation NotificationSweepCandidate

- (instancetype)initWithElement:(AXUIElementRef)element
                     windowName:(NSString *)windowName
                     actionName:(NSString *)actionName
                     actionKind:(NotificationSweepActionKind)actionKind {
    self = [super init];
    if (self) {
        _element = (AXUIElementRef)CFRetain(element);
        _windowName = [windowName copy] ?: @"Notification Center";
        _actionName = [actionName copy];
        _actionKind = actionKind;
    }
    return self;
}

- (void)dealloc {
    if (_element != NULL) {
        CFRelease(_element);
    }
}

@end

static id CopyAXAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (error != kAXErrorSuccess || value == NULL) {
        return nil;
    }
    return CFBridgingRelease(value);
}

static NSString *StringAXAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAXAttribute(element, attribute);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSArray *ChildrenOfElement(AXUIElementRef element) {
    id value = CopyAXAttribute(element, kAXChildrenAttribute);
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }
    return value;
}

static NSArray<NSString *> *ActionNamesForElement(AXUIElementRef element) {
    CFArrayRef actionNames = NULL;
    AXError error = AXUIElementCopyActionNames(element, &actionNames);
    if (error != kAXErrorSuccess || actionNames == NULL) {
        return @[];
    }
    return CFBridgingRelease(actionNames);
}

static NSString *NormalizedActionName(NSString *rawName) {
    if (rawName.length == 0) {
        return @"";
    }

    if ([rawName hasPrefix:@"Name:"]) {
        NSRange newlineRange = [rawName rangeOfString:@"\n"];
        NSString *firstLine = newlineRange.location == NSNotFound ? rawName : [rawName substringToIndex:newlineRange.location];
        return [firstLine substringFromIndex:5];
    }

    return rawName;
}

static void CollectCandidatesInElement(AXUIElementRef element,
                                       NSString *windowName,
                                       NSMutableArray<NotificationSweepCandidate *> *clearAllCandidates,
                                       NSMutableArray<NotificationSweepCandidate *> *closeCandidates) {
    NSString *role = StringAXAttribute(element, kAXRoleAttribute);
    if ([role isEqualToString:(__bridge NSString *)kAXButtonRole]) {
        NSArray<NSString *> *actions = ActionNamesForElement(element);
        NSString *clearAllAction = nil;
        NSString *closeAction = nil;

        for (NSString *action in actions) {
            NSString *normalized = NormalizedActionName(action);
            if ([normalized isEqualToString:@"Clear All"]) {
                clearAllAction = action;
            } else if ([normalized isEqualToString:@"Close"]) {
                closeAction = action;
            }
        }

        if (clearAllAction != nil) {
            [clearAllCandidates addObject:[[NotificationSweepCandidate alloc] initWithElement:element
                                                                                   windowName:windowName
                                                                                   actionName:clearAllAction
                                                                                   actionKind:NotificationSweepActionKindClearAll]];
        } else if (closeAction != nil) {
            [closeCandidates addObject:[[NotificationSweepCandidate alloc] initWithElement:element
                                                                                windowName:windowName
                                                                                actionName:closeAction
                                                                                actionKind:NotificationSweepActionKindClose]];
        }
    }

    for (id child in ChildrenOfElement(element)) {
        if (CFGetTypeID((__bridge CFTypeRef)child) == AXUIElementGetTypeID()) {
            CollectCandidatesInElement((__bridge AXUIElementRef)child, windowName, clearAllCandidates, closeCandidates);
        }
    }
}

static NSArray<NotificationSweepCandidate *> *CollectCandidatesForKind(NotificationSweepActionKind kind) {
    NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:kNotificationCenterBundleIdentifier];
    if (apps.count == 0) {
        return @[];
    }

    AXUIElementRef applicationElement = AXUIElementCreateApplication(apps.firstObject.processIdentifier);
    NSArray *windows = CopyAXAttribute(applicationElement, kAXWindowsAttribute);
    if (![windows isKindOfClass:[NSArray class]]) {
        windows = @[];
    }

    NSMutableArray<NotificationSweepCandidate *> *clearAllCandidates = [NSMutableArray array];
    NSMutableArray<NotificationSweepCandidate *> *closeCandidates = [NSMutableArray array];

    for (id window in windows) {
        if (CFGetTypeID((__bridge CFTypeRef)window) != AXUIElementGetTypeID()) {
            continue;
        }

        AXUIElementRef windowElement = (__bridge AXUIElementRef)window;
        NSString *windowName = StringAXAttribute(windowElement, kAXTitleAttribute) ?: @"Notification Center";
        CollectCandidatesInElement(windowElement, windowName, clearAllCandidates, closeCandidates);
    }

    CFRelease(applicationElement);
    return kind == NotificationSweepActionKindClearAll ? clearAllCandidates : closeCandidates;
}

static BOOL PerformCandidate(NotificationSweepCandidate *candidate, NSError **error) {
    AXError result = AXUIElementPerformAction(candidate.element, (__bridge CFStringRef)candidate.actionName);
    if (result == kAXErrorSuccess) {
        return YES;
    }

    if (error != NULL) {
        NSString *label = candidate.actionKind == NotificationSweepActionKindClearAll ? @"Clear All" : @"Close";
        *error = [NSError errorWithDomain:kNotificationSweepBundleIdentifier
                                     code:result
                                 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ failed in %@", label, candidate.windowName]}];
    }
    return NO;
}

static NSInteger PerformMatchingActions(NotificationSweepActionKind kind, NSError **error) {
    NSInteger performedCount = 0;
    NSInteger maxPasses = kind == NotificationSweepActionKindClearAll ? 20 : 50;
    NSTimeInterval delaySeconds = kind == NotificationSweepActionKindClearAll ? 0.15 : 0.1;

    for (NSInteger pass = 0; pass < maxPasses; pass += 1) {
        NSArray<NotificationSweepCandidate *> *candidates = CollectCandidatesForKind(kind);
        if (candidates.count == 0) {
            break;
        }

        if (!PerformCandidate(candidates.firstObject, error)) {
            return performedCount;
        }

        performedCount += 1;
        [NSThread sleepForTimeInterval:delaySeconds];
    }

    return performedCount;
}

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
    (void)PerformMatchingActions(NotificationSweepActionKindClearAll, &error);
    if (error != nil) {
        ShowAlertAndTerminate(error.localizedDescription, NO);
        return;
    }

    (void)PerformMatchingActions(NotificationSweepActionKindClose, &error);
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
        [NSApplication sharedApplication];
        NotificationSweepAppDelegate *delegate = [[NotificationSweepAppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
