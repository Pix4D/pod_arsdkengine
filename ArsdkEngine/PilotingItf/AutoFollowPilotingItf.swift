// Copyright (C) 2020 Parrot Drones SAS
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

/// Auto follow piloting interface component controller.
class AutoFollowPilotingItf: ActivablePilotingItfController {

    /// The piloting interface from which this object is the delegate
    private var followPilotingItf: FollowMePilotingItfCore {
        return pilotingItf as! FollowMePilotingItfCore
    }

    /// Mode requested in the pilotingItf
    private var followMode: FollowMode = .geographic

    /// Set of supported modes for this piloting interface.
    private(set) var supportedModes: Set<FollowMode> = []

    /// Local quality issues.
    private var _qualityIssues: [FollowMode: Set<TrackingIssue>] = [:]

    /// Config parameters for follow.
    private let configParam: [ArsdkFeatureAutoFollowConfigureParam] = [.distance, .azimuth, .elevation]

    /// Alerts about issues that currently hinder optimal behavior of this interface.
    public private(set) var qualityIssues = [FollowMode: Set<TrackingIssue>]() {
        didSet {
            if qualityIssues != oldValue {
                updateQualityIssues()
            }
        }
    }

    /// Local availability issues.
    private var _availabilityIssues: [FollowMode: Set<TrackingIssue>] = [:]

    /// Reasons that preclude this piloting interface from being available at present.
    private var availabilityIssues = [FollowMode: Set<TrackingIssue>]() {
         didSet {
            if availabilityIssues != oldValue {
                updateAvailabilityIssues()
                updateState()
            }
        }
    }

    /// Whether tracking is running (the interface should be .active)
    var trackingIsRunning = false {
        didSet {
            if trackingIsRunning != oldValue {
                updateState()
            }
        }
    }

    /// Constructor
    ///
    /// - Parameter activationController: activation controller that owns this piloting interface controller
    init(activationController: PilotingItfActivationController) {
        super.init(activationController: activationController, sendsPilotingCommands: true)
        pilotingItf = FollowMePilotingItfCore(store: droneController.drone.pilotingItfStore, backend: self)
    }

    override func didDisconnect() {
        super.didDisconnect()
        // the unavailable state will be set in unpublish
        pilotingItf.unpublish()
        supportedModes.removeAll()
    }

    override func didConnect() {
        if !supportedModes.isEmpty {
            followPilotingItf.update(supportedFollowModes: supportedModes)
            updateState()
            pilotingItf.publish()
        }
    }

    override func requestActivation() {
        sendStartFollowCommand(mode: followMode)
    }

    override func requestDeactivation() {
        sendStopFollowCommand()
    }

    /// Start a Follow Me with a specific mode
    ///
    /// - Parameter mode: desired follow mode
    func sendStartFollowCommand(mode: FollowMode) {
        switch mode {
        case .leash:
            sendCommand(ArsdkFeatureAutoFollow.startEncoder(mode: .leash,
                useDefaultBitField: Bitfield.of(configParam),
                distance: 0, elevation: 0, azimuth: 0))
        case .relative:
            sendCommand(ArsdkFeatureAutoFollow.startEncoder(mode: .relative,
                useDefaultBitField: Bitfield.of(configParam), distance: 0, elevation: 0,
                azimuth: 0))
        case .geographic:
            sendCommand(ArsdkFeatureAutoFollow.startEncoder(mode: .geographic,
                useDefaultBitField: Bitfield.of(configParam), distance: 0, elevation: 0,
                azimuth: 0))
        }
    }

    /// Stop Follow
    func sendStopFollowCommand() {
        sendCommand(ArsdkFeatureAutoFollow.stopEncoder())
    }

    private func updateAvailabilityIssues() {
        if let availabilityIssues = availabilityIssues[followMode] {
            followPilotingItf.update(availabilityIssues: availabilityIssues)
        } else {
            followPilotingItf.update(availabilityIssues: [])
        }
    }

    private func updateQualityIssues() {
        if let qualityIssues = qualityIssues[followMode] {
            followPilotingItf.update(qualityIssues: qualityIssues)
        } else {
            followPilotingItf.update(qualityIssues: [])
        }
    }

    /// Updates the state of the piloting interface.
    private func updateState() {
        if supportedModes.isEmpty {
            notifyUnavailable()
        } else if trackingIsRunning {
            notifyActive()
        } else {
            if let issues = availabilityIssues[followMode] {
                if issues.isEmpty {
                    notifyIdle()
                } else {
                    notifyUnavailable()
                }
            } else {
                notifyUnavailable()
            }
        }
    }

    /// A command has been received
    ///
    /// - Parameter command: received command
    override func didReceiveCommand(_ command: OpaquePointer) {
        if ArsdkCommand.getFeatureId(command) == kArsdkFeatureAutoFollowUid {
            ArsdkFeatureAutoFollow.decode(command, callback: self)
        }
    }
}

