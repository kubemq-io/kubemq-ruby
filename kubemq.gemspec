# frozen_string_literal: true

require_relative 'lib/kubemq/version'

Gem::Specification.new do |spec|
  spec.name          = 'kubemq'
  spec.version       = KubeMQ::VERSION
  spec.authors       = ['KubeMQ']
  spec.email         = ['support@kubemq.io']
  spec.summary       = 'KubeMQ Ruby SDK - Message Queue Client'
  spec.description   = 'Official Ruby SDK for KubeMQ message broker. ' \
                       'Supports Events, Events Store, Queues, Commands, and Queries.'
  spec.homepage      = 'https://github.com/kubemq-io/kubemq-ruby'
  spec.license       = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'documentation_uri' => 'https://www.rubydoc.info/gems/kubemq',
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'google-protobuf', '~> 4.0'
  spec.add_dependency 'grpc', '~> 1.65'
end
