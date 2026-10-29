#import "AppDelegate.h"

typedef NS_ENUM(NSInteger, GuardStatus) {
    GuardStatusIdle,
    GuardStatusLocked,
    GuardStatusAuthorized
};

@interface AppDelegate () {
    GuardStatus _currentStatus;
    NSString *_activeHeadsetName;
    AudioDeviceID _activeDeviceID;
}
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong) NSMenuItem *headerItem;
@property (nonatomic, strong) NSMenuItem *unlockMenuItem;
@property (nonatomic, strong) NSMenuItem *lockMenuItem;
@property (nonatomic, strong) NSMenuItem *disconnectMenuItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"[AppDelegate] HeadsetGuard starting up...");
    _currentStatus = GuardStatusIdle;
    _activeHeadsetName = nil;
    _activeDeviceID = kAudioObjectUnknown;

    // Set up Status Item in Menu Bar
    [self setupStatusItem];

    // Configure delegates
    [AudioGuard sharedGuard].delegate = self;
    [BluetoothManager sharedManager].delegate = self;

    // Start monitoring CoreAudio and Bluetooth
    [[AudioGuard sharedGuard] startMonitoring];
    [[BluetoothManager sharedManager] startMonitoring];

    // Listen for System Sleep and Screen Lock
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(workspaceWillSleep:)
                                                               name:NSWorkspaceWillSleepNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(workspaceDidWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(sessionDidResignActive:)
                                                               name:NSWorkspaceSessionDidResignActiveNotification
                                                             object:nil];

    // Check if Bluetooth headset is already connected right now
    [self checkInitialConnectedHeadsets];

    // First time setup prompt if password not configured
    if (![SecurityManager sharedManager].isPasswordConfigured) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[PreferencesWindowController sharedController] showPreferences];
        });
    }

    [[SecurityManager sharedManager] logEvent:@"App Started" details:@"HeadsetGuard armed and monitoring" type:@"system"];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    NSLog(@"[AppDelegate] HeadsetGuard terminating.");
    // If locked, restore audio before exit so user is not stuck muted
    if ([AudioGuard sharedGuard].isLocked) {
        [[AudioGuard sharedGuard] unlockCurrentDevice];
    }
    [[AudioGuard sharedGuard] stopMonitoring];
    [[BluetoothManager sharedManager] stopMonitoring];
}

#pragma mark - Menu Bar Setup

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    _statusMenu = [[NSMenu alloc] init];

    // Header item (shows current device & status)
    _headerItem = [[NSMenuItem alloc] initWithTitle:@"HeadsetGuard: Armed (No Headset)" action:nil keyEquivalent:@""];
    _headerItem.enabled = NO;
    [_statusMenu addItem:_headerItem];

    [_statusMenu addItem:[NSMenuItem separatorItem]];

    // Unlock item
    _unlockMenuItem = [[NSMenuItem alloc] initWithTitle:@"Authorize & Unlock Audio..." action:@selector(unlockMenuClicked:) keyEquivalent:@"u"];
    _unlockMenuItem.target = self;
    [_statusMenu addItem:_unlockMenuItem];

    // Lock item
    _lockMenuItem = [[NSMenuItem alloc] initWithTitle:@"Lock Headset Audio Now" action:@selector(lockMenuClicked:) keyEquivalent:@"l"];
    _lockMenuItem.target = self;
    [_statusMenu addItem:_lockMenuItem];

    [_statusMenu addItem:[NSMenuItem separatorItem]];

    // Disconnect device
    _disconnectMenuItem = [[NSMenuItem alloc] initWithTitle:@"Disconnect Headset" action:@selector(disconnectMenuClicked:) keyEquivalent:@"d"];
    _disconnectMenuItem.target = self;
    [_statusMenu addItem:_disconnectMenuItem];

    [_statusMenu addItem:[NSMenuItem separatorItem]];

    // Preferences & Dashboard
    NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Preferences & Security Dashboard..." action:@selector(preferencesMenuClicked:) keyEquivalent:@","];
    prefsItem.target = self;
    [_statusMenu addItem:prefsItem];

    // Setup Master PIN
    NSMenuItem *pinItem = [[NSMenuItem alloc] initWithTitle:@"Change Security Password/PIN..." action:@selector(changePinMenuClicked:) keyEquivalent:@"p"];
    pinItem.target = self;
    [_statusMenu addItem:pinItem];

    [_statusMenu addItem:[NSMenuItem separatorItem]];

    // Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit HeadsetGuard" action:@selector(quitMenuClicked:) keyEquivalent:@"q"];
    quitItem.target = self;
    [_statusMenu addItem:quitItem];

    self.statusItem.menu = _statusMenu;
    [self updateStatusIcon:GuardStatusIdle];
}

