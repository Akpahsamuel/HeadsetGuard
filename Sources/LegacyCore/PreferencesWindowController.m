#import "PreferencesWindowController.h"
#import "SecurityManager.h"
#import "BluetoothManager.h"
#import "AudioGuard.h"

@interface PreferencesWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTabView *tabView;

// Tab 1 controls
@property (nonatomic, strong) NSButton *autoLockCheckbox;
@property (nonatomic, strong) NSButton *strictMuteCheckbox;
@property (nonatomic, strong) NSButton *lockOnSleepCheckbox;
@property (nonatomic, strong) NSButton *biometricsCheckbox;
@property (nonatomic, strong) NSButton *autoDisconnectCheckbox;
@property (nonatomic, strong) NSPopUpButton *maxAttemptsPopup;

// Tab 2 controls
@property (nonatomic, strong) NSSecureTextField *currentPasswordField;
@property (nonatomic, strong) NSSecureTextField *freshPasswordField;
@property (nonatomic, strong) NSSecureTextField *confirmPasswordField;
@property (nonatomic, strong) NSTextField *passwordStatusLabel;

// Tab 3 controls
@property (nonatomic, strong) NSButton *protectAllCheckbox;
@property (nonatomic, strong) NSTableView *devicesTableView;
@property (nonatomic, strong) NSArray<IOBluetoothDevice *> *pairedDevices;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedDevices;

// Tab 4 controls
@property (nonatomic, strong) NSTableView *logTableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *logs;

@end

@implementation PreferencesWindowController

+ (instancetype)sharedController {
    static PreferencesWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PreferencesWindowController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 560, 480);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"HeadsetGuard Preferences & Security Dashboard";
    window.minSize = NSMakeSize(560, 480);

    self = [super initWithWindow:window];
    if (self) {
        _selectedDevices = [NSMutableSet setWithArray:[[SecurityManager sharedManager] protectedDevices]];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    _tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(16, 16, 528, 448)];
    _tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Tabs
    NSTabViewItem *tabGeneral = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    tabGeneral.label = @"General Security";
    tabGeneral.view = [self createGeneralTabView];
    [_tabView addTabViewItem:tabGeneral];

    NSTabViewItem *tabPassword = [[NSTabViewItem alloc] initWithIdentifier:@"password"];
    tabPassword.label = @"Password & PIN";
    tabPassword.view = [self createPasswordTabView];
    [_tabView addTabViewItem:tabPassword];

    NSTabViewItem *tabDevices = [[NSTabViewItem alloc] initWithIdentifier:@"devices"];
    tabDevices.label = @"Protected Headsets";
    tabDevices.view = [self createDevicesTabView];
    [_tabView addTabViewItem:tabDevices];

    NSTabViewItem *tabLogs = [[NSTabViewItem alloc] initWithIdentifier:@"logs"];
    tabLogs.label = @"Activity Log";
    tabLogs.view = [self createLogsTabView];
    [_tabView addTabViewItem:tabLogs];

    [contentView addSubview:_tabView];
}

#pragma mark - Tab 1: General Security

