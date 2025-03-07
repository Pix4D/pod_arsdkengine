// Copyright (C) 2019 Parrot Drones SAS
//
//    Redistribution and use in source and binary forms, with or without
//    modification, are permitted provided that the following conditions
//    are met:
//    * Redistributions of source code must retain the above copyright
//      notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above copyright
//      notice, this list of conditions and the following disclaimer in
//      the documentation and/or other materials provided with the
//      distribution.
//    * Neither the name of the Parrot Company nor the names
//      of its contributors may be used to endorse or promote products
//      derived from this software without specific prior written
//      permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//    PARROT COMPANY BE LIABLE FOR ANY DIRECT, INDIRECT,
//    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//    OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
//    AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
//    OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
//    SUCH DAMAGE.

import Foundation
import GroundSdk

/// Gimbal component controller for Gimbal feature message based drones
class GimbalFeatureGimbal: GimbalFeatureCalibratableGimbal {

    /// Component settings key
    private static let settingKey = "Gimbal-main"

    /// Gimbal control command encoder.
    private class GimbalControlCommandEncoder: NoAckCmdEncoder {
        let type = ArsdkNoAckCmdType.gimbalControl

        /// Max number of time the command should be sent with the same value
        let maxRepeatedSent = 10

        /// Queue used to dispatch messages on it in order to ensure synchronization between main queue and pomp loop.
        /// All synchronized variables of this object must be accessed (read and write) in this queue
        private let queue = DispatchQueue(label: "com.parrot.gimbal.encoder")

        // synchronized vars
        /// Whether encoding a message is allowed.
        /// both valueAttitudeReceivedFirstTimeInternalEncoder & valuesAtittudeChangedByUserInternalEncoder needs
        /// to be true
        /// boolean to check if if attitude was received a first time
        private var valueAttitudeReceivedFirstTimeInternalEncoder = false
        /// boolean to check if value of attitude has been changed by user
        private var encoderValuesUpdated = false
        /// Desired control mode
        private var controlModeInternalEncoder = ArsdkFeatureGimbalControlMode.position
        /// Set of desired stabilized axes
        private var stabilizationsInternalEncoder: [GimbalAxis: Bool] = [:]
        /// Desired targets. Value for an axis is nil if this axis should not be controlled
        private var targetInternalEncoder: [GimbalAxis: Double] = [:]
        /// Whether ongoing gimbal control commands are cancelled.
        private var controlCancelled = false

        // pomp loop only vars
        private var latestControlModeInternalEncoder = ArsdkFeatureGimbalControlMode.position
        private var latestStabilizationsInternalEncoder: [GimbalAxis: Bool] = [:]
        private var latestTargetInternalEncoder: [GimbalAxis: Double] = [:]

        /// Number of time the same command has been sent
        private var sentCnt = -1

        var encoder: () -> (ArsdkCommandEncoder?) {
            return encoderBlock
        }

        /// Encoder of the current piloting command that should be sent to the device.
        private var encoderBlock: (() -> (ArsdkCommandEncoder?))!

        /// Constructor
        init() {
            encoderBlock = { [unowned self] in
                // Note: this code will be called in the pomp loop

                var controlMode = ArsdkFeatureGimbalControlMode.position
                var stabilizations: [GimbalAxis: Bool] = [:]
                var target: [GimbalAxis: Double] = [:]
                var valueAttitudeReceivedFirstTime = false
                var valuesAtittudeChangedByUser = false
                var cancelled = false
                // set the local var in a synchronized queue
                self.queue.sync {
                    controlMode = controlModeInternalEncoder
                    stabilizations = stabilizationsInternalEncoder
                    target = targetInternalEncoder
                    valueAttitudeReceivedFirstTime = valueAttitudeReceivedFirstTimeInternalEncoder
                    valuesAtittudeChangedByUser = encoderValuesUpdated
                    cancelled = controlCancelled
                }

                /// if no new value has been set by user after connection to drone, we return immediately.
                guard valueAttitudeReceivedFirstTime && valuesAtittudeChangedByUser else {
                    return nil
                }

                if cancelled {
                    latestControlModeInternalEncoder = .position
                    latestStabilizationsInternalEncoder = [:]
                    latestTargetInternalEncoder = [:]
                    return nil
                }

                // if control, target or stabilization has changed
                if latestControlModeInternalEncoder != controlMode ||
                    latestStabilizationsInternalEncoder != stabilizations ||
                    latestTargetInternalEncoder != target {

                    latestControlModeInternalEncoder = controlMode
                    latestStabilizationsInternalEncoder = stabilizations
                    latestTargetInternalEncoder = target
                    sentCnt = maxRepeatedSent
                }

                let allTargetsAreZero = (target.values.reduce(0.0, +) == 0)
                // only decrement the counter if the control is in position,
                // or, if the control is in velocity and all velocity targets are null or zero
                if sentCnt >= 0 && (controlMode == .position || allTargetsAreZero) {
                    sentCnt -= 1
                }

                // if sendCnt is under 0, command is not sent
                if sentCnt >= 0 {
                    var frameOfReferences: [GimbalAxis: ArsdkFeatureGimbalFrameOfReference] = [:]
                    GimbalAxis.allCases.forEach {
                        if let stabilization = stabilizations[$0], target[$0] != nil {
                            frameOfReferences[$0] = stabilization ? .absolute : .relative
                        } else {
                            frameOfReferences[$0] = ArsdkFeatureGimbalFrameOfReference.none
                        }
                    }
                    return ArsdkFeatureGimbal.setTargetEncoder(
                        gimbalId: 0,
                        controlMode: controlMode,
                        yawFrameOfReference: frameOfReferences[.yaw]!,
                        yaw: Float(target[.yaw] ?? 0),
                        pitchFrameOfReference: frameOfReferences[.pitch]!,
                        pitch: Float(target[.pitch] ?? 0),
                        rollFrameOfReference: frameOfReferences[.roll]!,
                        roll: Float(target[.roll] ?? 0))
                }
                return nil
            }
        }

