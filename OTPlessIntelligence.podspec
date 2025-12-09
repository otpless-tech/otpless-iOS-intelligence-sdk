Pod::Spec.new do |s|
  s.name             = 'OTPlessIntelligence'
  s.version          = '1.0.4'
  s.summary          = 'OTPless device intelligence SDK for risk & fraud detection.'
  s.description      = <<-DESC
    OTPlessIntelligence is a device intelligence SDK used for risk scoring,
    fraud detection and identity signals, built on top of the IdentityFraud framework.
  DESC

  s.homepage         = 'https://github.com/otpless-tech/otpless-ios-intelligence-sdk'
  s.license          = { :type => 'Proprietary', :file => 'LICENSE' }  # or MIT, etc.
  s.author           = { 'OTPless' => 'help@otpless.com' }
  s.social_media_url = 'https://twitter.com/otpless'
  # Where the pod can be fetched from
  s.source           = {
    :git => 'https://github.com/otpless-tech/otpless-ios-intelligence-sdk',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'
  s.requires_arc          = true

  # Your Swift sources (SPM target path)
  s.source_files          = 'Sources/otpless-ios-intelligence-sdk/**/*.{swift}'

  # The xcframework used in the SPM binary target
  s.vendored_frameworks   = 'Frameworks/IdentityFraud.xcframework'

  # If IdentityFraud needs system frameworks, add them here
  # s.frameworks = 'UIKit', 'Foundation', 'Security', 'SystemConfiguration'

  # If you ever add resources, use:
  # s.resource_bundles = {
  #   'OTPlessIntelligenceResources' => ['Sources/otpless-ios-intelligence-sdk/Resources/**/*']
  # }
end
