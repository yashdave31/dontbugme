# frozen_string_literal: true

require_relative 'lib/dontbugme/version'

Gem::Specification.new do |spec|
  spec.name          = 'dontbugme'
  spec.version       = Dontbugme::VERSION
  spec.authors       = ['Inspector Contributors']
  spec.email         = ['hello@example.com']

  spec.summary       = 'Flight recorder for Rails — reconstruct the full execution story of Sidekiq jobs and HTTP requests'
  spec.description   = <<~DESC
    Dontbugme captures a structured trace of everything that happens during a unit of work
    (Sidekiq job, HTTP request, rake task). See exactly what database queries ran, what HTTP
    services were called, what exceptions were raised — with source locations pointing to your code.
  DESC
  spec.homepage      = 'https://github.com/example/dontbugme'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir['lib/**/*', 'app/**/*', 'config/**/*', 'bin/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']
  spec.executables = ['dontbugme']

  spec.add_dependency 'thor', '~> 1.0'
  spec.add_dependency 'sqlite3', '~> 1.6'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rack', '>= 2.0'
  spec.add_development_dependency 'rack-test', '>= 1.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
