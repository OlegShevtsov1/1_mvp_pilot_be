require 'rails_helper'
require 'kamal'

RSpec.describe 'config/deploy.yml' do
  let(:name) { project_env.fetch('PROJECT_NAME') }
  let(:zone) { project_env.fetch('PROJECT_ZONE') }

  def load_config(env)
    with_env(env) do
      Dir.chdir(Rails.root) do
        Kamal::Configuration.create_from(config_file: Pathname('config/deploy.yml'), version: 'prod-sha-x')
      end
    end
  end

  let(:config) { load_config('PROD_VPN_IP' => '192.0.2.70', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test') }

  it 'deploys the <name> service from the <name> image to the prod VPN address' do
    expect(config.service).to eq(name)
    expect(config.absolute_image).to eq("registry.example.test/#{name}:prod-sha-x")
    expect(config.primary_host).to eq('192.0.2.70')
    expect(config.ssh.user).to eq('ubuntu')
  end

  it 'needs PROD_VPN_IP, which is never committed' do
    expect { load_config('PROD_VPN_IP' => nil, 'KAMAL_REGISTRY_SERVER' => 'registry.example.test') }.to raise_error(KeyError)
  end

  it 'serves <zone> over HTTPS terminated by kamal-proxy, without trusting client forwarded headers' do
    proxy = config.role(:web).proxy

    expect(proxy.ssl?).to be(true)
    expect(proxy.deploy_options[:host]).to eq([ zone ])
    expect(proxy.deploy_options[:tls]).to be(true)
    expect(proxy.deploy_options[:'health-check-path']).to eq('/health')
    expect(proxy.deploy_options[:'forward-headers']).not_to be(true)
  end

  it 'forces SSL and reports to the prod environment with the prod secrets' do
    expect(config.env.clear).to include('RAILS_FORCE_SSL' => 'true', 'SENTRY_ENVIRONMENT' => 'prod')
    expect(config.env.secret_keys).to contain_exactly('SECRET_KEY_BASE', 'DATABASE_URL', 'SENTRY_DSN', 'SENTRY_ALLOWED_FE_DSN', 'SMOKE_TOKEN')
    expect(config.secrets_path).to eq('.kamal/secrets.prod')
  end

  it 'passes GOOGLE_CLIENT_ID from the deploy environment as plain env, empty when unset' do
    env = { 'PROD_VPN_IP' => '192.0.2.70', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test' }

    expect(load_config(env.merge('GOOGLE_CLIENT_ID' => 'placeholder-client-id.example.test')).env.clear['GOOGLE_CLIENT_ID'])
      .to eq('placeholder-client-id.example.test')
    expect(load_config(env.merge('GOOGLE_CLIENT_ID' => nil)).env.clear['GOOGLE_CLIENT_ID']).to eq('')
  end

  it 'passes OAUTH_CLIENT_ID from the deploy environment as plain env, empty when unset' do
    env = { 'PROD_VPN_IP' => '192.0.2.70', 'KAMAL_REGISTRY_SERVER' => 'registry.example.test' }
    with_client_id = load_config(env.merge('OAUTH_CLIENT_ID' => 'placeholder-oauth-client-id'))

    expect(with_client_id.env.clear['OAUTH_CLIENT_ID']).to eq('placeholder-oauth-client-id')
    expect(with_client_id.env.secret_keys).not_to include('OAUTH_CLIENT_ID')
    expect(load_config(env.merge('OAUTH_CLIENT_ID' => nil)).env.clear['OAUTH_CLIENT_ID']).to eq('')
  end

  it 'keeps the database and redis data in named volumes' do
    expect(config.accessories.map(&:service_name)).to eq([ "#{name}-db", "#{name}-redis" ])
    expect(config.accessories.map(&:volume_args)).to eq([
      [ '--volume', "#{name}-pg-data:/var/lib/postgresql/data" ],
      [ '--volume', "#{name}-redis-data:/data" ]
    ])
  end

  it 'has no Kamal 1 / Traefik leftovers' do
    expect(Rails.root.join('config/deploy.yml').read).not_to match(/traefik/i)
  end

  it 'is the only config besides config/deploy.dev.yml: no destination overlays' do
    expect(Dir.glob('config/deploy.*.yml', base: Rails.root.to_s)).to eq([ 'config/deploy.dev.yml' ])
  end
end
