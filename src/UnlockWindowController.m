#import "UnlockWindowController.h"
#import "SecurityManager.h"
#import "BluetoothManager.h"
#import "AudioGuard.h"
#import <QuartzCore/QuartzCore.h>

@interface UnlockWindowController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSVisualEffectView *visualEffectView;
@property (nonatomic, strong) NSImageView *iconImageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *deviceLabel;
@property (nonatomic, strong) NSTextField *statusBadge;
@property (nonatomic, strong) NSSecureTextField *passwordField;
@property (nonatomic, strong) NSButton *unlockButton;
@property (nonatomic, strong) NSButton *touchIDButton;
@property (nonatomic, strong) NSButton *disconnectButton;
@property (nonatomic, strong) NSTextField *errorLabel;

@end

@implementation UnlockWindowController

+ (instancetype)sharedController {
    static UnlockWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[UnlockWindowController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    NSRect windowRect = NSMakeRect(0, 0, 420, 410);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.level = NSFloatingWindowLevel + 1;
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.hasShadow = YES;

    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSWindow *window = self.window;
    NSView *contentView = window.contentView;
    contentView.wantsLayer = YES;

    // Background blur
    _visualEffectView = [[NSVisualEffectView alloc] initWithFrame:contentView.bounds];
    _visualEffectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _visualEffectView.material = NSVisualEffectMaterialHUDWindow;
    _visualEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _visualEffectView.state = NSVisualEffectStateActive;
    _visualEffectView.wantsLayer = YES;
    _visualEffectView.layer.cornerRadius = 18.0;
    _visualEffectView.layer.masksToBounds = YES;
    _visualEffectView.layer.borderWidth = 1.0;
    _visualEffectView.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.15].CGColor;
    [contentView addSubview:_visualEffectView];

    CGFloat width = 420.0;
    CGFloat y = 390.0;

    // Header Icon (Lock + Headphones)
    y -= 70.0;
    _iconImageView = [[NSImageView alloc] initWithFrame:NSMakeRect((width - 64) / 2.0, y, 64, 64)];
    NSImage *symbolImg = nil;
    if (@available(macOS 11.0, *)) {
        symbolImg = [NSImage imageWithSystemSymbolName:@"lock.shield.fill" accessibilityDescription:@"Security"];
    }
    if (!symbolImg) {
        symbolImg = [NSImage imageNamed:NSImageNameLockLockedTemplate];
    }
    _iconImageView.image = symbolImg;
    _iconImageView.contentTintColor = [NSColor systemOrangeColor];
    [_visualEffectView addSubview:_iconImageView];

    // Status Badge ("AUDIO LOCKED")
    y -= 30.0;
    _statusBadge = [[NSTextField alloc] initWithFrame:NSMakeRect((width - 160) / 2.0, y, 160, 22)];
    _statusBadge.editable = NO;
    _statusBadge.selectable = NO;
    _statusBadge.bordered = NO;
    _statusBadge.alignment = NSTextAlignmentCenter;
    _statusBadge.stringValue = @"AUDIO MUTED & LOCKED";
    _statusBadge.font = [NSFont boldSystemFontOfSize:10.5];
    _statusBadge.textColor = [NSColor systemRedColor];
    _statusBadge.wantsLayer = YES;
    _statusBadge.layer.backgroundColor = [NSColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.18].CGColor;
    _statusBadge.layer.cornerRadius = 6.0;
    _statusBadge.layer.masksToBounds = YES;
    [_visualEffectView addSubview:_statusBadge];

    // Title
    y -= 32.0;
    _titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, width - 40, 24)];
    _titleLabel.editable = NO;
    _titleLabel.selectable = NO;
    _titleLabel.bordered = NO;
    _titleLabel.alignment = NSTextAlignmentCenter;
    _titleLabel.stringValue = @"Headset Security Authorization";
    _titleLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.backgroundColor = [NSColor clearColor];
    [_visualEffectView addSubview:_titleLabel];

    // Device Subtitle
    y -= 22.0;
    _deviceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, width - 40, 20)];
    _deviceLabel.editable = NO;
    _deviceLabel.selectable = NO;
    _deviceLabel.bordered = NO;
    _deviceLabel.alignment = NSTextAlignmentCenter;
    _deviceLabel.stringValue = @"Bluetooth Headset Connected";
    _deviceLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _deviceLabel.textColor = [NSColor secondaryLabelColor];
    _deviceLabel.backgroundColor = [NSColor clearColor];
    [_visualEffectView addSubview:_deviceLabel];

    // Password Field
    y -= 52.0;
    _passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(50, y, width - 100, 36)];
    _passwordField.placeholderString = @"Enter PIN or Password";
    _passwordField.font = [NSFont systemFontOfSize:15];
    _passwordField.alignment = NSTextAlignmentCenter;
    _passwordField.focusRingType = NSFocusRingTypeExterior;
    _passwordField.target = self;
    _passwordField.action = @selector(unlockAction:);
    _passwordField.delegate = self;
    [_visualEffectView addSubview:_passwordField];

    // Error / status feedback message
    y -= 24.0;
    _errorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(30, y, width - 60, 18)];
    _errorLabel.editable = NO;
    _errorLabel.selectable = NO;
    _errorLabel.bordered = NO;
    _errorLabel.alignment = NSTextAlignmentCenter;
    _errorLabel.stringValue = @"";
    _errorLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    _errorLabel.textColor = [NSColor systemRedColor];
    _errorLabel.backgroundColor = [NSColor clearColor];
    [_visualEffectView addSubview:_errorLabel];

    // Primary Unlock Button
    y -= 46.0;
    _unlockButton = [NSButton buttonWithTitle:@"Unlock Audio Output" target:self action:@selector(unlockAction:)];
    _unlockButton.frame = NSMakeRect(50, y, width - 100, 36);
    _unlockButton.bezelStyle = NSBezelStylePush;
    _unlockButton.keyEquivalent = @"\r"; // Enter key
    _unlockButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    [_visualEffectView addSubview:_unlockButton];

    // Secondary Touch ID Button
    y -= 38.0;
    _touchIDButton = [NSButton buttonWithTitle:@"Use Touch ID / Mac Password" target:self action:@selector(touchIDAction:)];
    _touchIDButton.frame = NSMakeRect(50, y, width - 100, 32);
    _touchIDButton.bezelStyle = NSBezelStylePush;
    _touchIDButton.font = [NSFont systemFontOfSize:12];
    if (@available(macOS 11.0, *)) {
        _touchIDButton.image = [NSImage imageWithSystemSymbolName:@"touchid" accessibilityDescription:@"Touch ID"];
    }
    [_visualEffectView addSubview:_touchIDButton];

    // Disconnect Action (Bottom link)
    y -= 34.0;
    _disconnectButton = [NSButton buttonWithTitle:@"Disconnect Headset & Block" target:self action:@selector(disconnectAction:)];
    _disconnectButton.frame = NSMakeRect(50, y, width - 100, 24);
    _disconnectButton.bordered = NO;
    _disconnectButton.contentTintColor = [NSColor systemRedColor];
    _disconnectButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    [_visualEffectView addSubview:_disconnectButton];
}

