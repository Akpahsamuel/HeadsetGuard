#import "AudioGuard.h"
#import <Cocoa/Cocoa.h>

@interface AudioGuard () {
    BOOL _isMonitoring;
    BOOL _devicesListenerRegistered;
    BOOL _defaultListenerRegistered;
    dispatch_queue_t _guardQueue;
    dispatch_source_t _enforceTimer;
    Float32 _savedVolume;
    BOOL _savedMute;
    NSSet<NSNumber *> *_knownBluetoothDevices;
}

@property (nonatomic, assign) BOOL isLocked;
@property (nonatomic, assign) AudioDeviceID lockedDeviceID;
@property (nonatomic, copy, nullable) NSString *lockedDeviceName;

- (void)handleDevicesChanged;
- (void)handleDefaultOutputChanged;

@end

// Static C-function listener callbacks for CoreAudio
static OSStatus AudioDevicesChangedListener(AudioObjectID inObjectID,
                                           UInt32 inNumberAddresses,
                                           const AudioObjectPropertyAddress inAddresses[],
                                           void *inClientData) {
    (void)inObjectID;
    (void)inNumberAddresses;
    (void)inAddresses;
    AudioGuard *guard = (__bridge AudioGuard *)inClientData;
    dispatch_async(dispatch_get_main_queue(), ^{
        [guard handleDevicesChanged];
    });
    return noErr;
}

static OSStatus DefaultOutputChangedListener(AudioObjectID inObjectID,
                                            UInt32 inNumberAddresses,
                                            const AudioObjectPropertyAddress inAddresses[],
                                            void *inClientData) {
    (void)inObjectID;
    (void)inNumberAddresses;
    (void)inAddresses;
    AudioGuard *guard = (__bridge AudioGuard *)inClientData;
    dispatch_async(dispatch_get_main_queue(), ^{
        [guard handleDefaultOutputChanged];
    });
    return noErr;
}

@implementation AudioGuard

@synthesize isLocked = _isLocked;
@synthesize lockedDeviceID = _lockedDeviceID;
@synthesize lockedDeviceName = _lockedDeviceName;

+ (instancetype)sharedGuard {
    static AudioGuard *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AudioGuard alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isMonitoring = NO;
        _devicesListenerRegistered = NO;
        _defaultListenerRegistered = NO;
        _guardQueue = dispatch_queue_create("com.security.HeadsetGuard.guardQueue", DISPATCH_QUEUE_SERIAL);
        _isLocked = NO;
        _lockedDeviceID = kAudioObjectUnknown;
        _lockedDeviceName = nil;
        _strictMuteEnforcement = YES;
        _savedVolume = 0.5f;
        _savedMute = NO;
        _knownBluetoothDevices = [NSSet set];
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Thread-Safe Property Accessors

- (BOOL)isLocked {
    @synchronized(self) {
        return _isLocked;
    }
}

- (void)setIsLocked:(BOOL)isLocked {
    @synchronized(self) {
        _isLocked = isLocked;
    }
}

- (AudioDeviceID)lockedDeviceID {
    @synchronized(self) {
        return _lockedDeviceID;
    }
}

- (void)setLockedDeviceID:(AudioDeviceID)lockedDeviceID {
    @synchronized(self) {
        _lockedDeviceID = lockedDeviceID;
    }
}

- (nullable NSString *)lockedDeviceName {
    @synchronized(self) {
        return _lockedDeviceName;
    }
}

- (void)setLockedDeviceName:(nullable NSString *)lockedDeviceName {
    @synchronized(self) {
        _lockedDeviceName = [lockedDeviceName copy];
    }
}

#pragma mark - Monitoring Lifecycle

- (BOOL)startMonitoring {
    if (_isMonitoring) return YES;

    // Snapshot currently connected Bluetooth devices
    NSMutableSet *initialSet = [NSMutableSet set];
    for (NSDictionary *info in [self allBluetoothOutputDevices]) {
        [initialSet addObject:info[@"id"]];
    }
    _knownBluetoothDevices = [initialSet copy];

    // Listen for devices added / removed
    AudioObjectPropertyAddress devicesAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status1 = AudioObjectAddPropertyListener(kAudioObjectSystemObject,
                                                      &devicesAddress,
                                                      AudioDevicesChangedListener,
                                                      (__bridge void *)self);
    _devicesListenerRegistered = (status1 == noErr);

    // Listen for default output device changes
    AudioObjectPropertyAddress defaultAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status2 = AudioObjectAddPropertyListener(kAudioObjectSystemObject,
                                                      &defaultAddress,
                                                      DefaultOutputChangedListener,
                                                      (__bridge void *)self);
    _defaultListenerRegistered = (status2 == noErr);

    _isMonitoring = (_devicesListenerRegistered && _defaultListenerRegistered);
    return _isMonitoring;
}

- (void)stopMonitoring {
    if (_devicesListenerRegistered) {
        AudioObjectPropertyAddress devicesAddress = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        AudioObjectRemovePropertyListener(kAudioObjectSystemObject,
                                          &devicesAddress,
                                          AudioDevicesChangedListener,
                                          (__bridge void *)self);
        _devicesListenerRegistered = NO;
    }

    if (_defaultListenerRegistered) {
        AudioObjectPropertyAddress defaultAddress = {
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        AudioObjectRemovePropertyListener(kAudioObjectSystemObject,
                                          &defaultAddress,
                                          DefaultOutputChangedListener,
                                          (__bridge void *)self);
        _defaultListenerRegistered = NO;
    }

    [self stopEnforceTimer];
    _isMonitoring = NO;
}

#pragma mark - Device Queries

- (NSArray<NSDictionary *> *)allOutputDevices {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
    if (status != noErr || dataSize == 0) return @[];

    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = (AudioDeviceID *)malloc(dataSize);
    if (!devices) return @[];

    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, devices);
    if (status != noErr) {
        free(devices);
        return @[];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (UInt32 i = 0; i < deviceCount; i++) {
        AudioDeviceID devID = devices[i];

        // Check if device has output streams
        AudioObjectPropertyAddress streamsAddr = {
            kAudioDevicePropertyStreams,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        UInt32 streamSize = 0;
        AudioObjectGetPropertyDataSize(devID, &streamsAddr, 0, NULL, &streamSize);
        if (streamSize == 0) continue;

        NSString *name = [self deviceNameForID:devID];
        BOOL isBT = [self isBluetoothDevice:devID];

        [result addObject:@{
            @"id": @(devID),
            @"name": name ?: @"Unknown Device",
            @"isBluetooth": @(isBT)
        }];
    }

    free(devices);
    return result;
}

- (NSArray<NSDictionary *> *)allBluetoothOutputDevices {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"isBluetooth == YES"];
    return [[self allOutputDevices] filteredArrayUsingPredicate:predicate];
}

- (AudioDeviceID)defaultOutputDeviceID {
    AudioDeviceID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(AudioDeviceID);
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &deviceID);
    if (status != noErr) return kAudioObjectUnknown;
    return deviceID;
}

- (BOOL)setDefaultOutputDevice:(AudioDeviceID)deviceID {
    UInt32 size = sizeof(AudioDeviceID);
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, size, &deviceID);
    return (status == noErr);
}

