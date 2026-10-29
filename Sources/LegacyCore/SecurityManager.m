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

static NSString * const kLegacyMasterPasswordHashKey = @"MasterPasswordHash";
static NSString * const kLegacyMasterPasswordSaltKey = @"MasterPasswordSalt";
static NSString * const kLegacyAuditLogsKey          = @"SecurityAuditLogs";

static NSString * const kKeychainService             = @"com.security.HeadsetGuard";
static NSString * const kKeychainAccountCredentials = @"MasterPasswordCredentials";

static const uint32_t kPBKDF2Iterations            = 310000;

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

#pragma mark - Keychain Storage

- (BOOL)saveCredentialsToKeychainWithHash:(NSString *)hash salt:(NSData *)salt {
    if (!hash || !salt) return NO;
    
    NSDictionary *payload = @{
        @"hash": hash,
        @"salt": [salt base64EncodedStringWithOptions:0]
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (!data || jsonError) return NO;

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccountCredentials
    };

    // Remove any previous entry
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSMutableDictionary *attributes = [query mutableCopy];
    attributes[(__bridge id)kSecValueData] = data;
    attributes[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
    return (status == errSecSuccess);
}

- (nullable NSDictionary *)loadCredentialsFromKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccountCredentials,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        return nil;
    }

    NSData *data = (__bridge_transfer NSData *)result;
    NSError *error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return dict;
}

- (nullable NSDictionary *)storedCredentials {
    NSDictionary *creds = [self loadCredentialsFromKeychain];
    if (creds) return creds;

    // Check legacy NSUserDefaults and migrate securely to Keychain if present
    NSString *legacyHash = [self.defaults stringForKey:kLegacyMasterPasswordHashKey];
    NSData *legacySalt = [self.defaults dataForKey:kLegacyMasterPasswordSaltKey];
    if (legacyHash.length > 0 && legacySalt.length > 0) {
        if ([self saveCredentialsToKeychainWithHash:legacyHash salt:legacySalt]) {
            [self.defaults removeObjectForKey:kLegacyMasterPasswordHashKey];
            [self.defaults removeObjectForKey:kLegacyMasterPasswordSaltKey];
            return [self loadCredentialsFromKeychain];
        }
    }
    return nil;
}

#pragma mark - Password Hashing

- (NSData *)generateSalt {
    uint8_t salt[32];
    int result = SecRandomCopyBytes(kSecRandomDefault, sizeof(salt), salt);
    if (result == errSecSuccess) {
        return [NSData dataWithBytes:salt length:sizeof(salt)];
    }
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
        kPBKDF2Iterations,
        derivedKey,
        sizeof(derivedKey)
    );
    
    NSData *derivedData = [NSData dataWithBytes:derivedKey length:sizeof(derivedKey)];
    return [derivedData base64EncodedStringWithOptions:0];
}

- (BOOL)isPasswordConfigured {
    NSDictionary *creds = [self storedCredentials];
    NSString *hash = (NSString *)creds[@"hash"];
    NSString *saltB64 = (NSString *)creds[@"salt"];
    return (hash.length > 0 && saltB64.length > 0);
}

- (BOOL)setupMasterPassword:(NSString *)password error:(NSError * __autoreleasing *)error {
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
    
    BOOL saved = [self saveCredentialsToKeychainWithHash:hash salt:salt];
    if (!saved) {
        if (error) {
            *error = [NSError errorWithDomain:@"HeadsetGuard"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to save credentials to macOS Keychain."}];
        }
        return NO;
    }
    
    // Clear any obsolete plaintext defaults
    [self.defaults removeObjectForKey:kLegacyMasterPasswordHashKey];
    [self.defaults removeObjectForKey:kLegacyMasterPasswordSaltKey];
    
    self.failedAttemptsCount = 0;
    [self logEvent:@"Password Set" details:@"New master password configured in Keychain" type:@"security"];
    return YES;
}

- (BOOL)changePasswordFrom:(NSString *)oldPassword to:(NSString *)newPassword error:(NSError * __autoreleasing *)error {
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
    NSDictionary *creds = [self storedCredentials];
    if (!creds) {
        return NO;
    }
    
    NSString *storedHash = (NSString *)creds[@"hash"];
    NSString *saltB64 = (NSString *)creds[@"salt"];
    if (!storedHash || !saltB64) return NO;
    
    NSData *salt = [[NSData alloc] initWithBase64EncodedString:saltB64 options:0];
    if (!salt) return NO;
    
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
}

- (NSInteger)integerSetting:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id val = [self.defaults objectForKey:key];
    if (val == nil) return defaultValue;
    return [val integerValue];
}

- (void)setIntegerSetting:(NSString *)key value:(NSInteger)value {
    [self.defaults setInteger:value forKey:key];
}

- (NSArray<NSString *> *)protectedDevices {
    NSArray *list = [self.defaults arrayForKey:kSecuritySettingProtectedDevices];
    return list ? list : @[];
}

- (void)setProtectedDevices:(NSArray<NSString *> *)devices {
    [self.defaults setObject:devices forKey:kSecuritySettingProtectedDevices];
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

#pragma mark - Audit Logs (Application Support JSON File)

- (NSString *)auditLogFilePath {
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [appSupport stringByAppendingPathComponent:@"HeadsetGuard"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"audit_logs.json"];
}

- (void)logEvent:(NSString *)event details:(NSString *)details type:(NSString *)type {
    @synchronized(self) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *timestamp = [df stringFromDate:[NSDate date]];
        
        NSDictionary *entry = @{
            @"timestamp": timestamp,
            @"event": event ?: @"Event",
            @"details": details ?: @"",
            @"type": type ?: @"info"
        };
        
        NSMutableArray *logs = [[self recentLogs] mutableCopy];
        if (!logs) logs = [NSMutableArray array];
        
        [logs insertObject:entry atIndex:0]; // newest first
        if (logs.count > 100) {
            [logs removeObjectsInRange:NSMakeRange(100, logs.count - 100)];
        }
        
        NSString *path = [self auditLogFilePath];
        NSData *data = [NSJSONSerialization dataWithJSONObject:logs options:NSJSONWritingPrettyPrinted error:nil];
        if (data) {
            [data writeToFile:path atomically:YES];
        }
    }
}

- (NSArray<NSDictionary *> *)recentLogs {
    @synchronized(self) {
        NSString *path = [self auditLogFilePath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            // Migrate legacy logs from defaults if present
            NSArray *legacy = [self.defaults arrayForKey:kLegacyAuditLogsKey];
            if ([legacy isKindOfClass:[NSArray class]] && legacy.count > 0) {
                NSData *data = [NSJSONSerialization dataWithJSONObject:legacy options:NSJSONWritingPrettyPrinted error:nil];
                if (data) {
                    [data writeToFile:path atomically:YES];
                }
                [self.defaults removeObjectForKey:kLegacyAuditLogsKey];
                return legacy;
            }
            return @[];
        }
        
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) return @[];
        
        NSError *error = nil;
        NSArray *logs = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        return ([logs isKindOfClass:[NSArray class]] && !error) ? logs : @[];
    }
}

- (void)clearLogs {
    @synchronized(self) {
        NSString *path = [self auditLogFilePath];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [self.defaults removeObjectForKey:kLegacyAuditLogsKey];
    }
}

@end