#pragma mark - Presentation

- (void)presentForDevice:(NSString *)deviceName completion:(nullable UnlockCompletionBlock)completion {
    self.deviceName = deviceName ?: @"Bluetooth Headset";
    self.onCompletion = completion;

    self.deviceLabel.stringValue = [NSString stringWithFormat:@"Device: %@", self.deviceName];
    self.passwordField.stringValue = @"";
    self.errorLabel.stringValue = @"";
    self.statusBadge.stringValue = @"AUDIO MUTED & LOCKED";
    self.statusBadge.textColor = [NSColor systemRedColor];
    self.statusBadge.layer.backgroundColor = [NSColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.18].CGColor;
    
    if (@available(macOS 11.0, *)) {
        self.iconImageView.image = [NSImage imageWithSystemSymbolName:@"lock.shield.fill" accessibilityDescription:@"Security"];
        self.iconImageView.contentTintColor = [NSColor systemOrangeColor];
    }

    // Check if biometric authentication is available
    SecurityManager *sm = [SecurityManager sharedManager];
    self.touchIDButton.hidden = ![sm biometricsAvailable];

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeFirstResponder:self.passwordField];

    // Auto-prompt Touch ID if enabled for seamless UX
    if ([sm biometricsAvailable] && [sm boolSetting:kSecuritySettingBiometricsEnabled defaultValue:YES]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.window.isVisible) {
                [self touchIDAction:nil];
            }
        });
    }
}

- (void)dismissWindow {
    [self.window orderOut:nil];
}

#pragma mark - Actions