- (NSView *)createGeneralTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 410)];
    SecurityManager *sm = [SecurityManager sharedManager];

    CGFloat y = 370.0;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 24)];
    header.stringValue = @"Protection & Locking Rules";
    header.font = [NSFont boldSystemFontOfSize:14];
    header.editable = NO;
    header.bordered = NO;
    header.backgroundColor = [NSColor clearColor];
    [view addSubview:header];

    y -= 34.0;
    _autoLockCheckbox = [NSButton checkboxWithTitle:@"Auto-Lock audio whenever a Bluetooth headset connects"
                                             target:self
                                             action:@selector(settingChanged:)];
    _autoLockCheckbox.frame = NSMakeRect(24, y, 460, 22);
    _autoLockCheckbox.state = [sm boolSetting:kSecuritySettingAutoLockOnConnect defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:_autoLockCheckbox];

    y -= 30.0;
    _strictMuteCheckbox = [NSButton checkboxWithTitle:@"Strict Mute Clamp: intercept and block physical volume buttons while locked"
                                               target:self
                                               action:@selector(settingChanged:)];
    _strictMuteCheckbox.frame = NSMakeRect(24, y, 460, 22);
    _strictMuteCheckbox.state = [sm boolSetting:kSecuritySettingStrictMute defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:_strictMuteCheckbox];

    y -= 30.0;
    _lockOnSleepCheckbox = [NSButton checkboxWithTitle:@"Re-lock headset audio on Mac sleep or lock screen"
                                                target:self
                                                action:@selector(settingChanged:)];
    _lockOnSleepCheckbox.frame = NSMakeRect(24, y, 460, 22);
    _lockOnSleepCheckbox.state = [sm boolSetting:kSecuritySettingLockOnSleep defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:_lockOnSleepCheckbox];

    y -= 30.0;
    _biometricsCheckbox = [NSButton checkboxWithTitle:@"Allow Touch ID / Apple Watch / Mac Password for quick unlock"
                                               target:self
                                               action:@selector(settingChanged:)];
    _biometricsCheckbox.frame = NSMakeRect(24, y, 460, 22);
    _biometricsCheckbox.state = [sm boolSetting:kSecuritySettingBiometricsEnabled defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:_biometricsCheckbox];

    y -= 45.0;
    NSTextField *failHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 22)];
    failHeader.stringValue = @"Anti-Theft & Failure Safeguards";
    failHeader.font = [NSFont boldSystemFontOfSize:14];
    failHeader.editable = NO;
    failHeader.bordered = NO;
    failHeader.backgroundColor = [NSColor clearColor];
    [view addSubview:failHeader];

    y -= 32.0;
    _autoDisconnectCheckbox = [NSButton checkboxWithTitle:@"Disconnect and kick Bluetooth device off if password attempts exceed limit"
                                                   target:self
                                                   action:@selector(settingChanged:)];
    _autoDisconnectCheckbox.frame = NSMakeRect(24, y, 470, 22);
    _autoDisconnectCheckbox.state = [sm boolSetting:kSecuritySettingAutoDisconnectOnFailure defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:_autoDisconnectCheckbox];

    y -= 36.0;
    NSTextField *attemptsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(24, y, 200, 22)];
    attemptsLabel.stringValue = @"Maximum failed password attempts:";
    attemptsLabel.editable = NO;
    attemptsLabel.bordered = NO;
    attemptsLabel.backgroundColor = [NSColor clearColor];
    [view addSubview:attemptsLabel];

    _maxAttemptsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(230, y, 90, 24) pullsDown:NO];
    [_maxAttemptsPopup addItemsWithTitles:@[@"3", @"5", @"10"]];
    NSInteger cur = [sm integerSetting:kSecuritySettingMaxFailedAttempts defaultValue:3];
    [_maxAttemptsPopup selectItemWithTitle:[NSString stringWithFormat:@"%ld", (long)cur]];
    _maxAttemptsPopup.target = self;
    _maxAttemptsPopup.action = @selector(settingChanged:);
    [view addSubview:_maxAttemptsPopup];

    return view;
}

#pragma mark - Tab 2: Password / PIN

