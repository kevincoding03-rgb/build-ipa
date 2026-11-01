//  Look4Sat iOS port — SDP4 propagator for deep-space objects
//  Ported from Kotlin: core/domain/.../predict/DeepSpaceObject.kt
//  License: GPL-3.0
//
//  Implements the deep-space (period >= 225 min) terms of SGP4/SDP4
//  from PREDICT v2.2.5. Includes the lunisolar long-period integrator
//  and geopotential resonance terms for the near-geosynchronous region.
import Foundation

/// SDP4 for geosynchronous / deep-space orbits (period >= 225 min).
final class  DeepSpaceObject: OrbitalObject {
    // Short-periodic coefficients (shared naming with SGP4)
    private var c1: Double = 0.0
    private var c4: Double = 0.0
    private var x1mth2: Double = 0.0
    private var x3thm1: Double = 0.0
    private var xlcof: Double = 0.0
    private var xnodcf: Double = 0.0
    private var t2cof: Double = 0.0
    private var aycof: Double = 0.0
    private var x7thm1: Double = 0.0

    // Deep-space value object (mirrors Kotlin DeepSpaceValueObject)
    private var dsv = DeepSpaceValueObject()
    private var deep: DeepSpaceCalculator!

    override init(data: OrbitalData) {
        super.init(data: data)
        setupSDP4()
    }

    // MARK: - Setup