- (void)unlockAction:(id)sender {
    NSString *entered = self.passwordField.stringValue;
    SecurityManager *sm = [SecurityManager sharedManager];

    // If master password is not yet configured, first entry sets the password!
    if (!sm.isPasswordConfigured) {
        if (entered.length < 4) {
            self.errorLabel.stringValue = @"First time setup: Enter a PIN/password (min 4 chars)";
            [self shakeWindow];
            return;
        }
        NSError *setupErr = nil;
        if ([sm setupMasterPassword:entered error:&setupErr]) {
            [self handleSuccessfulUnlock];
            return;
        } else {
            self.errorLabel.stringValue = setupErr.localizedDescription ?: @"Setup failed";
            [self shakeWindow];
            return;
        }
    }

    if ([sm verifyPassword:entered]) {
        [self handleSuccessfulUnlock];
    } else {
        [self handleFailedAttempt];
    }
}

- (void)touchIDAction:(id)sender {
    SecurityManager *sm = [SecurityManager sharedManager];
    NSString *reason = [NSString stringWithFormat:@"Authorize audio output for %@", self.deviceName ?: @"Bluetooth Headset"];

    [sm authenticateWithBiometricsWithReason:reason completion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            [self handleSuccessfulUnlock];
        } else if (error && error.code != LAErrorUserCancel) {
            self.errorLabel.stringValue = @"Touch ID verification failed";
            [self shakeWindow];
        }
    }];
}

- (void)disconnectAction:(id)sender {
    NSLog(@"[UnlockWindowController] User requested emergency disconnect for %@", self.deviceName);
    [[SecurityManager sharedManager] logEvent:@"Manual Disconnect"
                                      details:[NSString stringWithFormat:@"User rejected and disconnected %@", self.deviceName]
                                         type:@"disconnect"];

    [[BluetoothManager sharedManager] disconnectDeviceNamed:self.deviceName];
    [[AudioGuard sharedGuard] routeAudioToBuiltIn];
    [self dismissWindow];

    if (self.onCompletion) {
        self.onCompletion(NO);
    }
}

#pragma mark - Unlock Flow

- (void)handleSuccessfulUnlock {
    [[NSSound soundNamed:@"Hero"] play];

    self.errorLabel.textColor = [NSColor systemGreenColor];
    self.errorLabel.stringValue = @"Authorization Approved!";
    self.statusBadge.stringValue = @"UNLOCKED & AUTHORIZED";
    self.statusBadge.textColor = [NSColor systemGreenColor];
    self.statusBadge.layer.backgroundColor = [NSColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:0.18].CGColor;

    if (@available(macOS 11.0, *)) {
        self.iconImageView.image = [NSImage imageWithSystemSymbolName:@"checkmark.shield.fill" accessibilityDescription:@"Success"];
        self.iconImageView.contentTintColor = [NSColor systemGreenColor];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self dismissWindow];
        if (self.onCompletion) {
            self.onCompletion(YES);
        }
    });
}

- (void)handleFailedAttempt {
    [[NSSound soundNamed:@"Funk"] play];
    [self shakeWindow];

    SecurityManager *sm = [SecurityManager sharedManager];
    NSInteger maxAttempts = [sm integerSetting:kSecuritySettingMaxFailedAttempts defaultValue:3];
    NSInteger remaining = maxAttempts - sm.failedAttemptsCount;

    if (remaining > 0) {
        self.errorLabel.stringValue = [NSString stringWithFormat:@"Incorrect password. %ld attempt%@ remaining.",
                                       (long)remaining, remaining == 1 ? @"" : @"s"];
    } else {
        self.errorLabel.stringValue = @"Security Limit Reached! Disconnecting...";
        
        if ([sm boolSetting:kSecuritySettingAutoDisconnectOnFailure defaultValue:YES]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self disconnectAction:nil];
            });
        }
    }

    self.passwordField.stringValue = @"";
}

- (void)shakeWindow {
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"frameOrigin.x"];
    CGFloat currentX = self.window.frame.origin.x;
    shake.values = @[
        @(currentX),
        @(currentX - 12),
        @(currentX + 12),
        @(currentX - 8),
        @(currentX + 8),
        @(currentX - 4),
        @(currentX + 4),
        @(currentX)
    ];
    shake.duration = 0.4;
    [self.window.contentView.layer addAnimation:shake forKey:@"shakeAnimation"];
}

@end