        /// Control the gimbal
        ///
        /// - Parameters:
        ///   - mode: control mode
        ///   - yaw: yaw target, nil if yaw should not be changed
        ///   - pitch: pitch target, nil if pitch should not be changed
        ///   - roll: roll target, nil if roll should not be changed
        func control(mode: GimbalControlMode, yaw: Double?, pitch: Double?, roll: Double?) {
            queue.sync {
                controlCancelled = false
                controlModeInternalEncoder = mode.arsdkValue!
                targetInternalEncoder[.yaw] = yaw
                targetInternalEncoder[.pitch] = pitch
                targetInternalEncoder[.roll] = roll
                encoderValuesUpdated = true
            }
        }

        /// Set the stabilization on a given axis.
        ///
        /// - Parameters:
        ///   - stabilization: the new stabilization
        ///   - targetAttitude: the target to set in the new frame of reference. If nil, new stabilization will only be
        ///     sent when a target for this axis will be set.
        ///   - axis: the axis
        func set(stabilization: Bool, targetAttitude: Double?, onAxis axis: GimbalAxis) {
            queue.sync {
                controlCancelled = false
                stabilizationsInternalEncoder[axis] = stabilization
                if valueAttitudeReceivedFirstTimeInternalEncoder {
                    GimbalAxis.allCases.forEach {
                        if stabilizationsInternalEncoder[$0] == nil {
                            stabilizationsInternalEncoder[$0] = latestStabilizationsInternalEncoder[$0]
                        }
                    }
                }

                if controlModeInternalEncoder == .position {
                    targetInternalEncoder[axis] = targetAttitude
                } else if targetInternalEncoder[axis] == nil {
                    // if the control is in velocity and the target in nil, replace it with 0 to be sure to send the
                    // stab change
                    targetInternalEncoder[axis] = 0
                }
                encoderValuesUpdated = true
            }
        }

        /// Sets the initial stabilizations.
        ///
        /// - Parameter stabilizations: initial stabilizations
        func setInitialStabilizations(_ stabilizations: [GimbalAxis: Bool]) {
            queue.sync {
                controlCancelled = false
                latestControlModeInternalEncoder = .position
                latestStabilizationsInternalEncoder = stabilizations
                GimbalAxis.allCases.forEach {
                    if self.stabilizationsInternalEncoder[$0] == nil {
                        self.stabilizationsInternalEncoder[$0] = latestStabilizationsInternalEncoder[$0]
                    }
                }
                valueAttitudeReceivedFirstTimeInternalEncoder = true
            }
        }

        /// Cancels ongoing gimbal control commands, if any.
        func cancelControl() {
            queue.sync {
                controlCancelled = true
            }
        }

        func reset() {
            queue.sync {
                controlCancelled = false
                stabilizationsInternalEncoder = [:]
                latestStabilizationsInternalEncoder = [:]
                targetInternalEncoder = [:]
                latestTargetInternalEncoder = [:]
                latestControlModeInternalEncoder = .position
                controlModeInternalEncoder = .position
                valueAttitudeReceivedFirstTimeInternalEncoder = false
                encoderValuesUpdated = false
                sentCnt = -1
            }
        }
    }

    /// Main Gimbal component
    var gimbalMain: GimbalCore {
        get {
            return gimbal as! GimbalCore
        }
        set {
            gimbal = newValue
        }
    }

    /// Store device specific values
    private let deviceStore: SettingsStore?
    /// Preset store for this piloting interface
    private var presetStore: SettingsStore?

    /// True when gimbal capabilities have been received
    private var capabilitiesReceived = false
    private var attitudeReceived = false

