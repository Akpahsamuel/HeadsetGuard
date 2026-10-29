#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kSecuritySettingAutoLockOnConnect;
extern NSString * const kSecuritySettingLockOnSleep;
extern NSString * const kSecuritySettingStrictMute;
extern NSString * const kSecuritySettingBiometricsEnabled;
extern NSString * const kSecuritySettingMaxFailedAttempts;
extern NSString * const kSecuritySettingAutoDisconnectOnFailure;
extern NSString * const kSecuritySettingProtectAllBluetooth;
extern NSString * const kSecuritySettingProtectedDevices;

@interface SecurityManager : NSObject

@property (nonatomic, readonly) BOOL isPasswordConfigured;
@property (nonatomic, readonly) BOOL biometricsAvailable;
@property (nonatomic, assign) NSInteger failedAttemptsCount;

+ (instancetype)sharedManager;

// Password management
- (BOOL)setupMasterPassword:(NSString *)password error:(NSError * _Nullable * _Nullable)error;
- (BOOL)changePasswordFrom:(NSString *)oldPassword to:(NSString *)newPassword error:(NSError * _Nullable * _Nullable)error;
- (BOOL)verifyPassword:(NSString *)password;

// Biometric authentication (Touch ID / Face ID / Watch)
- (void)authenticateWithBiometricsWithReason:(NSString *)reason completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

// Security settings
- (BOOL)boolSetting:(NSString *)key defaultValue:(BOOL)defaultValue;
- (void)setBoolSetting:(NSString *)key value:(BOOL)value;

- (NSInteger)integerSetting:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (void)setIntegerSetting:(NSString *)key value:(NSInteger)value;

- (NSArray<NSString *> *)protectedDevices;
- (void)setProtectedDevices:(NSArray<NSString *> *)devices;
- (BOOL)isDeviceProtected:(NSString *)deviceName;

// Audit and Event Logging
- (void)logEvent:(NSString *)event details:(NSString *)details type:(NSString *)type;
- (NSArray<NSDictionary *> *)recentLogs;
- (void)clearLogs;

@end

NS_ASSUME_NONNULL_END
