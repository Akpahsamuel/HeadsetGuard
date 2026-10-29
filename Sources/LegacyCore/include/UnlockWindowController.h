#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^UnlockCompletionBlock)(BOOL unlocked);

@interface UnlockWindowController : NSWindowController

@property (nonatomic, copy, nullable) NSString *deviceName;
@property (nonatomic, copy, nullable) UnlockCompletionBlock onCompletion;

+ (instancetype)sharedController;

- (void)presentForDevice:(NSString *)deviceName completion:(nullable UnlockCompletionBlock)completion;
- (void)dismissWindow;
- (void)dismissWithCompletion:(BOOL)unlocked;

@end

NS_ASSUME_NONNULL_END