    /// All settings that can be stored
    enum SettingKey: String, StoreKey {
        case supportedAxesKey = "supportedAxes"
        case maxSpeedsKey = "maxSpeeds"
        case stabilizedAxesKey = "stabilizedAxes"
    }

    /// Stored settings
    enum Setting: Hashable {
        case maxSpeeds([GimbalAxis: (min: Double, current: Double, max: Double)])
        case stabilizedAxes(Set<GimbalAxis>)
        /// Setting storage key
        var key: SettingKey {
            switch self {
            case .maxSpeeds: return .maxSpeedsKey
            case .stabilizedAxes: return .stabilizedAxesKey
            }
        }

        /// All values to allow enumerating settings
        static let allCases: Set<Setting> = [
            .maxSpeeds([:]),
            .stabilizedAxes([])
        ]

        func hash(into hasher: inout Hasher) {
            hasher.combine(key)
        }

        static func == (lhs: Setting, rhs: Setting) -> Bool {
            return lhs.key == rhs.key
        }
    }

    /// Stored capabilities for settings
    enum Capabilities: Hashable {
        case supportedAxes(Set<GimbalAxis>)

        /// All values to allow enumerating capabilities
        static let allCases: Set<Capabilities> = [
            .supportedAxes([])
        ]

        /// Capabilities storage key
        var key: SettingKey {
            switch self {
            case .supportedAxes: return .supportedAxesKey
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(key)
        }
    }

    /// Setting values as received from the drone
    private var droneSettings = Set<Setting>()

    /// Encoder of the gimbal control command
    private let controlEncoder = GimbalControlCommandEncoder()
    private var controlEncoderRegistration: RegisteredNoAckCmdEncoder?

    // cache vars
    private var expectedStabilization = [GimbalAxis: Bool]()// always contains info about supported axes
    private var pendingStabilizationChange = Set<GimbalAxis>()
    private var absoluteAttitude = [GimbalAxis: Double]()
    private var relativeAttitude = [GimbalAxis: Double]()
    private var absoluteAttitudeBounds = [GimbalAxis: Range<Double>]()
    private var relativeAttitudeBounds = [GimbalAxis: Range<Double>]()

    /// Constructor
    ///
    /// - Parameter deviceController: device controller owning this component controller (weak)
    init(deviceController: DeviceController) {
        if GroundSdkConfig.sharedInstance.offlineSettings == .off {
            deviceStore = nil
            presetStore = nil
        } else {
            deviceStore = deviceController.deviceStore.getSettingsStore(key: GimbalFeatureGimbal.settingKey)
            presetStore = deviceController.presetStore.getSettingsStore(key: GimbalFeatureGimbal.settingKey)
        }
        super.init(deviceController: deviceController, model: .main)
        gimbal = GimbalCore(store: deviceController.device.peripheralStore, backend: self)

        // load settings
        if let deviceStore = deviceStore, let presetStore = presetStore, !deviceStore.new && !presetStore.new {
            loadCapabilities()
            loadPresets()
            gimbalMain.publish()
        }
    }

    /// Drone is connected
    override func didConnect() {
        storeNewPresets()
        applyPresets()
        gimbalMain.publish()

        if let backend = deviceController.backend {
            controlEncoderRegistration = backend.subscribeNoAckCommandEncoder(encoder: controlEncoder)
        }
        super.didConnect()
    }

    /// Drone is disconnected
    override func didDisconnect() {
        // clear all non saved settings
        gimbalMain.update(lockedAxes: GimbalAxis.allCases)
            .cancelSettingsRollback()
        GimbalAxis.allCases.forEach {
            gimbalMain.update(absoluteAttitude: nil, onAxis: $0)
                .update(relativeAttitude: nil, onAxis: $0)
                .update(axisBounds: nil, onAxis: $0)
        }
        pendingStabilizationChange = []
        absoluteAttitude = [:]
        relativeAttitude = [:]
        absoluteAttitudeBounds = [:]
        relativeAttitudeBounds = [:]
        capabilitiesReceived = false
        attitudeReceived = false

        controlEncoderRegistration?.unregister()
        controlEncoderRegistration = nil
        controlEncoder.reset()

        gimbalMain.update(offsetsCorrectionProcessStarted: false)

        // empty the calibatable axes
        gimbalMain.update(calibratableAxes: [])

        super.didDisconnect()
        gimbalMain.notifyUpdated()
    }

    /// Drone is about to be forgotten
    override func willForget() {
        deviceStore?.clear()
        super.willForget()
    }

    /// Preset has been changed
    override func presetDidChange() {
        super.presetDidChange()
        // reload preset store
        presetStore = deviceController.presetStore.getSettingsStore(key: GimbalFeatureGimbal.settingKey)
        loadCapabilities()
        loadPresets()
        if connected {
            applyPresets()
        }
    }

