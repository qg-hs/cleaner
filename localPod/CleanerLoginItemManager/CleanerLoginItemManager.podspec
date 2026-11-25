#
# Be sure to run `pod lib lint CleanerLoginItemManager.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'CleanerLoginItemManager'
  s.version          = '0.1.0'
  s.summary          = 'A short description of CleanerLoginItemManager.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/qg-hs/CleanerLoginItemManager'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'cleaner' => 'cleaner@users.noreply.github.com' }
  s.source           = { :git => 'https://github.com/qg-hs/CleanerLoginItemManager.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.platform = :osx
  s.osx.deployment_target = "10.11"

  s.source_files = 'CleanerLoginItemManager/Classes/**/*'
  s.resources = ['CleanerLoginItemManager/Assets/**/*']

  s.dependency 'QMAppLoginItemManage'
  s.dependency 'QMUICommon'
  s.dependency 'QMCoreFunction'
  s.dependency "Masonry", '1.1.0'
  s.dependency 'FMDB', '2.7.5'
  s.dependency 'QMAppLoginItemManage'

  s.public_header_files = 'Pod/Classes/**/*.h'
end
