#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <string.h>

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

    NSString *trimmedName = [rawName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedName hasPrefix:@"Name:"]) {
        NSRange newlineRange = [trimmedName rangeOfString:@"\n"];
        NSString *firstLine = newlineRange.location == NSNotFound ? trimmedName : [trimmedName substringToIndex:newlineRange.location];
        return [[firstLine substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    return trimmedName;
}

static BOOL LabelEqualsAny(NSString *label, NSArray<NSString *> *targets) {
    if (label.length == 0) {
        return NO;
    }

    for (NSString *target in targets) {
        if ([label caseInsensitiveCompare:target] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

static BOOL IsClearAllLabel(NSString *label) {
    return LabelEqualsAny(label, @[@"Clear All", @"Clear all"]);
}

static BOOL IsCloseLabel(NSString *label) {
    return LabelEqualsAny(label, @[@"Close", @"Clear", @"Dismiss"]);
}

static NSString *MatchingExplicitActionNameForKind(NSArray<NSString *> *actions,
                                                  NSString *role,
                                                  NotificationSweepActionKind actionKind) {
    for (NSString *action in actions) {
        NSString *normalized = NormalizedActionName(action);
        if (actionKind == NotificationSweepActionKindClearAll && IsClearAllLabel(normalized)) {
            return action;
        }

        if (actionKind == NotificationSweepActionKindClose &&
            IsCloseLabel(normalized) &&
            ![role isEqualToString:(__bridge NSString *)kAXWindowRole]) {
            return action;
        }
    }

    return nil;
}

static BOOL HasPressAction(NSArray<NSString *> *actions) {
    for (NSString *action in actions) {
        if ([action isEqualToString:(__bridge NSString *)kAXPressAction]) {
            return YES;
        }
    }

    return NO;
}

static BOOL ElementLabelMatches(AXUIElementRef element, BOOL (*matcher)(NSString *)) {
    NSArray *attributes = @[
        (__bridge NSString *)kAXTitleAttribute,
        (__bridge NSString *)kAXDescriptionAttribute,
        (__bridge NSString *)kAXHelpAttribute,
        (__bridge NSString *)kAXValueAttribute,
        @"AXLabel"
    ];

    for (NSString *attribute in attributes) {
        NSString *value = StringAXAttribute(element, (__bridge CFStringRef)attribute);
        if (matcher(value)) {
            return YES;
        }
    }

    return NO;
}

static BOOL StringContainsText(NSString *value, NSString *needle) {
    return value.length > 0 && needle.length > 0 && [value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL ElementContainsText(AXUIElementRef element, NSString *needle) {
    NSArray *attributes = @[
        (__bridge NSString *)kAXTitleAttribute,
        (__bridge NSString *)kAXDescriptionAttribute,
        (__bridge NSString *)kAXHelpAttribute,
        (__bridge NSString *)kAXValueAttribute,
        @"AXLabel"
    ];

    for (NSString *attribute in attributes) {
        NSString *value = StringAXAttribute(element, (__bridge CFStringRef)attribute);
        if (StringContainsText(value, needle)) {
            return YES;
        }
    }

    for (id child in ChildrenOfElement(element)) {
        if (CFGetTypeID((__bridge CFTypeRef)child) == AXUIElementGetTypeID() &&
            ElementContainsText((__bridge AXUIElementRef)child, needle)) {
            return YES;
        }
    }

    return NO;
}

static BOOL NotificationCenterContainsText(NSString *needle) {
    NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:kNotificationCenterBundleIdentifier];
    if (apps.count == 0) {
        return NO;
    }

    AXUIElementRef applicationElement = AXUIElementCreateApplication(apps.firstObject.processIdentifier);
    NSArray *windows = CopyAXAttribute(applicationElement, kAXWindowsAttribute);
    if (![windows isKindOfClass:[NSArray class]]) {
        windows = @[];
    }

    BOOL found = NO;
    for (id window in windows) {
        if (CFGetTypeID((__bridge CFTypeRef)window) == AXUIElementGetTypeID() &&
            ElementContainsText((__bridge AXUIElementRef)window, needle)) {
            found = YES;
            break;
        }
    }

    CFRelease(applicationElement);
    return found;
}

static void AddCandidate(NSMutableArray<NotificationSweepCandidate *> *candidates,
                         AXUIElementRef element,
                         NSString *windowName,
                         NSString *actionName,
                         NotificationSweepActionKind actionKind) {
    [candidates addObject:[[NotificationSweepCandidate alloc] initWithElement:element
                                                                   windowName:windowName
                                                                   actionName:actionName
                                                                   actionKind:actionKind]];
}

static void CollectCandidatesInElement(AXUIElementRef element,
                                       NSString *windowName,
                                       NSMutableArray<NotificationSweepCandidate *> *clearAllCandidates,
                                       NSMutableArray<NotificationSweepCandidate *> *closeCandidates) {
    NSString *role = StringAXAttribute(element, kAXRoleAttribute);
    NSArray<NSString *> *actions = ActionNamesForElement(element);
    NSString *clearAllAction = MatchingExplicitActionNameForKind(actions, role, NotificationSweepActionKindClearAll);
    NSString *closeAction = MatchingExplicitActionNameForKind(actions, role, NotificationSweepActionKindClose);

    if (clearAllAction != nil) {
        AddCandidate(clearAllCandidates, element, windowName, clearAllAction, NotificationSweepActionKindClearAll);
    } else if (closeAction != nil) {
        AddCandidate(closeCandidates, element, windowName, closeAction, NotificationSweepActionKindClose);
    } else if (HasPressAction(actions) && [role isEqualToString:(__bridge NSString *)kAXButtonRole]) {
        if (ElementLabelMatches(element, IsClearAllLabel)) {
            AddCandidate(clearAllCandidates, element, windowName, (__bridge NSString *)kAXPressAction, NotificationSweepActionKindClearAll);
        } else if (ElementLabelMatches(element, IsCloseLabel)) {
            AddCandidate(closeCandidates, element, windowName, (__bridge NSString *)kAXPressAction, NotificationSweepActionKindClose);
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

static int PrintCandidateCounts(void) {
    NSArray<NotificationSweepCandidate *> *clearAllCandidates = CollectCandidatesForKind(NotificationSweepActionKindClearAll);
    NSArray<NotificationSweepCandidate *> *closeCandidates = CollectCandidatesForKind(NotificationSweepActionKindClose);
    printf("clear_all=%lu close=%lu total=%lu\n",
           (unsigned long)clearAllCandidates.count,
           (unsigned long)closeCandidates.count,
           (unsigned long)(clearAllCandidates.count + closeCandidates.count));
    return 0;
}

static int PrintContainsText(NSString *needle) {
    BOOL found = NotificationCenterContainsText(needle);
    printf("contains=%s\n", found ? "1" : "0");
    return found ? 0 : 2;
}

static BOOL SelfTestStringEquals(NSString *actual, NSString *expected, NSString *caseName) {
    BOOL passed = (actual == nil && expected == nil) || [actual isEqualToString:expected];
    if (!passed) {
        fprintf(stderr, "FAIL: %s expected \"%s\", got \"%s\"\n",
                caseName.UTF8String,
                expected.UTF8String ?: "(nil)",
                actual.UTF8String ?: "(nil)");
    }
    return passed;
}

static BOOL SelfTestBoolEquals(BOOL actual, BOOL expected, NSString *caseName) {
    if (actual != expected) {
        fprintf(stderr, "FAIL: %s expected %s, got %s\n",
                caseName.UTF8String,
                expected ? "YES" : "NO",
                actual ? "YES" : "NO");
        return NO;
    }
    return YES;
}

static int RunSelfTests(void) {
    NSInteger failures = 0;
    NSString *buttonRole = (__bridge NSString *)kAXButtonRole;
    NSString *windowRole = (__bridge NSString *)kAXWindowRole;
    NSString *groupRole = @"AXGroup";

    failures += !SelfTestStringEquals(NormalizedActionName(@" Clear All\n"),
                                      @"Clear All",
                                      @"trims plain action name");
    failures += !SelfTestStringEquals(NormalizedActionName(@"Name:Dismiss\nTarget:notification"),
                                      @"Dismiss",
                                      @"normalizes verbose action name");
    failures += !SelfTestStringEquals(MatchingExplicitActionNameForKind(@[@"Clear All"],
                                                                        buttonRole,
                                                                        NotificationSweepActionKindClearAll),
                                      @"Clear All",
                                      @"matches Sequoia Clear All action");
    failures += !SelfTestStringEquals(MatchingExplicitActionNameForKind(@[@"Name:Clear\nTarget:notification"],
                                                                        groupRole,
                                                                        NotificationSweepActionKindClose),
                                      @"Name:Clear\nTarget:notification",
                                      @"matches Tahoe non-button Clear action");
    failures += !SelfTestStringEquals(MatchingExplicitActionNameForKind(@[@"Dismiss"],
                                                                        groupRole,
                                                                        NotificationSweepActionKindClose),
                                      @"Dismiss",
                                      @"matches Tahoe Dismiss action");
    failures += !SelfTestStringEquals(MatchingExplicitActionNameForKind(@[@"Close"],
                                                                        windowRole,
                                                                        NotificationSweepActionKindClose),
                                      nil,
                                      @"does not match Notification Center window close");
    failures += !SelfTestBoolEquals(HasPressAction(@[(__bridge NSString *)kAXPressAction]),
                                    YES,
                                    @"detects AXPress fallback action");
    failures += !SelfTestBoolEquals(IsCloseLabel(@"clear"),
                                    YES,
                                    @"matches close labels case-insensitively");

    if (failures > 0) {
        fprintf(stderr, "%ld self-test(s) failed\n", (long)failures);
        return 1;
    }

    printf("All Notification Sweep self-tests passed\n");
    return 0;
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
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
            return RunSelfTests();
        }

        if (argc > 1 && strcmp(argv[1], "--count-candidates") == 0) {
            return PrintCandidateCounts();
        }

        if (argc > 2 && strcmp(argv[1], "--contains-text") == 0) {
            return PrintContainsText([NSString stringWithUTF8String:argv[2]]);
        }

        [NSApplication sharedApplication];
        NotificationSweepAppDelegate *delegate = [[NotificationSweepAppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