    /// Load the capabilities
    /// Should be called before `loadPreset()`.
    private func loadCapabilities() {
        if let deviceStore = deviceStore {
            for capability in Capabilities.allCases {
                switch capability {
                case .supportedAxes:
                    if let supportedAxes: StorableArray<GimbalAxis> = deviceStore.read(key: capability.key) {
                        gimbalMain.update(supportedAxes: Set(supportedAxes.storableValue))
                    }
                }
            }
            gimbalMain.notifyUpdated()
        }
    }

    /// Load saved settings
    private func loadPresets() {
        if let presetStore = presetStore, let deviceStore = deviceStore {
            for setting in Setting.allCases {
                switch setting {
                case .maxSpeeds:
                    if let currentMaxSpeeds: StorableDict<GimbalAxis, Double> = presetStore.read(key: setting.key),
                        let maxSpeedRanges: [GimbalAxis: (min: Double, max: Double)] =
                        deviceStore.readMultiRange(key: setting.key) {

                        maxSpeedRanges.forEach { axis, range in
                            if let currentVal = currentMaxSpeeds.storableValue[axis] {
                                gimbalMain.update(maxSpeedSetting: (range.min, currentVal, range.max), onAxis: axis)
                            }
                        }
                    }
                case .stabilizedAxes:
                    if let stabilizedAxes: StorableArray<GimbalAxis> = presetStore.read(key: setting.key) {
                        GimbalAxis.allCases.forEach { axis in
                            if gimbalMain.supportedAxes.contains(axis) {
                                let isStabilized = stabilizedAxes.storableValue.contains(axis)
                                expectedStabilization[axis] = isStabilized
                                controlEncoder.set(stabilization: isStabilized, targetAttitude: nil, onAxis: axis)
                                gimbalMain.update(stabilization: isStabilized, onAxis: axis)
                            }
                        }
                    }
                }
            }
            gimbalMain.notifyUpdated()
        }
    }

    /// Called when the drone is connected, save all received settings ranges
    private func storeNewPresets() {
        if let deviceStore = deviceStore {
            for setting in droneSettings {
                switch setting {
                case .maxSpeeds(let maxSpeeds):
                    // write in the device store the max speed range indexed by axis
                    deviceStore.writeMultiRange(
                        key: setting.key,
                        value: Dictionary(
                            uniqueKeysWithValues: maxSpeeds.map { ($0.key, ($0.value.min, $0.value.max)) }))
                case .stabilizedAxes:
                    break
                }
            }
            deviceStore.commit()
        }
    }

    /// Apply a preset
    ///
    /// Iterate settings received during connection
    private func applyPresets() {
        // iterate settings received during the connection
        for setting in droneSettings {
            switch setting {
            case .maxSpeeds(let maxSpeeds):
                if let storedMaxSpeeds: StorableDict<GimbalAxis, Double> = presetStore?.read(key: setting.key) {
                    // dictionary of max speed that differs between what the user wants and what the drone has
                    var speedToOverride: [GimbalAxis: Double] = [:]

                    storedMaxSpeeds.storableValue.forEach { axis, storedMaxSpeed in
                        let currentMaxSpeed = maxSpeeds[axis]

                        if currentMaxSpeed?.current != storedMaxSpeed {
                            speedToOverride[axis] = storedMaxSpeed
                        }
                        gimbalMain.update(
                            maxSpeedSetting: (currentMaxSpeed?.min, storedMaxSpeed, currentMaxSpeed?.max), onAxis: axis)
                    }

                    // send all values to override (if there is at least one value to override)
                    if !speedToOverride.isEmpty {
                        sendCommand(ArsdkFeatureGimbal.setMaxSpeedEncoder(
                            gimbalId: 0,
                            yaw: Float(speedToOverride[.yaw] ?? maxSpeeds[.yaw]!.current),
                            pitch: Float(speedToOverride[.pitch] ?? maxSpeeds[.pitch]!.current),
                            roll: Float(speedToOverride[.roll] ?? maxSpeeds[.roll]!.current)))
                    }
                } else {
                    maxSpeeds.forEach { gimbalMain.update(maxSpeedSetting: $1, onAxis: $0) }
                }
            case .stabilizedAxes(let stabilizedAxes):
                if let storedStabilizedAxes: StorableArray<GimbalAxis> = presetStore?.read(key: setting.key) {
                    gimbalMain.supportedAxes.forEach { axis in
                        let storedStab = storedStabilizedAxes.storableValue.contains(axis)
                        let targetAttitude: Double
                        if let bounds = storedStab ? absoluteAttitudeBounds[axis] : relativeAttitudeBounds[axis] {
                            if let currentAttitude = storedStab ? absoluteAttitude[axis] : relativeAttitude[axis] {
                                // if range and current attitude is known, the target attitude is the current
                                // attitude clamped into the range
                                targetAttitude = bounds.clamp(currentAttitude)
                            } else {
                                // if no current attitude, take the mid-range
                                targetAttitude = (bounds.upperBound + bounds.lowerBound) / 2.0
                            }
                        } else {
                            targetAttitude = 0
                        }

                        controlEncoder.set(
                            stabilization: storedStab,
                            targetAttitude: targetAttitude,
                            onAxis: axis)
                        gimbalMain.update(stabilization: storedStab, onAxis: axis)
                    }
                } else {
                    gimbalMain.supportedAxes.forEach {
                        gimbalMain.update(stabilization: stabilizedAxes.contains($0), onAxis: $0)
                    }
                }
            }
        }
        gimbalMain.notifyUpdated()
    }

