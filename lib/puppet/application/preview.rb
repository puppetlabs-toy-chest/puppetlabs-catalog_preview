require 'puppet/application'
require 'puppet_x/puppetlabs/preview'

class Puppet::Application::Preview < Puppet::Application
  run_mode :master

  option("--debug", "-d")
  option("--verbose", "-v")

  # internal option, only to be used by ext/rack/config.ru
  option("--rack")

  option("--migrate") do |arg|
    options[:migration_checker] = PuppetX::Puppetlabs::Migration::MigrationChecker.new
  end

  option("--logdest DEST",  "-l DEST") do |arg|
    handle_logdest_arg(arg)
  end

  option("--preview_environment ENV_NAME") do |arg|
    options[:preview_environment] = arg
  end

  #option("--compile host",  "-c host") do |arg|
   #options[:node] = arg
  #end

  def help
    <<-'HELP'
USAGE
-----
puppet preview [-d|--debug] [-h|--help] [--migrate]
  [-l|--logdest syslog|<FILE>|console] [-v|--verbose] [-V|--version]
  <node-name>

    HELP
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

    unless options[:node]
      raise "No node to perform preview compilation given"
    end

    unless options[:preview_environment]
      raise "No --preview_environment given - cannot compile and produce a diff when only the environment of the node is known"
    end

    prepare_output

    compile
  end

  def compile
    # Compilation start time
    timestamp = Time.now.iso8601(9)

    begin
      # COMPILE
      #
      Puppet[:catalog_terminus] = :diff_compiler
      # Do the compilations and get the catalogs
      unless result = Puppet::Resource::Catalog.indirection.find(options[:node], options)
        # TODO: Should always produce a result and give better error depending on what failed
        #
        raise "Could not compile catalogs for #{options[:node]}"
      end

      # Terminate the JSON logs (the final ] is missing, and it must be provided to produce correct JSON)
      #
      Puppet::FileSystem.open(options[:baseline_log], nil, 'ab') { |of| of.write("\n]") }
      Puppet::FileSystem.open(options[:preview_log],  nil, 'ab') { |of| of.write("\n]") }

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

      # Produce output as directed by the :view option
      #
      case options[:view]
      when :baseline_log
        display_file(options[:baseline_log])
      when :preview_log
        display_file(options[:preview_log])
      when :baseline_catalog
        display_file(options[:baseline_catalog])
      when :preview_catalog
        display_file(options[:preview_catalog])
      when :none
        # do nothing
      else
        display_summary(catalog_delta)
      end


    rescue => detail
      # TODO: Should give better error depending on what failed (when)
      Puppet.log_exception(detail, "Failed to compile catalogs for node #{options[:node]}: #{detail}")
      # TODO: Handle detailed exit codes
      exit(30)
    end

    # TODO: Handle detailed exit codes
    exit(0)
  end

  def prepare_output
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

    Puppet::FileSystem.open(options[:baseline_log], 0660, 'wb') { |of| of.write('') }
    Puppet::FileSystem.open(options[:preview_log],  0660, 'wb') { |of| of.write('') }

    # make the log paths absolute (required to use them as log destinations).
    options[:preview_log]      = options[:preview_log].realpath
    options[:baseline_log]     = options[:baseline_log].realpath
  end

  def catalog_diff(timestamp, baseline_hash, preview_hash)
    delta = PuppetX::Puppetlabs::Migration::CatalogDeltaModel::CatalogDelta.new(baseline_hash['data'], preview_hash['data'], false, false)
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
    Puppet::FileSystem.open(options[:baseline_catalog], nil, 'rb') do |source|
      FileUtils.copy_stream(source, $stdout)
      puts "" # ensure a new line at the end
    end
  end

  def display_summary(delta)
    preview_equal     = !!(delta[:preview_equal])
    preview_compliant = !!(delta[:preview_compliant])
    status = preview_equal ? "equal" : preview_compliant ? "compliant" : "neither equal nor compliant"
    puts "Catalogs for node '#{options[:node]}' are #{status}."
    puts "Passed #{delta[:passed_assertion_count]} of total #{delta[:assertion_count]} assertions"
    unless preview_equal
      puts "Baseline has: #{delta[:baseline_resource_count]} resources, and #{delta[:baseline_edge_count]} edges"
      puts "Preview has: #{delta[:preview_resource_count]} resources, and #{delta[:preview_edge_count]} edges"

      missing_r       = count_of(delta[:missing_resources])
      added_r         = count_of(delta[:added_resources])
      resource_diff = "Resource Diff: #{missing_r} missing, #{added_r} added, "
      if preview_compliant
        conflicting_r   = count_of(delta[:conflicting_resources])
        if conflicting_r > 0
          compliant_r = delta[:conflicting_resources].count {|r| r[:compliant] }
          conflicting_r -= compliant_r
          if compliant_r > 0
            resource_diff << "#{compliant_r} compliant, and #{conflicting_r} conflicting."
          else
            resource_diff << "and #{conflicting_r} conflicting."
          end
        end
      else
        conflicting_r   = count_of(delta[:conflicting_resources])
        resource_diff << "#{conflicting_r} with conflicting attributes."
      end
      puts resource_diff

      missing_e       = count_of(delta[:missing_edges])
      added_e         = count_of(delta[:added_edges])
      puts "Edge Diff: #{missing_e} missing, #{added_e} added."
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