- (void)updateStatusIcon:(GuardStatus)status {
    _currentStatus = status;

    NSImage *icon = nil;
    NSString *tooltip = @"HeadsetGuard";

    if (@available(macOS 11.0, *)) {
        switch (status) {
            case GuardStatusIdle:
                icon = [NSImage imageWithSystemSymbolName:@"headphones" accessibilityDescription:@"Idle"];
                icon.template = YES;
                tooltip = @"HeadsetGuard: Armed (Monitoring)";
                break;
            case GuardStatusLocked:
                icon = [NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:@"Locked"];
                icon.template = NO;
                tooltip = [NSString stringWithFormat:@"HeadsetGuard: LOCKED (%@)", _activeHeadsetName ?: @"Headset"];
                break;
            case GuardStatusAuthorized:
                icon = [NSImage imageWithSystemSymbolName:@"headphones.circle.fill" accessibilityDescription:@"Authorized"];
                icon.template = NO;
                tooltip = [NSString stringWithFormat:@"HeadsetGuard: Authorized (%@)", _activeHeadsetName ?: @"Headset"];
                break;
        }
    } else {
        icon = [NSImage imageNamed:NSImageNameLockLockedTemplate];
    }

    self.statusItem.button.image = icon;
    self.statusItem.button.toolTip = tooltip;

    // Update menu items
    switch (status) {
        case GuardStatusIdle:
            _headerItem.title = @"HeadsetGuard: Armed (No Headset)";
            _unlockMenuItem.hidden = YES;
            _lockMenuItem.hidden = YES;
            _disconnectMenuItem.hidden = YES;
            break;
        case GuardStatusLocked:
            _headerItem.title = [NSString stringWithFormat:@"🔒 %@ [LOCKED]", _activeHeadsetName ?: @"Headset"];
            _unlockMenuItem.hidden = NO;
            _lockMenuItem.hidden = YES;
            _disconnectMenuItem.hidden = NO;
            break;
        case GuardStatusAuthorized:
            _headerItem.title = [NSString stringWithFormat:@"🔓 %@ [AUTHORIZED]", _activeHeadsetName ?: @"Headset"];
            _unlockMenuItem.hidden = YES;
            _lockMenuItem.hidden = NO;
            _disconnectMenuItem.hidden = NO;
            break;
    }
}

#pragma mark - Initial Checks

- (void)checkInitialConnectedHeadsets {
    AudioGuard *ag = [AudioGuard sharedGuard];
    AudioDeviceID defID = [ag defaultOutputDeviceID];

    if (defID != kAudioObjectUnknown && [ag isBluetoothDevice:defID]) {
        NSString *name = [ag deviceNameForID:defID];
        NSLog(@"[AppDelegate] Discovered already active Bluetooth audio device: '%@' (ID: %u)", name, defID);
        [self handleHeadsetConnected:defID name:name];
    } else {
        NSArray<NSDictionary *> *btDevs = [ag allBluetoothOutputDevices];
        if (btDevs.count > 0) {
            NSDictionary *first = btDevs.firstObject;
            AudioDeviceID devID = [first[@"id"] unsignedIntValue];
            NSString *name = first[@"name"];
            NSLog(@"[AppDelegate] Discovered connected Bluetooth audio device: '%@' (ID: %u)", name, devID);
            [self handleHeadsetConnected:devID name:name];
        }
    }
}

#pragma mark - Security Enforcement Flow

