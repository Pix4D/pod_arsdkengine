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

/// Base controller for Anafi stereo vision sensor peripheral
class AnafiStereoVisionSensor: DeviceComponentController {
    /// sensorId of main stereo vision sensor is always zero
    private static let sensorId = UInt(0)

    /// Stereo vision sensor component
    private var stereorVisionSensor: StereoVisionSensorCore!

    /// `true` if stereo vision sensor is supported by the drone.
    private var isSupported = false

    /// Constructor
    ///
    /// - Parameter deviceController: device controller owning this component controller (weak)
    override init(deviceController: DeviceController) {
        super.init(deviceController: deviceController)
        stereorVisionSensor = StereoVisionSensorCore(store: deviceController.device.peripheralStore, backend: self)
    }

    /// Drone is connected
    override func didConnect() {
        if isSupported {
            stereorVisionSensor.publish()
        }
    }

    /// Drone is disconnected
    override func didDisconnect() {
        stereorVisionSensor.setCalibrationStopped()
        isSupported = false
        stereorVisionSensor.update(isComputing: false)
        stereorVisionSensor.unpublish()
    }

    /// A command has been received
    ///
    /// - Parameter command: received command
    override func didReceiveCommand(_ command: OpaquePointer) {
        if ArsdkCommand.getFeatureId(command) == kArsdkFeatureStereoVisionSensorUid {
            ArsdkFeatureStereoVisionSensor.decode(command, callback: self)
        }
    }
}

/// Anafi stereo vision sensor backend implementation
extension AnafiStereoVisionSensor: StereoVisionSensorBackend {
    func startCalibration() {
        sendCommand(ArsdkFeatureStereoVisionSensor.startCalibrationEncoder(
            sensorId: AnafiStereoVisionSensor.sensorId))
    }

    func cancelCalibration() {
        sendCommand(ArsdkFeatureStereoVisionSensor.cancelCalibrationEncoder(
            sensorId: AnafiStereoVisionSensor.sensorId))
    }
}

/// Anafi stereo vision sensor decode callback implementation
extension AnafiStereoVisionSensor: ArsdkFeatureStereoVisionSensorCallback {

    func onCapabilities(sensorId: UInt, model: ArsdkFeatureStereoVisionSensorModel, supportedFeaturesBitField: UInt) {
        if sensorId == AnafiStereoVisionSensor.sensorId {
            if ArsdkFeatureStereoVisionSensorFeatureBitField.isSet(.calibration,
                                                                   inBitField: supportedFeaturesBitField) {
                isSupported = true
            }
        } else {
            ULog.w(.stereovisionTag, """
                Calibration capabilities received for an
                unknown stereo vision sensor id=\(sensorId)
                """)
        }
    }

    func onCalibrationInfo(sensorId: UInt, stepCount: UInt, aspectRatio: Float) {
        if sensorId == AnafiStereoVisionSensor.sensorId {
            let decimal = 3
            stereorVisionSensor.update(calibrationStepCount: Int(stepCount))
                .update(aspectRatio: Double(aspectRatio).roundedToDecimal(decimal)).notifyUpdated()
        } else {
            ULog.w(.stereovisionTag, """
                Calibration capabilities received for an
                unknown stereo vision sensor id=\(sensorId)
                """)
        }
    }

    func onCalibrationState(sensorId: UInt, state: ArsdkFeatureStereoVisionSensorCalibrationState) {

        if sensorId == AnafiStereoVisionSensor.sensorId {
            switch state {
            case .required:
                stereorVisionSensor.update(calibrated: false)
                    .update(isComputing: false)
                    .notifyUpdated()
            case .captureInProgress:
                stereorVisionSensor.setCalibrationStarted()
                    .update(isComputing: false)
                    .notifyUpdated()
            case .computationInProgress:
                stereorVisionSensor.setCalibrationStarted()
                    .update(isComputing: true)
                    .notifyUpdated()
            case .ok:
                stereorVisionSensor.update(isComputing: false)
                    .update(calibrated: true)
                    .notifyUpdated()
            case .sdkCoreUnknown:
                fallthrough
            @unknown default:
                // don't change anything if value is unknown
                ULog.w(.tag, "Unknown state, skipping this calibration state event.")
            }

        } else {
            ULog.w(.stereovisionTag, "Calibration state received for an unknown stereo vision sensor id=\(sensorId)")
        }
    }

