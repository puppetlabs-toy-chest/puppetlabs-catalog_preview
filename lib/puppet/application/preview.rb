require 'puppet/application'
require 'puppet/file_system'
require 'puppet_x/puppetlabs/preview'
require 'puppet/util/colors'
require 'puppet/pops'

class Puppet::Application::Preview < Puppet::Application
  run_mode :master

  option("--debug", "-d")

  option("--baseline_environment ENV_NAME,", "--be ENV_NAME") do |arg|
    options[:baseline_environment] = arg
  end

  option("--preview_environment ENV_NAME", "--pe ENV_NAME") do |arg|
    options[:preview_environment] = arg
  end

  option("--view OPTION") do |arg|
    if %w{summary diff baseline preview baseline_log preview_log none}.include?(arg)
      options[:view] = arg.to_sym
    else
      raise "The --view option only accepts a restricted list of arguments. Run 'puppet preview --help' for more details"
    end
  end

  option("--last", "-l")

  option("--migrate", "-m") do |arg|
    options[:migration_checker] = PuppetX::Puppetlabs::Migration::MigrationChecker.new
  end

  option("--assert OPTION") do |arg|
    if %w{equal compliant}.include?(arg)
      options[:assert] = arg.to_sym
    else
      raise "The --assert option only accepts 'equal' or 'compliant' as arguments.\nRun 'puppet preview --help' for more details"
    end
  end

  option("--schema CATALOG") do |arg|
    if %w{catalog catalog_delta help}.include?(arg)
      options[:schema] = arg.to_sym
    else
      raise "The --schema option only accepts 'catalog', 'catalog_delta', or 'help' as arguments.\nRun 'puppet preview --help' for more details"
    end
  end

  option("--skip_tags")

  option("--verbose_diff", "-vd")

  CatalogDelta = PuppetX::Puppetlabs::Migration::CatalogDeltaModel::CatalogDelta

  def help
    path = ::File.expand_path( "../../../../api/documentation/preview-help.md", __FILE__)
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
      $stderr.puts "Canceling startup"
      exit(0)
    end

    # save ARGV to protect us from it being smashed later by something
    @argv = ARGV.dup
  end

  def run_command
    options[:node] = command_line.args.shift

    if options[:schema]
      if options[:node]
        raise "A node was given but no compilation will be done when running with the --schema option"
      end

      if options[:schema] == :catalog
        catalog_path = ::File.expand_path("../../../../api/schemas/catalog.json", __FILE__)
        display_file(catalog_path)
      elsif options[:schema] == :catalog_delta
        delta_path = ::File.expand_path("../../../../api/schemas/catalog-delta.json", __FILE__)
        display_file(delta_path)
      else
        help_path = ::File.expand_path("../../../../api/documentation/catalog-delta.md", __FILE__)
        display_file(help_path)
      end
    else
      unless options[:node]
        raise "No node to perform preview compilation given"
      end

      if options[:last]
        if %w{summary none}.include?(options[:view].to_s)
          raise "--view #{options[:view].to_s} can not be combined with the --last option"
        end

        last
      else
        unless options[:preview_environment]
          raise "No --preview_environment given - cannot compile and produce a diff when only the environment of the node is known"
        end

        compile
      end
    end
  end

  def compile
    @exit_code = -1 # assume something will go wrong in general
    prepare_output

    # Compilation start time
    timestamp = Time.now.iso8601(9)

    # COMPILE
    #
    Puppet[:catalog_terminus] = :diff_compiler
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
      of.write(PSON::pretty_generate(catalog_delta, :allow_nan => true, :max_nesting => false))
    end

    view(catalog_delta)

    # Set exit code for assertion status
    case options[:assert]
    when :equal
      @exit_code = catalog_delta[:preview_equal] ? 0 : 4
    when :compliant
      @exit_code = catalog_delta[:preview_compliant] ? 0 : 5
    else
      @exit_code = 0
    end

    rescue PuppetX::Puppetlabs::Preview::GeneralError => e
      @exit_code = 1
      @exception = e

    rescue PuppetX::Puppetlabs::Preview::BaselineCompileError => e
      @exit_code = 2
      @exception = e

    rescue PuppetX::Puppetlabs::Preview::PreviewCompileError => e
      @exit_code = 3
      @exception = e

    ensure
      terminate_logs
      Puppet::Util::Log.close_all()
      Puppet::Util::Log.newdestination(:console)

      case @exit_code
      when 2
        display_log(options[:baseline_log], :pretty_json)
        $stderr.puts Colorizer.new().colorize(:hred, "Run 'puppet preview #{options[:node]} --last --view baseline_log' for full details")

      when 3
        display_log(options[:preview_log], :pretty_json)
        $stderr.puts Colorizer.new().colorize(:hred, "Run 'puppet preview #{options[:node]} --last --view preview_log' for full details")

      end
      Puppet.err(@exception.message) if @exception
      exit(@exit_code)
  end

  def last
    prepare_output_options
    view(nil)
  end

  def view(catalog_delta)
    # Produce output as directed by the :view option
    #
    case options[:view]
    when :diff
        display_file(options[:catalog_diff])
    when :baseline_log
      display_file(options[:baseline_log])
    when :preview_log
      display_file(options[:preview_log])
    when :baseline
      display_file(options[:baseline_catalog])
    when :preview
      display_file(options[:preview_catalog])
    when :none
      # One line status if catalogs are equal or not
      display_status(catalog_delta)
    else
      display_summary(catalog_delta)
      display_status(catalog_delta)
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
    options[:baseline_catalog] = Puppet::FileSystem.pathname(File.join(node_output_dir, "baseline_catalog.json"))
    options[:baseline_log]     = Puppet::FileSystem.pathname(File.join(node_output_dir, "baseline_log.json"))
    options[:preview_catalog]  = Puppet::FileSystem.pathname(File.join(node_output_dir, "preview_catalog.json"))
    options[:preview_log]      = Puppet::FileSystem.pathname(File.join(node_output_dir, "preview_log.json"))
    options[:catalog_diff]     = Puppet::FileSystem.pathname(File.join(node_output_dir, "catalog_diff.json"))
  end

  def prepare_output
    prepare_output_options

    # Truncate all output files to ensure output is not a mismatch of old and new
    Puppet::FileSystem.open(options[:baseline_log], 0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:preview_log],  0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:baseline_catalog], 0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:preview_catalog],  0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:catalog_diff], 0660, 'wb') { |of| of.write('') }

    # make the log paths absolute (required to use them as log destinations).
    options[:preview_log]      = options[:preview_log].realpath
    options[:baseline_log]     = options[:baseline_log].realpath
  end

  def catalog_diff(timestamp, baseline_hash, preview_hash)
    delta = CatalogDelta.new(baseline_hash['data'], preview_hash['data'], options[:skip_tags], options[:verbose_diff])
    result = delta.to_hash

    # Finish result by supplying information that is not in the catalogs and not produced by the diff utility
    #
    result[:produced_by]      = 'puppet preview 3.8.0'
    result[:timestamp]        = timestamp
    result[:baseline_catalog] = options[:baseline_catalog]
    result[:preview_catalog]  = options[:preview_catalog]
    result[:node_name]        = options[:node]

    result
  end

  def display_file(file)
    Puppet::FileSystem.open(file, nil, 'rb') do |source|
      FileUtils.copy_stream(source, $stdout)
      puts "" # ensure a new line at the end
    end
  end

  def level_label(level)
    case level
    when :err, "err"
      "ERROR"
    else
      level.to_s.upcase
    end
  end

  def display_log(file_name, pretty_json = false)
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
      $stderr.puts  Colorizer.new().colorize(:hred, message)
    end
  end

  class Colorizer
    include Puppet::Util::Colors
  end

  def display_summary(delta)
    compliant_count = delta[:conflicting_resources].count {|r| r[:compliant] }
    compliant_attr_count = delta[:conflicting_resources].reduce(0) do |memo, r|
      memo + r[:conflicting_attributes].count {|a| a[:compliant] }
    end

    $stdout.puts <<-TEXT

