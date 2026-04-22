#ifndef CGEventTapHelper_h
#define CGEventTapHelper_h

#include <CoreGraphics/CoreGraphics.h>

/**
 * Creates a CGEvent tap at the specified location.
 * This C wrapper avoids Swift bridging issues with CGEventTapCreate/CGEvent.tapCreate.
 */
CFMachPortRef VBCreateEventTap(
    CGEventTapLocation tap,
    CGEventTapPlacement place,
    CGEventTapOptions options,
    CGEventMask eventsOfInterest,
    CGEventTapCallBack callback,
    void *userInfo,
    bool *success
);

#endif /* CGEventTapHelper_h */