    func onCalibrationStep(sensorId: UInt, step: UInt,
                           vertexLtX: Float, vertexLtY: Float,
                           vertexRtX: Float, vertexRtY: Float,
                           vertexLbX: Float, vertexLbY: Float,
                           vertexRbX: Float, vertexRbY: Float,
                           angleX: Float, angleY: Float) {
        if sensorId == AnafiStereoVisionSensor.sensorId {
            let decimal = 3
            stereorVisionSensor.update(currentStep: Int(step))
                .updateRequiredPosition(
                    leftTopX: Double(vertexLtX).roundedToDecimal(decimal),
                    leftTopY: Double(vertexLtY).roundedToDecimal(decimal),
                    rightTopX: Double(vertexRtX).roundedToDecimal(decimal),
                    rightTopY: Double(vertexRtY).roundedToDecimal(decimal),
                    leftBottomX: Double(vertexLbX).roundedToDecimal(decimal),
                    leftBottomY: Double(vertexLbY).roundedToDecimal(decimal),
                    rightBottomX: Double(vertexRbX).roundedToDecimal(decimal),
                    rightBottomY: Double(vertexRbY).roundedToDecimal(decimal))
                .updateRequiredRotation(xAngle: Double(angleX).roundedToDecimal(decimal),
                                        yAngle: Double(angleY).roundedToDecimal(decimal))
                .notifyUpdated()
        } else {
            ULog.w(.stereovisionTag, "Calibration step received for an unknown stereo vision sensor id=\(sensorId)")
        }
    }

    func onCalibrationIndication(sensorId: UInt, indication: ArsdkFeatureStereoVisionSensorCalibrationIndication,
                                 vertexLtX: Float, vertexLtY: Float,
                                 vertexRtX: Float, vertexRtY: Float,
                                 vertexLbX: Float, vertexLbY: Float,
                                 vertexRbX: Float, vertexRbY: Float,
                                 angleX: Float, angleY: Float) {
        if sensorId == AnafiStereoVisionSensor.sensorId {
            var newIndication: StereoVisionIndication
            switch indication {
            case .placeWithinSight:
                newIndication = .placeWithinSight
            case .checkBoardAndCameras:
                newIndication = .checkBoardAndCameras
            case .moveAway:
                newIndication = .moveAway
            case .moveCloser:
                newIndication = .moveCloser
            case .moveLeft:
                newIndication = .moveLeft
            case .moveRight:
                newIndication = .moveRight
            case .moveUpward:
                newIndication = .moveUpward
            case .moveDownward:
                newIndication = .moveDownward
            case .turnClockwise:
                newIndication = .turnClockwise
            case .turnCounterClockwise:
                newIndication = .turnCounterClockwise
            case .tiltLeft:
                newIndication = .tiltLeft
            case .tiltRight:
                newIndication = .tiltRight
            case .tiltForward:
                newIndication = .tiltForward
            case .tiltBackward:
                newIndication = .tiltBackward
            case .stop:
                newIndication = .stop
            case .sdkCoreUnknown:
                fallthrough
            @unknown default:
                // don't change anything if value is unknown
                ULog.w(.tag, "Unknown indication, skipping this event.")
                return
            }
            let decimal = 3
            stereorVisionSensor.update(indication: newIndication)
                .updateCurrentPosition(
                    leftTopX: Double(vertexLtX).roundedToDecimal(decimal),
                    leftTopY: Double(vertexLtY).roundedToDecimal(decimal),
                    rightTopX: Double(vertexRtX).roundedToDecimal(decimal),
                    rightTopY: Double(vertexRtY).roundedToDecimal(decimal),
                    leftBottomX: Double(vertexLbX).roundedToDecimal(decimal),
                    leftBottomY: Double(vertexLbY).roundedToDecimal(decimal),
                    rightBottomX: Double(vertexRbX).roundedToDecimal(decimal),
                    rightBottomY: Double(vertexRbY).roundedToDecimal(decimal))
                .updateCurrentRotation(xAngle: Double(angleX).roundedToDecimal(decimal),
                                        yAngle: Double(angleY).roundedToDecimal(decimal))
                .notifyUpdated()
        } else {
            ULog.w(.stereovisionTag, """
                Calibration indication received for an
                unknown stereo vision sensor id=\(sensorId)
                """)
        }
    }

    func onCalibrationResult(sensorId: UInt, result: ArsdkFeatureStereoVisionSensorCalibrationResult) {
        if sensorId == AnafiStereoVisionSensor.sensorId {
            var newResult: StereoVisionResult
            switch result {
            case .canceled:
                newResult = .canceled
            case .failure:
                newResult = .failed
            case .success:
                newResult = .success
            case .sdkCoreUnknown:
                fallthrough
            @unknown default:
                // don't change anything if value is unknown
                ULog.w(.tag, "Unknown resuly, skipping this event.")
                return
            }
            stereorVisionSensor.update(result: newResult).notifyUpdated() // notify transient result
            stereorVisionSensor.setCalibrationStopped().notifyUpdated()
        } else {
            ULog.w(.stereovisionTag, """
                Calibration result received for an
                unknown stereo vision sensor id=\(sensorId)
                """)
        }
    }
}