// MARK: - AutoFollowPilotingItf
extension AutoFollowPilotingItf: FollowMePilotingItfBackend {
    func set(followMode newFollowMode: FollowMode) -> Bool {
        followMode = newFollowMode
        updateAvailabilityIssues()
        updateQualityIssues()
        var returnValue: Bool = false
        if pilotingItf.state == .active {
            if followPilotingItf.availabilityIssues.isEmpty {

                // Change the followModeStting (updating). It will be validated when the drone will change the mode.
                sendStartFollowCommand(mode: newFollowMode)
                returnValue = true
            } else {
                followPilotingItf.update(followMode: newFollowMode)
                sendStopFollowCommand()
            }
        } else {
            followPilotingItf.update(followMode: newFollowMode)
        }
        updateState()
        return returnValue
    }

    func set(pitch: Int) {
        setPitch(pitch)
    }

    func set(roll: Int) {
        setRoll(roll)
    }

    func set(verticalSpeed: Int) {
        setGaz(verticalSpeed)
    }

    func activate() -> Bool {
        return droneController.pilotingItfActivationController.activate(pilotingItf: self)
    }
}

// MARK: - AutoFollowPilotingItf
extension AutoFollowPilotingItf: ArsdkFeatureAutoFollowCallback {
    func onState(mode: ArsdkFeatureAutoFollowMode, behavior: ArsdkFeatureAutoFollowBehavior) {
        switch mode {
        case .geographic:
            followMode = .geographic
        case .leash:
            followMode = .leash
        case .relative:
            followMode = .relative
        case .none:
            followPilotingItf.update(followBehavior: nil)
        case .sdkCoreUnknown:
            fallthrough
        @unknown default:
            ULog.w(.tag, "Unknown mode, skipping this event.")
            return
        }

        followPilotingItf.update(followMode: followMode)

        switch behavior {
        case .follow:
            followPilotingItf.update(followBehavior: .following)
        default:
            if mode != .none {
                followPilotingItf.update(followBehavior: .stationary)
            }
        }
        trackingIsRunning = mode != .none
        updateAvailabilityIssues()
        updateQualityIssues()
        updateState()
    }

    func onInfo(mode: ArsdkFeatureAutoFollowMode, missingInputsBitField: UInt, improvementsBitField: UInt,
                listFlagsBitField: UInt) {
        if ArsdkFeatureGenericListFlagsBitField.isSet(.first, inBitField: listFlagsBitField) {
            supportedModes.removeAll()
            _availabilityIssues.removeAll()
            _qualityIssues.removeAll()
        }
        var sdkMode: FollowMode?
        switch mode {
        case .geographic:
            sdkMode = .geographic
        case .leash:
            sdkMode = .leash
        case .relative:
            sdkMode = .relative
        case .none:
            break
        case .sdkCoreUnknown:
            fallthrough
        @unknown default:
            ULog.w(.tag, "Unknown mode, skipping this event.")
            return
        }
        if let sdkMode = sdkMode {
            supportedModes.insert(sdkMode)
            _availabilityIssues[sdkMode] = TrackingIssue.createSetFrom(bitField: missingInputsBitField)
            _qualityIssues[sdkMode] = TrackingIssue.createSetFrom(bitField: improvementsBitField)
        }
        if ArsdkFeatureGenericListFlagsBitField.isSet(.last, inBitField: listFlagsBitField) {
            qualityIssues = _qualityIssues
            availabilityIssues = _availabilityIssues
            followPilotingItf.notifyUpdated()
        }
    }
}

extension TrackingIssue: ArsdkMappableEnum {

    /// Create set of tracking issues from all value set in a bitfield
    ///
    /// - Parameter bitField: arsdk bitfield
    /// - Returns: set containing all tracking issues set in bitField
    static func createSetFrom(bitField: UInt) -> Set<TrackingIssue> {
        var result = Set<TrackingIssue>()
        ArsdkFeatureAutoFollowIndicatorBitField.forAllSet(in: bitField) { arsdkValue in
            if let missing = TrackingIssue(fromArsdk: arsdkValue) {
                result.insert(missing)
            }
        }
        return result
    }
    static var arsdkMapper = Mapper<TrackingIssue, ArsdkFeatureAutoFollowIndicator>([
        .droneGpsInfoInaccurate: .droneGps,
        .droneNotCalibrated: .droneMagneto,
        .droneOutOfGeofence: .droneGeofence,
        .droneTooCloseToGround: .droneMinAltitude,
        .droneAboveMaxAltitude: .droneMaxAltitude,
        .droneNotFlying: .droneFlying,
        .targetGpsInfoInaccurate: .targetPositionAccuracy,
        .targetDetectionInfoMissing: .targetImageDetection,
        .droneTooCloseToTarget: .droneTargetDistanceMin,
        .droneTooFarFromTarget: .droneTargetDistanceMax,
        .targetHorizontalSpeedKO: .targetHorizSpeed,
        .targetVerticalSpeedKO: .targetVertSpeed,
        .targetAltitudeAccuracyKO: .targetAltitudeAccuracy
        ])
}
