//
//  SimulatorChecker.h
//  IdentityFraud
//
//  Created by Ashish Gupta on 10/09/24.
//

#include <sys/socket.h>
#include <ifaddrs.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#import <sys/stat.h>
#include <mach-o/dyld.h>

@interface SimulatorChecker : NSObject

- (BOOL)isSimulator;

@end

@interface JailBrokenChecker : NSObject

- (BOOL)isJailBroken;

@end

@interface DeviceSignalsApiImplObjC : NSObject

- (NSString *)getMacAddress;
- (NSString *)getIPhoneBluetoothMacAddress;
- (NSString *)getIPadBluetoothMacAddress;

@end

//#endif /* SimulatorChecker_h */
