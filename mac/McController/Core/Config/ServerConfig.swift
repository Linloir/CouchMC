import Foundation

/// Root config object. Mirrors `ServerConfig.cs` on the PC side. Storage
/// shape is intentionally identical so a future user could (in theory)
/// hand-edit a single config across both platforms — but in practice each
/// platform writes its own file under its own Application Support /
/// APPDATA root.
final class ServerConfig: Codable {
    var port: Int = Protocol.defaultPort
    var activeProfileId: String = "default"
    var profiles: [ControllerProfile] = [ControllerProfile()]
    var bindings: [String: ButtonBinding] = ServerConfig.defaultBindings()
    /// Joystick → keyboard mapping for the 4 movement directions.
    /// Read every poll by `JoystickToWasdMapper`, so edits from the Key
    /// Bindings page take effect without a profile reload. Stored under
    /// the same `Movement_Keys` JSON name as the Windows config so the
    /// two files round-trip cleanly.
    var movementKeys: MovementBindings = MovementBindings()

    var activeProfile: ControllerProfile {
        get {
            if profiles.isEmpty { profiles.append(ControllerProfile()) }
            return profiles.first(where: { $0.id == activeProfileId }) ?? profiles[0]
        }
    }

    var camera: CameraConfig {
        get { activeProfile.camera }
        set { activeProfile.camera = newValue }
    }

    var movement: MovementConfig {
        get { activeProfile.movement }
        set { activeProfile.movement = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case port, activeProfileId, profiles, bindings
        case movementKeys = "Movement_Keys"
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? Protocol.defaultPort
        activeProfileId = try c.decodeIfPresent(String.self, forKey: .activeProfileId) ?? "default"
        profiles = try c.decodeIfPresent([ControllerProfile].self, forKey: .profiles)
            ?? [ControllerProfile()]
        bindings = try c.decodeIfPresent([String: ButtonBinding].self, forKey: .bindings)
            ?? ServerConfig.defaultBindings()
        movementKeys = try c.decodeIfPresent(MovementBindings.self, forKey: .movementKeys)
            ?? MovementBindings()
    }

    static func defaultMovementKeys() -> MovementBindings {
        MovementBindings()
    }

    static func defaultBindings() -> [String: ButtonBinding] {
        return [
            "0x01": ButtonBinding(type: "mouse", scancode: nil, button: "left"),
            "0x02": ButtonBinding(type: "mouse", scancode: nil, button: "right"),
            "0x10": ButtonBinding(type: "key", scancode: "jump",      button: nil),
            "0x11": ButtonBinding(type: "key", scancode: "sneak",     button: nil),
            "0x12": ButtonBinding(type: "key", scancode: "sprint",    button: nil),
            "0x20": ButtonBinding(type: "key", scancode: "inventory", button: nil),
            "0x21": ButtonBinding(type: "key", scancode: "drop",      button: nil),
            "0x22": ButtonBinding(type: "key", scancode: "swapHand",  button: nil),
            "0x30": ButtonBinding(type: "key", scancode: "esc",       button: nil),
            "0x40": ButtonBinding(type: "key", scancode: "hotbar1",   button: nil),
            "0x41": ButtonBinding(type: "key", scancode: "hotbar2",   button: nil),
            "0x42": ButtonBinding(type: "key", scancode: "hotbar3",   button: nil),
            "0x43": ButtonBinding(type: "key", scancode: "hotbar4",   button: nil),
            "0x44": ButtonBinding(type: "key", scancode: "hotbar5",   button: nil),
            "0x45": ButtonBinding(type: "key", scancode: "hotbar6",   button: nil),
            "0x46": ButtonBinding(type: "key", scancode: "hotbar7",   button: nil),
            "0x47": ButtonBinding(type: "key", scancode: "hotbar8",   button: nil),
            "0x48": ButtonBinding(type: "key", scancode: "hotbar9",   button: nil),
        ]
    }
}

/// A single named tuning profile (e.g. "默认" / "建筑" / "瞄准"). The active
/// profile drives the live camera curve + WASD mapper. Swapping it is
/// instant — `ServerHost` resets the residual sub-pixel state to avoid a
/// jolt across profiles.
final class ControllerProfile: Codable, Identifiable {
    var id: String = "default"
    var name: String = "默认"
    var camera: CameraConfig = CameraConfig()
    var movement: MovementConfig = MovementConfig()

    init() {}

    init(id: String, name: String,
         camera: CameraConfig = CameraConfig(),
         movement: MovementConfig = MovementConfig()) {
        self.id = id
        self.name = name
        self.camera = camera
        self.movement = movement
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "default"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "默认"
        camera = try c.decodeIfPresent(CameraConfig.self, forKey: .camera) ?? CameraConfig()
        movement = try c.decodeIfPresent(MovementConfig.self, forKey: .movement) ?? MovementConfig()
    }