    /// Called when a command that notify a setting change has been received
    ///
    /// - Parameter setting: setting that changed
    func settingDidChange(_ setting: Setting) {
        droneSettings.insert(setting)
        switch setting {
        case .maxSpeeds(let maxSpeeds):
            if connected {
                maxSpeeds.forEach { gimbalMain.update(maxSpeedSetting: $1, onAxis: $0) }
                deviceStore?.writeMultiRange(
                    key: setting.key,
                    value: Dictionary(uniqueKeysWithValues: maxSpeeds.map { ($0.key, ($0.value.min, $0.value.max)) }))
            }
        case .stabilizedAxes(let stabilizedAxes):
            if connected {
                GimbalAxis.allCases.forEach {
                    if gimbalMain.supportedAxes.contains($0) {
                        gimbalMain.update(stabilization: stabilizedAxes.contains($0), onAxis: $0)
                        controlEncoder.set(stabilization: stabilizedAxes.contains($0), targetAttitude: nil, onAxis: $0)
                    }
                }
            }
        }
        deviceStore?.commit()
        gimbalMain.notifyUpdated()
    }

    /// Process stored capabilities changes
    ///
    /// Update camera and device store. Note caller must call `camera.notifyUpdated()` to notify changes.
    ///
    /// - Parameter capabilities: changed capabilities
    func capabilitiesDidChange(_ capabilities: Capabilities) {
        switch capabilities {
        case .supportedAxes(let axes):
            deviceStore?.write(key: capabilities.key, value: StorableArray(Array(axes)))
            gimbalMain.update(supportedAxes: axes)

            // since it should be the first message to be received, update all non-stored infos relative to the axes
            gimbalMain.update(lockedAxes: axes)
            GimbalAxis.allCases.forEach { axis in
                gimbalMain.update(axisBounds: nil, onAxis: axis)
                gimbalMain.update(absoluteAttitude: nil, onAxis: axis)
                gimbalMain.update(relativeAttitude: nil, onAxis: axis)
            }
        }
        deviceStore?.commit()
        gimbalMain.notifyUpdated()
    }
}

/// Gimbal backend implementation
extension GimbalFeatureGimbal: GimbalBackend {

    func control(mode: GimbalControlMode, yaw: Double?, pitch: Double?, roll: Double?) {
        controlEncoder.control(mode: mode, yaw: yaw, pitch: pitch, roll: roll)
    }

    func resetAttitude() {
        if let gimbalId = gimbalId {
            controlEncoder.cancelControl()
            sendCommand(ArsdkFeatureGimbal.resetOrientationEncoder(gimbalId: gimbalId))
        }
    }

    func set(stabilization: Bool, onAxis axis: GimbalAxis) -> Bool {

        var stabilizedAxes = Set(expectedStabilization.filter { $1 }.keys)
        if stabilization {
            stabilizedAxes.insert(axis)
        } else {
            stabilizedAxes.remove(axis)
        }
        presetStore?.write(key: SettingKey.stabilizedAxesKey, value: StorableArray(Array(stabilizedAxes))).commit()

        expectedStabilization[axis] = stabilization
        pendingStabilizationChange.insert(axis)

        // Update the attitude bounds to take the correct frame of reference according to the new stab
        gimbalMain.update(axisBounds: stabilization ? absoluteAttitudeBounds[axis] : relativeAttitudeBounds[axis],
                          onAxis: axis)

        if connected {
            let targetAttitude: Double
            if let bounds = stabilization ? absoluteAttitudeBounds[axis] : relativeAttitudeBounds[axis] {
                if let currentAttitude = stabilization ? absoluteAttitude[axis] : relativeAttitude[axis] {
                    // if range and current attitude is known, the target attitude is the current attitude clamped into
                    // the range
                    targetAttitude = bounds.clamp(currentAttitude)
                } else {
                    // if no current attitude, take the mid-range
                    targetAttitude = (bounds.upperBound + bounds.lowerBound) / 2.0
                }
            } else {
                targetAttitude = 0
            }

            controlEncoder.set(
                stabilization: stabilization,
                targetAttitude: targetAttitude,
                onAxis: axis)
            return true
        } else {
            gimbalMain.update(stabilization: stabilization, onAxis: axis).notifyUpdated()
        }

        return false
    }

