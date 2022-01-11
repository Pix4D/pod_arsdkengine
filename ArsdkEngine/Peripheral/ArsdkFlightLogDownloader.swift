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

/// FlightLog downloader delegate
protocol ArsdkFlightLogDownloaderDelegate: AnyObject {
    /// Configure the delegate
    ///
    /// - Parameter downloader: the downloader in charge
    func configure(downloader: ArsdkFlightLogDownloader)
    /// Reset the delegate
    ///
    /// - Parameter downloader: the downloader in charge
    func reset(downloader: ArsdkFlightLogDownloader)
    /// Download all existing flight logs
    ///
    /// - Parameters:
    ///   - directory: the local directory to store the flight logs
    ///   - downloader: the downloader in charge
    /// - Returns: true if the download has been started, false otherwise
    func download(toDirectory directory: URL, downloader: ArsdkFlightLogDownloader) -> Bool
    /// Deletes all existing flight logs.
    ///
    /// - Returns: true if the deletion has been started, false otherwise
    func delete() -> Bool

    /// Cancel current request and all following ones.
    func cancel()
}

/// FlightLog downloader component controller subclass that does the download through http
class HttpFlightLogDownloader: ArsdkFlightLogDownloader {
    /// Constructor
    ///
    /// - Parameters:
    ///     - deviceController: device controller owning this component controller (weak)
    ///     - flightLogConverterStorage: flight Log converter Storage Utility
    init(deviceController: DeviceController, flightLogConverterStorage: FlightLogConverterStorageCore) {
        super.init(deviceController: deviceController, flightLogConverterStorage: flightLogConverterStorage,
                   delegate: HttpFlightLogDownloaderDelegate())
    }

    /// Constructor
    ///
    /// - Parameters:
    ///     - deviceController: device controller owning this component controller (weak)
    ///     - flightLogStorage: flight Log Storage Utility
    init(deviceController: DeviceController, flightLogStorage: FlightLogStorageCore) {
        super.init(deviceController: deviceController, flightLogStorage: flightLogStorage,
                   delegate: HttpFlightLogDownloaderDelegate())
    }
}

/// FlightLog downloader component controller subclass that does the download through ftp
class FtpFlightLogDownloader: ArsdkFlightLogDownloader {

    /// Constructor
    ///
    /// - Parameters:
    ///     - deviceController: device controller owning this component controller (weak)
    ///     - flightLogStorage: flight Log Storage Utility
    init(deviceController: DeviceController, flightLogStorage: FlightLogStorageCore) {
        super.init(deviceController: deviceController, flightLogStorage: flightLogStorage,
                   delegate: FtpFlightLogDownloaderDelegate())
    }
}

/// Generic flightLog downloader component controller
class ArsdkFlightLogDownloader: DeviceComponentController {

    /// FlightLogDownloader component.
    let flightLogDownloader: FlightLogDownloaderCore
    /// Flight Log converter storage utility
    var flightLogConverterStorage: FlightLogConverterStorageCore?
    /// Flight Log storage utility
    var flightLogStorage: FlightLogStorageCore?

    // swiftlint:disable weak_delegate
    /// Delegate to actually download the flight logs
    let delegate: ArsdkFlightLogDownloaderDelegate
    // swiftlint:enable weak_delegate

    /// Url path of the current work directory where flightLogs downloaded from remote devices get stored.
    /// This directory is located in `engineDir`.
    let workDir: URL

    /// User Account Utility
    private var userAccountUtilityCore: UserAccountUtilityCore?

    /// Constructor
    ///
    /// - Parameters:
    ///     - deviceController: device controller owning this component controller (weak)
    ///     - flightLogConverterStorage: flight Log converter Storage Utility
    ///     - delegate: flight log downloader delegate
    fileprivate init(deviceController: DeviceController, flightLogConverterStorage: FlightLogConverterStorageCore,
                     delegate: ArsdkFlightLogDownloaderDelegate) {
        self.delegate = delegate
        self.flightLogConverterStorage = flightLogConverterStorage
        self.workDir = flightLogConverterStorage.workDir
        self.flightLogDownloader = FlightLogDownloaderCore(store: deviceController.device.peripheralStore)
        self.userAccountUtilityCore =  deviceController.engine.utilities.getUtility(Utilities.userAccount)
        super.init(deviceController: deviceController)
    }

    /// Constructor
    ///
    /// - Parameters:
    ///     - deviceController: device controller owning this component controller (weak)
    ///     - flightLogStorage: flight Log Storage Utility
    ///     - delegate: flight log downloader delegate
    fileprivate init(deviceController: DeviceController, flightLogStorage: FlightLogStorageCore,
                     delegate: ArsdkFlightLogDownloaderDelegate) {
        self.delegate = delegate
        self.flightLogStorage = flightLogStorage
        self.workDir = flightLogStorage.workDir
        self.flightLogDownloader = FlightLogDownloaderCore(store: deviceController.device.peripheralStore)
        self.userAccountUtilityCore =  deviceController.engine.utilities.getUtility(Utilities.userAccount)
        super.init(deviceController: deviceController)
    }

    /// Device is connected
    override func didConnect() {
        delegate.configure(downloader: self)
        // note that it is safe to call `dataSyncAllowanceChanged` even if it has not changed.
        dataSyncAllowanceChanged(allowed: deviceController.dataSyncAllowed)
        flightLogDownloader.publish()
    }

    /// Device is disconnected
    override func didDisconnect() {
        flightLogDownloader.unpublish()
        delegate.reset(downloader: self)
    }

    override func dataSyncAllowanceChanged(allowed: Bool) {
        if allowed {
            download()
        } else {
            cancelDownload()
        }
    }

    /// Downloads flight logs from the controlled device.
    /// In private mode, flight logs are just deleted instead of being downloaded.
    private func download() {
        if userAccountUtilityCore?.userAccountInfo?.privateMode == true {
            _ = delegate.delete()
        } else {
            if delegate.download(toDirectory: workDir, downloader: self) {
                flightLogDownloader.update(downloadingFlag: true)
                    .update(completionStatus: .none)
                    .notifyUpdated()
            }
        }
    }

    /// Cancels current download
    ///
    /// - Returns: true if the cancel succeeded to start otherwise false
    private func cancelDownload() {
        delegate.cancel()
    }
}
