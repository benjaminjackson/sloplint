# frozen_string_literal: true

require_relative "../lib/sloplint"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
