//
//  CalibrationDataRxMessageTests.swift
//  xDripG5
//
//  Created by Nate Racklyeft on 9/18/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import G6SensorCore


class CalibrationDataRxMessageTests: XCTestCase {
    
    func testMessage() {
        let data = Data(hexadecimalString: "33002b290090012900ae00800050e929001225")!
        XCTAssertNotNil(CalibrationDataRxMessage(data: data))
    }
    
}
