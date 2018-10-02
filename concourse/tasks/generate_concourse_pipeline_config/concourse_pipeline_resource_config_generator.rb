require 'yaml'

class ConcoursePipelineResourceConfigGenerator

  def initialize(base_dir = ".", config_dir = '', templates_dir = '', output_dir = '')
    @pipelines = { 'pipelines' => [] }
    @pipelines_base_dir = base_dir
    @config_dir = config_dir
    @templates_dir = templates_dir
    @output_dir = output_dir
  end

  def execute
    validate_dir
    puts "execute"
    teams = list_teams
    teams.each do |team_name|
      puts "processing team #{team_name}"
      root_deployments = list_root_deployments(team_name)
      root_deployments.each do |root_deployment_name|
        puts "processing root_deployment #{root_deployment_name}"
        pipelines = list_pipelines(team_name, root_deployment_name)
        pipelines.each do |pipeline_config_filename|
          puts "processing #{pipeline_config_filename}"
          pipeline_name = File.basename(pipeline_config_filename, '.yml')
          vars_files = generate_vars_files(pipeline_name, root_deployment_name)
          add_pipeline(pipeline_name, team_name, pipeline_config_filename, vars_files)
        end

      end
    end
    @pipelines['pipelines'] = @pipelines['pipelines'].sort_by { |pipeline| pipeline['name'] }
    write_yaml
  end

  private

  def write_yaml
    puts "pipelines:"
    puts @pipelines.to_yaml
    pipeline_config_file = File.join(@output_dir,'pipelines-definitions.yml')
    File.open(pipeline_config_file, 'w') { |file| file.write(@pipelines.to_yaml) }
  end
  def list_teams
    Dir[File.join(@pipelines_base_dir, '*')].select { |item| File.directory?(item) }.map { |path| File.basename(path) }
  end

  def list_root_deployments(team = 'main')
    Dir[File.join(@pipelines_base_dir, team, '*')].select { |item| File.directory?(item) }.map { |path| File.basename(path) }
  end

  def list_pipelines(team = 'main', root_deployment)
    Dir[File.join(@pipelines_base_dir, team, root_deployment, '*')].select { |item| File.file?(item) }
  end


  def add_pipeline(name, team = 'main', config, vars_files)
    pipeline = {}
    pipeline['name'] = name
    pipeline['team'] = team
    pipeline['config_file'] = config
    pipeline['vars_files'] = vars_files || []
    @pipelines['pipelines']. << pipeline
  end

  def generate_vars_files(pipeline_name, root_deployment)
    vars_files = Dir[File.join(@config_dir, 'credentials-*.yml')].reject { |file| File.basename(file).include?('pipeline') || File.basename(file).include?('generated') }
    current_pipeline_config_file = File.join(@config_dir, "credentials-#{pipeline_name.gsub('-generated', '-pipeline')}.yml")
    vars_files << current_pipeline_config_file if File.exist?(current_pipeline_config_file)
    versions_file = File.join(@templates_dir, root_deployment, "#{root_deployment}-versions.yml")
    puts Dir[@templates_dir + '/**']
    raise "Missing version file: #{versions_file}" unless File.exist?(versions_file)
    vars_files << versions_file
    vars_files
  end

  def filter_empty_pipelines
    puts "This should be done at generation time !!!"
  end

  def validate_dir
    error_message = ''
    error_message << "\nPipelines directory does not exist: #{@pipelines_base_dir}" unless File.exist?(@pipelines_base_dir)
    error_message << "\nConfig directory does not exist: #{@config_dir}" unless File.exist?(@config_dir)
    error_message << "\nTemplates directory does not exist: #{@templates_dir}" unless File.exist?(@templates_dir)
    error_message << "\nOutput directory does not exist: #{@output_dir}" unless File.exist?(@output_dir)
    raise error_message unless error_message.empty?
  end
end