    private func setupSDP4() {
        // Recover original mean motion (xnodp) and semimajor axis (aodp)
        let a1 = pow(XKE / data.xno, TWO_THIRDS)
        dsv.cosio = cos(data.xincl)
        dsv.theta2 = dsv.cosio * dsv.cosio
        x3thm1 = 3.0 * dsv.theta2 - 1.0
        dsv.eosq = data.eccn * data.eccn
        dsv.betao2 = 1.0 - dsv.eosq
        dsv.betao = sqrt(dsv.betao2)
        let del1 = 1.5 * CK2 * x3thm1 / (a1 * a1 * dsv.betao * dsv.betao2)
        let ao = a1 * (1.0 - del1 * (0.5 * TWO_THIRDS + del1 * (1.0 + 134.0 / 81.0 * del1)))
        let delo = 1.5 * CK2 * x3thm1 / (ao * ao * dsv.betao * dsv.betao2)
        dsv.xnodp = data.xno / (1.0 + delo)
        dsv.aodp = ao / (1.0 - delo)
        // For perigee below 156 km, the values of S and QOMS2T are altered
        setPerigee((dsv.aodp * (1.0 - data.eccn) - 1.0) * EARTH_RADIUS)
        let pinvsq = invert(dsv.aodp * dsv.aodp * dsv.betao2 * dsv.betao2)
        dsv.sing = sin(data.omegao)
        dsv.cosg = cos(data.omegao)
        let tsi = invert(dsv.aodp - s4)
        let eta = dsv.aodp * data.eccn * tsi
        let etasq = eta * eta
        let eeta = data.eccn * eta
        let psisq = abs(1.0 - etasq)
        let coef = qoms24 * pow(tsi, 4.0)
        let coef1 = coef / pow(psisq, 3.5)
        let c2 = coef1 * dsv.xnodp * (dsv.aodp * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq))
            + 0.75 * CK2 * tsi / psisq * x3thm1 * (8.0 + 3.0 * etasq * (8.0 + etasq)))
        c1 = data.bstar * c2
        dsv.sinio = sin(data.xincl)
        let a3ovk2 = -J3_HARMONIC / CK2
        x1mth2 = 1.0 - dsv.theta2
        c4 = 2 * dsv.xnodp * coef1 * dsv.aodp * dsv.betao2 * (eta * (2.0 + 0.5 * etasq) + data.eccn
            * (0.5 + 2 * etasq)
            - 2 * CK2 * tsi / (dsv.aodp * psisq)
            * (-3 * x3thm1 * (1.0 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
            + 0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) * cos(2.0 * data.omegao)))
        let theta4 = dsv.theta2 * dsv.theta2
        let temp1 = 3.0 * CK2 * pinvsq * dsv.xnodp
        let temp2 = temp1 * CK2 * pinvsq
        let temp3 = 1.25 * CK4 * pinvsq * pinvsq * dsv.xnodp
        dsv.xmdot =
            dsv.xnodp + 0.5 * temp1 * dsv.betao * x3thm1
            + 0.0625 * temp2 * dsv.betao * (13.0 - 78.0 * dsv.theta2 + 137.0 * theta4)
        let x1m5th = 1.0 - 5 * dsv.theta2
        dsv.omgdot =
            -0.5 * temp1 * x1m5th
            + 0.0625 * temp2 * (7.0 - 114.0 * dsv.theta2 + 395.0 * theta4)
            + temp3 * (3.0 - 36.0 * dsv.theta2 + 49.0 * theta4)
        let xhdot1 = -temp1 * dsv.cosio
        dsv.xnodot =
            xhdot1
            + (0.5 * temp2 * (4.0 - 19.0 * dsv.theta2) + 2 * temp3 * (3.0 - 7.0 * dsv.theta2))
            * dsv.cosio
        xnodcf = 3.5 * dsv.betao2 * xhdot1 * c1
        t2cof = 1.5 * c1
        xlcof = 0.125 * a3ovk2 * dsv.sinio * (3.0 + 5 * dsv.cosio) / (1.0 + dsv.cosio)
        aycof = 0.25 * a3ovk2 * dsv.sinio
        x7thm1 = 7.0 * dsv.theta2 - 1.0
        deep = DeepSpaceCalculator(dsv: dsv, data: data)
    }

    // MARK: - Propagation

    /// Core SDP4 step. tsince is minutes since epoch.
    public func calculateSDP4(_ tsince: Double) {
        var tmp = [Double](repeating: 0.0, count: 12)
        let xmdf = data.xmo + dsv.xmdot * tsince
        let tsq = tsince * tsince
        let templ = t2cof * tsq
        dsv.xll = xmdf + dsv.xnodp * templ
        dsv.omgadf = data.omegao + dsv.omgdot * tsince
        let xnoddf = data.xnodeo + dsv.xnodot * tsince
        dsv.xnode = xnoddf + xnodcf * tsq
        let tempa = 1.0 - c1 * tsince
        let tempe = data.bstar * c4 * tsince
        dsv.xn = dsv.xnodp
        dsv.t = tsince
        deep.dpsec(data)
        let a = pow(XKE / dsv.xn, TWO_THIRDS) * tempa * tempa
        dsv.em -= tempe
        deep.dpper()
        let xl = dsv.xll + dsv.omgadf + dsv.xnode
        let beta = sqrt(1.0 - dsv.em * dsv.em)
        dsv.xn = XKE / pow(a, 1.5)

        // Long period periodics
        let axn = dsv.em * cos(dsv.omgadf)
        tmp[0] = invert(a * beta * beta)
        let xll = tmp[0] * xlcof * axn
        let aynl = tmp[0] * aycof
        let xlt = xl + xll
        let ayn = dsv.em * sin(dsv.omgadf) + aynl

        // Solve Kepler's equation
        let capu = mod2PI(xlt - dsv.xnode)
        tmp[2] = capu
        converge(&tmp, axn, ayn, capu)
        calculatePosAndVel(&tmp, a, axn, ayn)
        calculatePhase(xlt, dsv.xnode, dsv.omgadf)
    }

    private func calculatePosAndVel(_ tmp: inout [Double], _ a: Double, _ axn: Double, _ ayn: Double) {
        let ecose = tmp[5] + tmp[6]
        let esine = tmp[3] - tmp[4]
        let elsq = axn * axn + ayn * ayn
        tmp[0] = 1.0 - elsq
        let pl = a * tmp[0]
        tmp[9] = a * (1.0 - ecose)
        tmp[1] = invert(tmp[9])
        tmp[10] = XKE * sqrt(a) * esine * tmp[1]
        tmp[11] = XKE * sqrt(pl) * tmp[1]
        tmp[2] = a * tmp[1]
        let betal = sqrt(tmp[0])
        tmp[3] = invert(1.0 + betal)
        let cosu = tmp[2] * (tmp[8] - axn + ayn * esine * tmp[3])
        let sinu = tmp[2] * (tmp[7] - ayn - axn * esine * tmp[3])
        let u = atan2(sinu, cosu)
        let sin2u = 2.0 * sinu * cosu
        let cos2u = 2.0 * cosu * cosu - 1.0
        tmp[0] = invert(pl)
        tmp[1] = CK2 * tmp[0]
        tmp[2] = tmp[1] * tmp[0]
        // Update for short periodics
        let rk = tmp[9] * (1.0 - 1.5 * tmp[2] * betal * x3thm1) + 0.5 * tmp[1] * x1mth2 * cos2u
        let uk = u - 0.25 * tmp[2] * x7thm1 * sin2u
        let xnodek = dsv.xnode + 1.5 * tmp[2] * dsv.cosio * sin2u
        let xinck = dsv.xinc + 1.5 * tmp[2] * dsv.cosio * dsv.sinio * cos2u
        let rdotk = tmp[10] - dsv.xn * tmp[1] * x1mth2 * sin2u
        let rfdotk = tmp[11] + dsv.xn * tmp[1] * (x1mth2 * cos2u + 1.5 * x3thm1)

        super.calculatePosAndVel(rk, uk, xnodek, xinck, rdotk, rfdotk)
    }

    // MARK: - Supporting value object

    /// Shared SDP4 state. A class (not a struct) so both the object and its
    /// DeepSpaceCalculator can mutate it in place, matching the Kotlin
    /// reference semantics of `dsv`.
    final class DeepSpaceValueObject {
        var eosq = 0.0
        var sinio = 0.0
        var cosio = 0.0
        var betao = 0.0
        var aodp = 0.0
        var theta2 = 0.0
        var sing = 0.0
        var cosg = 0.0
        var betao2 = 0.0
        var xmdot = 0.0
        var omgdot = 0.0
        var xnodot = 0.0
        var xnodp = 0.0
        // Used by dpsec and dpper parts of Deep()
        var xll = 0.0
        var omgadf = 0.0
        var xnode = 0.0
        var em = 0.0
        var xinc = 0.0
        var xn = 0.0
        var t = 0.0
        // Used by thetg and Deep()
        var ds50 = 0.0
    }

    // MARK: - Lunisolar + resonance integrator

    /// The deep-space periodic integrator, mirroring the Kotlin
    /// `DeepSpaceCalculator` inner class.
    final class DeepSpaceCalculator {
        let dsv: DeepSpaceValueObject
        let data: OrbitalData

        // Lunar-solar constants
        let zSinis = 3.9785416e-1
        let zSings = -9.8088458e-1
        let zNs = 1.19459e-5
        let c1ss = 2.9864797e-6
        let zEs = 1.675e-2
        let zNl = 1.5835218e-4
        let c1l = 4.7968065e-7
        let zEl = 5.490e-2
        let root22 = 1.7891679e-6
        let root32 = 3.7393792e-7
        let root44 = 7.3636953e-9
        let root52 = 1.1428639e-7
        let root54 = 2.1765803e-9
        let tHdt = 4.3752691e-3
        let q22 = 1.7891679e-6
        let q31 = 2.1460748e-6
        let q33 = 2.2123015e-7
        let g22 = 5.7686396
        let g32 = 9.5240898e-1
        let g44 = 1.8014998
        let g52 = 1.0508330
        let g54 = 4.4108898

        private var thgr: Double = 0.0
        private var xnq: Double = 0.0
        private var xqncl: Double = 0.0
        private var omegaq: Double = 0.0
        private var zmol: Double = 0.0
        private var zmos: Double = 0.0

        // Iteratively refined state
        private var savtsn = 0.0
        private var ee2 = 0.0
        private var e3 = 0.0
        private var xi2 = 0.0
        private var xl2 = 0.0
        private var xl3 = 0.0
        private var xl4 = 0.0
        private var xgh2 = 0.0
        private var xgh3 = 0.0
        private var xgh4 = 0.0
        private var xh2 = 0.0
        private var xh3 = 0.0
        private var sse = 0.0
        private var ssi = 0.0
        private var ssg = 0.0
        private var xi3 = 0.0
        private var se2 = 0.0
        private var si2 = 0.0
        private var sl2 = 0.0
        private var sgh2 = 0.0
        private var sh2 = 0.0
        private var se3 = 0.0
        private var si3 = 0.0
        private var sl3 = 0.0
        private var sgh3 = 0.0
        private var sh3 = 0.0
        private var sl4 = 0.0
        private var sgh4 = 0.0
        private var ssl = 0.0
        private var ssh = 0.0
        private var d3210 = 0.0
        private var d3222 = 0.0
        private var d4410 = 0.0
        private var d4422 = 0.0
        private var d5220 = 0.0
        private var d5232 = 0.0
        private var d5421 = 0.0
        private var d5433 = 0.0
        private var del1 = 0.0
        private var del2 = 0.0
        private var del3 = 0.0
        private var fasx2 = 0.0
        private var fasx4 = 0.0
        private var fasx6 = 0.0
        private var xlamo = 0.0
        private var xfact: Double = 0.0
        private var xni: Double = 0.0
        private var atime: Double = 0.0
        private let stepp: Double = 720.0
        private let stepn: Double = -720.0
        private let step2: Double = 259200.0
        private var preep = 0.0
        private var pl = 0.0
        private var sghs = 0.0
        private var xli: Double = 0.0
        private var d2201 = 0.0
        private var d2211 = 0.0
        private var sghl = 0.0
        private var sh1 = 0.0
        private var pinc = 0.0
        private var pe = 0.0
        private var shs = 0.0
        private var zsingl = 0.0
        private var zcosgl = 0.0
        private var zsinhl = 0.0
        private var zcoshl = 0.0
        private var zsinil = 0.0
        private var zcosil = 0.0
        private var a1 = 0.0
        private var a2 = 0.0
        private var a3 = 0.0
        private var a4 = 0.0
        private var a5 = 0.0
        private var a6 = 0.0
        private var a7 = 0.0
        private var a8 = 0.0
        private var a9 = 0.0
        private var a10 = 0.0
        private var ainv2 = 0.0
        private var alfdp = 0.0
        private var aqnv: Double = 0.0
        private var sgh = 0.0
        private var sini2 = 0.0
        private var sinis = 0.0
        private var sinok = 0.0
        private var sh = 0.0
        private var si = 0.0
        private var sil = 0.0
        private var day: Double = 0.0
        private var betdp = 0.0
        private var dalf = 0.0
        private var bfact = 0.0
        private var c = 0.0
        private var cc = 0.0
        private var cosis = 0.0
        private var cosok = 0.0
        private var cosq: Double = 0.0
        private var ctem = 0.0
        private var f322 = 0.0
        private var zx = 0.0
        private var zy = 0.0
        private var dbet = 0.0
        private var dls = 0.0
        private var eoc = 0.0
        private var eq: Double = 0.0
        private var f2 = 0.0
        private var f220 = 0.0
        private var f221 = 0.0
        private var f3 = 0.0
        private var f311 = 0.0
        private var f321 = 0.0
        private var xnoh = 0.0
        private var f330 = 0.0
        private var f441 = 0.0
        private var f442 = 0.0
        private var f522 = 0.0
        private var f523 = 0.0
        private var f542 = 0.0
        private var f543 = 0.0
        private var g200 = 0.0
        private var g201 = 0.0
        private var g211 = 0.0
        private var pgh = 0.0
        private var ph = 0.0
        private var s1 = 0.0
        private var s2 = 0.0
        private var s3 = 0.0
        private var s4s = 0.0
        private var s5 = 0.0
        private var s6 = 0.0
        private var s7 = 0.0
        private var se = 0.0
        private var sel = 0.0
        private var ses = 0.0
        private var xls = 0.0
        private var g300 = 0.0
        private var g310 = 0.0
        private var g322 = 0.0
        private var g410 = 0.0
        private var g422 = 0.0
        private var g520 = 0.0
        private var g521 = 0.0
        private var g532 = 0.0
        private var g533 = 0.0
        private var gam = 0.0
        private var sinq: Double = 0.0
        private var sinzf = 0.0
        private var sis = 0.0
        private var sl = 0.0
        private var sll = 0.0
        private var sls = 0.0
        private var stem = 0.0
        private var temp = 0.0
        private var temp1 = 0.0
        private var x1 = 0.0
        private var x2 = 0.0
        private var x2li = 0.0
        private var x2omi = 0.0
        private var x3 = 0.0
        private var x4 = 0.0
        private var x5 = 0.0
        private var x6 = 0.0
        private var x7 = 0.0
        private var x8 = 0.0
        private var xl = 0.0
        private var xldot = 0.0
        private var xmao: Double = 0.0
        private var xnddt = 0.0
        private var xndot = 0.0
        private var xno2 = 0.0
        private var xnodce = 0.0
        private var xnoi = 0.0
        private var xomi = 0.0
        private var xpidot: Double = 0.0
        private var z1 = 0.0
        private var z11 = 0.0
        private var z12 = 0.0
        private var z13 = 0.0
        private var z2 = 0.0
        private var z21 = 0.0
        private var z22 = 0.0
        private var z23 = 0.0
        private var z3 = 0.0
        private var z31 = 0.0
        private var z32 = 0.0
        private var z33 = 0.0
        private var ze = 0.0
        private var zf = 0.0
        private var zm = 0.0
        private var zn = 0.0
        private var zsing = 0.0
        private var zsinh = 0.0
        private var zsini = 0.0
        private var zcosg = 0.0
        private var zcosh = 0.0
        private var zcosi = 0.0
        private var delt = 0.0
        private var ft = 0.0
        private var resonance = false
        private var synchronous = false
        private var doLoop = false
        private var epochRestart = false

        init(dsv: DeepSpaceValueObject, data: OrbitalData) {
            self.dsv = dsv
            self.data = data
            thgr = thetaG(data.epoch)
            eq = data.eccn
            xnq = dsv.xnodp
            aqnv = 1.0 / dsv.aodp
            xqncl = data.xincl
            xmao = data.xmo
            xpidot = dsv.omgdot + dsv.xnodot
            sinq = sin(data.xnodeo)
            cosq = cos(data.xnodeo)
            omegaq = data.omegao
            day = dsv.ds50 + 18261.5
            if abs(day - preep) > 1e-6 {
                preep = day
                xnodce = 4.5236020 - 9.2422029e-4 * day
                stem = sin(xnodce)
                ctem = cos(xnodce)
                zcosil = 0.91375164 - 0.03568096 * ctem
                zsinil = sqrt(1.0 - zcosil * zcosil)
                zsinhl = 0.089683511 * stem / zsinil
                zcoshl = sqrt(1.0 - zsinhl * zsinhl)
                c = 4.7199672 + 0.22997150 * day
                gam = 5.8351514 + 0.0019443680 * day
                zmol = mod2PI(c - gam)
                zx = 0.39785416 * stem / zsinil
                zy = zcoshl * ctem + 0.91744867 * zsinhl * stem
                zx = atan2(zx, zy)
                zx = gam + zx - xnodce
                zcosgl = cos(zx)
                zsingl = sin(zx)
                zmos = mod2PI(6.2565837 + 0.017201977 * day)
            } else {
                zmol = 0.0
                zmos = 0.0
            }
            doSolarTerms()

            // Geopotential resonance initialization for 12-hour orbits
            resonance = false
            synchronous = false
            if !(xnq < 0.0052359877 && xnq > 0.0034906585) {
                if !(xnq >= 0.00826 && xnq <= 0.00924) {
                    if eq < 0.5 { resonance = true }
                }
                eoc = eq * dsv.eosq
                g201 = -0.306 - (eq - 0.64) * 0.440
                if eq <= 0.65 {
                    g211 = 3.616 - 13.247 * eq + 16.290 * dsv.eosq
                    g310 = -19.302 + 117.390 * eq - 228.419 * dsv.eosq + 156.591 * eoc
                    g322 = -18.9068 + 109.7927 * eq - 214.6334 * dsv.eosq + 146.5816 * eoc
                    g410 = -41.122 + 242.694 * eq - 471.094 * dsv.eosq + 313.953 * eoc
                    g422 = -146.407 + 841.880 * eq - 1629.014 * dsv.eosq + 1083.435 * eoc
                    g520 = -532.114 + 3017.977 * eq - 5740 * dsv.eosq + 3708.276 * eoc
                } else {
                    g211 = -72.099 + 331.819 * eq - 508.738 * dsv.eosq + 266.724 * eoc
                    g310 = -346.844 + 1582.851 * eq - 2415.925 * dsv.eosq + 1246.113 * eoc
                    g322 = -342.585 + 1554.908 * eq - 2366.899 * dsv.eosq + 1215.972 * eoc
                    g410 = -1052.797 + 4758.686 * eq - 7193.992 * dsv.eosq + 3651.957 * eoc
                    g422 = -3581.69 + 16178.11 * eq - 24462.77 * dsv.eosq + 12422.52 * eoc
                    g520 = (eq <= 0.715)
                        ? 1464.74 - 4664.75 * eq + 3763.64 * dsv.eosq
                        : -5149.66 + 29936.92 * eq - 54087.36 * dsv.eosq + 31324.56 * eoc
                }
                if eq < 0.7 {
                    g533 = -919.2277 + 4988.61 * eq - 9064.77 * dsv.eosq + 5542.21 * eoc
                    g521 = -822.71072 + 4568.6173 * eq - 8491.4146 * dsv.eosq + 5337.524 * eoc
                    g532 = -853.666 + 4690.25 * eq - 8624.77 * dsv.eosq + 5341.4 * eoc
                } else {
                    g533 = -37995.78 + 161616.52 * eq - 229838.2 * dsv.eosq + 109377.94 * eoc
                    g521 = -51752.104 + 218913.95 * eq - 309468.16 * dsv.eosq + 146349.42 * eoc
                    g532 = -40023.88 + 170470.89 * eq - 242699.48 * dsv.eosq + 115605.82 * eoc
                }
                sini2 = dsv.sinio * dsv.sinio
                f220 = 0.75 * (1.0 + 2 * dsv.cosio + dsv.theta2)
                f221 = 1.5 * sini2
                f321 = 1.875 * dsv.sinio * (1.0 - 2 * dsv.cosio - 3.0 * dsv.theta2)
                f322 = -1.875 * dsv.sinio * (1.0 + 2 * dsv.cosio - 3.0 * dsv.theta2)
                f441 = 35 * sini2 * f220
                f442 = 39.3750 * sini2 * sini2
                f522 =
                    9.84375 * dsv.sinio
                        * (sini2 * (1.0 - 2 * dsv.cosio - 5 * dsv.theta2)
                        + 0.33333333 * (-2 + 4 * dsv.cosio + 6 * dsv.theta2))
                f523 =
                    dsv.sinio
                        * (4.92187512 * sini2 * (-2 - 4 * dsv.cosio + 10 * dsv.theta2)
                        + 6.56250012 * (1.0 + 2 * dsv.cosio - 3.0 * dsv.theta2))
                f542 =
                    29.53125 * dsv.sinio
                        * (2.0 - 8 * dsv.cosio + dsv.theta2 * (-12 + 8 * dsv.cosio + 10 * dsv.theta2))
                f543 =
                    29.53125 * dsv.sinio
                        * (-2 - 8 * dsv.cosio + dsv.theta2 * (12 + 8 * dsv.cosio - 10 * dsv.theta2))
                xno2 = xnq * xnq
                ainv2 = aqnv * aqnv
                temp1 = 3.0 * xno2 * ainv2
                temp = temp1 * root22
                d2201 = temp * f220 * g201
                d2211 = temp * f221 * g211
                temp1 *= aqnv
                temp = temp1 * root32
                d3210 = temp * f321 * g310
                d3222 = temp * f322 * g322
                temp1 *= aqnv
                temp = 2.0 * temp1 * root44
                d4410 = temp * f441 * g410
                d4422 = temp * f442 * g422
                temp1 *= aqnv
                temp = temp1 * root52
                d5220 = temp * f522 * g520
                d5232 = temp * f523 * g532
                temp = 2.0 * temp1 * root54
                d5421 = temp * f542 * g521
                d5433 = temp * f543 * g533
                xlamo = xmao + data.xnodeo + data.xnodeo - thgr - thgr
                bfact = dsv.xmdot + dsv.xnodot + dsv.xnodot - tHdt - tHdt
                bfact += ssl + ssh + ssh
            } else {
                // Init synchronous resonance terms
                resonance = true
                synchronous = true
                g200 = 1.0 + dsv.eosq * (-2.5 + 0.8125 * dsv.eosq)
                g310 = 1.0 + 2 * dsv.eosq
                g300 = 1.0 + dsv.eosq * (-6 + 6.60937 * dsv.eosq)
                f220 = 0.75 * (1.0 + dsv.cosio) * (1.0 + dsv.cosio)
                f311 =
                    0.9375 * dsv.sinio * dsv.sinio * (1.0 + 3.0 * dsv.cosio) - 0.75 * (1.0 + dsv.cosio)
                f330 = 1.0 + dsv.cosio
                f330 *= 1.875 * f330 * f330
                del1 = 3.0 * xnq * xnq * aqnv * aqnv
                del2 = 2.0 * del1 * f220 * g200 * q22
                del3 = 3.0 * del1 * f330 * g300 * q33 * aqnv
                del1 *= f311 * g310 * q31 * aqnv
                fasx2 = 0.13130908
                fasx4 = 2.8843198
                fasx6 = 0.37448087
                xlamo = xmao + data.xnodeo + data.omegao - thgr
                bfact = dsv.xmdot + xpidot - tHdt
                bfact += ssl + ssg + ssh
            }
            xfact = bfact - xnq
            // Init integrator
            xli = xlamo
            xni = xnq
            atime = 0.0
        }

        // Entrance for lunar-solar periodics
        func dpper() {
            sinis = sin(dsv.xinc)
            cosis = cos(dsv.xinc)
            if abs(savtsn - dsv.t) >= 30 {
                savtsn = dsv.t
                zm = zmos + zNs * dsv.t
                zf = zm + 2 * zEs * sin(zm)
                sinzf = sin(zf)
                f2 = 0.5 * sinzf * sinzf - 0.25
                f3 = -0.5 * sinzf * cos(zf)
                ses = se2 * f2 + e3 * f3
                sis = si2 * f2 + si3 * f3
                sls = sl2 * f2 + sl3 * f3 + sl4 * sinzf
                sghs = sgh2 * f2 + sgh3 * f3 + sgh4 * sinzf
                shs = sh2 * f2 + sh3 * f3
                zm = zmol + zNl * dsv.t
                zf = zm + 2 * zEl * sin(zm)
                sinzf = sin(zf)
                f2 = 0.5 * sinzf * sinzf - 0.25
                f3 = -0.5 * sinzf * cos(zf)
                sel = ee2 * f2 + e3 * f3
                sil = xi2 * f2 + xi3 * f3
                sll = xl2 * f2 + xl3 * f3 + xl4 * sinzf
                sghl = xgh2 * f2 + xgh3 * f3 + xgh4 * sinzf
                sh1 = xh2 * f2 + xh3 * f3
                pe = ses + sel
                pinc = sis + sil
                pl = sls + sll
            }
            pgh = sghs + sghl
            ph = shs + sh1
            dsv.xinc += pinc
            dsv.em += pe
            if xqncl >= 0.2 {
                // Apply periodics directly
                ph /= dsv.sinio
                pgh -= dsv.cosio * ph
                dsv.omgadf += pgh
                dsv.xnode += ph
                dsv.xll += pl
            } else {
                applyPeriodics()
                // This is a patch to the Lyddane modification suggested by Rob Matson
                if abs(xnoh - dsv.xnode) > PI {
                    if dsv.xnode < xnoh { dsv.xnode += TWO_PI } else { dsv.xnode -= TWO_PI }
                }
                dsv.xll += pl
                dsv.omgadf = xls - dsv.xll - cos(dsv.xinc) * dsv.xnode
            }
        }

        // Entrance for deep-space secular effects
        func dpsec(_ params: OrbitalData) {
            dsv.xll += ssl * dsv.t
            dsv.omgadf += ssg * dsv.t
            dsv.xnode += ssh * dsv.t
            dsv.em = params.eccn + sse * dsv.t
            dsv.xinc = params.xincl + ssi * dsv.t
            if dsv.xinc < 0 {
                dsv.xinc = -dsv.xinc
                dsv.xnode += PI
                dsv.omgadf -= PI
            }
            if !resonance { return }
            repeat {
                processEpochRestartLoop()
            } while doLoop && epochRestart
            dsv.xn = xni + xndot * ft + xnddt * ft * ft * 0.5
            xl = xli + xldot * ft + xndot * ft * ft * 0.5
            let tempVal = -dsv.xnode + thgr + dsv.t * tHdt
            if synchronous {
                dsv.xll = xl - dsv.omgadf + tempVal
            } else {
                dsv.xll = xl + tempVal + tempVal
            }
        }

        private func doSolarTerms() {
            savtsn = 1e20
            zcosg = 1.945905e-1
            zsing = zSings
            zcosi = 9.1744867e-1
            zsini = zSinis
            zcosh = cosq
            zsinh = sinq
            cc = c1ss
            zn = zNs
            ze = zEs
            xnoi = 1.0 / xnq
            calculateSolarTerms()
            calculateLunarTerms()
            calculateSolarTerms()
            sse += se
            ssi += si
            ssl += sl
            ssg = ssg + sgh - dsv.cosio / dsv.sinio * sh
            ssh += sh / dsv.sinio
        }

        private func calculateLunarTerms() {
            sse = se
            ssi = si
            ssl = sl
            ssh = sh / dsv.sinio
            ssg = sgh - dsv.cosio * ssh
            se2 = ee2
            si2 = xi2
            sl2 = xl2
            sgh2 = xgh2
            sh2 = xh2
            se3 = e3
            si3 = xi3
            sl3 = xl3
            sgh3 = xgh3
            sh3 = xh3
            sl4 = xl4
            sgh4 = xgh4
            zcosg = zcosgl
            zsing = zsingl
            zcosi = zcosil
            zsini = zsinil
            zcosh = zcoshl * cosq + zsinhl * sinq
            zsinh = sinq * zcoshl - cosq * zsinhl
            zn = zNl
            cc = c1l
            ze = zEl
        }

        private func calculateSolarTerms() {
            a1 = zcosg * zcosh + zsing * zcosi * zsinh
            a3 = -zsing * zcosh + zcosg * zcosi * zsinh
            a7 = -zcosg * zsinh + zsing * zcosi * zcosh
            a8 = zsing * zsini
            a9 = zsing * zsinh + zcosg * zcosi * zcosh
            a10 = zcosg * zsini
            a2 = dsv.cosio * a7 + dsv.sinio * a8
            a4 = dsv.cosio * a9 + dsv.sinio * a10
            a5 = -dsv.sinio * a7 + dsv.cosio * a8
            a6 = -dsv.sinio * a9 + dsv.cosio * a10
            x1 = a1 * dsv.cosg + a2 * dsv.sing
            x2 = a3 * dsv.cosg + a4 * dsv.sing
            x3 = -a1 * dsv.sing + a2 * dsv.cosg
            x4 = -a3 * dsv.sing + a4 * dsv.cosg
            x5 = a5 * dsv.sing
            x6 = a6 * dsv.sing
            x7 = a5 * dsv.cosg
            x8 = a6 * dsv.cosg
            z31 = 12 * x1 * x1 - 3.0 * x3 * x3
            z32 = 24 * x1 * x2 - 6 * x3 * x4
            z33 = 12 * x2 * x2 - 3.0 * x4 * x4
            z1 = 3.0 * (a1 * a1 + a2 * a2) + z31 * dsv.eosq
            z2 = 6.0 * (a1 * a3 + a2 * a4) + z32 * dsv.eosq
            z3 = 3.0 * (a3 * a3 + a4 * a4) + z33 * dsv.eosq
            z11 = -6 * a1 * a5 + dsv.eosq * (-24 * x1 * x7 - 6 * x3 * x5)
            z12 =
                -6 * (a1 * a6 + a3 * a5)
                    + dsv.eosq * (-24 * (x2 * x7 + x1 * x8) - 6 * (x3 * x6 + x4 * x5))
            z13 = -6 * a3 * a6 + dsv.eosq * (-24 * x2 * x8 - 6 * x4 * x6)
            z21 = 6.0 * a2 * a5 + dsv.eosq * (24 * x1 * x5 - 6 * x3 * x7)
            z22 =
                6.0 * (a4 * a5 + a2 * a6)
                    + dsv.eosq * (24 * (x2 * x5 + x1 * x6) - 6 * (x4 * x7 + x3 * x8))
            z23 = 6.0 * a4 * a6 + dsv.eosq * (24 * x2 * x6 - 6 * x4 * x8)
            z1 += z1 + dsv.betao2 * z31
            z2 += z2 + dsv.betao2 * z32
            z3 += z3 + dsv.betao2 * z33
            let s3val = cc * xnoi
            s2 = -0.5 * s3val / dsv.betao
            s4s = s3val * dsv.betao
            s1 = -15 * eq * s4s
            s5 = x1 * x3 + x2 * x4
            s6 = x2 * x3 + x1 * x4
            s7 = x2 * x4 - x1 * x3
            se = s1 * zn * s5
            si = s2 * zn * (z11 + z13)
            sl = -zn * s3val * (z1 + z3 - 14 - 6 * dsv.eosq)
            sgh = s4s * zn * (z31 + z33 - 6)
            sh = -zn * s2 * (z21 + z23)
            if xqncl < 5.2359877e-2 { sh = 0.0 }
            ee2 = 2.0 * s1 * s6
            e3 = 2.0 * s1 * s7
            xi2 = 2.0 * s2 * z12
            xi3 = 2.0 * s2 * (z13 - z11)
            xl2 = -2 * s3val * z2
            xl3 = -2 * s3val * (z3 - z1)
            xl4 = -2 * s3val * (-21 - 9 * dsv.eosq) * ze
            xgh2 = 2.0 * s4s * z32
            xgh3 = 2.0 * s4s * (z33 - z31)
            xgh4 = -18 * s4s * ze
            xh2 = -2 * s2 * z22
            xh3 = -2 * s2 * (z23 - z21)
        }

        private func processEpochRestartLoop() {
            if atime == 0.0 || (dsv.t >= 0 && atime < 0) || (dsv.t < 0 && atime >= 0) {
                calculateDelta()
                atime = 0.0
                xni = xnq
                xli = xlamo
            } else if abs(dsv.t) >= abs(atime) {
                calculateDelta()
            }
            processNotEpochRestartLoop()
        }

        private func calculateDelta() {
            delt = dsv.t < 0 ? stepn : stepp
        }

        private func processNotEpochRestartLoop() {
            repeat {
                if abs(dsv.t - atime) >= stepp {
                    doLoop = true
                    epochRestart = false
                } else {
                    ft = dsv.t - atime
                    doLoop = false
                }
                if abs(dsv.t) < abs(atime) {
                    delt = dsv.t >= 0 ? stepn : stepp
                    doLoop = doLoop || epochRestart
                }
                if synchronous {
                    xndot = del1 * sin(xli - fasx2)
                        + del2 * sin(2.0 * (xli - fasx4))
                        + del3 * sin(3.0 * (xli - fasx6))
                    xnddt = del1 * cos(xli - fasx2)
                        + 2 * del2 * cos(2.0 * (xli - fasx4))
                        + 3.0 * del3 * cos(3.0 * (xli - fasx6))
                } else {
                    xomi = omegaq + dsv.omgdot * atime
                    x2omi = xomi + xomi
                    x2li = xli + xli
                    xndot =
                        d2201 * sin(x2omi + xli - g22)
                            + d2211 * sin(xli - g22)
                            + (d3210 * sin(xomi + xli - g32))
                            + d3222 * sin(-xomi + xli - g32)
                            + (d4410 * sin(x2omi + x2li - g44))
                            + d4422 * sin(x2li - g44)
                            + (d5220 * sin(xomi + xli - g52))
                            + d5232 * sin(-xomi + xli - g52)
                            + (d5421 * sin(xomi + x2li - g54))
                            + d5433 * sin(-xomi + x2li - g54)
                    xnddt =
                        d2201 * cos(x2omi + xli - g22)
                            + d2211 * cos(xli - g22)
                            + (d3210 * cos(xomi + xli - g32))
                            + d3222 * cos(-xomi + xli - g32)
                            + (d5220 * cos(xomi + xli - g52))
                            + d5232 * cos(-xomi + xli - g52)
                            + (2
                                * (d4410 * cos(x2omi + x2li - g44)
                                + d4422 * cos(x2li - g44)
                                + (d5421 * cos(xomi + x2li - g54))
                                + d5433 * cos(-xomi + x2li - g54)))
                }
                xldot = xni + xfact
                xnddt *= xldot
                if doLoop {
                    xli += xldot * delt + xndot * step2
                    xni += xndot * delt + xnddt * step2
                    atime += delt
                }
            } while doLoop && !epochRestart
        }

        // Apply periodics with Lyddane modification
        private func applyPeriodics() {
            sinok = sin(dsv.xnode)
            cosok = cos(dsv.xnode)
            alfdp = sinis * sinok
            betdp = sinis * cosok
            dalf = ph * cosok + pinc * cosis * sinok
            dbet = -ph * sinok + pinc * cosis * cosok
            alfdp += dalf
            betdp += dbet
            dsv.xnode = mod2PI(dsv.xnode)
            xls = dsv.xll + dsv.omgadf + cosis * dsv.xnode
            dls = pl + pgh - pinc * dsv.xnode * sinis
            xls += dls
            xnoh = dsv.xnode
            dsv.xnode = atan2(alfdp, betdp)
        }

        // Calculates the Greenwich Mean Sidereal Time for an epoch, valid 1957 through 2056
        private func thetaG(_ epoch: Double) -> Double {
            var year = floor(epoch * 1e-3)
            var dayOfYear = (epoch * 1e-3 - year) * 1000.0
            year = year < 57 ? year + 2000 : year + 1900
            let dayFloor = floor(dayOfYear)
            let dayFraction = dayOfYear - dayFloor
            dayOfYear = dayFloor
            let jd = Self.julianDateOfYear(year) + dayOfYear
            dsv.ds50 = jd - 2433281.5 + dayFraction
            return mod2PI(6.3003880987 * dsv.ds50 + 1.72944494)
        }

        private static func julianDateOfYear(_ theYear: Double) -> Double {
            // Meeus (Astronomical Formulae, pp. 23-25); same formula as
            // OrbitalObject.julianDateOfYear (returns JD of 0.0 Jan {year}).
            let aYear = theYear - 1
            let a = Int64(floor(aYear / 100.0))
            let b: Int64 = 2 - a + a / 4
            var i = Int64(365.25 * aYear)
            i += 429
            return Double(i) + 1720994.5 + Double(b)
        }
    }
}
