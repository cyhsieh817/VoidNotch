//
//  sensors.m — Apple Silicon IOHID 溫度列舉實作
//
//  移植自 Stats Modules/Sensors/reader.m（MIT）。
//  原理：用 IOHIDEventSystemClient 以 {PrimaryUsagePage:0xff00, PrimaryUsage:0x0005} 過濾溫度感測器服務，
//  對每個 service 取 "Product" 名 + IOHIDServiceClientCopyEvent → IOHIDEventGetFloatValue。
//

#import "include/CSensors.h"

// HID 服務與 Product 名稱在 process 生命週期內通常固定；只有溫度 event 是即時值，
// 因此每次讀取只需重跑 CopyEvent，避免反覆建立 client、列舉服務與查詢名稱。
static dispatch_once_t VNTemperatureCacheLockOnce;
static dispatch_queue_t VNTemperatureCacheLock;
static IOHIDEventSystemClientRef VNTemperatureClient;
static CFArrayRef VNTemperatureServices;
static CFArrayRef VNTemperatureNames;

static void VNInitializeTemperatureCacheLock(void) {
    dispatch_once(&VNTemperatureCacheLockOnce, ^{
        VNTemperatureCacheLock = dispatch_queue_create("com.voidnotch.csensors.temperature-cache", DISPATCH_QUEUE_SERIAL);
    });
}

static void VNInvalidateTemperatureCache(void) {
    if (VNTemperatureNames != NULL) {
        CFRelease(VNTemperatureNames);
        VNTemperatureNames = NULL;
    }
    if (VNTemperatureServices != NULL) {
        CFRelease(VNTemperatureServices);
        VNTemperatureServices = NULL;
    }
    if (VNTemperatureClient != NULL) {
        CFRelease(VNTemperatureClient);
        VNTemperatureClient = NULL;
    }
}

NSDictionary<NSString *, NSNumber *> *VNReadAppleSiliconTemperatures(void) {
    return VNReadAppleSiliconTemperaturesWithFailure(NULL);
}

NSDictionary<NSString *, NSNumber *> *VNReadAppleSiliconTemperaturesWithFailure(NSInteger * _Nullable failureCode) {
    NSMutableDictionary<NSString *, NSNumber *> *results = [NSMutableDictionary dictionary];
    __block NSInteger failure = 0;

    VNInitializeTemperatureCacheLock();
    dispatch_sync(VNTemperatureCacheLock, ^{
        if (VNTemperatureClient == NULL) {
            // 溫度感測器的 HID 匹配條件（m1Preset）
            NSDictionary *matching = @{
                @"PrimaryUsagePage": @(0xff00),
                @"PrimaryUsage": @(0x0005),
            };

            VNTemperatureClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
            if (VNTemperatureClient == NULL) {
                failure = 1;
                return;
            }

            IOHIDEventSystemClientSetMatching(VNTemperatureClient, (__bridge CFDictionaryRef)matching);

            CFArrayRef discoveredServices = IOHIDEventSystemClientCopyServices(VNTemperatureClient);
            if (discoveredServices == NULL) {
                VNInvalidateTemperatureCache();
                failure = 2;
                return;
            }

            CFMutableArrayRef cachedServices = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            CFMutableArrayRef cachedNames = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            CFIndex discoveredCount = CFArrayGetCount(discoveredServices);
            for (CFIndex i = 0; i < discoveredCount; i++) {
                IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(discoveredServices, i);
                if (service == NULL) { continue; }

                CFTypeRef nameRef = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
                if (nameRef != NULL && CFGetTypeID(nameRef) == CFStringGetTypeID()) {
                    // 兩個 CFArray 都以 kCFTypeArrayCallBacks 持有元素，索引必須成對一致。
                    CFArrayAppendValue(cachedServices, service);
                    CFArrayAppendValue(cachedNames, nameRef);
                }
                if (nameRef != NULL) {
                    CFRelease(nameRef);
                }
            }
            CFRelease(discoveredServices);

            VNTemperatureServices = cachedServices;
            VNTemperatureNames = cachedNames;
        }

        CFIndex count = CFArrayGetCount(VNTemperatureServices);
        NSInteger readableEvents = 0;
        NSInteger invalidReadings = 0;

        for (CFIndex i = 0; i < count; i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(VNTemperatureServices, i);
            NSString *name = (__bridge NSString *)CFArrayGetValueAtIndex(VNTemperatureNames, i);
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

        // 所有快取 service 都沒有 event 時，下一輪重新建立 HID client 與服務清單。
        if (readableEvents == 0) {
            VNInvalidateTemperatureCache();
        }
    });

    if (failureCode != NULL) { *failureCode = failure; }
    return results;
}
