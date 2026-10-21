# frozen_string_literal: true

require_relative "lib/shotwolf/version"

Gem::Specification.new do |spec|
  spec.name = "shotwolf"
  spec.version = Shotwolf::VERSION
  spec.authors = ["ShotWolf"]
  spec.email = ["hello@shotwolf.com"]

  spec.summary = "Official Ruby SDK for the ShotWolf screenshot, mockup, OG image, HTML-to-PDF and visual-diff API."
  spec.description = "Ruby client for the ShotWolf API - capture screenshots, render device mockups, " \
                     "generate Open Graph cards, convert HTML to PDF, and run pixel-level visual " \
                     "regression diffs through a single JSON HTTP API. Zero dependencies."
  spec.homepage = "https://shotwolf.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => "https://shotwolf.com",
    "source_code_uri" => "https://github.com/shotwolf/ruby",
    "documentation_uri" => "https://shotwolf.com/docs/sdks/",
    "bug_tracker_uri" => "https://github.com/shotwolf/ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
