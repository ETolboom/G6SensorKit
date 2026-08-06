//
//  G6SensorKitPlugin.swift
//  G6SensorKitPlugin
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Principal class Loop instantiates after dlopening the plugin bundle.
//  Must be ObjC-instantiable via init() and conform to CGMManagerUIPlugin;
//  Loop calls fatalError otherwise.
//

import LoopKitUI
import G6SensorKit
import G6SensorKitUI
import os.log

public final class G6SensorKitPlugin: NSObject, CGMManagerUIPlugin {
    private let log = Logger(subsystem: "org.nightscout.G6SensorKit", category: "G6SensorKitPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        return nil
    }

    public var cgmManagerType: CGMManagerUI.Type? {
        return G6CGMManager.self
    }

    public override init() {
        super.init()
        log.debug("G6SensorKitPlugin instantiated")
    }
}
