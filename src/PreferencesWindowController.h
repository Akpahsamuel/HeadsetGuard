#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreferencesWindowController : NSWindowController

+ (instancetype)sharedController;
- (void)showPreferences;

@end

NS_ASSUME_NONNULL_END
