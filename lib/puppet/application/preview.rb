require 'puppet/application'
require 'puppet/file_system'
require 'puppet_x/puppetlabs/preview'
require 'puppet/util/colors'
require 'puppet/pops'

class Puppet::Application::Preview < Puppet::Application

  include PuppetX::Puppetlabs::Migration

  NOT_EQUAL = 4
  NOT_COMPLIANT = 5

  MIGRATION_3to4 = '3.8/4.0'.freeze
  RUNHELP = "Run 'puppet preview --help for more details".freeze

  run_mode :master

  option('--debug', '-d')

  option('--baseline_environment ENV_NAME,', '--be ENV_NAME') do |arg|
    options[:baseline_environment] = arg
  end

  option('--preview_environment ENV_NAME', '--pe ENV_NAME') do |arg|
    options[:preview_environment] = arg
  end

  option('--view OPTION') do |arg|
    if %w{overview overview_json summary diff baseline preview baseline_log preview_log none status failed_nodes diff_nodes equal_nodes compliant_nodes}.include?(arg)
      options[:view] = arg.to_sym
    else
      raise "The --view option only accepts a restricted list of arguments.\n#{RUNHELP}"
    end
  end

  option('--last', '-l')

  option('--migrate MIGRATION', '-m MIGRATION') do |arg|
    if MIGRATION_3to4 == arg
      options[:migrate] = arg
    else
      raise "The '#{arg}' is not a migration kind supported by this version of catalog preview. #{RUNHELP}"
    end
    options[:migration_checker] = MigrationChecker.new
    # Puppet 3.8.0's MigrationChecker does not have the method 'available_migrations' (but it still supports the 3to4 migration)
    unless Puppet.version.start_with?('3.8.0') || options[:migration_checker].available_migrations[MIGRATION_3to4]
      raise "The (#{Puppet.version}) version of Puppet does not support the '#{arg}' migration kind.\n#{RUNHELP}"
    end
  end

  option('--assert OPTION') do |arg|
    if %w{equal compliant}.include?(arg)
      options[:assert] = arg.to_sym
    else
      raise "The --assert option only accepts 'equal' or 'compliant' as arguments.\n#{RUNHELP}"
    end
  end

  option('--schema CATALOG') do |arg|
    if %w{catalog catalog_delta log help excludes}.include?(arg)
      options[:schema] = arg.to_sym
    else
      raise "The --schema option only accepts 'catalog', 'catalog_delta', 'log', 'excludes', or 'help' as arguments.\n#{RUNHELP}"
    end
  end

  option('--skip_tags')

  option('--diff_string_numeric')

  option('--trusted') do |_|
    unless Puppet.features.root?
      raise 'The --trusted option is only available when running as root'
    end
    # Allow root to keep authenticated in resurrected trusted data
    options[:trusted] = true
  end

  option('--verbose_diff', '-vd')

  option('--nodes NODES_FILE') do |arg|
    # Each line in the given file is a node name or space separated node names
    options[:nodes] = (arg == '-' ? $stdin.each_line : File.foreach(arg)).map {|line| line.chomp!.split }.flatten
  end

  option('--excludes EXCLUDES_FILE') do |arg|
    # File in excludes.json schema format
    options[:excludes] = arg
  end

  option('--clean')

  def help
    path = ::File.expand_path( '../../../puppet_x/puppetlabs/preview/api/documentation/preview-help.md', __FILE__)
    Puppet::FileSystem.read(path)
  end

  # Sets up the 'node_cache_terminus' default to use the Write Only Yaml terminus :write_only_yaml.
  # If this is not wanted, the setting ´node_cache_terminus´ should be set to nil.
  # @see Puppet::Node::WriteOnlyYaml
  # @see #setup_node_cache
  # @see puppet issue 16753
  #
  def app_defaults
    super.merge({
      :node_cache_terminus => :write_only_yaml,
      :facts_terminus => 'yaml'
    })
  end

  def preinit
    Signal.trap(:INT) do
      $stderr.puts 'Canceling startup'
      exit(0)
    end

    # save ARGV to protect us from it being smashed later by something
    @argv = ARGV.dup
  end

  def run_command
    options[:node] = command_line.args
    unless options[:nodes].is_a?(Array)
      options[:nodes] = []
    end
    options[:nodes] |= command_line.args

    if options[:clean]
      raise '--clean can only be used with options --nodes and --debug' unless (options.keys - [:clean, :node, :nodes, :debug]).empty?
      exit(clean)
    end

    if options[:excludes]
      raise '--excludes cannot be used with --schema or --last' if options[:last] || options[:schema]
    end

    if options[:schema]
      unless options[:nodes].empty?
        raise 'One or more nodes were given but no compilation will be done when running with the --schema option'
      end

      case options[:schema]
      when :catalog
        catalog_path = ::File.expand_path('../../../puppet_x/puppetlabs/preview/api/schemas/catalog.json', __FILE__)
        display_file(catalog_path)
      when :catalog_delta
        delta_path = ::File.expand_path('../../../puppet_x/puppetlabs/preview/api/schemas/catalog-delta.json', __FILE__)
        display_file(delta_path)
      when :log
        log_path = ::File.expand_path('../../../puppet_x/puppetlabs/preview/api/schemas/log.json', __FILE__)
        display_file(log_path)
      when :excludes
        excludes_path = ::File.expand_path('../../../puppet_x/puppetlabs/preview/api/schemas/excludes.json', __FILE__)
        display_file(excludes_path)
      else
        help_path = ::File.expand_path('../../../puppet_x/puppetlabs/preview/api/documentation/catalog-delta.md', __FILE__)
        display_file(help_path)
      end
    else
      if options[:nodes].empty? && !options[:last]
        raise 'No node(s) given to perform preview compilation for'
      end

      if options[:nodes].size > 1 && %w{diff baseline preview baseline_log preview_log }.include?(options[:view].to_s)
        raise "The --view option '#{options[:view]}' is not supported for multiple nodes"
      end

      if options[:last]
        if Dir["#{Puppet[:preview_outputdir]}/*"].empty?
          raise "There is no preview data in the specified output directory '#{Puppet[:preview_outputdir]}', you must have data from a previous preview run to use --last"
        else
          last
        end
      else
        unless options[:preview_environment]
          raise 'No --preview_environment given - cannot compile and produce a diff when only the environment of the node is known'
        end

        if options[:diff_string_numeric] && !options[:migration_checker] && !option[:migrate] == MIGRATION_3to4
          raise '--diff_string_numeric can only be used in combination with --migrate 3.8/4.0'
        end
        compile

        view

        assert_and_exit
      end
    end
  end

  def assert_and_exit
    nodes = @overview.of_class(OverviewModel::Node)
    @exit_code =  nodes.reduce(0) do |result, node|
      exit_code = node.exit_code
      break exit_code if exit_code == BASELINE_FAILED
      exit_code > result ? exit_code : result
    end

    exit(@exit_code) unless @exit_code == CATALOG_DELTA

    case options[:assert]
    when :equal
      @exit_code = NOT_EQUAL if nodes.any? { |node| node.severity != :equal }
    when :compliant
      @exit_code = NOT_COMPLIANT if nodes.any? { |node| node.severity != :equal && node.severity != :compliant }
    end

    exit(@exit_code)
  end

  def compile
    # COMPILE
    #
    Puppet[:catalog_terminus] = :diff_compiler

    # Ensure that the baseline and preview catalogs are not stored via the
    # catalog indirection (may go to puppet-db)- The preview application
    # has its own output directory (and purpose).
    #
    # TODO: Is there a better way to disable the cache ?
    #
    Puppet::Resource::Catalog.indirection.cache_class = false

    factory = OverviewModel::Factory.new

    # Hash where the DiffCompiler can propagate things like the name of the compiled baseline_environment even if the
    # compilation fails.
    #
    options[:back_channel] = {}

    node_names.each do |node|

      options[:node] = node
      begin
        # This call produces a catalog_delta, or sets @exit_code to something other than 0
        #
        timestamp = Time.now.iso8601(9)
        catalog_delta = compile_diff(timestamp)

        if options[:back_channel][:baseline_environment].to_s == options[:preview_environment]
          $stderr.puts "The baseline and preview environments for node '#{node}' are the same"
        end

        if @exit_code == CATALOG_DELTA
          baseline_log = JSON.load(File.read(options[:baseline_log]))
          preview_log = JSON.load(File.read(options[:preview_log]))
          factory.merge(catalog_delta, baseline_log, preview_log)
          @latest_catalog_delta = catalog_delta
        else
          case @exit_code
          when GENERAL_ERROR
            Puppet.log_exception(@exception)
            Puppet::Util::Log.force_flushqueue
            exit(@exit_code)
          when BASELINE_FAILED
            display_log(options[:baseline_log])
            log = JSON.load(File.read(options[:baseline_log]))
            factory.merge_failure(node, options[:back_channel][:baseline_environment], timestamp, @exit_code, log)
          when PREVIEW_FAILED
            display_log(options[:preview_log])
            log = JSON.load(File.read(options[:preview_log]))
            factory.merge_failure(node, options[:preview_environment], timestamp, @exit_code, log)
          end
        end
      end
      @overview = factory.create_overview
    end
  end

  def compile_diff(timestamp)
    prepare_output

    # Compilation start time
    @exit_code = 0

    begin

      # Do the compilations and get the catalogs
      unless result = Puppet::Resource::Catalog.indirection.find(options[:node], options)
        # TODO: Should always produce a result and give better error depending on what failed
        #
        raise "Could not compile catalogs for #{options[:node]}"
      end

      # WRITE the two catalogs to output files
      baseline_as_resource = result[:baseline].to_resource
      preview_as_resource = result[:preview].to_resource

      Puppet::FileSystem.open(options[:baseline_catalog], 0640, 'wb') do |of|
        of.write(PSON::pretty_generate(baseline_as_resource, :allow_nan => true, :max_nesting => false))
      end
      Puppet::FileSystem.open(options[:preview_catalog], 0640, 'wb') do |of|
        of.write(PSON::pretty_generate(preview_as_resource, :allow_nan => true, :max_nesting => false))
      end

      # Make paths real/absolute
      options[:baseline_catalog] = options[:baseline_catalog].realpath
      options[:preview_catalog]  = options[:preview_catalog].realpath

      # DIFF
      #
      # Take the two catalogs and produce pure hash (no class information).
      # Produce a diff hash using the diff utility.
      #
      baseline_hash = JSON::parse(baseline_as_resource.to_pson)
      preview_hash  = JSON::parse(preview_as_resource.to_pson)

      catalog_delta = catalog_diff(timestamp, baseline_hash, preview_hash)

      Puppet::FileSystem.open(options[:catalog_diff], 0640, 'wb') do |of|
        of.write(PSON::pretty_generate(catalog_delta.to_hash, :allow_nan => true, :max_nesting => false))
      end

      catalog_delta

    rescue PuppetX::Puppetlabs::Preview::GeneralError => e
      @exit_code = 1
      @exception = e

    rescue PuppetX::Puppetlabs::Preview::BaselineCompileError => e
      @exit_code = 2
      @exception = e

    rescue PuppetX::Puppetlabs::Preview::PreviewCompileError => e
      @exit_code = 3
      @exception = e

    rescue => e
      @exit_code = 1
      @exception = e

    ensure
      terminate_logs
      Puppet::FileSystem.open(options[:compile_info], 0640, 'wb') do |of|
        compile_info = {
          :exit_code => @exit_code,
          :baseline_environment => options[:back_channel][:baseline_environment].to_s,
          :preview_environment => options[:preview_environment],
          :time => timestamp
        }
        of.write(PSON::pretty_generate(compile_info))
      end
      Puppet::Util::Log.close_all
      Puppet::Util::Log.newdestination(:console)
    end
  end

  def last
    prepare_output_options
    view
  end

  def clean
    output_dir = Puppet[:preview_outputdir]
    node_names.each { |node| FileUtils.remove_entry_secure(File.join(output_dir, node)) }
    0
  rescue Exception => e
    $stderr.puts("Clean operation failed: #{e.message}")
    1
  end

  def node_names
    # If no nodes were specified, print everything we have
    if @node_names.nil?
      given_names = options[:nodes]
      @node_names = if given_names.nil? || given_names.empty?
        # Use the directories in preview_outputdir to get the list of nodes
        Dir.glob(File.join(Puppet[:preview_outputdir], '*')).select { |f| File.directory?(f) }.map { |f| File.basename(f) }
      else
        given_names
      end
    end
    @node_names
  end

  def view(catalog_delta = @latest_catalog_delta)
    if options[:last]
      generate_last_overview
      catalog_delta = @latest_catalog_delta
    end

    # Produce output as directed by the :view option
    #
    case options[:view]
    when :diff
      display_file(options[:catalog_diff])
    when :baseline_log
      display_file(options[:baseline_log], true)
    when :preview_log
      display_file(options[:preview_log], true)
    when :baseline
      display_file(options[:baseline_catalog])
    when :preview
      display_file(options[:preview_catalog])
    when :status
      if node_names.size > 1
        multi_node_status(generate_stats)
      else
        display_status
      end
    when :failed_nodes
      print_node_list
    when :diff_nodes
      print_node_list
    when :equal_nodes
      print_node_list
    when :compliant_nodes
      print_node_list
    when :overview
      display_overview(@overview, false)
    when :overview_json
      display_overview(@overview, true)
    when :none
      # print nothing
    else
      if node_names.size > 1
        multi_node_status(generate_stats)
        multi_node_summary
      else
        display_summary(catalog_delta)
        display_status
      end
    end
  end

  def prepare_output_options
    # TODO: Deal with the output directory
    # It should come from a puppet setting which user can override - that currently does not exist
    # while developing simply write files to CWD
    options[:output_dir] = Puppet[:preview_outputdir] # "./PREVIEW_OUTPUT"

    # Make sure the output directory for the node exists
    node_output_dir = Puppet::FileSystem.pathname(File.join(options[:output_dir], options[:node]))
    options[:node_output_dir] = node_output_dir
    Puppet::FileSystem.mkpath(options[:node_output_dir])
    Puppet::FileSystem.chmod(0750, options[:node_output_dir])

    # Construct file name for this diff
    options[:baseline_catalog] = Puppet::FileSystem.pathname(File.join(node_output_dir, 'baseline_catalog.json'))
    options[:baseline_log]     = Puppet::FileSystem.pathname(File.join(node_output_dir, 'baseline_log.json'))
    options[:preview_catalog]  = Puppet::FileSystem.pathname(File.join(node_output_dir, 'preview_catalog.json'))
    options[:preview_log]      = Puppet::FileSystem.pathname(File.join(node_output_dir, 'preview_log.json'))
    options[:catalog_diff]     = Puppet::FileSystem.pathname(File.join(node_output_dir, 'catalog_diff.json'))
    options[:compile_info]     = Puppet::FileSystem.pathname(File.join(node_output_dir, 'compile_info.json'))
  end

  def prepare_output
    prepare_output_options

    # Truncate all output files to ensure output is not a mismatch of old and new
    Puppet::FileSystem.open(options[:baseline_log], 0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:preview_log],  0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:baseline_catalog], 0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:preview_catalog],  0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:catalog_diff], 0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:compile_info], 0660, 'wb') { |of| of.write('') }

    # make the log paths absolute (required to use them as log destinations).
    options[:preview_log]      = options[:preview_log].realpath
    options[:baseline_log]     = options[:baseline_log].realpath
  end

  def catalog_diff(timestamp, baseline_hash, preview_hash)
    excl_file = options[:excludes]
    excludes = excl_file.nil? ? [] : CatalogDeltaModel::Exclude.parse_file(excl_file)
    CatalogDeltaModel::CatalogDelta.new(baseline_hash['data'], preview_hash['data'], options, timestamp, excludes)
  end

  # Displays a file, and if the argument pretty_json is truthy the file is loaded and displayed as
  # pretty json
  #
  def display_file(file, pretty_json=false)
    raise "Preview data for node '#{options[:node]}' does not exist" unless File.exists?(file)
    if pretty_json
      Puppet::FileSystem.open(file, nil, 'rb') do |input|
        json = JSON.load(input)
        $stdout.puts(PSON::pretty_generate(json, :allow_nan => true, :max_nesting => false))
      end
    else
      Puppet::FileSystem.open(file, nil, 'rb') do |source|
        FileUtils.copy_stream(source, $stdout)
        puts '' # ensure a new line at the end
      end
    end
  end

  def level_label(level)
    case level
    when :err, 'err'
      'ERROR'
    else
      level.to_s.upcase
    end
  end

  # Displays colorized essential information from the log (severity, message, and location)
  #
  def display_log(file_name)
    data = JSON.load(file_name)
    # Output only the bare essentials
    # TODO: PRE-16 (the stacktrace is in the message)
    data.each do |entry|
      message = "#{level_label(entry['level'])}: #{entry['message']}"
      file = entry['file']
      line = entry['line']
      pos = entry['pos']
      if file && line && pos
        message << "at #{entry['file']}:#{entry['line']}:#{entry['pos']}"
      elsif file && line
        message << "at #{entry['file']}:#{entry['line']}"
      elsif file
        message << "at #{entry['file']}"
      end
      $stderr.puts  Colorizer.new.colorize(:hred, message)
    end
  end

  class Colorizer
    include Puppet::Util::Colors
  end

  def display_summary(delta)

    if delta
      compliant_count = delta.conflicting_resources.count {|r| r.compliant? }
      compliant_attr_count = delta.conflicting_resources.reduce(0) do |memo, r|
        memo + r.conflicting_attributes.count {|a| a.compliant? }
      end

      $stdout.puts <<-TEXT

