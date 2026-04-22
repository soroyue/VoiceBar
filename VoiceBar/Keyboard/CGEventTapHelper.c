#include "CGEventTapHelper.h"
#import <CoreGraphics/CoreGraphics.h>

CFMachPortRef VBCreateEventTap(
    CGEventTapLocation tap,
    CGEventTapPlacement place,
    CGEventTapOptions options,
    CGEventMask eventsOfInterest,
    CGEventTapCallBack callback,
    void *userInfo,
    bool *success
) {
    CFMachPortRef result = CGEventTapCreate(
        tap,
        place,
        options,
        eventsOfInterest,
        callback,
        userInfo
    );
    if (success != NULL) {
        *success = (result != NULL);
    }
    return result;
}
