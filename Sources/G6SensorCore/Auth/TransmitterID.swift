//
//  TransmitterID.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit (Transmitter.swift / AESCrypt.m),
//  originally xDripG5, created by Nate Racklyeft on 6/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved. (MIT License)
//
//  The AES-128-ECB single-block encryption formerly lived in Objective-C
//  (AESCrypt.m); it is re-expressed here over CommonCrypto directly so the
//  package needs no bridging header.
//

import Foundation
import CommonCrypto

public struct TransmitterID {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    private var cryptKey: Data? {
        return "00\(id)00\(id)".data(using: .utf8)
    }

    /// Computes the authentication hash the transmitter expects for an
    /// 8-byte token or challenge: AES-128-ECB over the value repeated twice,
    /// truncated to the first 8 bytes of ciphertext.
    public func computeHash(of data: Data) -> Data? {
        guard data.count == 8, let key = cryptKey else {
            return nil
        }

        var doubleData = Data(capacity: data.count * 2)
        doubleData.append(data)
        doubleData.append(data)

        guard let outData = aesECBEncrypt(doubleData, key: key) else {
            return nil
        }

        return outData[0..<8]
    }

    private func aesECBEncrypt(_ data: Data, key: Data) -> Data? {
        var outData = Data(count: data.count + kCCBlockSizeAES128)
        let outLength = outData.count
        var movedBytes = 0

        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, key.count,
                        nil,
                        dataBytes.baseAddress, data.count,
                        outBytes.baseAddress, outLength,
                        &movedBytes
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            return nil
        }

        return outData.prefix(movedBytes)
    }
}
