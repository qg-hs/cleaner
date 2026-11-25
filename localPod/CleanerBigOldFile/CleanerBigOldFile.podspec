#
# Be sure to run `pod lib lint CleanerBigOldFile.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'CleanerBigOldFile'
  s.version          = '0.1.0'
  s.summary          = 'A short description of CleanerBigOldFile.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/qg-hs/CleanerBigOldFile'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'cleaner' => 'cleaner@users.noreply.github.com' }
  s.source           = { :git => 'https://github.com/qg-hs/CleanerBigOldFile.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.platform = :osx
  s.osx.deployment_target = "10.11"

  s.source_files = 'CleanerBigOldFile/Classes/**/*'

  s.resources = ['CleanerBigOldFile/Assets/**/*']
  
  s.dependency "QMCoreFunction"
  s.dependency "Masonry", '1.1.0'
  s.dependency "QMUICommon"

  s.public_header_files = 'CleanerBigOldFile/Classes/Controller/McBigFileWndController.h'
  s.dependency 'CleanerFileManager'
  # s.frameworks = 'Cocoa'
  # s.dependency 'AFNetworking', '~> 2.3'
end
