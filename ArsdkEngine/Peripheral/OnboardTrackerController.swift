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

/// Base controller for onboard tracker peripheral
class OnboardTrackerController: DeviceComponentController, OnboardTrackerBackend {
    /// Onboard tracker component.
    var onboardTracker: OnboardTrackerCore!

    /// Map of tracking objects, by id.
    var targetsList = [UInt: Target]()

    /// Request status.
    var requestStatus: RequestStatus?

    /// Whether onboard tracker is supported.
    private var isOnboardtrackerSupported = false

    /// Ignore tracking answer.
    private var ignoreTrackingAnswer = false

    /// Set of abandoned tracking objects ids.
    var abandonList = Set<UInt>()

    /// Constructor.
    ///
    /// - Parameter deviceController: device controller owning this component controller (weak)
    override init(deviceController: DeviceController) {
        super.init(deviceController: deviceController)
        onboardTracker = OnboardTrackerCore(store: deviceController.device.peripheralStore,
                                                                  backend: self)
    }

    override func didConnect() {
        if isOnboardtrackerSupported {
            onboardTracker.publish()
        }
        super.didConnect()
    }

    override func didDisconnect() {
        onboardTracker.update(trackingEngineState: .droneActivated)
        onboardTracker.unpublish()
        super.didDisconnect()
    }

    /// Send command addTargetFromRect
    ///
    /// - Parameters:
    ///   - timestamp: timestamp of the frame where the rect was selected
    ///   - horizontalPosition: horizontal position of the rect
    ///   - verticalPosition: vertical position of the rect
    ///   - height: height of the rect
    ///   - width: width of the rect
    ///   - cookie: cookie id given by the user to identify rect.
    func addTargetFromRect(timeStamp: UInt64, horizontalPosition: Float, verticalPosition: Float, height: Float,
                             width: Float, cookie: UInt) {
            sendCommand(ArsdkFeatureOnboardTracker.addTargetFromRectEncoder(timestamp: timeStamp,
                                                                        horizontalPosition: horizontalPosition,
                                                                        verticalPosition: verticalPosition,
                                                                        height: height, width: width, cookie: cookie))
    }

    /// Send command addTargetFromProposalEncoder
    ///
    /// - Parameters:
    ///   - timestamp: timestamp of the frame where the rect was selected
    ///   - targetId: id of the target given by the drone
    ///   - cookie: cookie given by the user.
    func addTargetFromProposal(timeStamp: UInt64, targetId: UInt, cookie: UInt) {
            sendCommand(ArsdkFeatureOnboardTracker.addTargetFromProposalEncoder(timestamp: timeStamp,
                                                                                targetId: targetId, cookie: cookie))
    }

    /// Adds a new target to track.
    ///
    /// - Parameter trackingRequest: the tracking request
    func addNewTarget(trackingRequest: TrackingRequestCore) {
        switch trackingRequest {
        case let rectangleRequest as RectTrackingRequestCore:
            sendCommand(ArsdkFeatureOnboardTracker.addTargetFromRectEncoder(
                timestamp: rectangleRequest.timestamp,
                horizontalPosition: rectangleRequest.horizontalPosition,
                verticalPosition: rectangleRequest.verticalPosition,
                height: rectangleRequest.height, width: rectangleRequest.width,
                cookie: UInt(rectangleRequest.cookie)))
        case let proposalRequest as ProposalTrackingRequestCore:
            sendCommand(ArsdkFeatureOnboardTracker.addTargetFromProposalEncoder(
                timestamp: proposalRequest.timestamp,
                targetId: proposalRequest.proposalId, cookie: UInt(proposalRequest.cookie)))
        default:
            ULog.w(.tag, "Unknown tracking request. Dropping command add new target")
        }
    }

    /// Replaces current targets by a new target.
    ///
    /// - Parameter trackingRequest: the tracking request
    func replaceAllTargetsBy(trackingRequest: TrackingRequestCore) {
        switch trackingRequest {
        case let rectangleRequest as RectTrackingRequestCore:
            sendCommand(ArsdkFeatureOnboardTracker.replaceAllByTargetFromRectEncoder(
                timestamp: rectangleRequest.timestamp,
                horizontalPosition: rectangleRequest.horizontalPosition,
                verticalPosition: rectangleRequest.verticalPosition,
                height: rectangleRequest.height, width: rectangleRequest.width,
                cookie: UInt(rectangleRequest.cookie)))
        case let proposalRequest as ProposalTrackingRequestCore:
            sendCommand(ArsdkFeatureOnboardTracker.replaceAllByTargetFromProposalEncoder(
                timestamp: proposalRequest.timestamp,
                targetId: proposalRequest.proposalId, cookie: UInt(proposalRequest.cookie)))
        default:
            ULog.w(.tag, "Unknown tracking request. Dropping command replace all targets")
        }
    }

