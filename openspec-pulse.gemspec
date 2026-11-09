# frozen_string_literal: true

require_relative "lib/openspec_pulse/version"

Gem::Specification.new do |spec|
  spec.name = "openspec-pulse"
  spec.version = OpenspecPulse::VERSION
  spec.authors = ["Jacob Degeling"]
  spec.summary = "Reminds you which OpenSpec changes have gone quiet"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"
  spec.files = Dir["lib/**/*.rb", "bin/*", "assets/*"]
  spec.bindir = "bin"
  spec.executables = ["openspec-pulse"]
  spec.add_dependency "thor", "~> 1.3"
end
