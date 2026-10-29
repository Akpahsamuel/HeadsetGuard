#import "BluetoothManager.h"

@interface BluetoothManager () {
    IOBluetoothUserNotification *_connectNotification;
}
@end

@implementation BluetoothManager

+ (instancetype)sharedManager {
    static BluetoothManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BluetoothManager alloc] init];
    });
    return shared;
}

- (void)startMonitoring {
    if (_connectNotification) return;

    _connectNotification = [IOBluetoothDevice registerForConnectNotifications:self
                                                                     selector:@selector(deviceConnectedNotification:device:)];
    NSLog(@"[BluetoothManager] Started listening for Bluetooth connect notifications.");
}

- (void)stopMonitoring {
    if (_connectNotification) {
        [_connectNotification unregister];
        _connectNotification = nil;
    }
}

- (void)deviceConnectedNotification:(IOBluetoothUserNotification *)note device:(IOBluetoothDevice *)device {
    NSLog(@"[BluetoothManager] IOBluetooth notification: connected to '%@' (%@)", device.nameOrAddress, device.addressString);
    if ([self.delegate respondsToSelector:@selector(bluetoothManagerDidDetectDeviceConnected:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate bluetoothManagerDidDetectDeviceConnected:device];
        });
    }
}

- (BOOL)isAudioDevice:(IOBluetoothDevice *)device {
    // Check device class: 0x0400 is Major Class Audio/Video
    BluetoothClassOfDevice cod = [device classOfDevice];
    BluetoothDeviceClassMajor majorClass = (cod & 0x1F00) >> 8;
    if (majorClass == 0x04) { // Audio / Video
        return YES;
    }

    // Secondary check: name contains common audio words
    NSString *name = device.nameOrAddress.lowercaseString;
    if ([name containsString:@"headset"] ||
        [name containsString:@"headphone"] ||
        [name containsString:@"earphone"] ||
        [name containsString:@"earbud"] ||
        [name containsString:@"airpod"] ||
        [name containsString:@"buds"] ||
        [name containsString:@"tws"] ||
        [name containsString:@"sound"] ||
        [name containsString:@"speaker"] ||
        [name containsString:@"wh-"] ||
        [name containsString:@"wf-"] ||
        [name containsString:@"bose"] ||
        [name containsString:@"sony"] ||
        [name containsString:@"audiomaster"]) {
        return YES;
    }

    return NO;
}

- (NSArray<IOBluetoothDevice *> *)pairedAudioDevices {
    NSArray *paired = [IOBluetoothDevice pairedDevices];
    NSMutableArray *audioDevs = [NSMutableArray array];
    for (IOBluetoothDevice *dev in paired) {
        if ([self isAudioDevice:dev]) {
            [audioDevs addObject:dev];
        }
    }
    return audioDevs;
}

- (NSArray<IOBluetoothDevice *> *)connectedAudioDevices {
    NSArray *audioDevs = [self pairedAudioDevices];
    NSMutableArray *connected = [NSMutableArray array];
    for (IOBluetoothDevice *dev in audioDevs) {
        if ([dev isConnected]) {
            [connected addObject:dev];
        }
    }
    return connected;
}

- (IOBluetoothDevice *)deviceNamed:(NSString *)name {
    if (!name) return nil;
    for (IOBluetoothDevice *dev in [IOBluetoothDevice pairedDevices]) {
        if ([dev.nameOrAddress localizedCaseInsensitiveContainsString:name] ||
            [name localizedCaseInsensitiveContainsString:dev.nameOrAddress]) {
            return dev;
        }
    }
    return nil;
}

- (IOBluetoothDevice *)deviceWithAddress:(NSString *)address {
    if (!address) return nil;
    return [IOBluetoothDevice deviceWithAddressString:address];
}

- (BOOL)disconnectDeviceNamed:(NSString *)name {
    IOBluetoothDevice *dev = [self deviceNamed:name];
    if (dev) {
        return [self disconnectDevice:dev];
    }
    return NO;
}

- (BOOL)disconnectDevice:(IOBluetoothDevice *)device {
    if (!device) return NO;
    NSLog(@"[BluetoothManager] Forcing disconnect for device: %@", device.nameOrAddress);
    IOReturn ret = [device closeConnection];
    return (ret == kIOReturnSuccess);
}

@end
