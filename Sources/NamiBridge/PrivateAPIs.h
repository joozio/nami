// Private Accessibility API bridge for Nami
// This exposes the undocumented _AXUIElementGetWindow function

#ifndef PrivateAPIs_h
#define PrivateAPIs_h

#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

// Get the CGWindowID for an AXUIElement
// Returns kAXErrorSuccess on success, stores window ID in *windowID
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

#endif /* PrivateAPIs_h */
