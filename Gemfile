source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '~> 3.3'
gem 'rails', '~> 8.0.5', '>= 8.0.5.2'
gem 'pg', '~> 1.1'
# Pinned to the rack 3.1 series; the patched floor is enforced by
# spec/config/gemfile_lock_spec.rb. Rails 8.0 also permits rack 3.2; moving to
# it is a separate change.
gem 'rack', '~> 3.1.21'
gem 'dotenv-rails', '>= 3.1.1'
gem 'puma', '~> 7.2.1'
gem 'bootsnap', require: false
gem 'devise', '~> 5.0', '>= 5.0.4'
# No rubygems release allows Rails 8; this upstream commit only widens the Rails
# caps, its lib/ is identical to 1.18.1.
gem 'simple_token_authentication', github: 'gonzalo-bulnes/simple_token_authentication', ref: 'f1cba4e3e614932ffcb6dfd2d8bf03acd64cb1ec'
gem 'doorkeeper', '~> 5.9'
gem 'jwt', '~> 3.3'
gem 'rswag-api'
gem 'rswag-ui'
gem 'cancancan', '~> 3.5'
gem 'redis', '~> 5.1'
gem 'redis-actionpack', '~> 5.0'
gem 'sentry-ruby', '~> 7.1'
gem 'sentry-rails', '~> 7.1'
gem 'rack-cors', '~> 3.0'

group :development do
  gem 'brakeman', '7.0.2'
  gem 'kamal', '~> 2.12'
  gem 'bundler-audit', '0.9.2'
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
  gem 'fasterer', '0.11.0', require: false
  gem 'overcommit', '0.67.1', require: false
  gem 'rubocop', '1.86.2', require: false
  gem 'rubocop-performance', '1.25.0'
  gem 'rubocop-rspec', '3.6.0', require: false
  gem 'rubocop-rails-omakase', require: false
  gem 'rubocop-rails'
  gem 'bullet'
  gem 'listen'
end

group :development, :test do
  gem 'rspec-rails', '~> 5.0'
  gem 'factory_bot_rails'
end

group :test do
  gem 'rspec', '~> 3.10'
  gem 'simplecov', '0.22.0', require: false
  gem 'rswag-specs'
  gem 'webmock', '~> 3.32'
  gem 'shoulda-matchers'
  gem 'rails-controller-testing'
  gem 'rspec_junit_formatter'
end

gem 'active_model_serializers', '~> 0.10.13'
