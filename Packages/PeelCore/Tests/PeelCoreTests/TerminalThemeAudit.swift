import Foundation
@testable import PeelCore

enum TerminalThemeAudit {
    static let chromatic = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14]
    static let huePairs = [(1, 5), (1, 3), (1, 2), (2, 3), (2, 6), (4, 6), (4, 5)]

    static func issues(of theme: TerminalTheme) -> [String] {
        let ansi = theme.ansi
        let worst = worstBackground(theme.background)
        func lc(_ color: UInt32) -> Double {
            min(apcaLc(color, on: theme.background), apcaLc(color, on: worst))
        }
        var issues: [String] = []
        func expect(_ passes: Bool, _ issue: @autoclosure () -> String) {
            if !passes { issues.append(issue()) }
        }

        expect(lc(theme.text) >= 75, "text Lc \(lc(theme.text))")
        for slot in chromatic {
            expect(lc(ansi[slot]) >= 45, "ANSI \(slot) Lc \(lc(ansi[slot]))")
        }
        expect(lc(ansi[7]) >= 75, "white Lc \(lc(ansi[7]))")
        expect(lc(ansi[15]) >= lc(ansi[7]), "bright white is dimmer than white")
        expect((30...60).contains(lc(ansi[8])), "bright black Lc \(lc(ansi[8]))")
        expect(deltaE(ansi[0], theme.background) >= 3, "black is lost on the background")
        for slot in 1...7 {
            expect(lc(ansi[slot + 8]) >= lc(ansi[slot]) - 0.5, "ANSI \(slot + 8) is dimmer than ANSI \(slot)")
            expect(deltaE(ansi[slot], ansi[slot + 8]) >= 5, "ANSI \(slot) and \(slot + 8) look alike")
        }
        for (first, second) in huePairs {
            expect(deltaE(ansi[first], ansi[second]) >= 15, "ANSI \(first) and \(second) look alike")
        }
        expect(colorBlindDifference(ansi[1], ansi[2]) >= 10, "red and green look alike to someone color blind")
        expect(apcaLc(theme.text, on: theme.selection) >= 75, "text on the selection Lc \(apcaLc(theme.text, on: theme.selection))")
        expect(deltaE(theme.selection, theme.background) >= 6, "the selection is lost on the background")
        expect(lc(theme.cursor) >= 45, "cursor Lc \(lc(theme.cursor))")
        expect(apcaLc(theme.background, on: theme.cursor) >= 45, "the letter under the cursor is hard to read")
        for slot in 1...6 {
            let best = max(
                apcaLc(theme.text, on: ansi[slot]),
                apcaLc(ansi[0], on: ansi[slot]),
                apcaLc(theme.background, on: ansi[slot])
            )
            expect(best >= 45, "no text reads on ANSI \(slot)")
        }
        return issues
    }

    static func meanDifference(_ first: TerminalTheme, _ second: TerminalTheme) -> Double {
        let firstColors = [first.background] + first.ansi
        let secondColors = [second.background] + second.ansi
        return zip(firstColors, secondColors).map { deltaE($0, $1) }.reduce(0, +) / Double(firstColors.count)
    }

    static func channels(_ color: UInt32) -> [Double] {
        [Double(color >> 16 & 0xFF), Double(color >> 8 & 0xFF), Double(color & 0xFF)]
    }

    static func packed(_ channels: [Double]) -> UInt32 {
        channels.map { UInt32($0.rounded()) }.reduce(0) { $0 << 8 | $1 }
    }

    static func worstBackground(_ background: UInt32) -> UInt32 {
        packed(channels(background).map { $0 + (255 - $0) * 0.05 })
    }

    static func apcaLuminance(_ color: UInt32) -> Double {
        let weights = [0.2126729, 0.7151522, 0.0721750]
        let luminance = zip(channels(color), weights).map { pow($0 / 255, 2.4) * $1 }.reduce(0, +)
        return luminance < 0.022 ? luminance + pow(0.022 - luminance, 1.414) : luminance
    }

    static func apcaLc(_ text: UInt32, on background: UInt32) -> Double {
        let textLuminance = apcaLuminance(text)
        let backgroundLuminance = apcaLuminance(background)
        guard abs(backgroundLuminance - textLuminance) >= 0.0005 else { return 0 }
        if backgroundLuminance > textLuminance {
            let contrast = (pow(backgroundLuminance, 0.56) - pow(textLuminance, 0.57)) * 1.14
            return contrast < 0.1 ? 0 : (contrast - 0.027) * 100
        }
        let contrast = (pow(backgroundLuminance, 0.65) - pow(textLuminance, 0.62)) * 1.14
        return contrast > -0.1 ? 0 : -(contrast + 0.027) * 100
    }

    static func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func lab(_ color: UInt32) -> (lightness: Double, a: Double, b: Double) {
        let rgb = channels(color).map { linear($0 / 255) }
        let x = (rgb[0] * 0.4124 + rgb[1] * 0.3576 + rgb[2] * 0.1805) / 0.95047
        let y = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
        let z = (rgb[0] * 0.0193 + rgb[1] * 0.1192 + rgb[2] * 0.9505) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    static func deltaE(_ first: UInt32, _ second: UInt32) -> Double {
        let (l1, a1, b1) = lab(first)
        let (l2, a2, b2) = lab(second)
        let radians = Double.pi / 180
        let chromaMean = (hypot(a1, b1) + hypot(a2, b2)) / 2
        let g = 0.5 * (1 - (pow(chromaMean, 7) / (pow(chromaMean, 7) + pow(25, 7))).squareRoot())
        let a1Prime = (1 + g) * a1
        let a2Prime = (1 + g) * a2
        let c1 = hypot(a1Prime, b1)
        let c2 = hypot(a2Prime, b2)
        func hue(_ b: Double, _ a: Double) -> Double {
            guard b != 0 || a != 0 else { return 0 }
            let degrees = atan2(b, a) / radians
            return degrees >= 0 ? degrees : degrees + 360
        }
        let h1 = hue(b1, a1Prime)
        let h2 = hue(b2, a2Prime)
        var hueDifference = 0.0
        if c1 * c2 != 0 {
            hueDifference = h2 - h1
            if hueDifference > 180 { hueDifference -= 360 } else if hueDifference < -180 { hueDifference += 360 }
        }
        let deltaL = l2 - l1
        let deltaC = c2 - c1
        let deltaH = 2 * (c1 * c2).squareRoot() * sin(hueDifference * radians / 2)
        let lightnessMean = (l1 + l2) / 2
        let chromaPrimeMean = (c1 + c2) / 2
        var hueMean = h1 + h2
        if c1 * c2 != 0 {
            if abs(h1 - h2) <= 180 {
                hueMean /= 2
            } else {
                hueMean = hueMean < 360 ? (hueMean + 360) / 2 : (hueMean - 360) / 2
            }
        }
        let t = 1 - 0.17 * cos((hueMean - 30) * radians) + 0.24 * cos(2 * hueMean * radians)
            + 0.32 * cos((3 * hueMean + 6) * radians) - 0.2 * cos((4 * hueMean - 63) * radians)
        let sl = 1 + 0.015 * pow(lightnessMean - 50, 2) / (20 + pow(lightnessMean - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * chromaPrimeMean
        let sh = 1 + 0.015 * chromaPrimeMean * t
        let rt = -2 * (pow(chromaPrimeMean, 7) / (pow(chromaPrimeMean, 7) + pow(25, 7))).squareRoot()
            * sin(60 * exp(-pow((hueMean - 275) / 25, 2)) * radians)
        return (pow(deltaL / sl, 2) + pow(deltaC / sc, 2) + pow(deltaH / sh, 2) + rt * (deltaC / sc) * (deltaH / sh))
            .squareRoot()
    }

    static func colorBlind(_ color: UInt32, protanopia: Bool) -> UInt32 {
        let rgb = channels(color).map { linear($0 / 255) }
        let long = 17.8824 * rgb[0] + 43.5161 * rgb[1] + 4.11935 * rgb[2]
        let medium = 3.45565 * rgb[0] + 27.1554 * rgb[1] + 3.86714 * rgb[2]
        let short = 0.0299566 * rgb[0] + 0.184309 * rgb[1] + 1.46709 * rgb[2]
        let seenLong = protanopia ? 2.02344 * medium - 2.52581 * short : long
        let seenMedium = protanopia ? medium : 0.494207 * long + 1.24827 * short
        let seen = [
            0.080944 * seenLong - 0.130504 * seenMedium + 0.116721 * short,
            -0.0102485 * seenLong + 0.0540194 * seenMedium - 0.113615 * short,
            -0.000365294 * seenLong - 0.00412163 * seenMedium + 0.693513 * short,
        ]
        return packed(seen.map { value in
            let clamped = min(1, max(0, value))
            let encoded = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
            return min(1, max(0, encoded)) * 255
        })
    }

    static func colorBlindDifference(_ first: UInt32, _ second: UInt32) -> Double {
        min(
            deltaE(colorBlind(first, protanopia: false), colorBlind(second, protanopia: false)),
            deltaE(colorBlind(first, protanopia: true), colorBlind(second, protanopia: true))
        )
    }
}
