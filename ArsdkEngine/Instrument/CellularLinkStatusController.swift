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

/// CellularLinkStatus component controller.
class CellularLinkStatusController: DeviceComponentController {

    /// Cellular link status component.
    private var cellularLinkStatus: CellularLinkStatusCore!

    /// Decoder for controller network events.
    private var arsdkDecoder: ArsdkControllernetworkEventDecoder!

    /// Constructor.
    ///
    /// - Parameter deviceController: device controller owning this component controller (weak)
    override init(deviceController: DeviceController) {
        super.init(deviceController: deviceController)
        cellularLinkStatus = CellularLinkStatusCore(store: deviceController.device.instrumentStore)
        arsdkDecoder = ArsdkControllernetworkEventDecoder(listener: self)
    }

    /// Device is about to be connected.
    override func willConnect() {
        super.willConnect()
        _ = sendGetStateCommand()
    }

    /// Device is disconnected.
    override func didDisconnect() {
        cellularLinkStatus.unpublish()
        cellularLinkStatus.update(status: nil)
    }

    /// A command has been received.
    ///
    /// - Parameter command: received command
    override func didReceiveCommand(_ command: OpaquePointer) {
        arsdkDecoder.decode(command)
    }
}

/// Extension for methods to send controller network commands.
extension CellularLinkStatusController {
    /// Sends to the device a controller network command.
    ///
    /// - Parameter command: command to send
    /// - Returns: `true` if the command has been sent
    func sendControllerNetworkCommand(_ command: Arsdk_Controllernetwork_Command.OneOf_ID) -> Bool {
        var sent = false
        if let encoder = ArsdkControllernetworkCommandEncoder.encoder(command) {
            sendCommand(encoder)
            sent = true
        }
        return sent
    }

    /// Sends command to get state.
    ///
    /// - Returns: `true` if the command has been sent
    func sendGetStateCommand() -> Bool {
        sendControllerNetworkCommand(.getState(Arsdk_Controllernetwork_Command.GetState()))
    }
}

/// Extension for events processing.
extension CellularLinkStatusController: ArsdkControllernetworkEventDecoderListener {
    func onState(_ state: Arsdk_Controllernetwork_Event.State) {
        // links status
        if state.hasLinksStatus {
            processLinksStatus(state.linksStatus)
        }

        cellularLinkStatus.publish()
        cellularLinkStatus.notifyUpdated()
    }

    /// Processes a `LinksStatus` message.
    ///
    /// - Parameter linksStatus: message to process
    func processLinksStatus(_ linksStatus: Arsdk_Network_LinksStatus) {
        let cellularLink = linksStatus.links
            .compactMap { $0.gsdkCellularLinkStatus }
            .first
        cellularLinkStatus.update(status: cellularLink)
    }
}

/// Extension that adds conversion from/to arsdk enum.
///
/// - Note: CellularLinkStatusError.init(fromArsdk: .none) will return `nil`.
extension CellularLinkStatusError: ArsdkMappableEnum {
    static let arsdkMapper = Mapper<CellularLinkStatusError, Arsdk_Network_LinkError>([
        .authentication: .authentication,
        .communicationLink: .commLink,
        .connect: .connect,
        .dns: .dns,
        .publish: .publish,
        .timeout: .timeout,
        .invite: .invite])
}

/// Extension that adds conversion to gsdk.
extension Arsdk_Network_LinksStatus.LinkInfo {
    /// Creates a new `CellularLinkStatusStatus` from `Arsdk_Network_LinksStatus.LinkInfo`.
    var gsdkCellularLinkStatus: CellularLinkStatusStatus? {
        if type == .cellular {
            switch status {
            case .up: return .up
            case .down: return .down
            case .connecting: return .connecting
            case .ready: return .ready
            case .running: return .running
            case .error:
                let theError = CellularLinkStatusError.init(fromArsdk: error)
                return .error(error: theError)
            case .UNRECOGNIZED:
                return nil
            }
        }
        return nil
    }
}
