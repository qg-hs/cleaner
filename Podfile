# Uncomment the next line to define a global platform for your project
#source 'https://github.com/CocoaPods/Specs.git'

platform :osx, '12.0'

install! 'cocoapods', :disable_input_output_paths => true

workspace 'Cleaner'

project 'Cleaner.xcodeproj'
project 'Tools/CleanerMonitor/CleanerMonitor.xcodeproj'
project 'Tools/CleanerDaemon/CleanerDaemon.xcodeproj'
project 'Tools/PrivacyProtect/PrivacyProtect.xcodeproj'

#use_frameworks!
def available_pods
    pod 'QMUICommon',:path => './localPod/QMUICommon'
    pod 'QMCoreFunction',:path => './localPod/QMCoreFunction'
    pod 'Masonry', '= 1.1.0'
    pod 'FMDB', '= 2.7.5'
    pod 'CleanerFileManager',:path => './localPod/CleanerFileManager'
end
target 'Cleaner' do
   use_frameworks!
   inherit! :search_paths
  project 'Cleaner.xcodeproj'
  available_pods
  pod 'QMAppLoginItemManage',:path => './localPod/QMAppLoginItemManage'
  pod 'CleanerSpaceAnalyse',:path => './localPod/CleanerSpaceAnalyse'
  pod 'CleanerSpaceAnalyse',:path => './localPod/CleanerSpaceAnalyse'
  pod 'CleanerBigOldFile',:path => './localPod/CleanerBigOldFile'
  pod 'CleanerPhotoClean',:path => './localPod/CleanerPhotoClean'
  pod 'CleanerDuplicateFile',:path => './localPod/CleanerDuplicateFile'
  pod 'CleanerPrivacyClean',:path => './localPod/CleanerPrivacyClean'
  pod 'CleanerUninstaller',:path => './localPod/CleanerUninstaller'
  pod 'CleanerLoginItemManager',:path => './localPod/CleanerLoginItemManager'
  pod 'CleanerFileMove',:path => './localPod/CleanerFileMove'
end

target 'CleanerMonitor' do
    use_frameworks!
    inherit! :search_paths
    project 'Tools/CleanerMonitor/CleanerMonitor.xcodeproj'
    available_pods
    pod 'CleanerStat',:path => './localPod/CleanerStat'
    pod 'CleanerUninstaller',:path => './localPod/CleanerUninstaller'
    pod 'CleanerHardware',:path => './localPod/CleanerHardware'
    pod 'CleanerNetSpeed',:path => './localPod/CleanerNetSpeed'
    pod 'CleanerFileMove',:path => './localPod/CleanerFileMove'
end

target 'CleanerDaemon' do
    inherit! :search_paths
    project 'Tools/CleanerDaemon/CleanerDaemon.xcodeproj'
end

target 'CleanerCore' do
    use_frameworks!
    inherit! :search_paths
    project 'CleanerCore/CleanerCore.xcodeproj'
    pod 'CleanerFileMove',:path => './localPod/CleanerFileMove'
    available_pods
end

target 'PrivacyProtect' do
    use_frameworks!
    inherit! :search_paths
    project 'Tools/PrivacyProtect/PrivacyProtect.xcodeproj'
    available_pods
end

post_install do |installer_representation|
    installer_representation.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
            config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
        end
    end
end
