//  Look4Sat iOS port — settings model
//  Ported from Kotlin: core/domain/.../model/Settings.kt
//  License: GPL-3.0
//
//  These mirror the app's SharedPreferences-backed settings. On iOS they
//  will be persisted to UserDefaults (with Codable JSON encoding for the
//  collection-valued types like DataSourcesSettings).
import Foundation

/// Database / satellite-data state snapshot.
public struct DatabaseState: Codable, Hashable {
    public let numberOfRadios: Int
    public let numberOfSatellites: Int
    public let updateTimestamp: Int64
}

/// Satellite-pass display settings.
public struct PassesSettings: Codable, Hashable {
    public var showDeepSpace: Bool = true
    public var hoursAhead: Int
    public var minElevation: Double
    public var aosStartMinute: Int = 0
    public var aosEndMinute: Int = 23 * 60 + 59
    public var invertAosTimeWindow: Bool = false
}

/// Rotator / frequency-control (remote control) settings.
public struct RCSettings: Codable, Hashable {
    public var rotatorState: Bool
    public var rotatorAddress: String
    public var rotatorPort: String
    public var rotatorFormat: String
    public var frequencyState: Bool
    public var frequencyAddress: String
    public var frequencyPort: String
    public var frequencyFormat: String
    public var frequencyOffsetHz: Int64 = 0
    public var bluetoothRotatorState: Bool
    public var bluetoothRotatorFormat: String
    public var bluetoothRotatorName: String
    public var bluetoothRotatorAddress: String
    public var bluetoothFrequencyState: Bool
    public var bluetoothFrequencyFormat: String
    public var bluetoothFrequencyAddress: String
}

/// General (non-pass, non-RC) settings.
public struct OtherSettings: Codable, Hashable {
    public var stateOfAutoUpdate: Bool
    public var stateOfSensors: Bool
    public var stateOfSweep: Bool
    public var stateOfUtc: Bool
    public var stateOfLightTheme: Bool
    public var stateOfNightMode: Bool = false
    public var shouldSeeWarning: Bool
    public var shouldSeeWhatsNew: Bool
    public var sstvMode: String = "Auto"
    public var lowElevation: Double = 15.0
    public var highElevation: Double = 45.0
    public var radarCompassOffset: Float = 0
    public var radarCompassOffsetElev: Float = 0
}

/// TLE / transceiver data-source URLs and their per-source enabled flags.
/// `satelliteEnabled` / `transceiversEnabled` are positionally aligned with the
/// corresponding URL list: the flag at index [i] applies to the URL at index [i].
/// Missing flags are treated as enabled.
public struct DataSourcesSettings: Codable, Hashable {
    public var satelliteUrls: [String]
    public var transceiversUrls: [String]
    public var satelliteEnabled: [Bool] = []
    public var transceiversEnabled: [Bool] = []

    public func isSatelliteEnabled(_ index: Int) -> Bool {
        (index < satelliteEnabled.count) ? satelliteEnabled[index] : true
    }

    public func isTransceiverEnabled(_ index: Int) -> Bool {
        (index < transceiversEnabled.count) ? transceiversEnabled[index] : true
    }
}

/// Radio-control (CAT) settings.
public struct RadioControlSettings: Codable, Hashable {
    public var enabled: Bool
    public var radioModel: String
    public var txRadioAddress: String
    public var rxRadioAddress: String
    public var txRadioName: String
    public var rxRadioName: String
    public var baudRate: Int
    /// IC-705 only: use single-radio split-VFO mode instead of two radios.
    public var splitMode: Bool = false

    public enum Model {
        static let YAESU_FT817 = "Yaesu FT-817/818"
        static let YAESU_FT857 = "Yaesu FT-857/897"
        static let ICOM_IC705 = "Icom IC-705"
        static let SUPPORTED: [String] = [YAESU_FT817, YAESU_FT857, ICOM_IC705]
    }

    static let BAUD_RATES_YAESU: [Int] = [4800, 9600, 38400]
    static let BAUD_RATES_ICOM: [Int] = [4800, 9600, 19200, 38400, 57600, 115200]
}
