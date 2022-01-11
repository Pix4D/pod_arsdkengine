// Copyright (C) 2021 Parrot Drones SAS
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

/// Controller for privacy related settings, like private mode.
class PrivacyController: DeviceComponentController {

    /// User Account Utility
    private var userAccountUtility: UserAccountUtilityCore?

    /// Monitor of the userAccount changes
    private var userAccountMonitor: MonitorCore?

    /// Decoder for privacy events.
    private var arsdkDecoder: ArsdkPrivacyEventDecoder!

    /// Whether `State` message has been received since `GetState` command was sent.
    private var stateReceived = false

    /// Whether connected drone supports private mode.
    private var privateModeSupported = false

    /// Private mode value.
    private var privateMode = false

    /// Constructor
    ///
    /// - Parameter deviceController: device controller owning this component controller (weak)
    override init(deviceController: DeviceController) {
        userAccountUtility = deviceController.engine.utilities.getUtility(Utilities.userAccount)

        super.init(deviceController: deviceController)

        arsdkDecoder = ArsdkPrivacyEventDecoder(listener: self)
    }

    /// Drone is about to be connected.
    override func willConnect() {
        super.willConnect()

        stateReceived = false
        _ = sendGetStateCommand()
    }

    /// Drone is connected.
    override func didConnect() {
        userAccountMonitor = userAccountUtility?.startMonitoring(accountDidChange: { _ in
            self.applyPresets()
        })
    }

    /// Drone is disconnected.
    override func didDisconnect() {
        userAccountMonitor?.stop()
        userAccountMonitor = nil
    }

    /// Applies presets.
    private func applyPresets() {
        let userPrivateMode = userAccountUtility?.userAccountInfo?.privateMode ?? false
        if privateModeSupported && privateMode != userPrivateMode {
            _ = sendLogModeCommand(userPrivateMode)
            privateMode = userPrivateMode
        }
    }

    /// A command has been received.
    ///
    /// - Parameter command: received command
    override func didReceiveCommand(_ command: OpaquePointer) {
        arsdkDecoder.decode(command)
    }
}

/// Extension for methods to send Privacy commands.
private extension PrivacyController {
    /// Sends to the drone a Privacy command.
    ///
    /// - Parameter command: command to send
    /// - Returns: `true` if the command has been sent
    func sendPrivacyCommand(_ command: Arsdk_Privacy_Command.OneOf_ID) -> Bool {
        var sent = false
        if let encoder = ArsdkPrivacyCommandEncoder.encoder(command) {
            sendCommand(encoder)
            sent = true
        }
        return sent
    }

    /// Sends get state command.
    ///
    /// - Returns: `true` if the command has been sent
    func sendGetStateCommand() -> Bool {
        var getState = Arsdk_Privacy_Command.GetState()
        getState.includeDefaultCapabilities = true
        return sendPrivacyCommand(.getState(getState))
    }

    /// Sends log mode command.
    ///
    /// - Parameter privateMode: requested private mode
    /// - Returns: `true` if the command has been sent
    func sendLogModeCommand(_ privateMode: Bool) -> Bool {
        var setLogMode = Arsdk_Privacy_Command.SetLogMode()
        setLogMode.logStorage = privateMode ? .none : .persistent
        setLogMode.logConfigPersistence = .persistent
        return sendPrivacyCommand(.setLogMode(setLogMode))
    }
}

/// Extension for events processing.
extension PrivacyController: ArsdkPrivacyEventDecoderListener {

    func onState(_ state: Arsdk_Privacy_Event.State) {
        if state.hasDefaultCapabilities {
            privateModeSupported = state.defaultCapabilities.supportedLogStorage.contains(.none)
        }

        privateMode = state.logStorage == .none && state.logConfigPersistence == .persistent

        if !stateReceived {
            stateReceived = true
            applyPresets()
        }
    }
}
