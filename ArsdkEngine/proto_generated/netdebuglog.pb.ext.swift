// Generated, do not edit !

import Foundation
import GroundSdk
import SwiftProtobuf

/// Listener for `ArsdkNetdebuglogEventDecoder`.
protocol ArsdkNetdebuglogEventDecoderListener: AnyObject {

    /// Processes a `String` event.
    ///
    /// - Parameter logsMsg: event to process
    func onLogsMsg(_ logsMsg: String)
}

/// Decoder for arsdk.netdebuglog.Event events.
class ArsdkNetdebuglogEventDecoder: NSObject, ArsdkFeatureGenericCallback {

    /// Service identifier.
    static let serviceId = "arsdk.netdebuglog.Event".serviceId

    /// Listener notified when events are decoded.
    private weak var listener: ArsdkNetdebuglogEventDecoderListener?

    /// Constructor.
    ///
    /// - Parameter listener: listener notified when events are decoded
    init(listener: ArsdkNetdebuglogEventDecoderListener) {
       self.listener = listener
    }

    /// Decodes an event.
    ///
    /// - Parameter event: event to decode
    func decode(_ event: OpaquePointer) {
       if ArsdkCommand.getFeatureId(event) == kArsdkFeatureGenericUid {
            ArsdkFeatureGeneric.decode(event, callback: self)
        }
    }

    func onCustomEvtNonAck(serviceId: UInt, msgNum: UInt, payload: Data) {
        processEvent(serviceId: serviceId, payload: payload, isNonAck: true)
    }

    func onCustomEvt(serviceId: UInt, msgNum: UInt, payload: Data!) {
        processEvent(serviceId: serviceId, payload: payload, isNonAck: false)
    }

    /// Processes a custom event.
    ///
    /// - Parameters:
    ///    - serviceId: service identifier
    ///    - payload: event payload
    private func processEvent(serviceId: UInt, payload: Data, isNonAck: Bool) {
        guard serviceId == ArsdkNetdebuglogEventDecoder.serviceId else {
            return
        }
        if let event = try? Arsdk_Netdebuglog_Event(serializedData: payload) {
            if !isNonAck {
                ULog.d(.tag, "ArsdkNetdebuglogEventDecoder event \(event)")
            }
            switch event.id {
            case .logsMsg(let event):
                listener?.onLogsMsg(event)
            case .none:
                ULog.w(.tag, "Unknown Arsdk_Netdebuglog_Event, skipping this event")
            }
        }
    }
}

/// Extension to get command field number.
extension Arsdk_Netdebuglog_Event.OneOf_ID {
    var number: Int32 {
        switch self {
        case .logsMsg: return 16
        }
    }
}
extension Arsdk_Netdebuglog_Event {
    static var logsMsgFieldNumber: Int32 { 16 }
}