Catalog:
  Versions......: #{delta.version_equal? ? 'equal' : 'different' }
  Preview.......: #{delta.preview_equal? ? 'equal' : delta.preview_compliant? ? 'compliant' : 'conflicting'}
  Tags..........: #{delta.tags_ignored? ? 'ignored' : 'compared'}
  String/Numeric: #{delta.string_numeric_diff_ignored? ? 'numerically compared' : 'type significant compare'}

Resources:
  Baseline......: #{delta.baseline_resource_count}
  Preview.......: #{delta.preview_resource_count}
  Equal.........: #{delta.equal_resource_count}
  Compliant.....: #{compliant_count}
  Missing.......: #{delta.missing_resource_count}
  Added.........: #{delta.added_resource_count}
  Conflicting...: #{delta.conflicting_resource_count - compliant_count}

Attributes:
  Equal.........: #{delta.equal_attribute_count}
  Compliant.....: #{compliant_attr_count}
  Missing.......: #{delta.missing_attribute_count}
  Added.........: #{delta.added_attribute_count}
  Conflicting...: #{delta.conflicting_attribute_count - compliant_attr_count}

Edges:
  Baseline......: #{delta.baseline_edge_count}
  Preview.......: #{delta.preview_edge_count}
  Missing.......: #{count_of(delta.missing_edges)}
  Added.........: #{count_of(delta.added_edges)}

  TEXT
    end

    $stdout.puts <<-TEXT
