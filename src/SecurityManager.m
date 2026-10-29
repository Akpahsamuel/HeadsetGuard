#import "SecurityManager.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

NSString * const kSecuritySettingAutoLockOnConnect          = @"AutoLockOnConnect";
NSString * const kSecuritySettingLockOnSleep                = @"LockOnSleep";
NSString * const kSecuritySettingStrictMute                 = @"StrictMute";
NSString * const kSecuritySettingBiometricsEnabled          = @"BiometricsEnabled";
NSString * const kSecuritySettingMaxFailedAttempts          = @"MaxFailedAttempts";
NSString * const kSecuritySettingAutoDisconnectOnFailure    = @"AutoDisconnectOnFailure";
NSString * const kSecuritySettingProtectAllBluetooth        = @"ProtectAllBluetooth";
NSString * const kSecuritySettingProtectedDevices           = @"ProtectedDevices";

static NSString * const kMasterPasswordHashKey = @"MasterPasswordHash";
static NSString * const kMasterPasswordSaltKey = @"MasterPasswordSalt";
static NSString * const kAuditLogsKey          = @"SecurityAuditLogs";

@interface SecurityManager ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation SecurityManager

+ (instancetype)sharedManager {
    static SecurityManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SecurityManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [NSUserDefaults standardUserDefaults];
        _failedAttemptsCount = 0;
        [self registerDefaultSettings];
    }
    return self;
}

- (void)registerDefaultSettings {
    NSDictionary *defaults = @{
        kSecuritySettingAutoLockOnConnect: @YES,
        kSecuritySettingLockOnSleep: @YES,
        kSecuritySettingStrictMute: @YES,
        kSecuritySettingBiometricsEnabled: @YES,
        kSecuritySettingMaxFailedAttempts: @3,
        kSecuritySettingAutoDisconnectOnFailure: @YES,
        kSecuritySettingProtectAllBluetooth: @YES,
        kSecuritySettingProtectedDevices: @[]
    };
    [self.defaults registerDefaults:defaults];
}

#pragma mark - Password Hashing

- (NSData *)generateSalt {
    uint8_t salt[32];
    int result = SecRandomCopyBytes(kSecRandomDefault, sizeof(salt), salt);
    if (result == errSecSuccess) {
        return [NSData dataWithBytes:salt length:sizeof(salt)];
    }
    // Fallback pseudo-random if SecRandomCopyBytes fails
    NSMutableData *fallback = [NSMutableData dataWithLength:32];
    arc4random_buf(fallback.mutableBytes, 32);
    return fallback;
}

- (NSString *)hashPassword:(NSString *)password withSalt:(NSData *)salt {
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t derivedKey[32];
    
    CCKeyDerivationPBKDF(
        kCCPBKDF2,
        passwordData.bytes,
        passwordData.length,
        salt.bytes,
        salt.length,
        kCCPRFHmacAlgSHA256,
        10000,
        derivedKey,
        sizeof(derivedKey)
    );
    
    NSData *derivedData = [NSData dataWithBytes:derivedKey length:sizeof(derivedKey)];
    return [derivedData base64EncodedStringWithOptions:0];
}

- (BOOL)isPasswordConfigured {
    NSString *hash = [self.defaults stringForKey:kMasterPasswordHashKey];
    NSData *salt = [self.defaults dataForKey:kMasterPasswordSaltKey];
    return (hash.length > 0 && salt.length > 0);
}