Catalog:
  Versions......: #{delta[:version_equal] ? 'equal' : 'different' }
  Preview.......: #{delta[:preview_equal] ? 'equal' : delta[:preview_compliant] ? 'compliant' : 'different'}
  Tags..........: #{delta[:tags_ignored] ? 'ignored' : 'compared'}

Resources:
  Baseline......: #{delta[:baseline_resource_count]}
  Preview.......: #{delta[:preview_resource_count]}
  Equal.........: #{delta[:equal_resource_count]}
  Compliant.....: #{compliant_count}
  Missing.......: #{delta[:missing_resource_count]}
  Added.........: #{delta[:added_resource_count]}
  Conflicting...: #{delta[:conflicting_resource_count] - compliant_count}

Attributes:
  Equal.........: #{delta[:equal_attribute_count]}
  Compliant.....: #{compliant_attr_count}
  Missing.......: #{delta[:missing_attribute_count]}
  Added.........: #{delta[:added_attribute_count]}
  Conflicting...: #{delta[:conflicting_attribute_count] - compliant_attr_count}

Edges:
  Baseline......: #{delta[:baseline_edge_count]}
  Preview.......: #{delta[:preview_edge_count]}
  Missing.......: #{count_of(delta[:missing_edges])}
  Added.........: #{count_of(delta[:added_edges])}

Output:
  For node......: #{Puppet[:preview_outputdir]}/#{options[:node]}

      TEXT
  end

  def display_status(delta)
    preview_equal     = !!(delta[:preview_equal])
    preview_compliant = !!(delta[:preview_compliant])
    status = preview_equal ? "equal" : preview_compliant ? "not equal but compliant" : "neither equal nor compliant"
    color = preview_equal || preview_compliant ? :green : :hred
    $stderr.puts Colorizer.new.colorize(color, "Catalogs for node '#{options[:node]}' are #{status}.")
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
    #
    Puppet::FileSystem.open(options[:baseline_log], nil, 'ab') { |of| of.write("\n]") }
    Puppet::FileSystem.open(options[:preview_log],  nil, 'ab') { |of| of.write("\n]") }
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
    raise Puppet::Error.new("Puppet preview is not supported on Microsoft Windows") if Puppet.features.microsoft_windows?

    setup_logs

    exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

    Puppet.settings.use :main, :master, :ssl, :metrics

    setup_terminuses

    # TODO: Do we need this in preview? It sets up a write only cache
    setup_node_cache

    setup_ssl
  end

end
