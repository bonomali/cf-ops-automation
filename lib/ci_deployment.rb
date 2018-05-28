require 'yaml'

class CiDeployment
  attr_reader :base_path
  attr_accessor :content

  def initialize(path)
    @base_path = path
    @content = {}
  end

  # ci-deployment:
  #   ops-depls:
  #     target_name: concourse-ops
  #     pipelines:
  #       ops-depls-generated:
  #         config_file: concourse/pipelines/ops-depls-generated.yml
  #         vars_files:
  #           - master-depls/concourse-ops/pipelines/credentials-ops-depls-pipeline.yml
  #           - ops-depls/ops-depls-versions.yml
  #       ops-depls-cf-apps-generated:
  #         config_file: concourse/pipelines/ops-depls-cf-apps-generated.yml
  #         vars_files:
  #           - master-depls/concourse-ops/pipelines/credentials-ops-depls-pipeline.yml
  #           - ops-depls/ops-depls-versions.yml
  #

  def overview
    puts "Path CI deployment overview: #{base_path}"

    Dir[base_path].select { |file| File.directory? file }.each do |path|
      load_ci_deployment_from_dir(path)
    end

    puts "ci_deployment loaded: \n#{YAML.dump(content)}"
    content
  end

  def self.teams(overview)
    overview.map { |_, root_depls| root_depls }
      .map { |root_depls| root_depls['pipelines'] }
      .inject([]) { |array, item| array + item.to_a }
      .map { |_, pipeline_config| pipeline_config['team'] }
      .compact
      .uniq
  end

  def self.team(overview, root_deployment, pipeline_name)
    ci_root_deployment = overview[root_deployment]
    ci_pipelines = ci_root_deployment['pipelines'] unless ci_root_deployment.nil?
    ci_pipeline_found = ci_pipelines[pipeline_name] unless ci_pipelines.nil?
    ci_pipeline_found['team'] unless ci_pipeline_found.nil?
  end

  private

  def load_ci_deployment_from_dir(path)
    dir_basename = File.basename(path)
    puts "Processing #{dir_basename}"

    Dir[path + '/ci-deployment-overview.yml'].each do |deployment_file|
      load_ci_deployment_from_file(deployment_file, dir_basename)
    end
  end

  def load_ci_deployment_from_file(deployment_file, dir_basename)
    puts "CI deployment detected in #{dir_basename}"

    deployment = YAML.load_file(deployment_file)
    raise "#{deployment} - Invalid deployment: expected 'ci-deployment' key as yaml root" unless deployment && deployment['ci-deployment']

    begin
      deployment['ci-deployment'].each do |deployment_name, deployment_details|
        processes_ci_deployment_data(deployment_name, deployment_details, dir_basename)
      end
    rescue RuntimeError => runtime_error
      raise "#{deployment_file}: #{runtime_error}"
    end
  end

  def processes_ci_deployment_data(deployment_name, deployment_details, dir_basename)
    raise 'missing keys: expecting keys target and pipelines' unless deployment_details
    raise "Invalid deployment: expected <#{dir_basename}> - Found <#{deployment_name}>" if deployment_name != dir_basename
    content[deployment_name] = deployment_details

    raise 'No target defined: expecting a target_name' unless deployment_details['target_name']
    raise 'No pipeline detected: expecting at least one pipeline' unless deployment_details['pipelines']

    processes_pipeline_data(deployment_details)
  end

  # TODO: LP 07.05.18: Does this method do anything?
  def processes_pipeline_data(deployment_details)
    deployment_details['pipelines'].each do |pipeline_name, pipeline_details|
      raise 'missing keys: expecting keys vars_files and config_file (optional)' unless pipeline_details
      raise 'missing key: vars_files. Expecting an array of at least one concourse var file' unless pipeline_details['vars_files']

      unless pipeline_details['config_file']
        puts "Generating default value for key config_file in #{pipeline_name}"
        pipeline_details['config_file'] = "concourse/pipelines/#{pipeline_name}.yml"
      end
    end
  end
end