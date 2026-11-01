//  Look4Sat iOS port — satellite item & transceiver (radio) models
//  Ported from Kotlin: core/domain/.../model/SatItem.kt, SatRadio.kt
//  License: GPL-3.0
import Foundation

/// A lightweight satellite row (name + NORAD cat num + selection flag)
/// used by the satellite list UI.
public struct SatItem: Hashable, Codable, Identifiable {
    public var id: Int { catnum }
    public let catnum: Int
    public let name: String
    public let isSelected: Bool

    public init(catnum: Int, name: String, isSelected: Bool = false) {
        self.catnum = catnum
        self.name = name
        self.isSelected = isSelected
    }
}

/// Transceiver (radio) parameters for a satellite.
/// Mirrors the SatNOGS downlink/uplink schema. Only `uuid` is mandatory:
/// third-party sources rarely publish the full schema, and a missing
/// optional field must not cost the whole transceiver.
public struct SatRadio: Codable, Hashable {
    public enum CodingKeys: String, CodingKey {
        case uuid, info, isAlive = "alive"
        case downlinkLow = "downlink_low"
        case downlinkHigh = "downlink_high"
        case downlinkMode = "downlink_mode"
        case uplinkLow = "uplink_low"
        case uplinkHigh = "uplink_high"
        case uplinkMode = "uplink_mode"
        case isInverted = "invert"
        case catnum = "norad_cat_id"
    }

    public let uuid: String
    public var info: String = ""
    public var isAlive: Bool = true
    public var downlinkLow: Int64?
    public var downlinkHigh: Int64?
    public var downlinkMode: String?
    public var uplinkLow: Int64?
    public var uplinkHigh: Int64?
    public var uplinkMode: String?
    public var isInverted: Bool = false
    public var catnum: Int?

    public init(uuid: String,
         info: String = "",
         isAlive: Bool = true,
         downlinkLow: Int64? = nil,
         downlinkHigh: Int64? = nil,
         downlinkMode: String? = nil,
         uplinkLow: Int64? = nil,
         uplinkHigh: Int64? = nil,
         uplinkMode: String? = nil,
         isInverted: Bool = false,
         catnum: Int? = nil) {
        self.uuid = uuid
        self.info = info
        self.isAlive = isAlive
        self.downlinkLow = downlinkLow
        self.downlinkHigh = downlinkHigh
        self.downlinkMode = downlinkMode
        self.uplinkLow = uplinkLow
        self.uplinkHigh = uplinkHigh
        self.uplinkMode = uplinkMode
        self.isInverted = isInverted
        self.catnum = catnum
    }
}
