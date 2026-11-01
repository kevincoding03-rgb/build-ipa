//  Look4Sat iOS port — SGP4 propagator for near-Earth objects
//  Ported from Kotlin: core/domain/.../predict/NearEarthObject.kt
//  License: GPL-3.0
//
//  The SGP4 short-period and long-period coefficient setup matches PREDICT
//  v2.2.5. Field naming follows the original: xnodp/aodp, xmdot/omgdot/
//  xnodot are derived in init and reused by calculateSGP4; xlcof/aycof
//  handle the long-period periodics.
import Foundation

final class  NearEarthObject: OrbitalObject {
    // Coefficients set during init, read by calculateSGP4.
    private var aodp = 0.0
    private var aycof = 0.0
    private var c1 = 0.0
    private var c4 = 0.0
    private var c5 = 0.0
    private var cosio = 0.0
    private var d2 = 0.0
    private var d3 = 0.0
    private var d4 = 0.0
    private var delmo = 0.0
    private var omgcof = 0.0
    private var eta = 0.0
    private var omgdot = 0.0
    private var sinio = 0.0
    private var xnodp = 0.0
    private var sinmo = 0.0
    private var t2cof = 0.0
    private var t3cof = 0.0
    private var t4cof = 0.0
    private var t5cof = 0.0
    private var x1mth2 = 0.0
    private var x3thm1 = 0.0
    private var x7thm1 = 0.0
    private var xmcof = 0.0
    private var xmdot = 0.0
    private var xnodcf = 0.0
    private var xnodot = 0.0
    private var xlcof = 0.0
    private var sgp4Simple = false

    override init(data: OrbitalData) {
        super.init(data: data)
        setupSGP4()
    }

