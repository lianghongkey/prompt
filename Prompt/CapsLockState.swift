import Foundation
import IOKit
import IOKit.hidsystem

/// Force-clears the OS-level Caps Lock state via IOHIDSystem.
///
/// Used when "使用 Caps Lock 键切换到中文" is enabled: the system still toggles
/// Caps Lock when the key is pressed (so IMK delivers a flagsChanged event we
/// can react to), but we immediately undo that toggle so the LED never stays on
/// and subsequent letters aren't uppercased.
enum CapsLockState {

        /// Sets the system Caps Lock state to off. Safe to call from the main thread;
        /// the IOServiceOpen / IOHIDSetModifierLockState calls are quick.
        static func forceOff() {
                let service: io_service_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
                guard service != 0 else { return }
                defer { IOObjectRelease(service) }
                var connect: io_connect_t = 0
                let openResult = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
                guard openResult == KERN_SUCCESS, connect != 0 else { return }
                defer { IOServiceClose(connect) }
                IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), false)
        }
}