    func set(maxSpeed: Double, onAxis axis: GimbalAxis) -> Bool {
        // dictionary containing all axes. Default value for unsupported axes is 0.
        var maxSpeeds: [GimbalAxis: Double] = [:]
        GimbalAxis.allCases.forEach {
            if $0 == axis {
                maxSpeeds[$0] = maxSpeed
            } else {
                maxSpeeds[$0] = gimbalMain.maxSpeedSettings[$0]?.value ?? 0.0
            }
        }
        presetStore?.write(key: SettingKey.maxSpeedsKey, value: StorableDict(maxSpeeds)).commit()

        if connected {
            sendCommand(ArsdkFeatureGimbal.setMaxSpeedEncoder(
                gimbalId: gimbalId!, yaw: Float(maxSpeeds[.yaw]!), pitch: Float(maxSpeeds[.pitch]!),
                roll: Float(maxSpeeds[.roll]!)))
            return true
        } else {
            gimbalMain.update(maxSpeedSetting: (min: nil, value: maxSpeed, max: nil), onAxis: axis).notifyUpdated()
        }
        return false
    }

    func startOffsetsCorrectionProcess() {
        sendCommand(ArsdkFeatureGimbal.startOffsetsUpdateEncoder(gimbalId: gimbalId!))
    }

    func stopOffsetsCorrectionProcess() {
        sendCommand(ArsdkFeatureGimbal.stopOffsetsUpdateEncoder(gimbalId: gimbalId!))
    }

    func set(offsetCorrection: Double, onAxis axis: GimbalAxis) -> Bool {
        // dictionary containing all axes. Default value for not correctable axes is 0.
        var offsetCorrections: [GimbalAxis: Double] = [:]
        GimbalAxis.allCases.forEach {
            if $0 == axis {
                offsetCorrections[$0] = offsetCorrection
            } else {
                offsetCorrections[$0] = gimbalMain.offsetsCorrectionProcess?.offsetsCorrection[$0]?.value ?? 0.0
            }
        }

        if connected {
            sendCommand(ArsdkFeatureGimbal.setOffsetsEncoder(
                gimbalId: gimbalId!, yaw: Float(offsetCorrections[.yaw]!),
                pitch: Float(offsetCorrections[.pitch]!), roll: Float(offsetCorrections[.roll]!)))
            return true
        }
        return false
    }
}

/// Gimbal decode callback implementation
extension GimbalFeatureGimbal {
    override func onGimbalCapabilities(gimbalId: UInt, model: ArsdkFeatureGimbalModel, axesBitField: UInt) {
        super.onGimbalCapabilities(gimbalId: gimbalId, model: model, axesBitField: axesBitField)
        if model == .main {
            if gimbalId == self.gimbalId {
                capabilitiesDidChange(.supportedAxes(GimbalAxis.createSetFrom(bitField: axesBitField)))
                capabilitiesReceived = true
            } else {
                ULog.w(.gimbalTag, "Axis capabilities received for an unknown gimbal id=\(gimbalId)")
            }
        }
    }

    func onRelativeAttitudeBounds(
        gimbalId: UInt, minYaw: Float, maxYaw: Float, minPitch: Float, maxPitch: Float, minRoll: Float,
        maxRoll: Float) {

        guard minYaw <= maxYaw, minPitch <= maxPitch, minRoll <= maxRoll else {
            ULog.w(.gimbalTag, "Relative attitude bounds are not correct, skipping this event.")
            return
        }

        if gimbalId == self.gimbalId {
            // store the values as they might be used later (when axis stabilization changes)
            relativeAttitudeBounds[.yaw] = Double(minYaw)..<Double(maxYaw)
            relativeAttitudeBounds[.pitch] = Double(minPitch)..<Double(maxPitch)
            relativeAttitudeBounds[.roll] = Double(minRoll)..<Double(maxRoll)

            // update the bounds on the axes that are not stabilized (i.e.: frame of reference is relative)
            gimbalMain.stabilizationSettings.forEach { axis, stabSetting in
                if !stabSetting.value {
                    _ = gimbalMain.update(axisBounds: relativeAttitudeBounds[axis], onAxis: axis)
                }
            }

            gimbalMain.notifyUpdated()
        } else {
            ULog.w(.gimbalTag, "Relative attitude bounds received for an unknown gimbal id=\(gimbalId)")
        }
    }