- (void)handleHeadsetConnected:(AudioDeviceID)deviceID name:(NSString *)name {
    _activeDeviceID = deviceID;
    _activeHeadsetName = name ?: @"Bluetooth Headset";

    SecurityManager *sm = [SecurityManager sharedManager];

    // Check if this device is protected
    if (![sm isDeviceProtected:name]) {
        NSLog(@"[AppDelegate] Device '%@' is not in protected list. Skipping lock.", name);
        [self updateStatusIcon:GuardStatusAuthorized];
        return;
    }

    if (![sm boolSetting:kSecuritySettingAutoLockOnConnect defaultValue:YES]) {
        NSLog(@"[AppDelegate] Auto-lock on connect disabled. Skipping lock.");
        [self updateStatusIcon:GuardStatusAuthorized];
        return;
    }

    // Lock device immediately
    NSLog(@"[AppDelegate] Auto-locking headset '%@'...", name);
    [[AudioGuard sharedGuard] lockDevice:deviceID];
    [self updateStatusIcon:GuardStatusLocked];

    [sm logEvent:@"Headset Connected"
         details:[NSString stringWithFormat:@"'%@' connected -> Audio muted and locked", name]
            type:@"connect_lock"];

    // Present unlock modal overlay
    __weak typeof(self) weakSelf = self;
    [[UnlockWindowController sharedController] presentForDevice:name completion:^(BOOL unlocked) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (unlocked) {
            NSLog(@"[AppDelegate] Audio unlocked successfully for '%@'", strongSelf->_activeHeadsetName);
            [[AudioGuard sharedGuard] unlockCurrentDevice];
            [strongSelf updateStatusIcon:GuardStatusAuthorized];
            [[SecurityManager sharedManager] logEvent:@"Unlocked"
                                              details:[NSString stringWithFormat:@"'%@' audio authorized", strongSelf->_activeHeadsetName]
                                                 type:@"auth_success"];
        } else {
            NSLog(@"[AppDelegate] Authorization rejected or failed for '%@'", strongSelf->_activeHeadsetName);
        }
    }];
}

- (void)handleHeadsetDisconnected:(AudioDeviceID)deviceID name:(NSString *)name {
    NSLog(@"[AppDelegate] Headset disconnected: '%@'", name);
    _activeDeviceID = kAudioObjectUnknown;
    _activeHeadsetName = nil;

    [[UnlockWindowController sharedController] dismissWindow];
    [self updateStatusIcon:GuardStatusIdle];

    [[SecurityManager sharedManager] logEvent:@"Headset Disconnected"
                                      details:[NSString stringWithFormat:@"'%@' disconnected", name]
                                         type:@"disconnect"];
}

#pragma mark - Public Control Methods

- (void)lockCurrentHeadset {
    AudioDeviceID devID = _activeDeviceID;
    if (devID == kAudioObjectUnknown) {
        devID = [[AudioGuard sharedGuard] defaultOutputDeviceID];
    }
    if (devID != kAudioObjectUnknown && [[AudioGuard sharedGuard] isBluetoothDevice:devID]) {
        NSString *name = [[AudioGuard sharedGuard] deviceNameForID:devID];
        _activeDeviceID = devID;
        _activeHeadsetName = name;
        [[AudioGuard sharedGuard] lockDevice:devID];
        [self updateStatusIcon:GuardStatusLocked];
        [[UnlockWindowController sharedController] presentForDevice:name completion:^(BOOL unlocked) {
            if (unlocked) {
                [[AudioGuard sharedGuard] unlockCurrentDevice];
                [self updateStatusIcon:GuardStatusAuthorized];
            }
        }];
    }
}

- (void)unlockCurrentHeadset {
    [[UnlockWindowController sharedController] presentForDevice:_activeHeadsetName completion:^(BOOL unlocked) {
        if (unlocked) {
            [[AudioGuard sharedGuard] unlockCurrentDevice];
            [self updateStatusIcon:GuardStatusAuthorized];
        }
    }];
}

- (void)disconnectCurrentHeadset {
    if (_activeHeadsetName) {
        [[BluetoothManager sharedManager] disconnectDeviceNamed:_activeHeadsetName];
        [[AudioGuard sharedGuard] routeAudioToBuiltIn];
        [self handleHeadsetDisconnected:_activeDeviceID name:_activeHeadsetName];
    }
}

#pragma mark - Menu Actions

- (void)unlockMenuClicked:(id)sender {
    [self unlockCurrentHeadset];
}

- (void)lockMenuClicked:(id)sender {
    [self lockCurrentHeadset];
}