- (NSString *)deviceNameForID:(AudioDeviceID)deviceID {
    CFStringRef devName = NULL;
    UInt32 nameSize = sizeof(CFStringRef);
    AudioObjectPropertyAddress nameAddr = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectGetPropertyData(deviceID, &nameAddr, 0, NULL, &nameSize, &devName);
    if (status == noErr && devName != NULL) {
        NSString *name = [(__bridge NSString *)devName copy];
        CFRelease(devName);
        return name;
    }
    return nil;
}

- (BOOL)isBluetoothDevice:(AudioDeviceID)deviceID {
    UInt32 transport = 0;
    UInt32 transSize = sizeof(UInt32);
    AudioObjectPropertyAddress transAddr = {
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectGetPropertyData(deviceID, &transAddr, 0, NULL, &transSize, &transport) == noErr;
    if (status) {
        // 'blue' = 0x626c7565, 'blea' = 0x626c6561
        if (transport == kAudioDeviceTransportTypeBluetooth ||
            transport == kAudioDeviceTransportTypeBluetoothLE ||
            transport == 0x626c7565 ||
            transport == 0x626c6561) {
            return YES;
        }
    }

    // Secondary check: Device UID containing "Bluetooth"
    CFStringRef uid = NULL;
    UInt32 uidSize = sizeof(CFStringRef);
    AudioObjectPropertyAddress uidAddr = {
        kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    status = AudioObjectGetPropertyData(deviceID, &uidAddr, 0, NULL, &uidSize, &uid) == noErr;
    if (status && uid != NULL) {
        NSString *uidStr = (__bridge NSString *)uid;
        BOOL containsBT = [uidStr localizedCaseInsensitiveContainsString:@"bluetooth"] ||
                          [uidStr localizedCaseInsensitiveContainsString:@"bt_"];
        CFRelease(uid);
        if (containsBT) return YES;
    }

    return NO;
}

- (BOOL)isDeviceMuted:(AudioDeviceID)deviceID {
    UInt32 mute = 0;
    UInt32 size = sizeof(UInt32);
    AudioObjectPropertyAddress muteAddr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectGetPropertyData(deviceID, &muteAddr, 0, NULL, &size, &mute);
    return (status == noErr && mute != 0);
}

- (BOOL)setDeviceMute:(AudioDeviceID)deviceID muted:(BOOL)muted {
    UInt32 muteVal = muted ? 1 : 0;
    UInt32 size = sizeof(UInt32);
    AudioObjectPropertyAddress muteAddr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectSetPropertyData(deviceID, &muteAddr, 0, NULL, size, &muteVal);
    
    // Also try left and right elements if main element fails
    if (status != noErr) {
        muteAddr.mElement = 1;
        AudioObjectSetPropertyData(deviceID, &muteAddr, 0, NULL, size, &muteVal);
        muteAddr.mElement = 2;
        AudioObjectSetPropertyData(deviceID, &muteAddr, 0, NULL, size, &muteVal);
    }
    return (status == noErr);
}

- (Float32)deviceVolume:(AudioDeviceID)deviceID {
    Float32 vol = 0.0f;
    UInt32 size = sizeof(Float32);
    AudioObjectPropertyAddress volAddr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectGetPropertyData(deviceID, &volAddr, 0, NULL, &size, &vol);
    if (status != noErr) {
        volAddr.mElement = 1;
        AudioObjectGetPropertyData(deviceID, &volAddr, 0, NULL, &size, &vol);
    }
    return vol;
}

- (BOOL)setDeviceVolume:(AudioDeviceID)deviceID volume:(Float32)volume {
    UInt32 size = sizeof(Float32);
    AudioObjectPropertyAddress volAddr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectSetPropertyData(deviceID, &volAddr, 0, NULL, size, &volume);
    
    // Only try channels 1 and 2 if main element fails (matching setDeviceMute)
    if (status != noErr) {
        volAddr.mElement = 1;
        AudioObjectSetPropertyData(deviceID, &volAddr, 0, NULL, size, &volume);
        volAddr.mElement = 2;
        AudioObjectSetPropertyData(deviceID, &volAddr, 0, NULL, size, &volume);
    }
    
    return (status == noErr);
}

#pragma mark - Built-in Audio Fallback

- (AudioDeviceID)findBuiltInOutputDeviceID {
    for (NSDictionary *info in [self allOutputDevices]) {
        AudioDeviceID devID = [info[@"id"] unsignedIntValue];
        UInt32 transport = 0;
        UInt32 transSize = sizeof(UInt32);
        AudioObjectPropertyAddress transAddr = {
            kAudioDevicePropertyTransportType,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        if (AudioObjectGetPropertyData(devID, &transAddr, 0, NULL, &transSize, &transport) == noErr) {
            // 'bltn' = 0x626c746e
            if (transport == kAudioDeviceTransportTypeBuiltIn || transport == 0x626c746e) {
                return devID;
            }
        }
    }
    return kAudioObjectUnknown;
}

- (BOOL)routeAudioToBuiltIn {
    AudioDeviceID builtIn = [self findBuiltInOutputDeviceID];
    if (builtIn != kAudioObjectUnknown) {
        return [self setDefaultOutputDevice:builtIn];
    }
    return NO;
}

#pragma mark - Lock / Unlock Operations

- (BOOL)lockDevice:(AudioDeviceID)deviceID {
    if (deviceID == kAudioObjectUnknown) return NO;

    NSString *name = [self deviceNameForID:deviceID];
    NSLog(@"[AudioGuard] Locking audio device: '%@' (ID: %u)", name, deviceID);

    // Save pre-lock volume and state if not currently locked
    @synchronized(self) {
        if (!_isLocked) {
            _savedVolume = [self deviceVolume:deviceID];
            if (_savedVolume < 0.05f) _savedVolume = 0.5f; // reasonable restore default
            _savedMute = [self isDeviceMuted:deviceID];
        }

        _lockedDeviceID = deviceID;
        _lockedDeviceName = name;
        _isLocked = YES;
    }

    // Immediately mute and zero volume
    [self setDeviceMute:deviceID muted:YES];
    [self setDeviceVolume:deviceID volume:0.0f];

    // Start aggressive enforcement loop to prevent manual physical hardware unmute
    [self startEnforceTimer];

    return YES;
}

- (BOOL)lockDefaultIfBluetooth {
    AudioDeviceID defID = [self defaultOutputDeviceID];
    if (defID != kAudioObjectUnknown && [self isBluetoothDevice:defID]) {
        return [self lockDevice:defID];
    }
    return NO;
}

- (BOOL)unlockCurrentDevice {
    AudioDeviceID devID = kAudioObjectUnknown;
    Float32 restoreVol = 0.5f;

    @synchronized(self) {
        if (!_isLocked || _lockedDeviceID == kAudioObjectUnknown) {
            _isLocked = NO;
            _lockedDeviceID = kAudioObjectUnknown;
            _lockedDeviceName = nil;
            [self stopEnforceTimer];
            return YES;
        }

        devID = _lockedDeviceID;
        restoreVol = _savedVolume;
        NSLog(@"[AudioGuard] Unlocking audio device: '%@' (ID: %u)", _lockedDeviceName, devID);

        _isLocked = NO;
        _lockedDeviceID = kAudioObjectUnknown;
        _lockedDeviceName = nil;
    }

    [self stopEnforceTimer];

    // Restore volume and unmute
    [self setDeviceMute:devID muted:NO];
    [self setDeviceVolume:devID volume:restoreVol];

    return YES;
}

#pragma mark - Mute Enforcement Timer

- (void)startEnforceTimer {
    [self stopEnforceTimer];

    _enforceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _guardQueue);
    
    // Check every 200 milliseconds to clamp any unauthorized volume adjustment
    dispatch_source_set_timer(_enforceTimer, dispatch_walltime(NULL, 0), 200 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_enforceTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        AudioDeviceID devID = kAudioObjectUnknown;
        @synchronized(strongSelf) {
            if (!strongSelf->_isLocked || strongSelf->_lockedDeviceID == kAudioObjectUnknown) {
                return;
            }
            devID = strongSelf->_lockedDeviceID;
        }

        BOOL isMuted = [strongSelf isDeviceMuted:devID];
        Float32 vol = [strongSelf deviceVolume:devID];

        if (!isMuted || vol > 0.001f) {
            NSLog(@"[AudioGuard] Tamper detected! Headset tried to unmute (Mute: %d, Vol: %.2f). Re-muting.", isMuted, vol);
            [strongSelf setDeviceMute:devID muted:YES];
            [strongSelf setDeviceVolume:devID volume:0.0f];

            dispatch_async(dispatch_get_main_queue(), ^{
                id<AudioGuardDelegate> d = strongSelf.delegate;
                if ([d respondsToSelector:@selector(audioGuardDidInterceptVolumeTamperOnDevice:)]) {
                    [d audioGuardDidInterceptVolumeTamperOnDevice:devID];
                }
            });
        }
    });

    dispatch_resume(_enforceTimer);
}

- (void)stopEnforceTimer {
    if (_enforceTimer) {
        dispatch_source_cancel(_enforceTimer);
        _enforceTimer = nil;
    }
}

#pragma mark - Event Handlers

- (void)handleDevicesChanged {
    NSArray<NSDictionary *> *btDevices = [self allBluetoothOutputDevices];
    NSMutableSet *currentSet = [NSMutableSet set];
    for (NSDictionary *info in btDevices) {
        [currentSet addObject:info[@"id"]];
    }

    // Newly connected
    NSMutableSet *added = [currentSet mutableCopy];
    [added minusSet:_knownBluetoothDevices];

    // Disconnected
    NSMutableSet *removed = [_knownBluetoothDevices mutableCopy];
    [removed minusSet:currentSet];

    _knownBluetoothDevices = [currentSet copy];

    id<AudioGuardDelegate> d = self.delegate;

    for (NSNumber *devNum in added) {
        AudioDeviceID devID = [devNum unsignedIntValue];
        NSString *name = [self deviceNameForID:devID];
        NSLog(@"[AudioGuard] Bluetooth audio device CONNECTED: '%@' (ID: %u)", name, devID);
        if ([d respondsToSelector:@selector(audioGuardDidDetectBluetoothDeviceConnected:name:)]) {
            [d audioGuardDidDetectBluetoothDeviceConnected:devID name:name ?: @"Bluetooth Headset"];
        }
    }

    for (NSNumber *devNum in removed) {
        AudioDeviceID devID = [devNum unsignedIntValue];
        BOOL wasLocked = NO;
        @synchronized(self) {
            if (devID == _lockedDeviceID) {
                wasLocked = YES;
                _isLocked = NO;
                _lockedDeviceID = kAudioObjectUnknown;
                _lockedDeviceName = nil;
            }
        }
        if (wasLocked) {
            NSLog(@"[AudioGuard] Currently locked device disconnected.");
            [self stopEnforceTimer];
        }
        if ([d respondsToSelector:@selector(audioGuardDidDetectBluetoothDeviceDisconnected:name:)]) {
            [d audioGuardDidDetectBluetoothDeviceDisconnected:devID name:@"Bluetooth Headset"];
        }
    }
}

- (void)handleDefaultOutputChanged {
    AudioDeviceID defID = [self defaultOutputDeviceID];
    NSString *name = [self deviceNameForID:defID];
    BOOL isBT = [self isBluetoothDevice:defID];

    NSLog(@"[AudioGuard] Default output changed to '%@' (ID: %u, Bluetooth: %@)", name, defID, isBT ? @"YES" : @"NO");

    id<AudioGuardDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(audioGuardDidDetectDefaultOutputChanged:name:isBluetooth:)]) {
        [d audioGuardDidDetectDefaultOutputChanged:defID name:name ?: @"Unknown" isBluetooth:isBT];
    }
}

@end
