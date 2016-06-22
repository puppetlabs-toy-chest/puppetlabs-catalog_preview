require 'puppet/application'
require 'puppet/file_system'
require 'puppet_x/puppetlabs/preview'
require 'puppet/util/colors'
require 'puppet/pops'
require 'puppet/interface'

class Puppet::Application::Preview < Puppet::Application

  include PuppetX::Puppetlabs::Migration

  class UsageError < RuntimeError; end

  NOT_EQUAL = 4
  NOT_COMPLIANT = 5

  MIGRATION_3to4 = '3.8/4.0'.freeze
  RUNHELP = "Run 'puppet preview --help for more details".freeze

  run_mode :master

  option('--debug', '-d')

  option('--baseline-environment ENV_NAME', '--baseline_environment ENV_NAME', '--be ENV_NAME') do |arg|
    options[:baseline_environment] = arg
  end

  option('--preview-environment ENV_NAME', '--preview_environment ENV_NAME', '--pe ENV_NAME') do |arg|
    options[:preview_environment] = arg
  end

  option('--view OPTION') do |arg|
    arg = arg.gsub(/-/, '_')
    if %w{overview overview_json summary diff baseline preview baseline_log preview_log none status
        failed_nodes diff_nodes equal_nodes compliant_nodes}.include?(arg)
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
    # Puppet 3.8.0's MigrationChecker does not have the method 'available_migrations' (but
    # it still supports the 3to4 migration)
    unless Puppet.version.start_with?('3.8.0') || options[:migration_checker].available_migrations[MIGRATION_3to4]
      raise "The (#{Puppet.version}) version of Puppet does not support the '#{arg}' migration kind.\n#{RUNHELP}"
    end

    if Puppet.version.start_with?('3.8.0')
      output_stream.puts(
        'Warning: Due to a bug in PE 3.8.0 you cannot set the parser setting per environment. '\
        'This means you  may not be able to use your desired migration workflow unless you upgrade to PE 3.8.1')
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
      raise "The --schema option only accepts 'catalog', 'catalog_delta', 'log', 'excludes', "\
       "or 'help' as arguments.\n#{RUNHELP}"
    end
  end

  option('--[no-]skip-tags', '--skip_tags')

  option('--[no-]diff-string-numeric', '--diff_string_numeric')

  option('--[no-]diff-array-value')

  option('--[no-]report-all')

  option('--[no-]skip-inactive-nodes')

  option('--trusted') do |_|
    options[:trusted] = true
  end

  option('--[no-]verbose-diff', '--verbose_diff', '-vd')

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
    Puppet::FileSystem.read(api_path('documentation', 'preview-help.md'))
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
    nodes = options[:nodes]
    if nodes.nil?
      nodes = command_line.args
    else
      nodes += command_line.args
    end
    options[:nodes] = nodes.uniq

    begin
      main
    rescue UsageError => err
      raise RuntimeError, err.message
    rescue Exception => err
      ## NOTE: when debugging spec failures, these two lines can be very useful
      #puts err.inspect
      #puts Puppet::Util.pretty_backtrace(err.backtrace)
      Puppet.log_exception(err)
      Puppet::Util::Log.force_flushqueue()
      @exit_code = GENERAL_ERROR
    end
    exit(@exit_code)
  end

  def latest_catalog_delta=(catalog_delta)
    @latest_catalog_delta = catalog_delta
  end

  def main
    if options[:clean]
      unless (options.keys - [:clean, :node, :nodes, :debug]).empty?
        raise UsageError, '--clean can only be used with options --nodes and --debug'
      end
      clean
      return @exit_code
    end

    if options[:excludes]
      raise UsageError, '--excludes cannot be used with --schema or --last' if options[:last] || options[:schema]
    end

    # Issue a deprecation warning unless JSON output is expected to avoid that the warning invalidates the output
    if options.include?(:trusted) && ![:overview_json, :baseline_log, :preview_log].include?(options[:view])
      Puppet.deprecation_warning('The --trusted option is deprecated and has no effect')
    end

    if options[:schema]
      unless options[:nodes].empty?
        raise UsageError,
          'One or more nodes were given but no compilation will be done when running with the --schema option'
      end

      case options[:schema]
      when :catalog
        catalog_path = api_path('schemas', 'catalog.json')
        display_file(catalog_path)
      when :catalog_delta
        delta_path = api_path('schemas', 'catalog-delta.json')
        display_file(delta_path)
      when :log
        log_path = api_path('schemas', 'log.json')
        display_file(log_path)
      when :excludes
        excludes_path = api_path('schemas', 'excludes.json')
        display_file(excludes_path)
      else
        help_path = api_path('documentation', 'catalog-delta.md')
        display_file(help_path)
      end
      @exit_code = 0
    else
      init_node_names_for_compile unless options[:last]

      if node_names.size > 1 && [:diff, :baseline, :preview, :baseline_log, :preview_log].include?(options[:view])
        raise UsageError, "The --view option '#{options[:view].to_s.gsub(/_/, '-')}' is not supported for multiple nodes"
      end

      if options[:last]
        last
        @exit_code = 0
      else
        unless options[:preview_environment] || options[:migrate]
          raise UsageError, 'Neither --preview_environment or --migrate given - cannot compile and produce a diff "\
                "when only the environment of the node is known'
        end

        if options.include?(:diff_string_numeric)
          if options[:migrate] != MIGRATION_3to4
            raise UsageError, '--diff-string-numeric can only be used in combination with --migrate 3.8/4.0'
          end
        else
          # the string/numeric diff is ignored when migrating from 3 to 4
          options[:diff_string_numeric] = options[:migrate] != MIGRATION_3to4
        end

        if options.include?(:diff_array_value)
          if options[:migrate] != MIGRATION_3to4
            raise UsageError, '--diff-array-value can only be used in combination with --migrate 3.8/4.0'
          end
        else
          options[:diff_array_value] = true # this is the default
        end

        if options.include?(:report_all)
          unless options[:view] == :overview
            raise UsageError, '--report-all can only be used in combination with --view overview'
          end
        else
          # Default is to just report the top ten nodes
          options[:report_all] = false
        end

        compile

        view

        assert_and_set_exit_code
      end
    end
    @exit_code
  end

  def assert_and_set_exit_code
    nodes = @overview.nil? ? [] : @overview.of_class(OverviewModel::Node)
    @exit_code =  nodes.reduce(0) do |result, node|
      exit_code = node.exit_code
      break exit_code if exit_code == BASELINE_FAILED
      exit_code > result ? exit_code : result
    end

    if @exit_code == CATALOG_DELTA
      case options[:assert]
      when :equal
        @exit_code = NOT_EQUAL if nodes.any? { |node| node.severity != :equal }
      when :compliant
        @exit_code = NOT_COMPLIANT if nodes.any? { |node| node.severity != :equal && node.severity != :compliant }
      end
    end
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

      begin
        # This call produces a catalog_delta, or sets @exit_code to something other than 0
        #
        timestamp = Time.now.iso8601(9)
        catalog_delta = compile_diff(node, timestamp)

        baseline_env = options[:back_channel][:baseline_environment]
        preview_env = options[:back_channel][:preview_environment]
        if baseline_env.to_s == preview_env.to_s && !options[:migrate]
          raise UsageError, "The baseline and preview environments for node '#{node}' are the same: '#{baseline_env}'"
        end

        if @exit_code == CATALOG_DELTA
          baseline_log = read_json(node, :baseline_log)
          preview_log = read_json(node, :preview_log)
          factory.merge(catalog_delta, baseline_log, preview_log)
          @latest_catalog_delta = catalog_delta
        else
          case @exit_code
          when BASELINE_FAILED
            display_log(options[:baseline_log])
            log = read_json(node, :baseline_log)
            factory.merge_failure(node, baseline_env, timestamp, @exit_code, log)
          when PREVIEW_FAILED
            display_log(options[:preview_log])
            log = read_json(node, :preview_log)
            factory.merge_failure(node, preview_env, timestamp, @exit_code, log)
          end
        end
      end
      @overview = factory.create_overview
    end
  end

  def compile_diff(node, timestamp)
    prepare_output(node)

    # Compilation start time
    @exit_code = 0

    begin

      # Do the compilations and get the catalogs
      unless result = Puppet::Resource::Catalog.indirection.find(node, options)
        # TODO: Should always produce a result and give better error depending on what failed
        #
        raise PuppetX::Puppetlabs::Preview::GeneralError, "Could not compile catalogs for #{node}"
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

      catalog_delta = catalog_diff(node, timestamp, baseline_hash, preview_hash)

      Puppet::FileSystem.open(options[:catalog_diff], 0640, 'wb') do |of|
        of.write(PSON::pretty_generate(catalog_delta.to_hash, :allow_nan => true, :max_nesting => false))
      end

      catalog_delta

    rescue PuppetX::Puppetlabs::Preview::BaselineCompileError => e
      @exit_code = BASELINE_FAILED
      @exception = e

    rescue PuppetX::Puppetlabs::Preview::PreviewCompileError => e
      @exit_code = PREVIEW_FAILED
      @exception = e

    ensure
      terminate_logs
      Puppet::FileSystem.open(options[:compile_info], 0640, 'wb') do |of|
        compile_info = {
          :exit_code => @exit_code,
          :baseline_environment => options[:back_channel][:baseline_environment].to_s,
          :preview_environment => options[:back_channel][:preview_environment].to_s,
          :time => timestamp
        }
        of.write(PSON::pretty_generate(compile_info))
      end
      Puppet::Util::Log.close_all
      Puppet::Util::Log.newdestination(:console)
    end
  end

  def last
    node_directories = Dir["#{Puppet[:preview_outputdir]}/*"]
    if node_directories.empty?
      raise UsageError, "There is no preview data in the specified output directory "\
        "'#{Puppet[:preview_outputdir]}', you must have data from a previous preview run to use --last"
    else
      available_nodes = node_directories.map { |dir| dir.match(/^.*\/([^\/]*)$/)[1] }

      unless (missing_nodes = node_names - available_nodes).empty?
        raise UsageError, "No preview data available for node(s) '#{missing_nodes.join(", ")}'"
      end

      generate_last_overview
      view
    end
  end

  def clean
    output_dir = Puppet[:preview_outputdir]
    node_names.each { |node| FileUtils.remove_entry_secure(File.join(output_dir, node)) }
    @exit_code = 0
  end

  def init_node_names_for_compile
    given_names = options[:nodes]
    raise UsageError, 'No node(s) given to perform preview compilation for' if given_names.nil? || given_names.empty?

    # If the face action 'node status' exists (provided by PuppetDB), then purge inactive and non existent nodes from the list
    node_face = Puppet::Interface[:node, :current]
    if using_puppetdb? && node_face.respond_to?(:status)
      skip_inactive = options.include?(:skip_inactive_nodes) ? options[:skip_inactive_nodes] : true
      given_names = given_names.select do |node_name|
        status = node_face.status(node_name)[0]
        if status.nil? || status.size < 1
          # An error has been output by the status action
          false
        elsif skip_inactive && !status['deactivated'].nil?
          # Notice unless JSON output is expected.
          Puppet.notice("Skipping inactive node '#{node_name}'") unless options[:view] == :overview_json
          false
        else
          true
        end
      end
      raise UsageError, 'No compilation can be performed since none of the given node(s) are active' if given_names.empty?
    end
    @node_names = given_names
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

  def view_node(node)
    # Produce output as directed by the :view option
    #
    case options[:view]
    when :diff
      display_node_file(node, options[:catalog_diff])
    when :baseline_log
      display_node_file(node, options[:baseline_log], true)
    when :preview_log
      display_node_file(node, options[:preview_log], true)
    when :baseline
      display_node_file(node, options[:baseline_catalog])
    when :preview
      display_node_file(node, options[:preview_catalog])
    end
  end

  def view
    # Produce output as directed by the :view option
    #
    case options[:view]
    when :diff, :baseline_log, :preview_log, :baseline, :preview
      node_names.each do |node|
        prepare_output_options(node)
        view_node(node)
      end
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
        display_summary(node_names[0], @latest_catalog_delta) unless @latest_catalog_delta.nil?
        display_status
      end
    end
  end

  def prepare_output_options(node)
    # TODO: Deal with the output directory
    # It should come from a puppet setting which user can override - that currently does not exist
    # while developing simply write files to CWD
    options[:output_dir] = Puppet[:preview_outputdir] # "./PREVIEW_OUTPUT"

    # Make sure the output directory for the node exists
    node_output_dir = Puppet::FileSystem.pathname(File.join(options[:output_dir], node))
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

  def prepare_output(node)
    prepare_output_options(node)

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

  def catalog_diff(node, timestamp, baseline_hash, preview_hash)
    excl_file = options[:excludes]
    excludes = excl_file.nil? ? [] : CatalogDeltaModel::Exclude.parse_file(excl_file)
    # Puppet 3 (Before PUP-3355) used a catalog format where the real data was under a
    # 'data' tag. After PUP-3355, the content outside 'data' was removed, and everything in
    # 'data' move up to the main body of "the hash".
    # Here this is normalized in order to support a mix of 3.x and 4.x catalogs.
    #
    baseline_hash = baseline_hash['data'] if baseline_hash.has_key?('data')
    preview_hash  = preview_hash['data']  if preview_hash.has_key?('data')
    delta_options = options.merge({:node => node})
    CatalogDeltaModel::CatalogDelta.new(baseline_hash, preview_hash, delta_options, timestamp, excludes)
  end

  # Displays a file, and if the argument pretty_json is truthy the file is loaded and displayed as
  # pretty json
  #
  def display_file(file, pretty_json=false)
    raise UsageError, "File '#{file} does not exist" unless File.exists?(file)
    display_existing_file(file, pretty_json)
  end

  def display_node_file(node, file, pretty_json=false)
    raise UsageError, "Preview data for node '#{node}' does not exist" unless File.exists?(file)
    display_existing_file(file, pretty_json)
  end

  def display_existing_file(file, pretty_json)
    out = output_stream
    if pretty_json
      Puppet::FileSystem.open(file, nil, 'rb') do |input|
        json = JSON.load(input)
        out.puts(PSON::pretty_generate(json, :allow_nan => true, :max_nesting => false))
      end
    else
      Puppet::FileSystem.open(file, nil, 'rb') do |source|
        FileUtils.copy_stream(source, out)
        out.puts '' # ensure a new line at the end
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
      error_stream.puts  Colorizer.new.colorize(:hred, message)
    end
  end

  class Colorizer
    include Puppet::Util::Colors
  end

  def display_summary(node, delta)
    out = output_stream

    if delta
      compliant_count = delta.conflicting_resources.count {|r| r.compliant? }
      compliant_attr_count = delta.conflicting_resources.reduce(0) do |memo, r|
        memo + r.conflicting_attributes.count {|a| a.compliant? }
      end

      out.puts <<-TEXT

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

    out.puts <<-TEXT
