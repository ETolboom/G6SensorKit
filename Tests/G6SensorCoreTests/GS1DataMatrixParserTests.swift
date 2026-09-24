//
//  GS1DataMatrixParserTests.swift
//  G6SensorKit
//
//  Ported from DexKit (DexKitTests/GS1DataMatrixParserTests.swift), trimmed
//  to G6 alongside the parser.
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import XCTest
@testable import G6SensorCore

/// Payloads follow the GS1 spec: a package Data Matrix = (01) GTIN,
/// (17) expiry, (10) lot, (21) serial, (240) additional product ID, with
/// FNC1 (\u{1D}) separating variable-length elements that aren't last.
final class GS1DataMatrixParserTests: XCTestCase {
    private let fnc1 = "\u{1D}"

    // MARK: - Basic element extraction

    /// Real payload from a public G7 box image: (01) GTIN, (11) production
    /// date, (17) expiry, (10) lot, (21) 12-char serial, (241) customer
    /// part number. Note the box carries no (240): the pairing/sensor code
    /// lives on the applicator label.
    private var g7BoxPayload: String {
        "01" + "00386270002839" + "11" + "230201" + "17" + "240731" +
            "10" + "1523041787" + fnc1 + "21" + "448421319350" + fnc1 + "241" + "STP-AT-012301"
    }

    func testParsesFullPayloadWithAIMPrefixAndFNC1() {
        // ]d2 = AIM symbology identifier for GS1 Data Matrix
        let elements = GS1DataMatrixParser.parse("]d2" + g7BoxPayload)
        XCTAssertEqual(elements, [
            GS1Element(ai: "01", value: "00386270002839"),
            GS1Element(ai: "11", value: "230201"),
            GS1Element(ai: "17", value: "240731"),
            GS1Element(ai: "10", value: "1523041787"),
            GS1Element(ai: "21", value: "448421319350"),
            GS1Element(ai: "241", value: "STP-AT-012301")
        ])
    }

    func testParsesPayloadWithoutAIMPrefix() {
        // VisionKit/Vision typically deliver the payload without "]d2".
        let scan = G6PackageScan(payload: g7BoxPayload)
        XCTAssertEqual(scan.gtin, "00386270002839")
        XCTAssertEqual(scan.serial, "448421319350")
        XCTAssertEqual(scan.value(forAI: "241"), "STP-AT-012301")
    }

    func testStripsLeadingFNC1() {
        // Some hardware scanners report the leading FNC1 of the first element.
        let scan = G6PackageScan(payload: fnc1 + g7BoxPayload)
        XCTAssertEqual(scan.gtin, "00386270002839")
        XCTAssertEqual(scan.serial, "448421319350")
    }

    // MARK: - Dexcom mapping

    func testG6PackageYieldsTransmitterIDCandidate() {
        // G6 transmitter box: (21) serial is the 6-char transmitter ID.
        let payload = "0100386270004070" + fnc1 + "218KAB12"
        let scan = G6PackageScan(payload: payload)

        XCTAssertTrue(scan.isDexcomPackage)
        XCTAssertEqual(scan.transmitterIDCandidate, "8KAB12")
    }

    func testSensorPackageYieldsNoTransmitterIDCandidate() {
        // G7 box (the public payload above): (21) is a 12-char sensor
        // serial, not a transmitter ID.
        let scan = G6PackageScan(payload: g7BoxPayload)

        XCTAssertTrue(scan.isDexcomPackage)
        XCTAssertNil(scan.transmitterIDCandidate)
        XCTAssertNil(scan.sensorCodeCandidate) // the box carries no (240)
    }

    func testFNC1StrippedG7BoxYieldsNoCandidates() {
        // The same public payload as scanners and pastes deliver it without
        // separators: the dates still parse, nothing G6-usable falls out.
        let payload = "0100386270002839112302011724073110152304178721448421319350241STP-AT-012301"
        let scan = G6PackageScan(payload: payload)

        XCTAssertTrue(scan.isDexcomPackage)
        XCTAssertEqual(scan.value(forAI: "11"), "230201")
        XCTAssertEqual(scan.value(forAI: "17"), "240731")
        XCTAssertNil(scan.transmitterIDCandidate)
        XCTAssertNil(scan.sensorCodeCandidate)
    }

    func testLowercaseSerialIsUppercased() {
        let scan = G6PackageScan(payload: "0100386270004070" + fnc1 + "218kab12")
        XCTAssertEqual(scan.transmitterIDCandidate, "8KAB12")
    }

    func testNonDexcomGTINIsFlagged() {
        // Another manufacturer's package: same GS1 shape, different company prefix.
        let payload = "01" + "06991234567890" + fnc1 + "10LOT123" + fnc1 + "21991234ABCD5678"
        let scan = G6PackageScan(payload: payload)
        XCTAssertFalse(scan.isDexcomPackage)
        XCTAssertEqual(scan.gtin, "06991234567890")
        XCTAssertEqual(scan.lot, "LOT123")
        XCTAssertEqual(scan.serial, "991234ABCD5678")
        XCTAssertNil(scan.transmitterIDCandidate)
    }

    // MARK: - G6 applicator sensor codes

    // The applicator payloads below are real, public G6 labels; the
    // transmitter/sensor box structures mirror our own captures with
    // serials, lots and dates anonymized.