    private func setupSGP4() {
        // Recover original mean motion (xnodp) and semimajor axis (aodp)
        let a1 = pow(XKE / data.xno, TWO_THIRDS)
        cosio = cos(data.xincl)
        let theta2 = sqr(cosio)
        x3thm1 = 3.0 * theta2 - 1.0
        let eo = data.eccn
        let eosq = sqr(eo)
        let betao2 = 1.0 - eosq
        let betao = sqrt(betao2)
        let del1 = 1.5 * CK2 * x3thm1 / (sqr(a1) * betao * betao2)
        let ao = a1 * (1.0 - del1 * (0.5 * TWO_THIRDS + del1 * (1.0 + 134.0 / 81.0 * del1)))
        let delo = 1.5 * CK2 * x3thm1 / (sqr(ao) * betao * betao2)
        xnodp = data.xno / (1.0 + delo)
        aodp = ao / (1.0 - delo)

        // For perigee less than 220 kilometers, the "simple" flag is set
        sgp4Simple = aodp * (1.0 - eo) < 220 / EARTH_RADIUS + 1.0

        // For perigees below 156 km, the values of S and QOMS2T are altered
        setPerigee((aodp * (1.0 - eo) - 1.0) * EARTH_RADIUS)

        let pinvsq = invert(sqr(aodp) * sqr(betao2))
        let tsi = invert(aodp - s4)
        eta = aodp * eo * tsi
        let etasq = eta * eta
        let eeta = eo * eta
        let psisq = abs(1.0 - etasq)
        let coef = qoms24 * pow(tsi, 4.0)
        let coef1 = coef / pow(psisq, 3.5)
        let bstar = data.bstar
        let c2 = coef1 * xnodp * (aodp * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq))
            + 0.75 * CK2 * tsi / psisq * x3thm1 * (8.0 + 3.0 * etasq * (8.0 + etasq)))
        c1 = bstar * c2
        sinio = sin(data.xincl)
        let a3ovk2 = -J3_HARMONIC / CK2
        let c3 = coef * tsi * a3ovk2 * xnodp * sinio / eo
        x1mth2 = 1.0 - theta2
        let omegao = data.omegao
        c4 = 2 * xnodp * coef1 * aodp * betao2 * (eta * (2.0 + 0.5 * etasq)
            + eo * (0.5 + 2 * etasq)
            - 2 * CK2 * tsi / (aodp * psisq) * (-3 * x3thm1 * (1.0 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
            + 0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) * cos(2.0 * omegao)))
        c5 = 2.0 * coef1 * aodp * betao2 * (1.0 + 2.75 * (etasq + eeta) + eeta * etasq)
        let theta4 = sqr(theta2)
        let temp1 = 3.0 * CK2 * pinvsq * xnodp
        let temp2 = temp1 * CK2 * pinvsq
        let temp3 = 1.25 * CK4 * pinvsq * pinvsq * xnodp
        xmdot = xnodp + 0.5 * temp1 * betao * x3thm1
            + 0.0625 * temp2 * betao * (13.0 - 78.0 * theta2 + 137.0 * theta4)
        let x1m5th = 1.0 - 5.0 * theta2
        omgdot = -0.5 * temp1 * x1m5th
            + 0.0625 * temp2 * (7.0 - 114.0 * theta2 + 395.0 * theta4)
            + temp3 * (3.0 - 36.0 * theta2 + 49.0 * theta4)
        let xhdot1 = -temp1 * cosio
        xnodot = xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * theta2) + 2.0 * temp3 * (3.0 - 7.0 * theta2)) * cosio
        omgcof = bstar * c3 * cos(omegao)
        xmcof = -TWO_THIRDS * coef * bstar / eeta
        xnodcf = 3.5 * betao2 * xhdot1 * c1
        t2cof = 1.5 * c1
        xlcof = 0.125 * a3ovk2 * sinio * (3.0 + 5 * cosio) / (1.0 + cosio)
        aycof = 0.25 * a3ovk2 * sinio
        let xmo = data.xmo
        delmo = pow(1.0 + eta * cos(xmo), 3.0)
        sinmo = sin(xmo)
        x7thm1 = 7.0 * theta2 - 1.0
        if !sgp4Simple {
            let c1sq = sqr(c1)
            d2 = 4.0 * aodp * tsi * c1sq
            let temp = d2 * tsi * c1 / 3.0
            d3 = (17 * aodp + s4) * temp
            d4 = 0.5 * temp * aodp * tsi * (221 * aodp + 31 * s4) * c1
            t3cof = d2 + 2 * c1sq
            t4cof = 0.25 * (3.0 * d3 + c1 * (12 * d2 + 10 * c1sq))
            t5cof = 0.2 * (3.0 * d4 + 12 * c1 * d3 + 6 * d2 * d2 + 15 * c1sq * (2.0 * d2 + c1sq))
        } else {
            d2 = 0.0
            d3 = 0.0
            d4 = 0.0
            t3cof = 0.0
            t4cof = 0.0
            t5cof = 0.0
        }
    }

    /// Core SGP4 step. tsince is minutes since epoch.
    public func calculateSGP4(_ tsince: Double) {
        var tmp = [Double](repeating: 0.0, count: 9)
        let xmdf = data.xmo + xmdot * tsince
        let omgadf = data.omegao + omgdot * tsince
        let xnoddf = data.xnodeo + xnodot * tsince
        var omega = omgadf
        var xmp = xmdf
        let tsq = tsince * tsince
        let xnode = xnoddf + xnodcf * tsq
        let bstar = data.bstar
        var tempa = 1.0 - c1 * tsince
        var tempe = bstar * c4 * tsq
        var templ = t2cof * tsq
        if !sgp4Simple {
            let delomg = omgcof * tsince
            let delm = xmcof * (pow(1.0 + eta * cos(xmdf), 3.0) - delmo)
            tmp[0] = delomg + delm
            xmp = xmdf + tmp[0]
            omega = omgadf - tmp[0]
            let tcube = tsq * tsince
            let tfour = tsq * tcube
            tempa = tempa - d2 * tsq - d3 * tcube - d4 * tfour
            tempe += bstar * c5 * (sin(xmp) - sinmo)
            templ += t3cof * tcube + tfour * (t4cof + tsince * t5cof)
        }
        let a = aodp * tempa * tempa
        let eo = data.eccn
        let e = eo - tempe
        let xl = xmp + omega + xnode + xnodp * templ
        let beta = sqrt(1.0 - e * e)
        let xn = XKE / pow(a, 1.5)

        // Long period periodics
        let axn = e * cos(omega)
        tmp[0] = invert(a * sqr(beta))
        let xll = tmp[0] * xlcof * axn
        let aynl = tmp[0] * aycof
        let xlt = xl + xll
        let ayn = e * sin(omega) + aynl

        // Solve Kepler's equation
        let capu = mod2PI(xlt - xnode)
        tmp[2] = capu
        converge(&tmp, axn, ayn, capu)
        calculatePosAndVel(tmp, xnode, a, xn, axn, ayn)
        calculatePhase(xlt, xnode, omgadf)
    }

    private func calculatePosAndVel(_ tmp: [Double], _ xnode: Double, _ a: Double,
                                    _ xn: Double, _ axn: Double, _ ayn: Double) {
        let ecose = tmp[5] + tmp[6]
        let esine = tmp[3] - tmp[4]
        let elsq = sqr(axn) + sqr(ayn)
        let pl = a * (1.0 - elsq)
        let r = a * (1.0 - ecose)
        let invR = invert(r)
        let rdot = XKE * sqrt(a) * esine * invR
        let rfdot = XKE * sqrt(pl) * invR
        let betal = sqrt(1.0 - elsq)
        let t3 = invert(1.0 + betal)
        let cosu = (a * invR) * (tmp[8] - axn + ayn * esine * t3)
        let sinu = (a * invR) * (tmp[7] - ayn - axn * esine * t3)
        let u = atan2(sinu, cosu)
        let sin2u = 2.0 * sinu * cosu
        let cos2u = 2.0 * cosu * cosu - 1.0
        let plInv = invert(pl)
        let t1 = CK2 * plInv
        let t2 = t1 * plInv

        // Update for short periodics
        let rk = r * (1.0 - 1.5 * t2 * betal * x3thm1) + 0.5 * t1 * x1mth2 * cos2u
        let uk = u - 0.25 * t2 * x7thm1 * sin2u
        let xnodek = xnode + 1.5 * t2 * cosio * sin2u
        let xinck = data.xincl + 1.5 * t2 * cosio * sinio * cos2u
        let rdotk = rdot - xn * t1 * x1mth2 * sin2u
        let rfdotk = rfdot + xn * t1 * (x1mth2 * cos2u + 1.5 * x3thm1)

        super.calculatePosAndVel(rk, uk, xnodek, xinck, rdotk, rfdotk)
    }
}
