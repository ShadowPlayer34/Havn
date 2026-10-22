import CoreLocation
import Foundation

/// The ten districts of Kyiv, the launch city — the places someone can say they live in.
///
/// A choice rather than a fix: the district widget and its notifications work with location
/// access off, and say nothing about where the phone is.
nonisolated enum KyivDistrict: String, CaseIterable, Codable, Sendable, Identifiable {
    case holosiivskyi
    case darnytskyi
    case desnianskyi
    case dniprovskyi
    case obolonskyi
    case pecherskyi
    case podilskyi
    case sviatoshynskyi
    case solomianskyi
    case shevchenkivskyi

    var id: String { rawValue }

    /// "Shevchenkivskyi district" — how a notification or the widget names it.
    var name: String {
        switch self {
        case .holosiivskyi: String(localized: "Holosiivskyi district")
        case .darnytskyi: String(localized: "Darnytskyi district")
        case .desnianskyi: String(localized: "Desnianskyi district")
        case .dniprovskyi: String(localized: "Dniprovskyi district")
        case .obolonskyi: String(localized: "Obolonskyi district")
        case .pecherskyi: String(localized: "Pecherskyi district")
        case .podilskyi: String(localized: "Podilskyi district")
        case .sviatoshynskyi: String(localized: "Sviatoshynskyi district")
        case .solomianskyi: String(localized: "Solomianskyi district")
        case .shevchenkivskyi: String(localized: "Shevchenkivskyi district")
        }
    }

    /// "Shevchenkivskyi" — for the picker, where every chip is a district.
    var shortName: String {
        switch self {
        case .holosiivskyi: String(localized: "Holosiivskyi")
        case .darnytskyi: String(localized: "Darnytskyi")
        case .desnianskyi: String(localized: "Desnianskyi")
        case .dniprovskyi: String(localized: "Dniprovskyi")
        case .obolonskyi: String(localized: "Obolonskyi")
        case .pecherskyi: String(localized: "Pecherskyi")
        case .podilskyi: String(localized: "Podilskyi")
        case .sviatoshynskyi: String(localized: "Sviatoshynskyi")
        case .solomianskyi: String(localized: "Solomianskyi")
        case .shevchenkivskyi: String(localized: "Shevchenkivskyi")
        }
    }

    /// Points 1.5 km apart covering the district, plus one guaranteed to sit inside it.
    ///
    /// An alert over part of a district is an alert in it, so asking about a single centre
    /// would miss the buffer that clips one edge — and a district is a choice the overlay
    /// has to be tested against, not a polygon worth shipping and intersecting. At this
    /// spacing nothing narrower than the backend's 2 km buffer floor slips between them.
    ///
    /// Generated from `data/osm_kyiv_districts.geojson` in the backend, the same boundaries
    /// it resolves reported districts against, with Shapely's `representative_point()`
    /// first and then a lattice clipped to the polygon.
    var samplePoints: [CLLocationCoordinate2D] {
        let flat: [Double] = switch self {
        case .holosiivskyi: Self.holosiivskyiPoints
        case .darnytskyi: Self.darnytskyiPoints
        case .desnianskyi: Self.desnianskyiPoints
        case .dniprovskyi: Self.dniprovskyiPoints
        case .obolonskyi: Self.obolonskyiPoints
        case .pecherskyi: Self.pecherskyiPoints
        case .podilskyi: Self.podilskyiPoints
        case .sviatoshynskyi: Self.sviatoshynskyiPoints
        case .solomianskyi: Self.solomianskyiPoints
        case .shevchenkivskyi: Self.shevchenkivskyiPoints
        }
        return stride(from: 0, to: flat.count - 1, by: 2).map {
            CLLocationCoordinate2D(latitude: flat[$0], longitude: flat[$0 + 1])
        }
    }

    // Latitude, longitude pairs, flattened so the type checker sees one homogeneous literal.

    private static let holosiivskyiPoints: [Double] = [
        50.3273, 30.5556, 50.2200, 30.6097, 50.2335, 30.6097, 50.2335, 30.6308,
        50.2469, 30.5886, 50.2469, 30.6097, 50.2469, 30.6308, 50.2604, 30.5886,
        50.2604, 30.6097, 50.2739, 30.5464, 50.2739, 30.5675, 50.2739, 30.5886,
        50.2739, 30.6097, 50.2739, 30.6519, 50.2874, 30.5675, 50.2874, 30.5886,
        50.2874, 30.6097, 50.2874, 30.6308, 50.2874, 30.6519, 50.3008, 30.5464,
        50.3008, 30.5675, 50.3008, 30.5886, 50.3008, 30.6097, 50.3008, 30.6308,
        50.3143, 30.5464, 50.3143, 30.5675, 50.3143, 30.5886, 50.3143, 30.6097,
        50.3278, 30.5041, 50.3278, 30.5253, 50.3278, 30.5464, 50.3278, 30.5675,
        50.3278, 30.5886, 50.3278, 30.6097, 50.3413, 30.4830, 50.3413, 30.5041,
        50.3413, 30.5253, 50.3413, 30.5464, 50.3413, 30.5675, 50.3413, 30.5886,
        50.3547, 30.4830, 50.3547, 30.5041, 50.3547, 30.5253, 50.3547, 30.5464,
        50.3547, 30.5675, 50.3547, 30.5886, 50.3682, 30.4408, 50.3682, 30.4619,
        50.3682, 30.4830, 50.3682, 30.5041, 50.3682, 30.5253, 50.3682, 30.5464,
        50.3682, 30.5675, 50.3817, 30.4619, 50.3817, 30.4830, 50.3817, 30.5041,
        50.3817, 30.5253, 50.3817, 30.5464, 50.3817, 30.5675, 50.3952, 30.4830,
        50.3952, 30.5041, 50.3952, 30.5253, 50.3952, 30.5464, 50.3952, 30.5675,
        50.3952, 30.5886, 50.4086, 30.5041, 50.4086, 30.5886, 50.4356, 30.5041,
    ]

    private static let darnytskyiPoints: [Double] = [
        50.4026, 30.7099, 50.3440, 30.6361, 50.3575, 30.5938, 50.3575, 30.6150,
        50.3575, 30.6361, 50.3575, 30.6784, 50.3575, 30.6995, 50.3710, 30.5938,
        50.3710, 30.6150, 50.3710, 30.6361, 50.3710, 30.6573, 50.3710, 30.6784,
        50.3710, 30.6995, 50.3844, 30.5938, 50.3844, 30.6150, 50.3844, 30.6361,
        50.3844, 30.6573, 50.3844, 30.6784, 50.3844, 30.6995, 50.3844, 30.7207,
        50.3844, 30.7418, 50.3844, 30.7630, 50.3979, 30.6150, 50.3979, 30.6361,
        50.3979, 30.6573, 50.3979, 30.6784, 50.3979, 30.6995, 50.3979, 30.7207,
        50.3979, 30.7418, 50.3979, 30.7630, 50.3979, 30.7841, 50.3979, 30.8052,
        50.4114, 30.6150, 50.4114, 30.6361, 50.4114, 30.6573, 50.4114, 30.6784,
        50.4114, 30.6995, 50.4114, 30.7207, 50.4114, 30.7418, 50.4114, 30.7630,
        50.4114, 30.7841, 50.4249, 30.6361, 50.4249, 30.6573, 50.4249, 30.6784,
        50.4249, 30.6995, 50.4249, 30.7207, 50.4249, 30.7418, 50.4249, 30.7630,
        50.4249, 30.7841, 50.4383, 30.6784, 50.4383, 30.6995, 50.4383, 30.7207,
        50.4383, 30.7418, 50.4383, 30.7630, 50.4518, 30.7207, 50.4518, 30.7418,
        50.4653, 30.7418,
    ]

    private static let desnianskyiPoints: [Double] = [
        50.5191, 30.6447, 50.4541, 30.6420, 50.4675, 30.6420, 50.4810, 30.6208,
        50.4810, 30.6420, 50.4810, 30.6631, 50.4810, 30.6843, 50.4945, 30.5360,
        50.4945, 30.6208, 50.4945, 30.6420, 50.4945, 30.6631, 50.4945, 30.6843,
        50.4945, 30.7055, 50.4945, 30.7267, 50.5080, 30.5360, 50.5080, 30.5572,
        50.5080, 30.5784, 50.5080, 30.5996, 50.5080, 30.6208, 50.5080, 30.6420,
        50.5080, 30.6631, 50.5080, 30.6843, 50.5080, 30.7055, 50.5080, 30.7267,
        50.5080, 30.7479, 50.5214, 30.5360, 50.5214, 30.5784, 50.5214, 30.5996,
        50.5214, 30.6208, 50.5214, 30.6420, 50.5214, 30.6631, 50.5214, 30.6843,
        50.5214, 30.7055, 50.5349, 30.5572, 50.5349, 30.5784, 50.5349, 30.5996,
        50.5349, 30.6208, 50.5349, 30.6631, 50.5349, 30.6843, 50.5349, 30.7055,
        50.5349, 30.7267, 50.5349, 30.7479, 50.5349, 30.7691, 50.5349, 30.7903,
        50.5349, 30.8115, 50.5484, 30.6631, 50.5484, 30.6843, 50.5484, 30.7055,
        50.5484, 30.7267, 50.5484, 30.7479, 50.5484, 30.7691, 50.5484, 30.7903,
        50.5484, 30.8115, 50.5619, 30.7267, 50.5619, 30.7479, 50.5619, 30.7691,
        50.5619, 30.7903, 50.5619, 30.8115, 50.5753, 30.7267, 50.5753, 30.7479,
        50.5753, 30.7691, 50.5888, 30.7267,
    ]

    private static let dniprovskyiPoints: [Double] = [
        50.4564, 30.5837, 50.4240, 30.6030, 50.4375, 30.5819, 50.4375, 30.6030,
        50.4375, 30.6242, 50.4375, 30.6454, 50.4375, 30.6665, 50.4509, 30.5607,
        50.4509, 30.5819, 50.4509, 30.6030, 50.4509, 30.6242, 50.4509, 30.6665,
        50.4509, 30.6877, 50.4509, 30.7089, 50.4644, 30.5395, 50.4644, 30.5607,
        50.4644, 30.5819, 50.4644, 30.6030, 50.4644, 30.6242, 50.4644, 30.6665,
        50.4644, 30.6877, 50.4644, 30.7089, 50.4644, 30.7300, 50.4779, 30.5607,
        50.4779, 30.5819, 50.4779, 30.6030, 50.4779, 30.7089, 50.4779, 30.7300,
        50.4913, 30.5395, 50.4913, 30.5607, 50.4913, 30.5819, 50.4913, 30.6030,
    ]

    private static let obolonskyiPoints: [Double] = [
        50.5306, 30.4384, 50.4839, 30.4989, 50.4839, 30.5201, 50.4839, 30.5413,
        50.4974, 30.4565, 50.4974, 30.4777, 50.4974, 30.4989, 50.4974, 30.5201,
        50.5108, 30.4565, 50.5108, 30.4777, 50.5108, 30.4989, 50.5108, 30.5201,
        50.5243, 30.3505, 50.5243, 30.3717, 50.5243, 30.3929, 50.5243, 30.4141,
        50.5243, 30.4565, 50.5243, 30.4777, 50.5243, 30.4989, 50.5243, 30.5201,
        50.5243, 30.5413, 50.5378, 30.3293, 50.5378, 30.3505, 50.5378, 30.3717,
        50.5378, 30.3929, 50.5378, 30.4141, 50.5378, 30.4353, 50.5378, 30.4565,
        50.5378, 30.4777, 50.5378, 30.4989, 50.5378, 30.5201, 50.5513, 30.3081,
        50.5513, 30.3505, 50.5513, 30.3717, 50.5513, 30.3929, 50.5513, 30.4141,
        50.5513, 30.4353, 50.5513, 30.4565, 50.5513, 30.4777, 50.5513, 30.4989,
        50.5647, 30.3293, 50.5647, 30.3505, 50.5647, 30.3717, 50.5647, 30.3929,
        50.5647, 30.4141, 50.5647, 30.4353, 50.5647, 30.4565, 50.5647, 30.4777,
        50.5782, 30.3717, 50.5782, 30.3929, 50.5782, 30.4141, 50.5782, 30.4353,
        50.5782, 30.4565,
    ]

    private static let pecherskyiPoints: [Double] = [
        50.4287, 30.5490, 50.4093, 30.5266, 50.4093, 30.5478, 50.4093, 30.5689,
        50.4228, 30.5266, 50.4228, 30.5478, 50.4228, 30.5689, 50.4362, 30.5266,
        50.4362, 30.5478, 50.4362, 30.5689, 50.4497, 30.5266, 50.4497, 30.5478,
    ]

    private static let podilskyiPoints: [Double] = [
        50.4895, 30.4288, 50.4591, 30.5208, 50.4725, 30.4997, 50.4725, 30.5208,
        50.4860, 30.4149, 50.4860, 30.4573, 50.4860, 30.4785, 50.4995, 30.3726,
        50.4995, 30.3938, 50.4995, 30.4149, 50.4995, 30.4361, 50.5130, 30.3726,
        50.5130, 30.3938, 50.5130, 30.4149, 50.5130, 30.4361,
    ]

    private static let sviatoshynskyiPoints: [Double] = [
        50.4727, 30.3252, 50.4047, 30.4161, 50.4182, 30.3949, 50.4182, 30.4161,
        50.4317, 30.2467, 50.4317, 30.2679, 50.4317, 30.3738, 50.4317, 30.3949,
        50.4451, 30.2467, 50.4451, 30.2679, 50.4451, 30.3102, 50.4451, 30.3314,
        50.4451, 30.3738, 50.4451, 30.3949, 50.4586, 30.2467, 50.4586, 30.2679,
        50.4586, 30.2891, 50.4586, 30.3102, 50.4586, 30.3314, 50.4586, 30.3526,
        50.4586, 30.3738, 50.4586, 30.3949, 50.4721, 30.2679, 50.4721, 30.2891,
        50.4721, 30.3102, 50.4721, 30.3314, 50.4721, 30.3526, 50.4721, 30.3738,
        50.4721, 30.3949, 50.4856, 30.2679, 50.4856, 30.2891, 50.4856, 30.3102,
        50.4856, 30.3526, 50.4856, 30.3738, 50.4856, 30.3949, 50.4990, 30.2891,
        50.4990, 30.3102, 50.4990, 30.3314, 50.4990, 30.3526, 50.5125, 30.2679,
        50.5125, 30.2891, 50.5125, 30.3102, 50.5125, 30.3314, 50.5125, 30.3526,
        50.5260, 30.2891, 50.5260, 30.3102, 50.5260, 30.3314, 50.5395, 30.3102,
    ]

    private static let solomianskyiPoints: [Double] = [
        50.4205, 30.4585, 50.3885, 30.4504, 50.4019, 30.4292, 50.4019, 30.4504,
        50.4019, 30.4715, 50.4154, 30.4292, 50.4154, 30.4504, 50.4154, 30.4715,
        50.4154, 30.4927, 50.4289, 30.4081, 50.4289, 30.4292, 50.4289, 30.4504,
        50.4289, 30.4715, 50.4289, 30.4927, 50.4424, 30.4081, 50.4424, 30.4292,
        50.4424, 30.4504, 50.4424, 30.4715, 50.4558, 30.4292,
    ]

    private static let shevchenkivskyiPoints: [Double] = [
        50.4629, 30.4518, 50.4454, 30.4909, 50.4454, 30.5121, 50.4588, 30.4063,
        50.4588, 30.4274, 50.4588, 30.4486, 50.4588, 30.4698, 50.4588, 30.4909,
        50.4588, 30.5121, 50.4723, 30.4063, 50.4723, 30.4274, 50.4723, 30.4486,
        50.4723, 30.4698, 50.4723, 30.4909,
    ]
}