- (NSView *)createPasswordTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 410)];
    SecurityManager *sm = [SecurityManager sharedManager];

    CGFloat y = 370.0;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 24)];
    header.stringValue = sm.isPasswordConfigured ? @"Change Master Security PIN / Password" : @"Set Up Master Security PIN / Password";
    header.font = [NSFont boldSystemFontOfSize:14];
    header.editable = NO;
    header.bordered = NO;
    header.backgroundColor = [NSColor clearColor];
    [view addSubview:header];

    y -= 26.0;
    NSTextField *sub = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 20)];
    sub.stringValue = @"Used to authorize audio streaming whenever your Bluetooth headset connects.";
    sub.font = [NSFont systemFontOfSize:12];
    sub.textColor = [NSColor secondaryLabelColor];
    sub.editable = NO;
    sub.bordered = NO;
    sub.backgroundColor = [NSColor clearColor];
    [view addSubview:sub];

    y -= 44.0;
    NSTextField *lblCurrent = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 160, 22)];
    lblCurrent.stringValue = @"Current Password:";
    lblCurrent.editable = NO;
    lblCurrent.bordered = NO;
    lblCurrent.backgroundColor = [NSColor clearColor];
    [view addSubview:lblCurrent];

    _currentPasswordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(180, y, 260, 24)];
    _currentPasswordField.enabled = sm.isPasswordConfigured;
    _currentPasswordField.placeholderString = sm.isPasswordConfigured ? @"Enter current password" : @"(No password configured yet)";
    [view addSubview:_currentPasswordField];

    y -= 36.0;
    NSTextField *lblNew = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 160, 22)];
    lblNew.stringValue = @"New PIN / Password:";
    lblNew.editable = NO;
    lblNew.bordered = NO;
    lblNew.backgroundColor = [NSColor clearColor];
    [view addSubview:lblNew];

    _freshPasswordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(180, y, 260, 24)];
    _freshPasswordField.placeholderString = @"At least 4 characters";
    [view addSubview:_freshPasswordField];

    y -= 36.0;
    NSTextField *lblConfirm = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 160, 22)];
    lblConfirm.stringValue = @"Confirm New Password:";
    lblConfirm.editable = NO;
    lblConfirm.bordered = NO;
    lblConfirm.backgroundColor = [NSColor clearColor];
    [view addSubview:lblConfirm];

    _confirmPasswordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(180, y, 260, 24)];
    _confirmPasswordField.placeholderString = @"Re-enter new password";
    [view addSubview:_confirmPasswordField];

    y -= 42.0;
    NSButton *btnSave = [NSButton buttonWithTitle:@"Save Password" target:self action:@selector(savePasswordClicked:)];
    btnSave.frame = NSMakeRect(180, y, 140, 32);
    btnSave.bezelStyle = NSBezelStylePush;
    [view addSubview:btnSave];

    y -= 30.0;
    _passwordStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 22)];
    _passwordStatusLabel.stringValue = @"";
    _passwordStatusLabel.editable = NO;
    _passwordStatusLabel.bordered = NO;
    _passwordStatusLabel.backgroundColor = [NSColor clearColor];
    _passwordStatusLabel.alignment = NSTextAlignmentCenter;
    [view addSubview:_passwordStatusLabel];

    return view;
}

#pragma mark - Tab 3: Protected Devices

- (NSView *)createDevicesTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 410)];
    SecurityManager *sm = [SecurityManager sharedManager];

    CGFloat y = 370.0;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 480, 24)];
    header.stringValue = @"Target Headsets & Bluetooth Devices";
    header.font = [NSFont boldSystemFontOfSize:14];
    header.editable = NO;
    header.bordered = NO;
    header.backgroundColor = [NSColor clearColor];
    [view addSubview:header];

    y -= 30.0;
    _protectAllCheckbox = [NSButton checkboxWithTitle:@"Protect ALL Bluetooth Audio Devices (Recommended)"
                                               target:self
                                               action:@selector(protectAllToggled:)];
    _protectAllCheckbox.frame = NSMakeRect(24, y, 460, 22);
    _protectAllCheckbox.state = [sm boolSetting:kSecuritySettingProtectAllBluetooth defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:_protectAllCheckbox];

    y -= 26.0;
    NSTextField *sub = [[NSTextField alloc] initWithFrame:NSMakeRect(24, y, 480, 18)];
    sub.stringValue = @"Or select specific paired headsets below to lock:";
    sub.font = [NSFont systemFontOfSize:11.5];
    sub.textColor = [NSColor secondaryLabelColor];
    sub.editable = NO;
    sub.bordered = NO;
    sub.backgroundColor = [NSColor clearColor];
    [view addSubview:sub];

    y -= 210.0;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, y, 480, 200)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    _devicesTableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    NSTableColumn *colCheck = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    colCheck.title = @"Protect";
    colCheck.width = 60.0;
    [_devicesTableView addTableColumn:colCheck];

    NSTableColumn *colName = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    colName.title = @"Device Name";
    colName.width = 240.0;
    [_devicesTableView addTableColumn:colName];

    NSTableColumn *colStatus = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    colStatus.title = @"Status";
    colStatus.width = 150.0;
    [_devicesTableView addTableColumn:colStatus];

    _devicesTableView.dataSource = self;
    _devicesTableView.delegate = self;
    scrollView.documentView = _devicesTableView;
    [view addSubview:scrollView];

    y -= 40.0;
    NSButton *btnRefresh = [NSButton buttonWithTitle:@"Refresh Paired Headsets" target:self action:@selector(refreshDevicesClicked:)];
    btnRefresh.frame = NSMakeRect(20, y, 180, 30);
    btnRefresh.bezelStyle = NSBezelStylePush;
    [view addSubview:btnRefresh];

    [self reloadPairedDevices];

    return view;
}

