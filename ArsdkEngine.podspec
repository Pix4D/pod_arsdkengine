
Pod::Spec.new do |s|
    s.name                  = "ArsdkEngine"
    s.version               = "1.8.0"
    s.summary               = "Parrot Drone SDK, arsdk based engine"
    s.homepage              = "https://developer.parrot.com"
    s.license               = "{ :type => 'BSD 3-Clause License', :file => 'LICENSE' }"
    s.author                = 'Parrot Drone SAS'
    s.source                = { :git => 'https://github.com/Parrot-Developers/pod_arsdkengine.git', :tag => "1.8.0" }
    s.platform              = :ios
    s.ios.deployment_target = '10.0'
    s.source_files          = 'ArsdkEngine/**/*'
    s.dependency            'GroundSdk', '1.8.0'
    s.swift_version         = '4.2'
    s.pod_target_xcconfig   = {'SWIFT_VERSION' => '4.2'}
    s.xcconfig              = { 'ONLY_ACTIVE_ARCH' => 'YES' }
end
