platform :ios, '11.0'

# Explicitly set the workspace CocoaPods should generate/use
workspace 'GiftersClub.xcworkspace'

# Link Swift pods as static frameworks for faster builds
use_frameworks! :linkage => :static

target 'GiftersClub' do
  # Core app dependencies
  pod 'FlutterwaveSDK', '1.4.4'
  pod 'IQKeyboardManagerSwift', '6.5.16'
  pod 'MDFInternationalization', '3.0.0'
  pod 'MaterialComponents', '124.2.0'
  pod 'RxSwift', '6.9.0'
  pod 'RxCocoa', '6.9.0'
  pod 'RxRelay', '6.9.0'
  pod 'Swinject', '2.9.1'
  pod 'SwinjectAutoregistration', '2.9.1'
  pod 'lottie-ios', '4.4.1'

  # Test targets inherit search paths from the app
  target 'GiftersClubTests' do
    inherit! :search_paths
  end

  target 'GiftersClubUITests' do
    inherit! :search_paths
  end
end

