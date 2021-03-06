require 'rspec'
require 'deployment_factory'

describe DeploymentFactory do
  let(:root_deployment_name) { 'main_depls' }
  let(:deployment_name) { 'my_deployment' }
  let(:config) { Config.new }
  let(:versions) do
    { 'deployment-name' => root_deployment_name, 'stemcell-version' => '10.0',
      'bosh-version' => '264.10.0',
      'bosh-openstack-cpi-release-version' => '37' }
  end

  describe '#initialize' do
    subject { described_class.new(root_deployment_name, versions, config) }

    context 'when version is valid' do
      it 'contains a stemcell version' do
        expect(subject.version_reference).to include('stemcell-version')
      end
    end

    context 'when version is invalid' do
      let(:versions) {}

      it 'raise an error about stemcell-version' do
        expect { subject }.to raise_error(RuntimeError, 'invalid version: missing stemcell version')
      end
    end

    context 'when config is valid' do
      it 'contains a stemcell name' do
        expect(subject.stemcell_name).to eq(Config::DEFAULT_STEMCELL)
      end
    end

    context 'when config is nil' do
      let(:config) {}

      it 'complains about nil config' do
        expect { subject }.to raise_error(RuntimeError, 'invalid config: cannot be nil')
      end
    end

    context 'when config is incomplete' do
      let(:config) { instance_double(Config) }

      it 'raises an error about stemcell-name' do
        allow(config).to receive(:stemcell_name).and_return('')

        expect { subject }.to raise_error(RuntimeError, /invalid config: missing stemcell, expected: a config with a stemcell name defined/)
      end
    end
  end

  describe '#load_file_with_iaas' do
    let(:deployment_factory) { described_class.new(root_deployment_name, versions, config) }
    let(:generic_deployment) { [Deployment.default(deployment_name)] }
    let(:loaded_deployment) { deployment_factory.load_file_with_iaas('dummy-filename.yml') }
    let(:my_deployment) { loaded_deployment.first }

    context 'when no iaas file exists' do
      let(:current_iaas_type) { 'a_custom_iaas' }

      it 'loads deployment-dependencies.yml' do
        allow(config).to receive(:iaas_type).and_return(current_iaas_type)
        allow(deployment_factory).to receive(:load_file).with('dummy-filename.yml').and_return(generic_deployment)
        allow(File).to receive(:exist?).with("dummy-filename-#{current_iaas_type}.yml").and_return(false)

        expect(my_deployment.details).to eq(Deployment.default_details)
      end
    end

    context 'when a iaas file exists' do
      let(:generic_deployment) do
        content = <<~YAML
          releases:
            my-bosh-release:
              base_location: https://bosh.io/d/github.com/
              repository: cloudfoundry/my-bosh-release
            overridden-bosh-release:
              base_location: to-be-overriden
              repository: to-be-overriden
        YAML
        details = YAML.safe_load(content)
        [Deployment.new(deployment_name, Deployment.default_details.merge(details))]
      end
      let(:iaas_deployment) do
        content = <<~YAML
          iaas-type: true
          releases:
            bosh-openstack-cpi-release:
              base_location: https://bosh.io/d/github.com/
              repository: cloudfoundry-incubator/bosh-openstack-cpi-release 
            overridden-bosh-release:
              base_location: https://bosh.io/d/github.com/
              repository: cloudfoundry/overridden-bosh-release
        YAML
        details = YAML.safe_load(content)
        [Deployment.new('iaas-override', details)]
      end
      let(:expected_details) do
        { 'iaas-type' => true,
          'releases' => {
            'my-bosh-release' => {'base_location' => 'https://bosh.io/d/github.com/', 'repository' => 'cloudfoundry/my-bosh-release'},
            'overridden-bosh-release' => {'base_location' => 'https://bosh.io/d/github.com/', 'repository' => 'cloudfoundry/overridden-bosh-release'},
            'bosh-openstack-cpi-release' => {'base_location' => 'https://bosh.io/d/github.com/', 'repository' => 'cloudfoundry-incubator/bosh-openstack-cpi-release'}
          },
          'stemcells' => {} }
      end

      it 'merge deployment-dependencies with iaas file' do
        allow(deployment_factory).to receive(:load_file).with('dummy-filename.yml').and_return(generic_deployment)
        allow(deployment_factory).to receive(:load_file).with('dummy-filename-openstack.yml').and_return(iaas_deployment)
        allow(File).to receive(:exist?).with("dummy-filename-#{config.iaas_type}.yml").and_return(true)

        expect(my_deployment.details).to eq(expected_details)
      end
    end
  end

  describe '#load_file' do
    context 'when file does not exist' do
      subject { described_class.new(root_deployment_name, versions, config).load_file 'dummy-filename.yml' }

      it 'raise an error' do
        expect { subject }.to raise_error(RuntimeError, /file not found: dummy-filename.yml/)
      end
    end

    context 'when filename is nil ' do
      subject { described_class.new(root_deployment_name, versions, config).load_file nil }

      it 'raise an error' do
        expect { subject }.to raise_error(RuntimeError, /invalid filename. Cannot be empty/)
      end
    end

    context 'when filename is empty ' do
      subject { described_class.new(root_deployment_name, versions, config).load_file '' }

      it 'raise an error' do
        expect { subject }.to raise_error(RuntimeError, /invalid filename. Cannot be empty/)
      end
    end
  end

  describe '#load' do
    let(:deployment_factory) { described_class.new(root_deployment_name, versions) }

    context 'when data is not set' do
      it 'raise an error' do
        expect { deployment_factory.load(deployment_name) }.
          to raise_error(RuntimeError, /invalid data. Cannot load empty data/)
      end
    end

    context 'when data is invalid' do
      let(:invalid_data) { YAML.load('invalid: true').to_s }

      it 'raise an error' do
        expect { deployment_factory.load(deployment_name, invalid_data) }.
          to raise_error(RuntimeError, /Invalid data. Missing root: 'deployment'/)
      end
    end

    context 'when deployment_name is not set' do
      it 'raise an error' do
        expect { deployment_factory.load }.to raise_error(RuntimeError, /invalid deployment_name. Cannot be empty/)
      end
    end

    context 'when deployment_name does not match yaml content' do
      let(:ntp_deployment_dependencies_content) { { 'deployment' => { 'ntp' => Deployment.default_details } } }

      it 'raise an error' do
        expect { deployment_factory.load('my-deployment', ntp_deployment_dependencies_content) }.to raise_error(RuntimeError, /Invalid deployment_name: expected <my-deployment> or <bosh-deployment> - Found <ntp>/)
      end
    end

    context 'when deployment dependencies yaml follows COA conventions' do
      let(:generic_deployment_dependencies_content) { { 'deployment' => { 'bosh-deployment' => Deployment.default_details } } }
      let(:deployment_name) { 'my-deployment' }
      let(:loaded_deployment) { deployment_factory.load(deployment_name, generic_deployment_dependencies_content) }
      let(:my_deployment) { loaded_deployment.first }

      it 'loads my_deployment' do
        expect(my_deployment.name).to eq(deployment_name)
      end
    end

    context 'when a deployment does not have any details' do
      let(:loaded_deployments) { deployment_factory.load(deployment_name, 'deployment' => { deployment_name => nil }) }

      it 'creates a deployment object with an empty details field' do
        expect(loaded_deployments.first).to have_attributes(name: deployment_name, details: {})
      end
    end

    context 'when a deployment is loaded' do
      let(:versions) do
        { 'deployment-name' => root_deployment_name, 'stemcell-version' => '10.0',
          'bosh-version' => '264.10.0',
          'bosh-openstack-cpi-release-version' => '37' }
      end
      let(:deployment_factory) { described_class.new(root_deployment_name, versions, config) }
      let(:loaded_deployments) { deployment_factory.load(deployment_name, 'deployment' => bosh_master_deployment) }
      let(:bosh_master_deployment) do
        my_yaml = <<~YAML
          #{deployment_name}:
            releases:
              bosh:
                base_location: https://bosh.io/d/github.com/
                repository: cloudfoundry/bosh
              bosh-openstack-cpi-release:
                base_location: https://bosh.io/d/github.com/
                repository: cloudfoundry-incubator/bosh-openstack-cpi-release
        YAML
        YAML.safe_load(my_yaml)
      end

      it 'creates an enhanced deployment' do
        expect(loaded_deployments.first).to have_attributes(name: deployment_name, details: include('stemcells' => { 'bosh-openstack-kvm-ubuntu-xenial-go_agent' => {} }))
      end
    end
  end
end
