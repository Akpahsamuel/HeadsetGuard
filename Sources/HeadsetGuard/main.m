#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "SecurityManager.h"
#import "AudioGuard.h"
#import "BluetoothManager.h"

static void PrintUsage(void) {
    printf("HeadsetGuard - Bluetooth Headset Security & Audio Locker for macOS\n\n");
    printf("Usage:\n");
    printf("  HeadsetGuard                 Run full menu bar application and security daemon\n");
    printf("  HeadsetGuard --status        Show current audio and Bluetooth security status\n");
    printf("  HeadsetGuard --list          List all detected Bluetooth headsets and paired devices\n");
    printf("  HeadsetGuard --lock          Manually lock current active Bluetooth headset\n");
    printf("  HeadsetGuard --unlock        Prompt to unlock active Bluetooth headset\n");
    printf("  HeadsetGuard --disconnect    Disconnect active Bluetooth headset immediately\n");
    printf("  HeadsetGuard --set-password  Set or change master password from terminal\n");
    printf("  HeadsetGuard --logs          Display recent security audit log events\n");
    printf("  HeadsetGuard --help          Show this help message\n\n");
}

static int RunCLI(int argc, const char * argv[]) {
    (void)argc;
    NSString *arg = [NSString stringWithUTF8String:argv[1]];

    if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
    }

    if ([arg isEqualToString:@"--status"]) {
        AudioGuard *ag = [AudioGuard sharedGuard];
        AudioDeviceID defID = [ag defaultOutputDeviceID];
        NSString *defName = [ag deviceNameForID:defID];
        BOOL isBT = [ag isBluetoothDevice:defID];
        SecurityManager *sm = [SecurityManager sharedManager];

        printf("=== HeadsetGuard Status ===\n");
        printf("Master Password Configured: %s\n", sm.isPasswordConfigured ? "YES" : "NO (First-time setup needed)");
        printf("Touch ID / Biometrics Available: %s\n", sm.biometricsAvailable ? "YES" : "NO");
        printf("Default Output: %s (ID: %u)\n", defName ? defName.UTF8String : "Unknown", defID);
        printf("Default Output is Bluetooth: %s\n", isBT ? "YES" : "NO");
        printf("Current Audio Guard State: %s\n", ag.isLocked ? "LOCKED (Muted)" : "UNLOCKED / Normal");
        if (ag.isLocked) {
            printf("Locked Device: %s (ID: %u)\n", ag.lockedDeviceName ? ag.lockedDeviceName.UTF8String : "Unknown", ag.lockedDeviceID);
        }
        return 0;
    }

    if ([arg isEqualToString:@"--list"]) {
        printf("=== Paired Bluetooth Audio Devices ===\n");
        NSArray<IOBluetoothDevice *> *paired = [[BluetoothManager sharedManager] pairedAudioDevices];
        if (paired.count == 0) {
            printf("No paired Bluetooth audio devices found.\n");
        } else {
            for (IOBluetoothDevice *dev in paired) {
                printf("  • %-30s [Addr: %s, Connected: %s]\n",
                       dev.nameOrAddress.UTF8String,
                       dev.addressString.UTF8String,
                       dev.isConnected ? "YES 🎧" : "NO");
            }
        }

        printf("\n=== Active CoreAudio Output Devices ===\n");
        NSArray<NSDictionary *> *outputs = [[AudioGuard sharedGuard] allOutputDevices];
        for (NSDictionary *info in outputs) {
            NSString *devName = (NSString *)info[@"name"];
            NSNumber *devIDNum = (NSNumber *)info[@"id"];
            NSNumber *isBTNum = (NSNumber *)info[@"isBluetooth"];
            printf("  • %-30s [ID: %u, Bluetooth: %s]\n",
                   devName.UTF8String,
                   devIDNum.unsignedIntValue,
                   isBTNum.boolValue ? "YES" : "NO");
        }
        return 0;
    }

    if ([arg isEqualToString:@"--lock"]) {
        AudioGuard *ag = [AudioGuard sharedGuard];
        AudioDeviceID defID = [ag defaultOutputDeviceID];
        if (defID != kAudioObjectUnknown && [ag isBluetoothDevice:defID]) {
            NSString *name = [ag deviceNameForID:defID];
            [ag lockDevice:defID];
            printf("Successfully locked and muted Bluetooth headset '%s' (ID: %u).\n", name.UTF8String, defID);
            return 0;
        } else {
            printf("No active Bluetooth headset detected on default output to lock.\n");
            return 1;
        }
    }

    if ([arg isEqualToString:@"--disconnect"]) {
        AudioGuard *ag = [AudioGuard sharedGuard];
        AudioDeviceID defID = [ag defaultOutputDeviceID];
        NSString *name = [ag deviceNameForID:defID];
        if (name) {
            [[BluetoothManager sharedManager] disconnectDeviceNamed:name];
            [ag routeAudioToBuiltIn];
            printf("Disconnected '%s' and restored audio to built-in speakers.\n", name.UTF8String);
            return 0;
        }
        printf("No active device found to disconnect.\n");
        return 1;
    }

    if ([arg isEqualToString:@"--logs"]) {
        printf("=== Recent Security Audit Logs ===\n");
        NSArray<NSDictionary *> *logs = [[SecurityManager sharedManager] recentLogs];
        if (logs.count == 0) {
            printf("No log entries recorded yet.\n");
        } else {
            for (NSDictionary *log in logs) {
                NSString *timestamp = (NSString *)log[@"timestamp"];
                NSString *event = (NSString *)log[@"event"];
                NSString *details = (NSString *)log[@"details"];
                printf("[%s] %-22s: %s\n",
                       timestamp.UTF8String,
                       event.UTF8String,
                       details.UTF8String);
            }
        }
        return 0;
    }

    if ([arg isEqualToString:@"--set-password"]) {
        printf("Enter new Master PIN or Password (min 4 characters): ");
        char buf[256];
        if (fgets(buf, sizeof(buf), stdin)) {
            NSString *newPass = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSError *err = nil;
            if ([[SecurityManager sharedManager] setupMasterPassword:newPass error:&err]) {
                printf("Master PIN/Password successfully configured!\n");
                return 0;
            } else {
                printf("Error: %s\n", err.localizedDescription.UTF8String);
                return 1;
            }
        }
        return 1;
    }

    printf("Unknown argument: %s\nRun 'HeadsetGuard --help' for usage.\n", arg.UTF8String);
    return 1;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            return RunCLI(argc, argv);
        }

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; // Menu bar accessory app

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