#pragma mark - Tab 4: Activity Log

- (NSView *)createLogsTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 410)];

    CGFloat y = 370.0;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 300, 24)];
    header.stringValue = @"Security Audit & Event Log";
    header.font = [NSFont boldSystemFontOfSize:14];
    header.editable = NO;
    header.bordered = NO;
    header.backgroundColor = [NSColor clearColor];
    [view addSubview:header];

    NSButton *btnClear = [NSButton buttonWithTitle:@"Clear Log" target:self action:@selector(clearLogsClicked:)];
    btnClear.frame = NSMakeRect(380, y, 120, 26);
    btnClear.bezelStyle = NSBezelStylePush;
    [view addSubview:btnClear];

    y -= 320.0;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, y, 480, 310)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    _logTableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    
    NSTableColumn *colTime = [[NSTableColumn alloc] initWithIdentifier:@"time"];
    colTime.title = @"Timestamp";
    colTime.width = 130.0;
    [_logTableView addTableColumn:colTime];

    NSTableColumn *colEvent = [[NSTableColumn alloc] initWithIdentifier:@"event"];
    colEvent.title = @"Event";
    colEvent.width = 130.0;
    [_logTableView addTableColumn:colEvent];

    NSTableColumn *colDetails = [[NSTableColumn alloc] initWithIdentifier:@"details"];
    colDetails.title = @"Details";
    colDetails.width = 200.0;
    [_logTableView addTableColumn:colDetails];

    _logTableView.dataSource = self;
    _logTableView.delegate = self;
    scrollView.documentView = _logTableView;
    [view addSubview:scrollView];

    [self reloadLogs];

    return view;
}

#pragma mark - Actions

- (void)showPreferences {
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self reloadPairedDevices];
    [self reloadLogs];
}

- (void)settingChanged:(id)sender {
    SecurityManager *sm = [SecurityManager sharedManager];
    [sm setBoolSetting:kSecuritySettingAutoLockOnConnect value:(_autoLockCheckbox.state == NSControlStateValueOn)];
    [sm setBoolSetting:kSecuritySettingStrictMute value:(_strictMuteCheckbox.state == NSControlStateValueOn)];
    [sm setBoolSetting:kSecuritySettingLockOnSleep value:(_lockOnSleepCheckbox.state == NSControlStateValueOn)];
    [sm setBoolSetting:kSecuritySettingBiometricsEnabled value:(_biometricsCheckbox.state == NSControlStateValueOn)];
    [sm setBoolSetting:kSecuritySettingAutoDisconnectOnFailure value:(_autoDisconnectCheckbox.state == NSControlStateValueOn)];
    
    NSInteger attempts = [_maxAttemptsPopup.titleOfSelectedItem integerValue];
    if (attempts > 0) {
        [sm setIntegerSetting:kSecuritySettingMaxFailedAttempts value:attempts];
    }

    [AudioGuard sharedGuard].strictMuteEnforcement = (_strictMuteCheckbox.state == NSControlStateValueOn);
}

- (void)protectAllToggled:(id)sender {
    BOOL protectAll = (_protectAllCheckbox.state == NSControlStateValueOn);
    [[SecurityManager sharedManager] setBoolSetting:kSecuritySettingProtectAllBluetooth value:protectAll];
    [_devicesTableView reloadData];
}

