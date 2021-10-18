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

/// StreamServer controller base
/// Must be inherited
class StreamServerMultiController: DeviceComponentController, StreamServerBackend {

    /// StreamServer peripheral for which this object is the backend.
    var streamServerCore: StreamServerCore!

    /// All currently maintained streams.
    var streams: Set<StreamCore> = []

    /// 'true' when streaming is enabled.
    public var enabled: Bool = false {
        didSet {
            if enabled != oldValue {
                streamServerCore.update(enable: enabled)
                if enabled {
                    for stream in streams {
                        stream.resume()
                    }
                } else {
                    for stream in streams {
                        stream.interrupt()
                    }
                }
            }
        }
    }

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
    /// - Parameter source: the camera live source of the live stream to retreive
    /// - Returns: the camera live stream researched or `nil` if there not already exists
    func getCameraLive(source: CameraLiveSource) -> CameraLiveCore? {
        return streams.compactMap { $0 as? CameraLiveCore }
            .first { $0.source == source }
    }

    /// Retrieves live stream backend.
    ///
    /// - Parameters:
    ///    - cameraType: camera type of the live stream to open
    ///    - stream: stream owner of the backend
    /// - Returns: a new live stream backend
    func getStreamBackendLive(cameraType: CameraLiveSource, stream: StreamCore) -> StreamBackend {
        let streamCtrl = StreamController.Live(deviceController: deviceController, cameraType: cameraType,
                                     stream: stream)
        streamCtrl.enabled = enabled
        return streamCtrl
    }

    /// Retrieves media stream backend.
    ///
    /// - Parameters:
    ///    - url: url of the media stream to open
    ///    - trackName: track name of the stream to open
    ///    - stream: stream owner of the backend
    /// - Returns: a new media stream backend
    func getStreamBackendMedia(url: String, trackName: String?, stream: StreamCore) -> StreamBackend {
        let streamCtrl = StreamController.Media(deviceController: deviceController, url: url, trackName: trackName,
                                      stream: stream)
        streamCtrl.enabled = enabled
        return streamCtrl
    }
}
