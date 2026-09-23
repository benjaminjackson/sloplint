# frozen_string_literal: true

source "https://rubygems.org"

# The gems themselves declare nothing here; this is for the specs and scripts.
group :development do
  gem "retries"
  gem "rspec"
  # Ruby 3.4 dropped csv from the default gems; script/calibrate still needs it to read RAID's prompts.
  gem "csv"
  # red-parquet needs an Arrow C library this machine doesn't have; njaremko/parquet-ruby
  # ships a prebuilt native extension for arm64-darwin and needs nothing else installed.
  gem "parquet"
end
