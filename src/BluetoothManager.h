#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

@protocol BluetoothManagerDelegate <NSObject>
@optional
- (void)bluetoothManagerDidDetectDeviceConnected:(IOBluetoothDevice *)device;
@end

@interface BluetoothManager : NSObject

@property (nonatomic, weak) id<BluetoothManagerDelegate> delegate;

+ (instancetype)sharedManager;

- (void)startMonitoring;
- (void)stopMonitoring;

// Querying devices
- (NSArray<IOBluetoothDevice *> *)pairedAudioDevices;
- (NSArray<IOBluetoothDevice *> *)connectedAudioDevices;
- (nullable IOBluetoothDevice *)deviceNamed:(NSString *)name;
- (nullable IOBluetoothDevice *)deviceWithAddress:(NSString *)address;

// Disconnection
- (BOOL)disconnectDeviceNamed:(NSString *)name;
- (BOOL)disconnectDevice:(IOBluetoothDevice *)device;

@end

NS_ASSUME_NONNULL_END