    func onAbsoluteAttitudeBounds(
        gimbalId: UInt, minYaw: Float, maxYaw: Float, minPitch: Float, maxPitch: Float, minRoll: Float,
        maxRoll: Float) {

        guard minYaw <= maxYaw, minPitch <= maxPitch, minRoll <= maxRoll else {
            ULog.w(.gimbalTag, "Absolute attitude bounds are not correct, skipping this event.")
            return
        }

        if gimbalId == self.gimbalId {
            // store the values as they might be used later (when axis stabilization changes)
            absoluteAttitudeBounds[.yaw] = Double(minYaw)..<Double(maxYaw)
            absoluteAttitudeBounds[.pitch] = Double(minPitch)..<Double(maxPitch)
            absoluteAttitudeBounds[.roll] = Double(minRoll)..<Double(maxRoll)

            // update the bounds on the axes that are stabilized (i.e.: frame of reference is absolute)
            gimbalMain.stabilizationSettings.forEach { axis, stabSetting in
                if stabSetting.value {
                    _ = gimbalMain.update(axisBounds: absoluteAttitudeBounds[axis], onAxis: axis)
                }
            }

            gimbalMain.notifyUpdated()
        } else {
            ULog.w(.gimbalTag, "Absolute attitude bounds received for an unknown gimbal id=\(gimbalId)")
        }
    }

    func onMaxSpeed(
        gimbalId: UInt, minBoundYaw: Float, maxBoundYaw: Float, currentYaw: Float, minBoundPitch: Float,
        maxBoundPitch: Float, currentPitch: Float, minBoundRoll: Float, maxBoundRoll: Float, currentRoll: Float) {

        guard minBoundYaw <= maxBoundYaw, minBoundPitch <= maxBoundPitch, minBoundRoll <= maxBoundRoll else {
            ULog.w(.gimbalTag, "Max speed bounds are not correct, skipping this event.")
            return
        }

        if gimbalId == self.gimbalId {
            settingDidChange(.maxSpeeds([
                .yaw: (Double(minBoundYaw), Double(currentYaw), Double(maxBoundYaw)),
                .pitch: (Double(minBoundPitch), Double(currentPitch), Double(maxBoundPitch)),
                .roll: (Double(minBoundRoll), Double(currentRoll), Double(maxBoundRoll))
            ]))
        } else {
            ULog.w(.gimbalTag, "Max speed received for an unknown gimbal id=\(gimbalId)")
        }
    }

    func onAttitude(
        gimbalId: UInt, yawFrameOfReference: ArsdkFeatureGimbalFrameOfReference,
        pitchFrameOfReference: ArsdkFeatureGimbalFrameOfReference,
        rollFrameOfReference: ArsdkFeatureGimbalFrameOfReference,
        yawRelative: Float, pitchRelative: Float, rollRelative: Float,
        yawAbsolute: Float, pitchAbsolute: Float, rollAbsolute: Float) {

        // This non-ack event may be received before the capabilities one. In this case just ignore it.
        guard capabilitiesReceived else {
            return
        }

        guard yawFrameOfReference != .sdkCoreUnknown && pitchFrameOfReference != .sdkCoreUnknown &&
            rollFrameOfReference != .sdkCoreUnknown else {
                ULog.w(.gimbalTag, "Unknown frame of reference, skipping this event.")
                return
        }
        guard !yawRelative.isNaN, !pitchRelative.isNaN, !rollRelative.isNaN,
            !yawAbsolute.isNaN, !pitchAbsolute.isNaN, !rollAbsolute.isNaN else {
                ULog.w(.gimbalTag, "Invalid attitude values, skipping this event.")
                return
        }

        if gimbalId == self.gimbalId {
            // store internally the current attitude on each frame of reference
            let decimal = 3
            relativeAttitude[.yaw] = Double(yawRelative).roundedToDecimal(decimal)
            relativeAttitude[.pitch] = Double(pitchRelative).roundedToDecimal(decimal)
            relativeAttitude[.roll] = Double(rollRelative).roundedToDecimal( decimal)
            absoluteAttitude[.yaw] = Double(yawAbsolute).roundedToDecimal(decimal)
            absoluteAttitude[.pitch] = Double(pitchAbsolute).roundedToDecimal(decimal)
            absoluteAttitude[.roll] = Double(rollAbsolute).roundedToDecimal(decimal)
            let stabilizedAxes: [GimbalAxis: Bool] = [
                .yaw: (yawFrameOfReference == .absolute),
                .pitch: (pitchFrameOfReference == .absolute),
                .roll: (rollFrameOfReference == .absolute)
            ]

            var settingHasChanged = false

            if expectedStabilization.isEmpty {
                expectedStabilization = stabilizedAxes.filter { gimbalMain.supportedAxes.contains($0.key) }

                settingHasChanged = true
            }

            // if it is the first attitude received, set the initial stabilization in the encoder
            if !attitudeReceived {
                controlEncoder.setInitialStabilizations(stabilizedAxes)
                attitudeReceived = true
            }

            GimbalAxis.allCases.forEach { axis in
                if gimbalMain.supportedAxes.contains(axis) {
                    // update the stabilization information according to the frame of reference on each axis
                    // if a change has been previously asked and it matches the desired stabilization
                    // or if it has changed without being asked
                    if pendingStabilizationChange.contains(axis) ==
                        (expectedStabilization[axis] == stabilizedAxes[axis]) {
                        // can force unwrap because we know that the axis is supported
                        let isStabilized = stabilizedAxes[axis]!
                        expectedStabilization[axis] = isStabilized
                        pendingStabilizationChange.remove(axis)
                        settingHasChanged = true
                    }

                    // update the attitude bounds according to the frame reference that has been asked
                    gimbalMain.update(
                        axisBounds: expectedStabilization[axis]! ?
                            absoluteAttitudeBounds[axis] : relativeAttitudeBounds[axis],
                        onAxis: axis)
                        .update(
                            absoluteAttitude: absoluteAttitude[axis]!,
                            onAxis: axis)
                        .update(
                            relativeAttitude: relativeAttitude[axis]!,
                            onAxis: axis)
                }
            }

            if settingHasChanged {
                settingDidChange(.stabilizedAxes(
                    Set(expectedStabilization.filter { $1 && gimbalMain.supportedAxes.contains($0) }.keys)))
            }

            gimbalMain.notifyUpdated()
        } else {
            ULog.w(.gimbalTag, "Attitude received for an unknown gimbal id=\(gimbalId)")
        }
    }

