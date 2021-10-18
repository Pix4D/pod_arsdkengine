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

/// Mono StreamServer implementation.
class StreamServerMonoController: DeviceComponentController, StreamServerBackend {

    /// StreamServer peripheral for which this object is the backend.
    private var streamServerCore: StreamServerCore!

    /// All currently maintained streams.
    private var streams: Set<StreamCore> = []

    /// Live stream controller enebeled by default.
    private var liveStreamCtrl: StreamController?

    /// 'true' when streaming is enabled.
    public var enabled: Bool = false {
        didSet {
            if enabled != oldValue {
                streamServerCore.update(enable: enabled)
                if enabled {
                    // Reset live stream controler as active stream.
                    if let liveStreamCtrl = liveStreamCtrl {
                        setPriorityStream(liveStreamCtrl)
                    }
                } else {
                    for stream in streams {
                        stream.interrupt()
                    }
                }
            }
        }
    }

    /// Active stream controller.
    private var currentStreamCtrl: StreamController?

    /// Stream waiting to become the active stream controller.
    private var pendingStreamCtrl: StreamController?

    /// Constructor
    ///
    /// - Parameter devicontroller: the drone controller that owns this peripheral controller.
    override init(deviceController: DeviceController) {
        super.init(deviceController: deviceController)
        streamServerCore = StreamServerCore(store: deviceController.device.peripheralStore, backend: self)
    }

    /// Drone is connected.
    override func didConnect() {
        streamServerCore.enabled = true
        streamServerCore.publish()
    }

    /// Drone is disconnected.
    override func didDisconnect() {
        for stream in streams {
            stream.releaseStream()
        }
        streamServerCore.unpublish()
    }

    /// Register a stream.
    ///
    /// - Parameter stream: stream to register
    func register(stream: StreamCore) {
        streams.insert(stream)
    }

    /// Unregister a stream.
    ///
    /// - Parameter stream: stream to unregister
    func unregister(stream: StreamCore) {
        streams.remove(stream)
    }

    /// Retrieves a camera live stream.
    ///
    /// - Parameter source: the camera live source of the live stream to retrieve
    /// - Returns: the camera live stream researched or `nil` if there not already exists
    func getCameraLive(source: CameraLiveSource) -> CameraLiveCore? {
        return streams.compactMap { $0 as? CameraLiveCore }
            .first { $0.source == .unspecified }
    }

    /// Retrieves a new live stream backend.
    ///
    /// - Parameters:
    ///    - cameraType: type of camera live source to stream
    ///    - stream: stream ower of the backend.
    /// - Returns: a new live stream backend.
    func getStreamBackendLive(cameraType: CameraLiveSource, stream: StreamCore) -> StreamBackend {
        let streamCtrl = StreamController.Live(deviceController: deviceController,
                                               cameraType: .unspecified, stream: stream)
        streamCtrl.serverListener = self
        streamCtrl.enabled = false
        liveStreamCtrl = streamCtrl
        return streamCtrl
    }

    /// Retrieves a new media stream backend.
    ///
    /// - Parameters:
    ///    - url: url of the media to stream
    ///    - trackName: name of the track to select, `nil` if not specified.
    ///    - stream: stream ower of the backend.
    /// - Returns: a new media stream backend.
    func getStreamBackendMedia(url: String, trackName: String?, stream: StreamCore) -> StreamBackend {
        let streamCtrl = StreamController.Media(deviceController: deviceController, url: url, trackName: trackName,
                                      stream: stream)
        streamCtrl.serverListener = self
        streamCtrl.enabled = false
        return streamCtrl
    }

    /// Sets the priority stream controller.
    ///
    /// - Parameter streamCtrl: priority stream controller to enable.
    private func setPriorityStream(_ streamCtrl: StreamController) {
        if currentStreamCtrl == nil ||
                currentStreamCtrl?.state == .stopped ||
                currentStreamCtrl == streamCtrl {
            // The new stream controller can be directly the current.
            currentStreamCtrl = streamCtrl
            currentStreamCtrl?.enabled = enabled
        } else {
            // Wait current stream stop.
            pendingStreamCtrl = streamCtrl
            currentStreamCtrl?.enabled = false
        }
    }
}

/// StreamControllerServerListener implementation.
extension StreamServerMonoController: StreamControllerServerListener {
    func streamWouldOpen(streamController: StreamController) {
        setPriorityStream(streamController)
    }

    func streamDidClose(streamController: StreamController) {
        if streamController.isEqual(currentStreamCtrl) {
            currentStreamCtrl = pendingStreamCtrl
            pendingStreamCtrl = nil

            if let currentStreamCtrl = currentStreamCtrl {
                currentStreamCtrl.enabled = enabled
            } else if let liveStreamCtrl = liveStreamCtrl {
                // Reset live stream controler as active stream.
                setPriorityStream(liveStreamCtrl)
            }
        } else if streamController.isEqual(pendingStreamCtrl) {
            pendingStreamCtrl = nil
        }
    }
}