- (void)savePasswordClicked:(id)sender {
    SecurityManager *sm = [SecurityManager sharedManager];
    NSString *curr = _currentPasswordField.stringValue;
    NSString *newP = _freshPasswordField.stringValue;
    NSString *conf = _confirmPasswordField.stringValue;

    if (newP.length < 4) {
        _passwordStatusLabel.textColor = [NSColor systemRedColor];
        _passwordStatusLabel.stringValue = @"New password must be at least 4 characters.";
        return;
    }
    if (![newP isEqualToString:conf]) {
        _passwordStatusLabel.textColor = [NSColor systemRedColor];
        _passwordStatusLabel.stringValue = @"New passwords do not match.";
        return;
    }

    NSError *error = nil;
    BOOL ok = NO;
    if (sm.isPasswordConfigured) {
        ok = [sm changePasswordFrom:curr to:newP error:&error];
    } else {
        ok = [sm setupMasterPassword:newP error:&error];
    }

    if (ok) {
        _passwordStatusLabel.textColor = [NSColor systemGreenColor];
        _passwordStatusLabel.stringValue = @"Master password successfully updated!";
        _currentPasswordField.stringValue = @"";
        _freshPasswordField.stringValue = @"";
        _confirmPasswordField.stringValue = @"";
        _currentPasswordField.enabled = YES;
    } else {
        _passwordStatusLabel.textColor = [NSColor systemRedColor];
        _passwordStatusLabel.stringValue = error.localizedDescription ?: @"Failed to update password.";
    }
}

- (void)refreshDevicesClicked:(id)sender {
    [self reloadPairedDevices];
}

- (void)clearLogsClicked:(id)sender {
    [[SecurityManager sharedManager] clearLogs];
    [self reloadLogs];
}

- (void)reloadPairedDevices {
    _pairedDevices = [[BluetoothManager sharedManager] pairedAudioDevices];
    [_devicesTableView reloadData];
}

- (void)reloadLogs {
    _logs = [[SecurityManager sharedManager] recentLogs];
    [_logTableView reloadData];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _devicesTableView) {
        return _pairedDevices.count;
    } else if (tableView == _logTableView) {
        return _logs.count;
    }
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == _devicesTableView) {
        IOBluetoothDevice *dev = _pairedDevices[row];
        NSString *colId = tableColumn.identifier;

        if ([colId isEqualToString:@"check"]) {
            NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(deviceCheckToggled:)];
            check.tag = row;
            BOOL protectAll = [[SecurityManager sharedManager] boolSetting:kSecuritySettingProtectAllBluetooth defaultValue:YES];
            if (protectAll) {
                check.state = NSControlStateValueOn;
                check.enabled = NO;
            } else {
                check.enabled = YES;
                check.state = [_selectedDevices containsObject:dev.nameOrAddress] ? NSControlStateValueOn : NSControlStateValueOff;
            }
            return check;
        } else if ([colId isEqualToString:@"name"]) {
            NSTextField *txt = [NSTextField labelWithString:dev.nameOrAddress ?: @"Unknown"];
            txt.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
            return txt;
        } else if ([colId isEqualToString:@"status"]) {
            NSString *stat = [dev isConnected] ? @"Connected 🎧" : @"Paired (Offline)";
            NSTextField *txt = [NSTextField labelWithString:stat];
            txt.textColor = [dev isConnected] ? [NSColor systemGreenColor] : [NSColor secondaryLabelColor];
            txt.font = [NSFont systemFontOfSize:11.5];
            return txt;
        }
    } else if (tableView == _logTableView) {
        NSDictionary *entry = _logs[row];
        NSString *colId = tableColumn.identifier;
        if ([colId isEqualToString:@"time"]) {
            return [NSTextField labelWithString:entry[@"timestamp"] ?: @""];
        } else if ([colId isEqualToString:@"event"]) {
            NSTextField *txt = [NSTextField labelWithString:entry[@"event"] ?: @""];
            txt.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold];
            return txt;
        } else if ([colId isEqualToString:@"details"]) {
            return [NSTextField labelWithString:entry[@"details"] ?: @""];
        }
    }
    return nil;
}

- (void)deviceCheckToggled:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || (NSUInteger)row >= _pairedDevices.count) return;
    IOBluetoothDevice *dev = _pairedDevices[row];
    NSString *name = dev.nameOrAddress;

    if (sender.state == NSControlStateValueOn) {
        [_selectedDevices addObject:name];
    } else {
        [_selectedDevices removeObject:name];
    }

    [[SecurityManager sharedManager] setProtectedDevices:[_selectedDevices allObjects]];
}

@end
