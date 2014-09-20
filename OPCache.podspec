Pod::Spec.new do |spec|
  spec.name         = 'OPCache'
  spec.version      = '0.1.0'
  spec.license      = { type: 'BSD' }
  spec.homepage     = 'https://github.com/mbrandonw/OPCache'
  spec.authors      = { 'Brandon Williams' => 'mbw234@gmail.com' }
  spec.summary      = ''
  spec.source       = { :git => 'https://github.com/mbrandonw/OPCache.git' }
  spec.source_files = 'OPCache/OPCache/*.{h,m}'
  spec.requires_arc = true
end
