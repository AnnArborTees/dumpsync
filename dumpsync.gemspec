# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dumpsync/version'

Gem::Specification.new do |spec|
  spec.name          = "dumpsync"
  spec.version       = Dumpsync::VERSION
  spec.authors       = ["Resonious"]
  spec.email         = ["metreckk@gmail.com"]
  spec.summary       = %q{Dump from remote, sync to local.}
  spec.description   = %q{Quick rake task for running mysqldump on a remote database,
                          then loading it into your app's database.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 2.2.10"
  spec.add_development_dependency "rake"
end
