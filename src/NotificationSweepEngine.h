#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NotificationSweepActionKind) {
    NotificationSweepActionKindClearAll,
    NotificationSweepActionKindClose,
};

NSInteger NotificationSweepPerformMatchingActions(NotificationSweepActionKind kind, NSError **error);
int NotificationSweepPrintCandidateCounts(void);
int NotificationSweepPrintContainsText(NSString *needle);
int NotificationSweepRunSelfTests(void);