    func testApplicatorYieldsSensorCodeCandidate() {
        // Real public applicator labels: (10) 16-char lot glued to
        // (240) + the 4-digit sensor code, FNC1 separators stripped.
        let cases: [(payload: String, code: String)] = [
            ("10731863521434687D2405937", "5937"),
            ("10527390421846477D2405931", "5931"),
            ("10729148021365863F2409117", "9117")
        ]
        for (payload, code) in cases {
            let scan = G6PackageScan(payload: payload)
            XCTAssertEqual(scan.sensorCodeCandidate, code, payload)
            XCTAssertNotNil(SensorCode(scan.sensorCodeCandidate), payload)
            // No GTIN and no (21): an applicator label says nothing about the transmitter.
            XCTAssertNil(scan.transmitterIDCandidate, payload)
            XCTAssertFalse(scan.isDexcomPackage, payload)
        }
    }

    func testApplicatorWithFNC1YieldsSensorCodeCandidate() {
        let payload = "10" + "731863521434687D" + fnc1 + "2405937"
        let scan = G6PackageScan(payload: payload)
        XCTAssertEqual(scan.lot, "731863521434687D")
        XCTAssertEqual(scan.sensorCodeCandidate, "5937")
    }

    func testApplicatorTailMustBeExactlyFourDigits() {
        // "240" followed by 5 digits is not a sensor code.
        let scan = G6PackageScan(payload: "10731863521434687D24059377")
        XCTAssertNil(scan.sensorCodeCandidate)
    }

    func testTransmitterBoxSerialWithTrailingPackagingData() {
        // Transmitter box: (21) is the 6-char ID glued to "-<batch/date>".
        let payload = "0100386270003072" + "241STT-GS-003" + fnc1 +
            "10AB12CD34" + fnc1 + "218ZXY12-199270101"
        let scan = G6PackageScan(payload: payload)

        XCTAssertTrue(scan.isDexcomPackage)
        XCTAssertEqual(scan.transmitterIDCandidate, "8ZXY12")
        XCTAssertNil(scan.sensorCodeCandidate)
    }

    func testFNC1StrippedTransmitterBoxYieldsTransmitterID() {
        // Same box with every FNC1 stripped: the strict parse cannot
        // segment past (241), so the raw-payload fallback recovers the ID.
        let payload = "0100386270003072241STT-GS-00310AB12CD34218ZXY12-199270101"
        let scan = G6PackageScan(payload: payload)

        XCTAssertTrue(scan.isDexcomPackage)
        XCTAssertEqual(scan.transmitterIDCandidate, "8ZXY12")
    }

    func testTransmitterBoxSerialOnlyBarcode() {
        // Real public G6 transmitter box: the small Data Matrix carries
        // only (21) + the 6-char transmitter ID.
        let scan = G6PackageScan(payload: "2188H03B")

        XCTAssertEqual(scan.transmitterIDCandidate, "88H03B")
        XCTAssertNil(scan.sensorCodeCandidate)
        XCTAssertFalse(scan.isDexcomPackage)
    }

    func testTransmitterBoxFullDataMatrix() {
        // Same box's large Data Matrix: (241) customer part number, (10)
        // lot, (21) serial, (17) expiry. The GTIN is a separate linear
        // barcode on the box, so no (01) appears here.
        let payload = "241STT-OM-001" + fnc1 + "1018038762" + fnc1 + "2188H03B" + fnc1 + "17250226"
        let scan = G6PackageScan(payload: payload)

        XCTAssertEqual(scan.elements, [
            GS1Element(ai: "241", value: "STT-OM-001"),
            GS1Element(ai: "10", value: "18038762"),
            GS1Element(ai: "21", value: "88H03B"),
            GS1Element(ai: "17", value: "250226")
        ])
        XCTAssertEqual(scan.transmitterIDCandidate, "88H03B")
        XCTAssertNil(scan.sensorCodeCandidate)
        XCTAssertFalse(scan.isDexcomPackage)
    }

    func testSensorBoxYieldsNoCandidates() {
        // Sensor box: GTIN, customer part number, dates; no code at all.
        // The sensor code is only on the applicator label.
        let payload = "0100386270000927" + "2419500-46107380885" + "11251207" + "17270630"
        let scan = G6PackageScan(payload: payload)

        XCTAssertTrue(scan.isDexcomPackage)
        XCTAssertNil(scan.transmitterIDCandidate)
        XCTAssertNil(scan.sensorCodeCandidate)
    }

    // MARK: - Robustness

    func testVariableLengthSerialAtEndOfPayloadWithoutFNC1() {
        let payload = "0100386270004758" + fnc1 + "21ABCD12345678"
        XCTAssertEqual(GS1DataMatrixParser.parse(payload).last,
                       GS1Element(ai: "21", value: "ABCD12345678"))
    }

    func testStopsAtUnknownAIKeepingParsedPrefix() {
        // (99) is not in the registry; parsing stops but keeps (01) and (21).
        let payload = "0100386270004758" + fnc1 + "218KAB12" + fnc1 + "99JUNK"
        let elements = GS1DataMatrixParser.parse(payload)
        XCTAssertEqual(elements, [
            GS1Element(ai: "01", value: "00386270004758"),
            GS1Element(ai: "21", value: "8KAB12")
        ])
    }

    func testTruncatedFixedLengthFieldStopsParsing() {
        let payload = "0100386" // truncated GTIN
        XCTAssertTrue(GS1DataMatrixParser.parse(payload).isEmpty)
    }

    func testGarbageYieldsNoElements() {
        XCTAssertTrue(GS1DataMatrixParser.parse("hello world").isEmpty)
        XCTAssertTrue(GS1DataMatrixParser.parse("").isEmpty)
    }

    func testFourDigitAIIsNotMisreadAsTwoDigitAI() {
        // "240..." must read as AI 240, not AI 24 + garbage.
        let payload = "0100386270004758" + fnc1 + "2401249"
        XCTAssertEqual(GS1DataMatrixParser.parse(payload).last,
                       GS1Element(ai: "240", value: "1249"))
    }
}
