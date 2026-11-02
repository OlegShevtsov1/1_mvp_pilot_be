require 'rails_helper'
require 'kamal'

RSpec.describe 'config/deploy.prod-srv.yml' do
  let(:name) { project_env.fetch('PROJECT_NAME') }
  let(:zone) { project_env.fetch('PROJECT_ZONE') }
  let(:host) { '192.0.2.80' }

  def load_config(file, env)
    with_env({ 'KAMAL_REGISTRY_SERVER' => 'registry.example.test' }.merge(env)) do
      Dir.chdir(Rails.root) do
        Kamal::Configuration.create_from(config_file: Pathname(file), version: 'prod-sha-x')
      end
    end
  end

  let(:config) { load_config('config/deploy.prod-srv.yml', 'PROD_SRV_VPN_IP' => host, 'PROD_VPN_IP' => nil) }
  let(:aws) { load_config('config/deploy.yml', 'PROD_VPN_IP' => '192.0.2.70') }

  it 'deploys the <name> service from the promoted <name> image as its own <name>-prod user' do
    expect(config.service).to eq(name)
    expect(config.absolute_image).to eq("registry.example.test/#{name}:prod-sha-x")
    expect(config.ssh.user).to eq("#{name}-prod")
  end

  it 'points every role and accessory only at PROD_SRV_VPN_IP, never at the AWS host' do
    expect(config.all_hosts).to eq([ host ])
    expect(config.primary_host).to eq(host)
    config.roles.each { |role| expect(role.hosts).to eq([ host ]), role.name }
    config.accessories.each { |accessory| expect(accessory.hosts).to eq([ host ]), accessory.name }
  end

  it 'needs PROD_SRV_VPN_IP, which is never committed' do
    expect { load_config('config/deploy.prod-srv.yml', 'PROD_SRV_VPN_IP' => nil, 'PROD_VPN_IP' => '192.0.2.70') }
      .to raise_error(KeyError)
  end

  it 'routes only <zone> through the shared proxy with forwarded headers, TLS being terminated in front of it' do
    proxy = config.role(:web).proxy

    expect(proxy.ssl?).to be(false)
    expect(proxy.deploy_options[:host]).to eq([ zone ])
    expect(proxy.deploy_options[:'forward-headers']).to be(true)
    expect(proxy.deploy_options[:'health-check-path']).to eq('/health')
  end

  it "keeps the shared proxy's ports if it ever had to be started" do
    run = config.proxy_run(host)

    expect([ run.http_port, run.https_port ]).to eq([ 8091, 8491 ])
  end

  it 'gives the health check and smoke the port its proxy listens on' do
    script_port = Rails.root.join('deploy/_common.sh').read[/^PROXY_HTTP_PORT=(\d+)$/, 1]

    expect(script_port).to eq(config.proxy_run(host).http_port.to_s)
  end

  it 'uses names distinct from the dev deployment and the other deployment on the host' do
    names = [ config.service, *config.roles.map(&:container_prefix), *config.accessories.map(&:service_name),
              *config.accessories.flat_map(&:volume_args).grep_v('--volume') ]

    expect(names).to include("#{name}-web", "#{name}-cron", "#{name}-db", "#{name}-redis")
    names.each { |used| expect(used).not_to start_with("#{name}-dev", "#{name}-srv") }
  end

  it 'differs from config/deploy.yml only in the host, the user and the proxy' do
    expect(config.env.clear).to eq(aws.env.clear)
    expect(config.env.secret_keys).to eq(aws.env.secret_keys)
    expect(config.secrets_path).to eq(aws.secrets_path)
    expect(config.roles.map(&:name)).to eq(aws.roles.map(&:name))
    expect(config.role(:cron).cmd).to eq(aws.role(:cron).cmd)
    expect(config.accessories.map(&:service_name)).to eq(aws.accessories.map(&:service_name))
    expect(config.accessories.map(&:volume_args)).to eq(aws.accessories.map(&:volume_args))
    expect(config.accessories.map(&:image)).to eq(aws.accessories.map(&:image))
    expect(config.accessories.map { |accessory| accessory.env.clear }).to eq(aws.accessories.map { |accessory| accessory.env.clear })
    expect(config.accessories.map { |accessory| accessory.env.secret_keys }).to eq(aws.accessories.map { |accessory| accessory.env.secret_keys })
    expect(config.deploy_timeout).to eq(aws.deploy_timeout)
  end
end