    func duplicate(newId: String, nameSuffix: String) -> ControllerProfile {
        ControllerProfile(
            id: newId,
            name: name + nameSuffix,
            camera: CameraConfig(
                userSensitivity: camera.userSensitivity,
                curveType: camera.curveType,
                accelFactor: camera.accelFactor,
                accelExp: camera.accelExp,
                maxAccelMultiplier: camera.maxAccelMultiplier),
            movement: MovementConfig(
                deadZone: movement.deadZone,
                enterThreshold: movement.enterThreshold,
                exitThreshold: movement.exitThreshold))
    }

    enum CodingKeys: String, CodingKey { case id, name, camera, movement }
}

/// Camera-related tuning. User-facing sensitivity is exposed in the
/// Settings page; the curve sub-fields hide behind the "Curve (advanced)"
/// disclosure.
final class CameraConfig: Codable {
    var userSensitivity: Float = 1.5
    var curveType: CurveType = .linear
    var accelFactor: Float = 0.0
    var accelExp: Float = 1.0
    var maxAccelMultiplier: Float = 3.0

    init() {}

    init(userSensitivity: Float = 1.5,
         curveType: CurveType = .linear,
         accelFactor: Float = 0.0,
         accelExp: Float = 1.0,
         maxAccelMultiplier: Float = 3.0) {
        self.userSensitivity = userSensitivity
        self.curveType = curveType
        self.accelFactor = accelFactor
        self.accelExp = accelExp
        self.maxAccelMultiplier = maxAccelMultiplier
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userSensitivity = try c.decodeIfPresent(Float.self, forKey: .userSensitivity) ?? 1.5
        curveType = try c.decodeIfPresent(CurveType.self, forKey: .curveType) ?? .linear
        accelFactor = try c.decodeIfPresent(Float.self, forKey: .accelFactor) ?? 0.0
        accelExp = try c.decodeIfPresent(Float.self, forKey: .accelExp) ?? 1.0
        maxAccelMultiplier = try c.decodeIfPresent(Float.self, forKey: .maxAccelMultiplier) ?? 3.0
    }

    enum CodingKeys: String, CodingKey {
        case userSensitivity, curveType, accelFactor, accelExp, maxAccelMultiplier
    }
}

final class MovementConfig: Codable {
    var deadZone: Float = 0.0
    var enterThreshold: Float = 0.30
    var exitThreshold: Float = 0.20

    init() {}

    init(deadZone: Float = 0.0,
         enterThreshold: Float = 0.30,
         exitThreshold: Float = 0.20) {
        self.deadZone = deadZone
        self.enterThreshold = enterThreshold
        self.exitThreshold = exitThreshold
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deadZone = try c.decodeIfPresent(Float.self, forKey: .deadZone) ?? 0.0
        enterThreshold = try c.decodeIfPresent(Float.self, forKey: .enterThreshold) ?? 0.30
        exitThreshold = try c.decodeIfPresent(Float.self, forKey: .exitThreshold) ?? 0.20
    }

    enum CodingKeys: String, CodingKey { case deadZone, enterThreshold, exitThreshold }
}

/// `Type` + (`scancode` | `button`). `scancode` accepts either a hex
/// string (Windows-compat, e.g. `"0x39"`) for backward compatibility
/// with the Windows config files, or a symbolic name like `"jump"` /
/// `"sneak"` that the input layer maps to the macOS virtual key code.
/// Symbolic is preferred on Mac because Windows scancodes and macOS
/// virtual key codes don't match.
struct ButtonBinding: Codable, Equatable {
    var type: String = "key"
    var scancode: String?
    var button: String?
}

enum CurveType: String, Codable, CaseIterable {
    case linear, power
}

/// Joystick-direction → key mapping for the four movement axes. Defaults
/// to the classic W / S / A / D MC layout (stored as symbolic names so
/// the mac config is human-readable; the Windows config file uses hex
/// scancodes for the same field and `KeyCodes.resolve` accepts either).
/// Mirrors `MovementBindings` on the Windows side, JSON-key-compatible.
struct MovementBindings: Codable, Equatable {
    /// Forward — joystick y > 0. Default W.
    var forward: String = "w"
    /// Back — joystick y < 0. Default S.
    var back: String = "s"
    /// Strafe-left — joystick x < 0. Default A.
    var left: String = "a"
    /// Strafe-right — joystick x > 0. Default D.
    var right: String = "d"

    init() {}

    init(forward: String = "w", back: String = "s",
         left: String = "a", right: String = "d") {
        self.forward = forward
        self.back = back
        self.left = left
        self.right = right
    }

    enum CodingKeys: String, CodingKey {
        // Capitalised to match the Windows JSON field names so a
        // hand-migrated config from the Windows side decodes cleanly.
        case forward = "Forward"
        case back    = "Back"
        case left    = "Left"
        case right   = "Right"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forward = try c.decodeIfPresent(String.self, forKey: .forward) ?? "w"
        back    = try c.decodeIfPresent(String.self, forKey: .back)    ?? "s"
        left    = try c.decodeIfPresent(String.self, forKey: .left)    ?? "a"
        right   = try c.decodeIfPresent(String.self, forKey: .right)   ?? "d"
    }
}