    func onAxisLockState(gimbalId: UInt, lockedBitField: UInt) {
        if gimbalId == self.gimbalId {
            gimbalMain.update(lockedAxes: GimbalAxis.createSetFrom(bitField: lockedBitField)).notifyUpdated()
        } else {
            ULog.w(.gimbalTag, "Axis lock state received for an unknown gimbal id=\(gimbalId)")
        }
    }

    func onOffsets(
        gimbalId: UInt, updateState: ArsdkFeatureGimbalState, minBoundYaw: Float, maxBoundYaw: Float, currentYaw: Float,
        minBoundPitch: Float, maxBoundPitch: Float, currentPitch: Float, minBoundRoll: Float, maxBoundRoll: Float,
        currentRoll: Float) {
        guard minBoundYaw <= maxBoundYaw, minBoundPitch <= maxBoundPitch, minBoundRoll <= maxBoundRoll else {
            ULog.w(.gimbalTag, "Offset bounds are not correct, skipping this event.")
            return
        }
        if gimbalId == self.gimbalId {
            if updateState == .active {
                gimbalMain.update(offsetsCorrectionProcessStarted: true)
                var calibratableAxes = Set<GimbalAxis>()
                if minBoundYaw < maxBoundYaw {
                    calibratableAxes.insert(.yaw)
                }
                if minBoundPitch < maxBoundPitch {
                    calibratableAxes.insert(.pitch)
                }
                if  minBoundRoll < maxBoundRoll {
                    calibratableAxes.insert(.roll)
                }
                gimbalMain.update(calibratableAxes: calibratableAxes)
                // now that the calibratable axes have been set, the offsets can be set on the component
                if calibratableAxes.contains(.yaw) {
                    gimbalMain.update(
                        calibrationOffset: (min: Double(minBoundYaw), value: Double(currentYaw),
                                            max: Double(maxBoundYaw)),
                        onAxis: .yaw)
                }
                if calibratableAxes.contains(.pitch) {
                    gimbalMain.update(
                        calibrationOffset: (min: Double(minBoundPitch), value: Double(currentPitch),
                                            max: Double(maxBoundPitch)),
                        onAxis: .pitch)
                }
                if  calibratableAxes.contains(.roll) {
                    gimbalMain.update(
                        calibrationOffset: (min: Double(minBoundRoll), value: Double(currentRoll),
                                            max: Double(maxBoundRoll)),
                        onAxis: .roll)
                }
            } else {
                gimbalMain.update(offsetsCorrectionProcessStarted: false)
            }
            gimbalMain.notifyUpdated()
        } else {
            ULog.w(.gimbalTag, "Offsets received for an unknown gimbal id=\(gimbalId)")
        }
    }
}

// MARK: - Extensions

/// Extension that add conversion from/to arsdk enum
extension GimbalControlMode: ArsdkMappableEnum {
    static let arsdkMapper = Mapper<GimbalControlMode, ArsdkFeatureGimbalControlMode>([
        .position: .position,
        .velocity: .velocity])
}

extension GimbalAxis: ArsdkMappableEnum {
    static func createSetFrom(bitField: UInt) -> Set<GimbalAxis> {
        var result = Set<GimbalAxis>()
        ArsdkFeatureGimbalAxisBitField.forAllSet(in: bitField) { arsdkValue in
            if let axis = GimbalAxis(fromArsdk: arsdkValue) {
                result.insert(axis)
            }
        }
        return result
    }

    static let arsdkMapper = Mapper<GimbalAxis, ArsdkFeatureGimbalAxis>(
        [.yaw: .yaw, .pitch: .pitch, .roll: .roll])
}

extension GimbalAxis: StorableEnum {
    static var storableMapper = Mapper<GimbalAxis, String>([
        .yaw: "yaw",
        .pitch: "pitch",
        .roll: "roll"])
}
