source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '~> 3.3'
gem 'rails', '~> 7.2.3', '>= 7.2.3.2'
gem 'pg', '~> 1.1'
# Pinned to the rack 3.1 series: 3.1.21+ carries every published rack security
# fix. Rails 7.2.3.2 also permits rack 3.2, so drop this pin when Rails moves.
gem 'rack', '~> 3.1.21'
gem 'dotenv-rails', '>= 3.1.1'
gem 'puma', '~> 7.2.1'
gem 'bootsnap', require: false
gem 'devise', '~> 5.0', '>= 5.0.4'
gem 'simple_token_authentication', '~> 1.18'
gem 'rswag-api'
gem 'rswag-ui'
gem 'cancancan', '~> 3.5'
gem 'redis', '~> 5.1'
gem 'redis-rails', '~> 5.0'
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
  gem 'rubocop', '1.76.1', require: false
  gem 'rubocop-performance', '1.25.0'
  gem 'rubocop-rspec', '3.6.0', require: false
  gem 'rubocop-rails-omakase', require: false
end

group :test do
  gem 'rspec', '~> 3.10'
  gem 'simplecov', '0.22.0', require: false
  gem 'rswag-specs'
  gem 'webmock', '~> 3.32'
end

gem 'bullet'
gem 'rspec-rails', '~> 5.0'
gem 'rubocop-rails'
gem 'shoulda-matchers'
gem 'listen'
gem 'factory_bot_rails'
gem 'rails-controller-testing'
gem 'rspec_junit_formatter'
gem 'active_model_serializers', '~> 0.10.13'
