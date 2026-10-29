#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AudioGuardDelegate <NSObject>
@optional
- (void)audioGuardDidDetectBluetoothDeviceConnected:(AudioDeviceID)deviceID name:(NSString *)name;
- (void)audioGuardDidDetectBluetoothDeviceDisconnected:(AudioDeviceID)deviceID name:(NSString *)name;
- (void)audioGuardDidDetectDefaultOutputChanged:(AudioDeviceID)deviceID name:(NSString *)name isBluetooth:(BOOL)isBluetooth;
- (void)audioGuardDidInterceptVolumeTamperOnDevice:(AudioDeviceID)deviceID;
@end

@interface AudioGuard : NSObject

@property (nonatomic, weak) id<AudioGuardDelegate> delegate;
@property (nonatomic, readonly) BOOL isLocked;
@property (nonatomic, readonly) AudioDeviceID lockedDeviceID;
@property (nonatomic, readonly, nullable) NSString *lockedDeviceName;
@property (nonatomic, assign) BOOL strictMuteEnforcement;

+ (instancetype)sharedGuard;

// CoreAudio monitoring lifecycle
- (BOOL)startMonitoring;
- (void)stopMonitoring;

// Device queries
- (NSArray<NSDictionary *> *)allOutputDevices;
- (NSArray<NSDictionary *> *)allBluetoothOutputDevices;
- (AudioDeviceID)defaultOutputDeviceID;
- (NSString *)deviceNameForID:(AudioDeviceID)deviceID;
- (BOOL)isBluetoothDevice:(AudioDeviceID)deviceID;
- (BOOL)isDeviceMuted:(AudioDeviceID)deviceID;
- (Float32)deviceVolume:(AudioDeviceID)deviceID;

// Lock and unlock enforcement
- (BOOL)lockDevice:(AudioDeviceID)deviceID;
- (BOOL)lockDefaultIfBluetooth;
- (BOOL)unlockCurrentDevice;

// Audio redirection fallback
- (AudioDeviceID)findBuiltInOutputDeviceID;
- (BOOL)routeAudioToBuiltIn;

@end

NS_ASSUME_NONNULL_END