Output:
  For node......: #{Puppet[:preview_outputdir]}/#{options[:node]}

  TEXT

  end

  # Outputs the given _overview_ on `$stdout`. The output is either in JSON format
  # or in textual form as determined by _as_json_.
  #
  # @param overview [OverviewModel::Overview] the model to output
  # @param as_json [Boolean] true for JSON output, false for textual output
  #
  def display_overview(overview, as_json)
    report = OverviewModel::Report.new(overview)
    $stdout.puts(as_json ? report.to_json : report.to_s)
  end

  def read_json(type)
    json = File.read(options[type])
    raise Puppet::Error.new("Output for node #{options[:node]} is invalid - use --clean and/or recompile") if json.nil? || json.empty?
    JSON.load(json)
  end

  def generate_last_overview
    factory = OverviewModel::Factory.new
    node_names.each do |node|
      options[:node] = node
      prepare_output_options

      compile_info = read_json(:compile_info)
      case compile_info['exit_code']
      when CATALOG_DELTA
        catalog_delta = CatalogDeltaModel::CatalogDelta.from_hash(read_json(:catalog_diff))
        factory.merge(catalog_delta, read_json(:baseline_log), read_json(:preview_log))
        @latest_catalog_delta = catalog_delta
      when BASELINE_FAILED
        factory.merge_failure(node, compile_info['time'], compile_info['baseline_environment'], 2, read_json(:baseline_log))
      when PREVIEW_FAILED
        factory.merge_failure(node, compile_info['time'], compile_info['preview_environment'], 3, read_json(:preview_log))
      end
    end
    @overview = factory.create_overview
  end

  def display_status

    node = @overview.of_class(OverviewModel::Node)[0]

    colorizer = Colorizer.new
    case node.exit_code
    when BASELINE_FAILED
      $stdout.puts colorizer.colorize(:hred, "Node #{node.name} failed baseline compilation.")
    when PREVIEW_FAILED
      $stdout.puts colorizer.colorize(:hred, "Node #{node.name} failed preview compilation.")
    when CATALOG_DELTA

      if node.severity == :equal
        $stdout.puts colorizer.colorize(:green, "Catalogs for node '#{options[:node]}' are equal.")
      elsif node.severity == :compliant
        $stdout.puts "Catalogs for '#{node.name}' are not equal but compliant."
      else
        $stdout.puts "Catalogs for '#{node.name}' are neither equal nor compliant."
      end
    end
  end

  def count_of(elements)
    return 0 if elements.nil?
    elements.size
  end

  def setup_logs
    # This sets up logging based on --debug or --verbose if they are set in `options`
    set_log_level

    # This uses console for everything that is not a compilation
    Puppet::Util::Log.newdestination(:console)
  end

  def terminate_logs
    # Terminate the JSON logs (the final ] is missing, and it must be provided to produce correct JSON)
    # Also, if nothing was logged, the opening [ is required, or the file will not be valid JSON
    #
    endtext = Puppet::FileSystem.size(options[:baseline_log]) == 0 ? "[\n]" : "\n]"
    Puppet::FileSystem.open(options[:baseline_log], nil, 'ab') { |of| of.write(endtext) }
    endtext = Puppet::FileSystem.size(options[:preview_log]) == 0 ? "[\n]" : "\n]"
    Puppet::FileSystem.open(options[:preview_log],  nil, 'ab') { |of| of.write(endtext) }
  end

  def configure_indirector_routes
    # Same implementation as the base Application class, except this loads
    # routes configured for the "master" application in order to conform with
    # the behavior of `puppet master --compile`
    #
    # TODO: In 4.0, this block can be replaced with:
    #     Puppet::ApplicationSupport.configure_indirector_routes('master')
    route_file = Puppet[:route_file]
    if Puppet::FileSystem.exist?(route_file)
      routes = YAML.load_file(route_file)
      application_routes = routes['master'] # <-- This line is the actual change.
      Puppet::Indirector.configure_routes(application_routes) if application_routes
    end

    # NOTE: PE 3.x ships PuppetDB 2.x and uses the v3 PuppetDB API endpoints.
    # These return stringified, non-structured facts. However, many Future
    # parser comparisions are type-sensitive. For example, a variable holding a
    # stringified fact will fail to compare against an integer.
    #
    # So, if PuppetDB is in use, we swap in a copy of the 2.x terminus which
    # uses the v4 API which returns properly structured and typed facts.
    if Puppet::Node::Facts.indirection.terminus_class.to_s == 'puppetdb'
      Puppet::Node::Facts.indirection.terminus_class = :diff_puppetdb
      # Ensure we don't accidentally use any facts that were cached from the
      # PuppetDB v3 API.
      Puppet::Node::Facts.indirection.cache_class = false
    end
  end

  def setup_terminuses
    require 'puppet/file_serving/content'
    require 'puppet/file_serving/metadata'

    Puppet::FileServing::Content.indirection.terminus_class = :file_server
    Puppet::FileServing::Metadata.indirection.terminus_class = :file_server

    Puppet::FileBucket::File.indirection.terminus_class = :file
  end

  def setup_ssl
    # Configure all of the SSL stuff.
    if Puppet::SSL::CertificateAuthority.ca?
      Puppet::SSL::Host.ca_location = :local
      Puppet.settings.use :ca
      Puppet::SSL::CertificateAuthority.instance
    else
      Puppet::SSL::Host.ca_location = :none
    end
    # These lines are not on stable (seems like a copy was made from master)
    #
    # Puppet::SSL::Oids.register_puppet_oids
    # Puppet::SSL::Oids.load_custom_oid_file(Puppet[:trusted_oid_mapping_file])
  end

  # Sets up a special node cache "write only yaml" that collects and stores node data in yaml
  # but never finds or reads anything (this since a real cache causes stale data to be served
  # in circumstances when the cache can not be cleared).
  # @see puppet issue 16753
  # @see Puppet::Node::WriteOnlyYaml
  # @return [void]
  def setup_node_cache
    Puppet::Node.indirection.cache_class = Puppet[:node_cache_terminus]
  end

  def setup
    raise Puppet::Error.new('Puppet preview is not supported on Microsoft Windows') if Puppet.features.microsoft_windows?

    setup_logs

    exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

    Puppet.settings.use :main, :master, :ssl, :metrics

    setup_terminuses

    # TODO: Do we need this in preview? It sets up a write only cache
    setup_node_cache

    setup_ssl
  end


  def generate_stats
    @overview.of_class(OverviewModel::Node).reduce(Hash.new(0)) do | result, node |
      case node.exit_code
      when BASELINE_FAILED
        result[:baseline_failed] += 1
      when PREVIEW_FAILED
        result[:preview_failed] += 1
      when CATALOG_DELTA
        result[:catalog_diff] += 1

        if node.severity == :equal
          result[:equal] += 1
        elsif node.severity == :compliant
          result[:compliant] += 1
        end
      end
    result
    end
  end

  def multi_node_summary
    summary = Hash[[ :equal, :compliant, :conflicting, :error ].map do |severity|
      [severity, @overview.of_class(OverviewModel::Node).select { |n| n.severity == severity }.sort.map do |n|
        { :name => n.name,
          :baseline_env => n.baseline_env.name,
          :preview_env => n.preview_env.name,
          :exit_code => n.exit_code
        }
      end]
    end]

    summary.each do |category, nodes|
      case category
      when :error
        nodes.each do |node|
          if node[:exit_code] == BASELINE_FAILED
            $stdout.puts Colorizer.new.colorize(:red, "baseline failed (#{node[:baseline_env]}): #{node[:name]}")
          elsif node[:exit_code] == PREVIEW_FAILED
            $stdout.puts Colorizer.new.colorize(:red, "preview failed (#{node[:preview_env]}): #{node[:name]}")
          else
            $stdout.puts Colorizer.new.colorize(:red, "general error (#{node[:preview_env]}): #{node[:name]}")
          end
        end
      when :conflicting
        nodes.each do |node|
          $stdout.puts "catalog delta: #{node[:name]}"
        end
      when :compliant
        nodes.each do |node|
          $stdout.puts "compliant: #{node[:name]}"
        end
      when :equal
        nodes.each do |node|
          $stdout.puts Colorizer.new.colorize(:green, "equal: #{node[:name]}")
        end
      end
    end
  end

  def multi_node_status(stats)
    $stdout.puts <<-TEXT