- (void)disconnectMenuClicked:(id)sender {
    [self disconnectCurrentHeadset];
}

- (void)preferencesMenuClicked:(id)sender {
    [[PreferencesWindowController sharedController] showPreferences];
}

- (void)changePinMenuClicked:(id)sender {
    PreferencesWindowController *pwc = [PreferencesWindowController sharedController];
    [pwc showPreferences];
    // Select password tab
    [pwc.window makeKeyAndOrderFront:nil];
}

- (void)quitMenuClicked:(id)sender {
    [NSApp terminate:nil];
}

#pragma mark - System Sleep / Lock Notifications

- (void)workspaceWillSleep:(NSNotification *)note {
    NSLog(@"[AppDelegate] System going to sleep.");
    if ([[SecurityManager sharedManager] boolSetting:kSecuritySettingLockOnSleep defaultValue:YES]) {
        if (_activeDeviceID != kAudioObjectUnknown && [[AudioGuard sharedGuard] isBluetoothDevice:_activeDeviceID]) {
            [[AudioGuard sharedGuard] lockDevice:_activeDeviceID];
            [self updateStatusIcon:GuardStatusLocked];
            [[SecurityManager sharedManager] logEvent:@"Sleep Lock" details:@"System sleeping -> Headset audio locked" type:@"sleep_lock"];
        }
    }
}

- (void)workspaceDidWake:(NSNotification *)note {
    NSLog(@"[AppDelegate] System woke up.");
    if ([AudioGuard sharedGuard].isLocked) {
        [[UnlockWindowController sharedController] presentForDevice:_activeHeadsetName completion:^(BOOL unlocked) {
            if (unlocked) {
                [[AudioGuard sharedGuard] unlockCurrentDevice];
                [self updateStatusIcon:GuardStatusAuthorized];
            }
        }];
    }
}

- (void)sessionDidResignActive:(NSNotification *)note {
    NSLog(@"[AppDelegate] User session resigned active (screen lock).");
    if ([[SecurityManager sharedManager] boolSetting:kSecuritySettingLockOnSleep defaultValue:YES]) {
        if (_activeDeviceID != kAudioObjectUnknown && [[AudioGuard sharedGuard] isBluetoothDevice:_activeDeviceID]) {
            [[AudioGuard sharedGuard] lockDevice:_activeDeviceID];
            [self updateStatusIcon:GuardStatusLocked];
            [[SecurityManager sharedManager] logEvent:@"Screen Lock" details:@"Screen locked -> Headset audio locked" type:@"sleep_lock"];
        }
    }
}

#pragma mark - AudioGuardDelegate

- (void)audioGuardDidDetectBluetoothDeviceConnected:(AudioDeviceID)deviceID name:(NSString *)name {
    NSLog(@"[AppDelegate] AudioGuard detected Bluetooth connected: '%@' (ID: %u)", name, deviceID);
    [self handleHeadsetConnected:deviceID name:name];
}

- (void)audioGuardDidDetectBluetoothDeviceDisconnected:(AudioDeviceID)deviceID name:(NSString *)name {
    NSLog(@"[AppDelegate] AudioGuard detected Bluetooth disconnected: '%@' (ID: %u)", name, deviceID);
    [self handleHeadsetDisconnected:deviceID name:name];
}

- (void)audioGuardDidDetectDefaultOutputChanged:(AudioDeviceID)deviceID name:(NSString *)name isBluetooth:(BOOL)isBluetooth {
    if (isBluetooth) {
        if (_currentStatus != GuardStatusAuthorized || _activeDeviceID != deviceID) {
            [self handleHeadsetConnected:deviceID name:name];
        }
    }
}

- (void)audioGuardDidInterceptVolumeTamperOnDevice:(AudioDeviceID)deviceID {
    [[SecurityManager sharedManager] logEvent:@"Volume Tamper Intercepted"
                                      details:@"Headset physical volume button pressed while locked; forced re-mute"
                                         type:@"tamper"];
}

#pragma mark - BluetoothManagerDelegate

- (void)bluetoothManagerDidDetectDeviceConnected:(IOBluetoothDevice *)device {
    NSLog(@"[AppDelegate] BluetoothManager detected connection: '%@'", device.nameOrAddress);
}

@end
