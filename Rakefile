# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

namespace :proto do
  desc 'Generate protobuf Ruby stubs (proto at repo root: clients/kubemq.proto; SDK in clients/kubemq-ruby/)'
  task :generate do
    sh 'grpc_tools_ruby_protoc ' \
       '--ruby_out=lib/kubemq/proto ' \
       '--grpc_out=lib/kubemq/proto ' \
       '-I ../ ' \
       '../kubemq.proto'
  end
end

task default: %i[rubocop spec]
