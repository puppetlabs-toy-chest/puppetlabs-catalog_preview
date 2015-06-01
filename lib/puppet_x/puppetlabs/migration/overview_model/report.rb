module PuppetX::Puppetlabs::Migration::OverviewModel
  class Report
    # Creates a new {Report} instance based on an {Overview}.
    # @param overview [Overview] the overview to create a report from
    def initialize(overview)
      @overview = overview
    end

    # Returns a hash representing the content of the report
    # @return [Hash<Symbol,Hash>] the report hash
    def to_hash
      { :stats => stats, :top_ten => top_ten, :changes => changes }
    end

    # Creates and returns a formatted JSON string that represents the content of the report
    # @return [String] The JSON representation of this report
    def to_json
      PSON::pretty_generate(to_hash, :allow_nan => true, :max_nesting => false)
    end

    # Returns this report as a human readable multi-line string
    # @return [String] The textual representation of this report
    def to_s
      bld = StringIO.new
      stats_to_s(bld, stats)
      changes_to_s(bld, changes)
      top_ten_to_s(bld, top_ten)
      bld.string
    end

    private

    def percent(n, total)
      (n.to_f / total.to_f * 1000.0).round / 10.0
    end

    def rjust(n, width)
      n.to_s.rjust(width)
    end

    def add_percentages(hash, node_count)
      hash[:percent] = percent(hash[:total], node_count) if hash.include?(:total)
      hash.each_value { |v| add_percentages(v, node_count) if v.is_a?(Hash) }
    end

    def resource_ref(resource)
      "#{resource.type.name}[#{resource.title}]"
    end

    def issue_key(issue)
      case issue.entity
      when ResourceMissing
        :missing_resources
      when ResourceAdded
        :added_resources
      when ResourceConflict
        :conflicting_resources
      when EdgeMissing
        :missing_edges
      when EdgeAdded
        :added_edges
      when AttributeMissing
        :missing_in
      when AttributeAdded
        :added_in
      when AttributeConflict
        :conflicting_in
      end
    end

    def get_hash(hash, key, default=nil)
      hash[key] ||= Hash.new(default)
    end

    def total_and_percent(bld, hash, nc_width)
      if hash.nil?
        total = 0
        percent = 0.0
      else
        total = hash[:total]
        percent = hash[:percent]
      end
      bld << rjust(total, nc_width) << ', ' << rjust(percent, 5)
      bld.puts('%')
    end

    # Produces text base on a hash produced by the {#stats} method onto the IO
    # stream _bld_
    def stats_to_s(bld, stats)
      node_count = stats[:node_count]
      nc_width = node_count.to_s.length
      bld.puts 'Stats'
      bld << '  Total number of nodes: ' << node_count << ', 100.0%' << "\n"

      failures = stats[:failures]
      unless failures.empty?
        bld << '  Failed compilation...: '
        total_and_percent(bld, failures, nc_width)
        bld << '    baseline...........: '
        total_and_percent(bld, failures[:baseline], nc_width)
        bld << '    preview............: '
        total_and_percent(bld, failures[:preview], nc_width)
      end
      bld << '  Conflicting..........: '
      total_and_percent(bld, stats[:different], nc_width)
      bld << '  Compliant............: '
      total_and_percent(bld, stats[:compliant], nc_width)
      bld << '  Equal................: '
      total_and_percent(bld, stats[:equal], nc_width)
    end

    # Builds the hash that represents catalog change statistics
    #
    # @return [Hash<Symbol,Hash>] The hash, keyed by the symbols :node_count and :failures, :different, :compliant, and :equal
    def stats
      nodes = @overview.of_class(Node)
      stats = {}
      node_count = nodes.size
      stats[:node_count] = node_count
      nodes.each { |node| stats_on_node(stats, node) }
      add_percentages(stats, node_count)
    end

    def stats_on_node(stats, node)
      case node.exit_code
      when BASELINE_FAILED, PREVIEW_FAILED
        failures = get_hash(stats, :failures)
        failures[:total] = (failures[:total] || 0) + 1
        if node.exit_code == BASELINE_FAILED
          get_hash(failures, :baseline, 0)[:total] += 1
        else
          get_hash(failures, :preview, 0)[:total] += 1
        end
        stats[:failures] = failures
      else
        get_hash(stats, node.severity, 0)[:total] += 1
        stats[:failures] = {}
      end
    end

    def issue_location_string(issue)
      location = issue.location
      "#{location.file.path}:#{location.line}"
    end

    # top_ten
    #
    def top_ten
      nodes = @overview.of_class(Node)
      nodes.sort {|a, b| b.issues.size <=> a.issues.size }.take(10).map {|n| { :name => n.name, :issue_count => n.issues.size }}
    end

    # Builds the hash that represents all catalog changes
    #
    # @return [Hash<Symbol,Hash>] The hash, keyed by the symbols :resource_type_changes and :edge_changes
    def changes
      changes = {}
      rt_changes = changes_on_resource_types
      edge_changes = changes_on_edges
      changes[:resource_type_changes] = rt_changes unless rt_changes.nil?
      changes[:edge_changes] = edge_changes unless edge_changes.empty?
      changes
    end


    # Builds the hash that represents changes per {ResourceType}
    #
    # @return [Hash<String,Hash>] The hash, keyed by resource type name
    #
    def changes_on_resource_types
      rt_changes = {}
      @overview.of_class(ResourceType).map do |t|
        tc = changes_on_resource_type(t)
        rt_changes[t.name] = tc unless tc.empty?
      end
      rt_changes
    end

    def changes_on_resource_type(resource_type)
      entry = {}
      resource_type.resources.each do |resource|
        title = resource.title
        issues = resource.issues
        issues.each do |issue|
          tm = get_hash(get_hash(entry, issue_key(issue)), title)
          key = issue_location_string(issue)
          tm[key] = (tm[key] ||= []) | issue.nodes.map { |node| node.name }
        end

        issues.of_class(ResourceConflict).each do |resource_conflict|
          node_names = resource_conflict.nodes.map { |node| node.name }
          resource_conflict.attribute_issues.each do |attr_issue|
            am = get_hash(get_hash(get_hash(get_hash(entry, :attribute_issues), attr_issue.attribute.name), issue_key(attr_issue)), title)
            key = issue_location_string(resource_conflict)
            am[key] = (am[key] || []) | node_names
          end
        end
      end
      entry
    end

    # Builds the hash that represents edge changes
    #
    # @return [Hash<Symbol,Hash>] The hash, keyed by the symbols :added_edges and :missing_edges
    def changes_on_edges
      edge_changes = {}
      @overview.of_class(EdgeIssue).map do |ei|
        changes_on_edge(get_hash(edge_changes, issue_key(ei)), ei)
      end
      edge_changes
    end

    def changes_on_edge(edge_hash, edge)
      get_hash(edge_hash, resource_ref(edge.source))[resource_ref(edge.target)] = edge.nodes.map { |node| node.name }
    end

    def changes_to_s(bld, changes)
      rt_changes = changes[:resource_type_changes]
      resource_type_changes_to_s(bld, rt_changes) unless rt_changes.nil?
      edge_changes = changes[:edge_changes]
      edge_changes_to_s(bld, edge_changes) unless edge_changes.nil?
    end

    def resource_type_changes_to_s(bld, changes)
      return if changes.empty?
      bld.puts
      bld.puts('Changes per Resource Type')
      changes.each_pair do |type_name, per_type|
        bld << '  ' << type_name << "\n"
        { :missing_resources => 'Missing', :added_resources => 'Added', :conflicting_resources => 'Conflicting' }.each_pair do |key, key_text|
          per_key = per_type[key]
          next if per_key.nil?
          per_key.each_pair do |title, title_entry|
            title_entry.each_pair do |location, nodes|
              bld << '    ' << key_text << " title: '" << title << "' at: " << location << ' on ' << nodes.join(', ') << "\n"
            end
          end
        end

        attr_issues = per_type[:attribute_issues]
        next if attr_issues.nil?
        bld << '    Attribute Issues' << "\n"
        attr_issues.each_pair do |attribute_name, issues|
          { :missing_in => 'Missing', :added_in => 'Added', :conflicting_in => 'Conflicting' }.each_pair do |key, key_text|
            per_key = issues[key]
            next if per_key.nil?
            bld << '      ' << attribute_name << "\n"
            per_key.each_pair do |attr_title, title_entry|
              title_entry.each_pair do |location, nodes|
                bld << '        ' << key_text << " for title: '" << attr_title << "' at: " << location << ' on ' << nodes.join(', ') << "\n"
              end
            end
          end
        end
      end
    end

    def top_ten_to_s(bld, top_ten)
      bld.puts
      bld.puts('Top ten nodes with most issues')
      top_ten.each {|n| bld << '  ' << n[:name] << ' (' << n[:issue_count] << ')' << "\n" }
    end

    def edge_changes_to_s(bld, changes)
      return if changes.empty?
      bld.puts
      bld.puts('Changes of Edges')
      changes.each_pair do |type, edges|
        bld << '  ' << type << "\n"
        edges.each_pair do |source, targets|
          targets.each_pair do |target, nodes|
            bld << '    ' << source << ' => ' << target << ' on nodes ' << nodes.join(', ') << "\n"
          end
        end
      end
    end
  end
end
