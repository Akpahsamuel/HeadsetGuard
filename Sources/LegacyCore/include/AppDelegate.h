#import <Cocoa/Cocoa.h>
#import "AudioGuard.h"
#import "BluetoothManager.h"
#import "SecurityManager.h"
#import "UnlockWindowController.h"
#import "PreferencesWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate, AudioGuardDelegate, BluetoothManagerDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;

- (void)lockCurrentHeadset;
- (void)unlockCurrentHeadset;
- (void)disconnectCurrentHeadset;

@end

NS_ASSUME_NONNULL_END