- (BOOL)setupMasterPassword:(NSString *)password error:(NSError **)error {
    if (password.length < 4) {
        if (error) {
            *error = [NSError errorWithDomain:@"HeadsetGuard"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Password must be at least 4 characters long."}];
        }
        return NO;
    }
    
    NSData *salt = [self generateSalt];
    NSString *hash = [self hashPassword:password withSalt:salt];
    
    [self.defaults setObject:hash forKey:kMasterPasswordHashKey];
    [self.defaults setObject:salt forKey:kMasterPasswordSaltKey];
    [self.defaults synchronize];
    
    self.failedAttemptsCount = 0;
    [self logEvent:@"Password Set" details:@"New master password configured" type:@"security"];
    return YES;
}

- (BOOL)changePasswordFrom:(NSString *)oldPassword to:(NSString *)newPassword error:(NSError **)error {
    if (![self verifyPassword:oldPassword]) {
        if (error) {
            *error = [NSError errorWithDomain:@"HeadsetGuard"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Current password is incorrect."}];
        }
        return NO;
    }
    return [self setupMasterPassword:newPassword error:error];
}

- (BOOL)verifyPassword:(NSString *)password {
    if (!self.isPasswordConfigured) {
        return NO;
    }
    
    NSString *storedHash = [self.defaults stringForKey:kMasterPasswordHashKey];
    NSData *salt = [self.defaults dataForKey:kMasterPasswordSaltKey];
    if (!storedHash || !salt) return NO;
    
    NSString *testHash = [self hashPassword:password withSalt:salt];
    BOOL valid = [testHash isEqualToString:storedHash];
    
    if (valid) {
        self.failedAttemptsCount = 0;
        [self logEvent:@"Password Verified" details:@"Authentication successful" type:@"auth_success"];
    } else {
        self.failedAttemptsCount++;
        [self logEvent:@"Password Failed" details:[NSString stringWithFormat:@"Attempt %ld failed", (long)self.failedAttemptsCount] type:@"auth_failure"];
    }
    
    return valid;
}

#pragma mark - Biometrics

- (BOOL)biometricsAvailable {
    if (![self boolSetting:kSecuritySettingBiometricsEnabled defaultValue:YES]) {
        return NO;
    }
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;
    return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
}

- (void)authenticateWithBiometricsWithReason:(NSString *)reason completion:(void(^)(BOOL success, NSError *error))completion {
    LAContext *context = [[LAContext alloc] init];
    context.localizedFallbackTitle = @"Use PIN/Password";
    
    LAPolicy policy = LAPolicyDeviceOwnerAuthenticationWithBiometrics;
    NSError *authError = nil;
    if (![context canEvaluatePolicy:policy error:&authError]) {
        policy = LAPolicyDeviceOwnerAuthentication; // fallback to mac user auth
    }
    
    [context evaluatePolicy:policy
            localizedReason:reason
                      reply:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                self.failedAttemptsCount = 0;
                [self logEvent:@"Biometrics Success" details:@"Unlocked via Touch ID / Mac Auth" type:@"auth_success"];
            } else if (error) {
                [self logEvent:@"Biometrics Cancelled/Failed" details:error.localizedDescription type:@"auth_failure"];
            }
            if (completion) {
                completion(success, error);
            }
        });
    }];
}

#pragma mark - Settings Accessors

- (BOOL)boolSetting:(NSString *)key defaultValue:(BOOL)defaultValue {
    id val = [self.defaults objectForKey:key];
    if (val == nil) return defaultValue;
    return [val boolValue];
}

- (void)setBoolSetting:(NSString *)key value:(BOOL)value {
    [self.defaults setBool:value forKey:key];
    [self.defaults synchronize];
}

- (NSInteger)integerSetting:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id val = [self.defaults objectForKey:key];
    if (val == nil) return defaultValue;
    return [val integerValue];
}

- (void)setIntegerSetting:(NSString *)key value:(NSInteger)value {
    [self.defaults setInteger:value forKey:key];
    [self.defaults synchronize];
}

- (NSArray<NSString *> *)protectedDevices {
    NSArray *list = [self.defaults arrayForKey:kSecuritySettingProtectedDevices];
    return list ? list : @[];
}

- (void)setProtectedDevices:(NSArray<NSString *> *)devices {
    [self.defaults setObject:devices forKey:kSecuritySettingProtectedDevices];
    [self.defaults synchronize];
}

- (BOOL)isDeviceProtected:(NSString *)deviceName {
    if ([self boolSetting:kSecuritySettingProtectAllBluetooth defaultValue:YES]) {
        return YES;
    }
    if (!deviceName) return NO;
    NSArray *devices = [self protectedDevices];
    for (NSString *d in devices) {
        if ([deviceName localizedCaseInsensitiveContainsString:d] || [d localizedCaseInsensitiveContainsString:deviceName]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Audit Logs

- (void)logEvent:(NSString *)event details:(NSString *)details type:(NSString *)type {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    
    NSDictionary *entry = @{
        @"timestamp": timestamp,
        @"event": event ?: @"Event",
        @"details": details ?: @"",
        @"type": type ?: @"info"
    };
    
    NSMutableArray *logs = [[self.defaults arrayForKey:kAuditLogsKey] mutableCopy];
    if (!logs) logs = [NSMutableArray array];
    
    [logs insertObject:entry atIndex:0]; // newest first
    if (logs.count > 100) {
        [logs removeObjectsInRange:NSMakeRange(100, logs.count - 100)];
    }
    
    [self.defaults setObject:logs forKey:kAuditLogsKey];
    [self.defaults synchronize];
}

- (NSArray<NSDictionary *> *)recentLogs {
    NSArray *logs = [self.defaults arrayForKey:kAuditLogsKey];
    return logs ? logs : @[];
}

- (void)clearLogs {
    [self.defaults removeObjectForKey:kAuditLogsKey];
    [self.defaults synchronize];
}

@end
