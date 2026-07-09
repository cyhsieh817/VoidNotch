//
//  CSensors.h — Apple Silicon IOHID 溫度感測器橋接
//
//  移植自 Stats（MIT, © 2019 Serhiy Mytrovtsiy）Modules/Sensors/{reader.m,bridge.h}。
//  IOHIDEventSystemClient 系列為私有 IOKit 符號（公開 header 未宣告），於此手動 extern。
//  → 此即 VoidNotch 不可上 Mac App Store 的根因之一（私有 API）。見 distribution-and-entitlements.md。
//

#ifndef CSensors_h
#define CSensors_h

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - 私有 IOHID 型別與函式（手動宣告）

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

#define kVN_IOHIDEventTypeTemperature 15
// IOHIDEventFieldBase(type) == type << 16
#define kVN_IOHIDEventFieldTemperature (kVN_IOHIDEventTypeTemperature << 16)

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef _Nullable IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef _Nullable IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// MARK: - VoidNotch 對外介面

/// 列舉 Apple Silicon 溫度感測器，回傳 { 感測器名稱(NSString) : 攝氏溫度(NSNumber) }。
/// 名稱前綴：pACC=效能核, eACC=效率核, GPU, SOC。非 Apple Silicon 或無權限時回傳空字典。
NSDictionary<NSString *, NSNumber *> *VNReadAppleSiliconTemperatures(void);

/// 同 VNReadAppleSiliconTemperatures，但額外回傳 failureCode：
/// 0=none, 1=client unavailable, 2=services unavailable, 3=no services,
/// 4=no readable sensors, 5=value out of range.
NSDictionary<NSString *, NSNumber *> *VNReadAppleSiliconTemperaturesWithFailure(NSInteger * _Nullable failureCode);

NS_ASSUME_NONNULL_END

#endif /* CSensors_h */