    /// Send command removeAllTargets
    func removeAllTargets() {
        sendCommand(ArsdkFeatureOnboardTracker.removeAllTargetsEncoder())
    }

    /// Send command to start tracking engine.
    func startTrackingEngine(boxProposals: Bool) {
        sendCommand(ArsdkFeatureOnboardTracker.startTrackingEngineEncoder(boxProposals: boxProposals ? 1 : 0))
    }

    /// Send command to stop tracking engine.
    func stopTrackingEngine() {
        sendCommand(ArsdkFeatureOnboardTracker.stopTrackingEngineEncoder())
    }

    /// Send command removeTarget
    ///
    /// - Parameters:
    ///   - targetId: id of the target given by the drone
    func removeTarget(targetId: UInt) {
        sendCommand(ArsdkFeatureOnboardTracker.removeTargetEncoder(targetId: targetId))
    }

    override func didReceiveCommand(_ command: OpaquePointer) {
        if ArsdkCommand.getFeatureId(command) == kArsdkFeatureOnboardTrackerUid {
            ArsdkFeatureOnboardTracker.decode(command, callback: self)
        }
    }

    /// Remove first abandon target
    func removeFirstAbandonTarget() {
        for target in abandonList {
            ignoreTrackingAnswer = true
            self.abandonList.remove(target)
            sendCommand(ArsdkFeatureOnboardTracker.removeTargetEncoder(targetId: target))
            return
        }
        ignoreTrackingAnswer = false
    }
}

/// Onboard tracker controller decode callback implementation
extension OnboardTrackerController: ArsdkFeatureOnboardTrackerCallback {

    func onTargetTrackingState(targetId: UInt, cookie: UInt, state: ArsdkFeatureOnboardTrackerTargetTrackingState,
                               listFlagsBitField: UInt) {

        isOnboardtrackerSupported = true
        let clearList = ArsdkFeatureGenericListFlagsBitField.isSet(.empty, inBitField: listFlagsBitField)
        if clearList {
            targetsList.removeAll()
            abandonList.removeAll()
        } else if ArsdkFeatureGenericListFlagsBitField.isSet(.remove, inBitField: listFlagsBitField) {
            targetsList.removeValue(forKey: targetId)
        } else {
            if ArsdkFeatureGenericListFlagsBitField.isSet(.first, inBitField: listFlagsBitField) {
                targetsList.removeAll()
                abandonList.removeAll()
            }
            switch state {
            case .tracking:
                targetsList[targetId] = Target(targetId: targetId, cookie: cookie, state: .tracked)
            case .searching:
                targetsList[targetId] = Target(targetId: targetId, cookie: cookie, state: .lost)
            case .abandon:
                abandonList.insert(targetId)
            case .sdkCoreUnknown:
                fallthrough
            @unknown default:
                // don't change anything if value is unknown
                ULog.w(.tag, "Unknown tracking state, skipping this event.")
            }
        }
        if clearList || ArsdkFeatureGenericListFlagsBitField.isSet(.last, inBitField: listFlagsBitField) {
           onboardTracker.update(targetsList: targetsList).notifyUpdated()
        }
        if ArsdkFeatureGenericListFlagsBitField.isSet(.last, inBitField: listFlagsBitField) ||
            ArsdkFeatureGenericListFlagsBitField.isSet(.remove, inBitField: listFlagsBitField) {
            removeFirstAbandonTarget()
        }
    }

    func onTrackingAnswer(answer: ArsdkFeatureOnboardTrackerTrackingAnswer) {
        if !ignoreTrackingAnswer {
            switch answer {
            case .processed:
                requestStatus = .processed
            case .targetLimitReached:
                requestStatus = .droppedTargetLimitReached
            case .invalid:
                requestStatus = .droppedUnknownError
            case .notFound:
                requestStatus = .droppedNotFound
            case .sdkCoreUnknown:
                fallthrough
            @unknown default:
                ULog.w(.tag, "Unknown tracking answer, skipping this event.")
            }

            onboardTracker.update(requestStatus: requestStatus).notifyUpdated()
            onboardTracker.update(requestStatus: nil).notifyUpdated()
        }
    }

    func onTrackingFeatureAvailability(availability: UInt) {
        isOnboardtrackerSupported = true
        onboardTracker.update(isAvailable: availability == 1 ? true : false).notifyUpdated()
    }

    func onTrackingEngineState(state: ArsdkFeatureOnboardTrackerTrackingEngineState) {
        switch state {
        case .droneActivated:
            onboardTracker.update(trackingEngineState: .droneActivated)
        case .available:
            onboardTracker.update(trackingEngineState: .available)
        case .activated:
            onboardTracker.update(trackingEngineState: .activated)
        case .sdkCoreUnknown:
            ULog.w(.tag, "Unknown tracking engine state, skipping this event.")
        @unknown default:
            ULog.w(.tag, "Unknown tracking engine state, skipping this event.")
        }
        onboardTracker.notifyUpdated()
    }
}
