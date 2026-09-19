import Foundation
import IOKit
import IOKit.usb

/// Lightweight checks for Astro A50 USB presence that don't need the HID layer.
public enum USBPresence {
    /// True when the headset is plugged in by USB cable directly (`0x002b`),
    /// which exposes only USB-audio and no control interface.
    public static func cableModeConnected() -> Bool {
        deviceExists(vendor: A50.vendorID, product: A50.cableProductID)
    }

    /// True when the base station (`0x002c`) is present on the USB bus.
    public static func baseStationConnected() -> Bool {
        deviceExists(vendor: A50.vendorID, product: A50.baseStationProductID)
    }

    private static func deviceExists(vendor: Int, product: Int) -> Bool {
        guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else {
            return false
        }
        matching["idVendor"] = vendor
        matching["idProduct"] = product
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        if service != 0 {
            IOObjectRelease(service)
            return true
        }
        return false
    }
}
