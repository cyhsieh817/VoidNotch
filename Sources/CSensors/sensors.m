//
//  sensors.m — Apple Silicon IOHID 溫度列舉實作
//
//  移植自 Stats Modules/Sensors/reader.m（MIT）。
//  原理：用 IOHIDEventSystemClient 以 {PrimaryUsagePage:0xff00, PrimaryUsage:0x0005} 過濾溫度感測器服務，
//  對每個 service 取 "Product" 名 + IOHIDServiceClientCopyEvent → IOHIDEventGetFloatValue。
//

#import "include/CSensors.h"

NSDictionary<NSString *, NSNumber *> *VNReadAppleSiliconTemperatures(void) {
    return VNReadAppleSiliconTemperaturesWithFailure(NULL);
}

NSDictionary<NSString *, NSNumber *> *VNReadAppleSiliconTemperaturesWithFailure(NSInteger * _Nullable failureCode) {
    NSMutableDictionary<NSString *, NSNumber *> *results = [NSMutableDictionary dictionary];
    NSInteger failure = 0;

    // 溫度感測器的 HID 匹配條件（m1Preset）
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(0xff00),
        @"PrimaryUsage": @(0x0005),
    };

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        if (failureCode != NULL) { *failureCode = 1; }
        return results;
    }

    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        if (failureCode != NULL) { *failureCode = 2; }
        return results;
    }

    CFIndex count = CFArrayGetCount(services);
    NSInteger readableEvents = 0;
    NSInteger invalidReadings = 0;

    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (service == NULL) { continue; }

        CFTypeRef nameRef = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (nameRef == NULL) { continue; }

        NSString *name = nil;
        if (CFGetTypeID(nameRef) == CFStringGetTypeID()) {
            name = (__bridge NSString *)nameRef;
        }

        if (name != nil) {
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kVN_IOHIDEventTypeTemperature, 0, 0);
            if (event != NULL) {
                readableEvents += 1;
                double temp = IOHIDEventGetFloatValue(event, kVN_IOHIDEventFieldTemperature);
                // 過濾明顯無效讀數（0 或負或離譜高）
                if (temp > 0.0 && temp < 130.0) {
                    results[name] = @(temp);
                } else {
                    invalidReadings += 1;
                }
                CFRelease(event);
            }
        }

        CFRelease(nameRef);
    }

    CFRelease(services);
    CFRelease(client);

    if (results.count > 0) {
        failure = 0;
    } else if (count == 0) {
        failure = 3;
    } else if (invalidReadings > 0) {
        failure = 5;
    } else if (readableEvents == 0) {
        failure = 4;
    } else {
        failure = 4;
    }

    if (failureCode != NULL) { *failureCode = failure; }
    return results;
}
