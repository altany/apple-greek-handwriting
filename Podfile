# ML Kit is CocoaPods-only (no Swift Package). Version pinned to match the official
# quickstart (github.com/googlesamples/mlkit, ios/quickstarts/digitalinkrecognition).
platform :ios, '17.0'
use_frameworks!

project 'GreekInk.xcodeproj'

pod 'GoogleMLKit/DigitalInkRecognition', '9.0.0'

# Both the app (Phase 1 prototype) and the keyboard (Phase 2) need the recognizer.
target 'GreekInk' do
end

target 'GreekInkKeyboard' do
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Pods inherit our deployment target, otherwise Xcode warns about ancient minimums.
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
