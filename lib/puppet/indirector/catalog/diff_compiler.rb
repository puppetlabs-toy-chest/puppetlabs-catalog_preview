require 'puppet/node'
require 'puppet/resource/catalog'
require 'puppet/indirector/code'
require 'puppet/util/profiler'
require 'yaml'

# This is almost the same as the Compiler indirection but
# it compiles two catalogs, one in a baseline environment (the one specified) by the
# regular way puppet determines the environment for a node, and once in a preview environment
# given as a request option.
#
# Ideally, this would derive from the Compiler implementation, but it is too private
# and would require changes.
#
class Puppet::Resource::Catalog::DiffCompiler < Puppet::Indirector::Code
  desc "Compiles two catalogs and computes delta and migration warnings using Puppet's compiler."

  include Puppet::Util

  attr_accessor :code

  def extract_facts_from_request(request)
    return unless text_facts = request.options[:facts]
    unless format = request.options[:facts_format]
      raise ArgumentError, "Facts but no fact format provided for #{request.key}"
    end

    Puppet::Util::Profiler.profile("Found facts", [:compiler, :find_facts]) do
      # If the facts were encoded as yaml, then the param reconstitution system
      # in Network::HTTP::Handler will automagically deserialize the value.
      if text_facts.is_a?(Puppet::Node::Facts)
        facts = text_facts
      else
        # We unescape here because the corresponding code in Puppet::Configurer::FactHandler escapes
        facts = Puppet::Node::Facts.convert_from(format, CGI.unescape(text_facts))
      end

      unless facts.name == request.key
        raise Puppet::Error, "Catalog for #{request.key.inspect} was requested with fact definition for the wrong node (#{facts.name.inspect})."
      end

      options = {
        :environment => request.environment,
        :transaction_uuid => request.options[:transaction_uuid],
      }

      Puppet::Node::Facts.indirection.save(facts, nil, options)
    end
  end

  # The find request should
  # - change logging to json output (as directed by baseline-log option)
  # - compile in the baseline (reqular) environment given by the node/infrastructure
  # - write baseline catalog to file as directed by option
  # - change logging to json output (as directed by preview-log option)
  # - compile in the preview environment as directed by options
  # - write preview catalog to file as directed by option
  # - produce a diff (passing options to it from the request
  # - write diff to file as directed by options
  #
  # - return a hash of information
  #
  # Compile a node's catalog.
  def find(request)
    extract_facts_from_request(request)

    node = node_from_request(request)

    # Resurrect "trusted information" that comes from node/fact terminus.
    # The current way this is done in puppet db (currently the only one)
    # is to store the node parameter 'trusted' as a hash of the trusted information.
    #
    # Thus here there are two main cases:
    # 1. This terminus was used in a real agent call (only meaningful if someone curls the request as it would
    #  fail since the result is a hash of two catalogs).
    # 2  It is a command line call with a given node that use a terminus that:
    # 2.1 does not include a 'trusted' fact - use local from node trusted information
    # 2.2 has a 'trusted' fact - this in turn could be
    # 2.2.1 puppet db having stored trusted node data as a fact (not a great design)
    # 2.2.2 some other terminus having stored a fact called "trusted" (most likely that would have failed earlier, but could
    #       be spoofed).
    #
    # For the reasons above, the resurection of trusted node data with authenticated => true is only performed
    # if user is running as root, else it is resurrected as unauthenticated.
    #
    trusted_param = node.parameters['trusted']
    if trusted_param
      # Blows up if it is a parameter as it will be set as $trusted by the compiler as if it was a variable
      node.parameters.delete('trusted')
      if trusted_param.is_a?(Hash) && %w{authenticated certname extensions}.all? {|key| trusted_param.has_key?(key) }
        # looks like a hash of trusted data - resurrect it
        # Allow root to trust the authenticated information if option --trusted is given
        if ! (Puppet.features.root? && request.options[:trusted])
          # Set as not trusted - but keep the information
          trusted_param['authenticated'] = false
        end
      else
        # trusted is some kind of garbage, do not resurrect
        trusted_param = nil
      end
    else
      # trusted may be boolean false if set as a fact by someone
      trusted_param = nil
    end

    node.trusted_data = Puppet.lookup(:trusted_information) do
      # resurrect trusted param if set, else use a local node
      trusted_param || Puppet::Context::TrustedInformation.local(node).to_h
    end

    if catalog = compile(node, request.options)
      return catalog
    else
      # This shouldn't actually happen; we should either return
      # a config or raise an exception.
      return nil
    end
  end

  # filter-out a catalog to remove exported resources
  def filter(catalog)
    return catalog.filter { |r| r.virtual? } if catalog.respond_to?(:filter)
    catalog
  end

  def initialize
    Puppet::Util::Profiler.profile("Setup server facts for compiling", [:diff_compiler, :init_server_facts]) do
      set_server_facts
    end
  end

  # Is our compiler part of a network, or are we just local?
  def networked?
    Puppet.run_mode.master?
  end

  private

  # Add any extra data necessary to the node.
  def add_node_data(node)
    # Merge in our server-side facts, so they can be used during compilation.
    node.merge(@server_facts)
  end

  # Compile baseline and preview catalogs
  #
  def compile(node, options)
    baseline_catalog = nil
    preview_catalog = nil

    benchmark(:notice, str) do
      baseline_dest = options[:baseline_log].to_s
      preview_dest = options[:preview_log].to_s
      begin

        # Baseline compilation
        #
        Puppet::Util::Log.close_all()
        Puppet::Util::Log.newdestination(baseline_dest)
        Puppet::Util::Log.with_destination(baseline_dest) do
          if options[:baseline_environment]
            # Switch the node's environment (it finds and instantiates the Environment)
            node.environment = options[:baseline_environment]
          end
          Puppet.override({:current_environment => node.environment}, "puppet-preview-baseline-compile") do

            if Puppet.future_parser?
              raise PuppetX::Puppetlabs::Preview::GeneralError, "Migration is only possible from an environment that is not using parser=future"
            end
            begin
              baseline_catalog = Puppet::Parser::Compiler.compile(node)
            rescue StandardError => e
              # Log it (ends up in baseline_log)
              Puppet.err(e.to_s)
              raise PuppetX::Puppetlabs::Preview::BaselineCompileError, "Error while compiling the baseline catalog"
            end
          end
        end
        Puppet::Util::Log.close(baseline_dest)

        # Preview compilation
        #
        Puppet::Util::Log.close_all()
        Puppet::Util::Log.newdestination(preview_dest)
        Puppet::Util::Log.with_destination(preview_dest) do

          # Switch the node's environment (it finds and instantiates the Environment)
          node.environment = options[:preview_environment]

          # optional migration checking in preview
          # override environment with specified env for preview
          overrides = { :current_environment => node.environment }
          if (checker = options[:migration_checker])
            overrides[:migration_checker] = checker
          end

          Puppet.override(overrides, "puppet-preview-compile") do

            unless Puppet.future_parser?
              raise PuppetX::Puppetlabs::Preview::GeneralError, "Migration preview is only possible when the target env is configured with parser=future"
            end

            begin
              preview_catalog = Puppet::Parser::Compiler.compile(node)
            rescue Puppet::Error => e
              raise PuppetX::Puppetlabs::Preview::PreviewCompileError, "Error while compiling the preview catalog"

            rescue StandardError => e
              # Log it (ends up in preview_log)
              Puppet.err(e.to_s)
              raise PuppetX::Puppetlabs::Preview::PreviewCompileError, "Error while compiling the preview catalog"
            end

            if checker
              Puppet::Pops::IssueReporter.assert_and_report(checker.acceptor,
                :emit_warnings     => true,
                :max_warnings      => Float::INFINITY,
                :max_errors        => Float::INFINITY,
                :max_deprecations  => Float::INFINITY
              )
            end
          end
        end
        Puppet::Util::Log.newdestination(:console)
        Puppet::Util::Log.close(preview_dest)
      rescue Puppet::Error => detail
        Puppet.err(detail.to_s) if networked?
        raise
      ensure
        Puppet::Util::Log.close(baseline_dest)
        Puppet::Util::Log.close(preview_dest)
      end
    end

    {:baseline =>  baseline_catalog, :preview => preview_catalog}
  end

  # Turn our host name into a node object.
  def find_node(name, environment, transaction_uuid)
    Puppet::Util::Profiler.profile("Found node information", [:diff_compiler, :find_node]) do
      node = nil
      begin
        node = Puppet::Node.indirection.find(name,
          :environment => environment,
          :transaction_uuid => transaction_uuid)

      rescue => detail
        message = "Failed when searching for node #{name}: #{detail}"
        Puppet.log_exception(detail, message)
        raise Puppet::Error, message, detail.backtrace
      end


      # Add any external data to the node.
      if node
        add_node_data(node)
      end
      node
    end
  end

  # Extract the node from the request, or use the request
  # to find the node.
  def node_from_request(request)
    if node = request.options[:use_node]
      if request.remote?
        raise Puppet::Error, "Invalid option use_node for a remote request"
      else
        return node
      end
    end

    # We rely on our authorization system to determine whether the connected
    # node is allowed to compile the catalog's node referenced by key.
    # By default the REST authorization system makes sure only the connected node
    # can compile its catalog.
    # This allows for instance monitoring systems or puppet-load to check several
    # node's catalog with only one certificate and a modification to auth.conf
    # If no key is provided we can only compile the currently connected node.
    name = request.key || request.node
    if node = find_node(name, request.environment, request.options[:transaction_uuid])
      return node
    end

    raise ArgumentError, "Could not find node '#{name}'; cannot compile"
  end

  # Initialize our server fact hash; we add these to each client, and they
  # won't change while we're running, so it's safe to cache the values.
  def set_server_facts
    @server_facts = {}

    # Add our server version to the fact list
    @server_facts["serverversion"] = Puppet.version.to_s

    # And then add the server name and IP
    {"servername" => "fqdn",
      "serverip" => "ipaddress"
    }.each do |var, fact|
      if value = Facter.value(fact)
        @server_facts[var] = value
      else
        Puppet.warning "Could not retrieve fact #{fact}"
      end
    end

    if @server_facts["servername"].nil?
      host = Facter.value(:hostname)
      if domain = Facter.value(:domain)
        @server_facts["servername"] = [host, domain].join(".")
      else
        @server_facts["servername"] = host
      end
    end
  end
end