Output:
  For node......: #{Puppet[:preview_outputdir]}/#{node}

  TEXT

  end

  # Outputs the given _overview_ on `$stdout` or configured `:output_stream`. The output is either in JSON format
  # or in textual form as determined by _as_json_.
  #
  # @param overview [OverviewModel::Overview] the model to output
  # @param as_json [Boolean] true for JSON output, false for textual output
  #
  def display_overview(overview, as_json)
    report = OverviewModel::Report.new(overview)
    output_stream.puts(as_json ? report.to_json : report.to_text(!options[:report_all]))
  end

  def read_json(node, type)
    filename = options[type]
    json = nil
    source = File.read(filename)
    unless source.nil? || source.empty?
      begin
        json = JSON.load(source)
      rescue JSON::ParserError
      end
    end
    raise Puppet::Error, "Output for node #{node} is invalid - use --clean and/or recompile" if json.nil?
    json
  end

  def generate_last_overview
    factory = OverviewModel::Factory.new
    node_names.each do |node|
      prepare_output_options(node)

      compile_info = read_json(node, :compile_info)
      case compile_info['exit_code']
      when CATALOG_DELTA
        catalog_delta = CatalogDeltaModel::CatalogDelta.from_hash(read_json(node, :catalog_diff))
        factory.merge(catalog_delta, read_json(node, :baseline_log), read_json(node, :preview_log))
        @latest_catalog_delta = catalog_delta
      when BASELINE_FAILED
        factory.merge_failure(node, compile_info['time'], compile_info['baseline_environment'], 2, read_json(node, :baseline_log))
      when PREVIEW_FAILED
        factory.merge_failure(node, compile_info['time'], compile_info['preview_environment'], 3, read_json(node, :preview_log))
      end
    end
    @overview = factory.create_overview
  end

  def display_status
    return if @overview.nil?

    node = @overview.of_class(OverviewModel::Node)[0]
    out = output_stream

    colorizer = Colorizer.new
    case node.exit_code
    when BASELINE_FAILED
      out.puts colorizer.colorize(:hred, "Node #{node.name} failed baseline compilation.")
    when PREVIEW_FAILED
      out.puts colorizer.colorize(:hred, "Node #{node.name} failed preview compilation.")
    when CATALOG_DELTA

      if node.severity == :equal
        out.puts colorizer.colorize(:green, "Catalogs for node '#{node}' are equal.")
      elsif node.severity == :compliant
        out.puts "Catalogs for '#{node.name}' are not equal but compliant."
      else
        out.puts "Catalogs for '#{node.name}' are neither equal nor compliant."
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
    terminate_log(options[:baseline_log])
    terminate_log(options[:preview_log])
  end

  def terminate_log(filename)
    # Terminate a JSON log (the final ] is missing, and it must be provided to produce correct JSON)
    # Also, if nothing was logged, the opening [ is required, or the file will not be valid JSON
    #
    endtext = Puppet::FileSystem.size(filename) == 0 ? "[\n]\n" : "\n]\n"
    Puppet::FileSystem.open(filename, nil, 'ab') { |of| of.write(endtext) }
  end

  def using_puppetdb?
    Puppet::Node::Facts.indirection.terminus_class.to_s == 'puppetdb'
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
    # parser comparisons are type-sensitive. For example, a variable holding a
    # stringified fact will fail to compare against an integer.
    #
    # So, if PuppetDB is in use, we swap in a copy of the 2.x terminus which
    # uses the v4 API which returns properly structured and typed facts.
    if using_puppetdb?
      # Versions prior to pdb 3 uses the v3 REST API, but there is not easy
      # way to figure out which version is in use that works for both old
      # and new versions. The method 'Puppet::Util::Puppetdb.url_path' has
      # been removed in pdb 3 and is therefore used as a test. This means
      # that on pdb 3 catalog preview uses the default fact indirection.
      #
      require 'puppet/util/puppetdb'
      if Puppet::Util::Puppetdb.respond_to?(:url_path)
        Puppet::Node::Facts.indirection.terminus_class = :diff_puppetdb
      end
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
    raise Puppet::Error, 'Puppet preview is not supported on Microsoft Windows' if Puppet.features.microsoft_windows?

    # Make process owner current user unless process owner is 'root'
    unless Puppet.features.root?
      Puppet[:user] = Etc.getpwuid(Process.uid).name
      Puppet[:group] = Etc.getgrgid(Process.gid).name
    end

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

    out = output_stream

    summary.each do |category, nodes|
      case category
      when :error
        nodes.each do |node|
          if node[:exit_code] == BASELINE_FAILED
            out.puts Colorizer.new.colorize(:red, "baseline failed (#{node[:baseline_env]}): #{node[:name]}")
          elsif node[:exit_code] == PREVIEW_FAILED
            out.puts Colorizer.new.colorize(:red, "preview failed (#{node[:preview_env]}): #{node[:name]}")
          else
            out.puts Colorizer.new.colorize(:red, "general error (#{node[:preview_env]}): #{node[:name]}")
          end
        end
      when :conflicting
        nodes.each do |node|
          out.puts "catalog delta: #{node[:name]}"
        end
      when :compliant
        nodes.each do |node|
          out.puts "compliant: #{node[:name]}"
        end
      when :equal
        nodes.each do |node|
          out.puts Colorizer.new.colorize(:green, "equal: #{node[:name]}")
        end
      end
    end
  end

  def multi_node_status(stats)
    output_stream.puts <<-TEXT

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

    out = output_stream
    if options[:view] == :equal_nodes
      nodes[:equal].each do |node|
        out.puts node
      end
    elsif options[:view] == :compliant_nodes
      nodes[:compliant].each do |node|
        out.puts node
      end
      nodes[:equal].each do |node|
        out.puts node
      end
    else
      nodes[:error].each do |node|
        out.puts node
      end
      if options[:view] == :diff_nodes
        nodes[:conflicting].each do |node|
          out.puts node
        end
        if options[:assert] == :equal
          nodes[:compliant].each do |node|
            out.puts node
          end
        end
      end
    end
  end

  API_BASE = ::File.expand_path(::File.join('..', '..', '..', 'puppet_x', 'puppetlabs', 'preview', 'api'), __FILE__)

  def api_path(*segments)
    ::File.join(API_BASE, *segments)
  end

  def error_stream
    options[:error_stream] || $stderr
  end

  def output_stream
    options[:output_stream] || $stdout
  end
end
