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
    begin
      Puppet[:catalog_terminus] = :diff_compiler
      # Do the compilations and get the catalogs
      unless result = Puppet::Resource::Catalog.indirection.find(options[:node], options)
        # TODO: Should always produce a result and give better error depending on what failed
        #
        raise "Could not compile catalogs for #{options[:node]}"
      end

      # Write the two catalogs to output files
      Puppet::FileSystem.open(options[:baseline_catalog], 0640, 'wb') do |of|
        of.write(PSON::pretty_generate(result[:baseline].to_resource, :allow_nan => true, :max_nesting => false))
      end
      Puppet::FileSystem.open(options[:preview_catalog], 0640, 'wb') do |of|
        of.write(PSON::pretty_generate(result[:preview].to_resource, :allow_nan => true, :max_nesting => false))
      end

      # TODO: Produce a diff
      # take the two catalogs and ask for their `to_data_hash` and give that to the diff utility
      # which then produces a diff hash (which is written with PSON pretty_generate
      #
      # TODO HACK: Create a fake diff to be able to write the summary output

      # TODO: View summary, baseline catalog/log, preview catalog/log, or none
      # Base the view of copying one of the outputs from where it is written to file to stdout


    rescue => detail
      # TODO: Should give better error depending on what failed (when)
      Puppet.log_exception(detail, "Failed to compile catalogs for node #{options[:node]}: #{detail}")
      exit(30)
    end
    exit(0)
  end

  def prepare_output
    # TODO: Deal with the output directory
    # It should come from a puppet setting which user can override - that currently does not exist
    # while developing simply write files to CWD
    options[:output_dir] = "./PREVIEW_OUTPUT"

    # Make sure the output directory for the node exists
    node_output_dir = Puppet::FileSystem.pathname(File.join(options[:output_dir], options[:node]))
    options[:node_output_dir] = node_output_dir
    Puppet::FileSystem.mkpath(options[:node_output_dir])

    # Construct file name for this diff
    options[:baseline_catalog] = Puppet::FileSystem.pathname(File.join(node_output_dir, "baseline_catalog.json"))
    options[:baseline_log]     = Puppet::FileSystem.pathname(File.join(node_output_dir, "baseline_log.json"))
    options[:preview_catalog]  = Puppet::FileSystem.pathname(File.join(node_output_dir, "preview_catalog.json"))
    options[:preview_log]      = Puppet::FileSystem.pathname(File.join(node_output_dir, "preview_log.json"))
    options[:catalog_diff]     = Puppet::FileSystem.pathname(File.join(node_output_dir, "preview_log.json"))

    # TODO: Truncate all of them to ensure mix of output is not produced on error?
  end

  def setup_logs
    set_log_level

    # TODO: This uses console for everything...
    #
    Puppet::Util::Log.newdestination(:console)

    # # What master --compile did
#    if !options[:setdest]
#      if options[:node]
#        # We are compiling a catalog for a single node with '--compile' and logging
#        # has not already been configured via '--logdest' so log to the console.
#        Puppet::Util::Log.newdestination(:console)
#      elsif !(Puppet[:daemonize] or options[:rack])
#        # We are running a webrick master which has been explicitly foregrounded
#        # and '--logdest' has not been passed, assume users want to see logging
#        # and log to the console.
#        Puppet::Util::Log.newdestination(:console)
#      else
#        # No explicit log destination has been given with '--logdest' and we're
#        # either a daemonized webrick master or running under rack, log to syslog.
#        Puppet::Util::Log.newdestination(:syslog)
#      end
#    end
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