Summary:
  Total Number of Nodes...: #{@overview.of_class(OverviewModel::Node).length}
  Baseline Failed.........: #{stats[:baseline_failed]}
  Preview Failed..........: #{stats[:preview_failed]}
  Catalogs with Difference: #{stats[:catalog_diff]}
  Compliant Catalogs......: #{stats[:compliant]}
  Equal Catalogs..........: #{stats[:equal]}

  TEXT
  end

  def print_node_list
    nodes = Hash[[ :equal, :compliant, :conflicting, :error ].map do |severity|
      [severity, @overview.of_class(OverviewModel::Node).select { |n| n.severity == severity }.sort.map do |n|
        n.name
      end]
    end]

    if options[:view] == :equal_nodes
      nodes[:equal].each do |node|
        $stdout.puts node
      end
    elsif options[:view] == :compliant_nodes
      nodes[:compliant].each do |node|
        $stdout.puts node
      end
      nodes[:equal].each do |node|
        $stdout.puts node
      end
    else
      nodes[:error].each do |node|
        $stdout.puts node
      end
      if options[:view] == :diff_nodes
        nodes[:conflicting].each do |node|
          $stdout.puts node
        end
        if options[:assert] == :equal
          nodes[:compliant].each do |node|
            $stdout.puts node
          end
        end
      end
    end
  end

end
