module PuppetX::Puppetlabs::Migration
module OverviewModel
  class Report
    # Creates a new {Report} instance based on an {Overview}.
    # @param overview [Overview] the overview to create a report from
    def initialize(overview)
      @overview = overview
    end

    # Returns a hash representing the content of the report
    # @return [Hash<Symbol,Hash>] the report hash
    def to_hash
      hash = {
        :stats => stats,
        :all_nodes => all_nodes,
        :changes => changes
      }
      baseline = log_entries_hash(true)
      hash[:baseline] = baseline unless baseline.empty?
      preview = log_entries_hash(false)
      hash[:preview] = preview unless preview.empty?
      hash
    end

    # Creates and returns a formatted JSON string that represents the content of the report
    # @return [String] The JSON representation of this report
    def to_json
      PSON::pretty_generate(to_hash, :allow_nan => true, :max_nesting => false)
    end

    # Returns this report as a human readable multi-line string. Only the top ten nodes with the most issues
    # will be included in the nodes list.
    # @return [String] The textual representation of this report
    def to_s
      to_text(true)
    end

    # Returns this report as a human readable multi-line string
    # @param top_ten_only [Boolean] `true`to limit the list of nodes to the ten nodes with most issues. `false` to include all nodes.
    # @return [String] The textual representation of this report
    def to_text(top_ten_only)
      bld = StringIO.new
      stats_to_s(bld, stats)
      log_entries_hash_to_s(bld, log_entries_hash(true), true)
      log_entries_hash_to_s(bld, log_entries_hash(false), false)
      changes_to_s(bld, changes)
      all_nodes_to_s(bld, all_nodes, top_ten_only)
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
        issue.compliant? ? :compliant_resources : :conflicting_resources
      when EdgeMissing
        :missing_edges
      when EdgeAdded
        :added_edges
      when AttributeMissing
        :missing_in
      when AttributeAdded
        :added_in
      when AttributeConflict
        issue.compliant? ? :compliant_in : :conflicting_in
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
      total_and_percent(bld, stats[:conflicting], nc_width)
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
      location.nil? ? 'unknown location' : "#{location.file.path}:#{location.line}"
    end

    # all_nodes
    #
    def all_nodes
      nodes = @overview.of_class(Node)
      issues_map = nodes.map do |n|
        logged_issue_levels = n.log_entries.message.issue.level
        issues = n.issues
        {
          :name => n.name,
          :error_count => logged_issue_levels.count { |level| level.name == 'err' },
          :warning_count => logged_issue_levels.count { |level| level.name == 'warning' },
          :added_resource_count => issues.of_class(ResourceAdded).size,
          :missing_resource_count => issues.of_class(ResourceMissing).size,
          :conflicting_resource_count => issues.of_class(ResourceConflict).size
        }
      end
      issues_map.sort do |a, b|
        cmp = b[:error_count] <=> a[:error_count]
        if cmp == 0
          cmp = b[:warning_count] <=> a[:warning_count]
          cmp = diff_count(b) <=> diff_count(a) if cmp == 0
          cmp = a[:name] <=> b[:name] if cmp == 0
        end
        cmp
      end
    end

    def diff_count(h)
      h[:added_resource_count] + h[:missing_resource_count] + h[:conflicting_resource_count]
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

    # Builds the hash that represents the log entires for a compilation
    #
    # @param baseline [Boolean] true for baseline, false for preview
    # @return [Hash<Symbol,Object>] the hash
    def log_entries_hash(baseline)
      error_counts = count_by_issue_code('err', baseline)
      warning_counts = count_by_issue_code('warning', baseline)

      hash = {}
      unless error_counts.empty?
        hash[:compilation_errors] = compilation_errors(baseline)
        hash[:error_count_by_issue_code] = error_counts
      end
      hash[:warning_count_by_issue_code] = warning_counts unless warning_counts.empty?
      hash
    end

    def log_entries_hash_to_s(bld, hash, baseline)
      compilation_errors_to_s(bld, hash[:compilation_errors], baseline)
      count_by_issue_code_to_s(bld, hash[:error_count_by_issue_code], 'err', baseline)
      count_by_issue_code_to_s(bld, hash[:warning_count_by_issue_code], 'warning', baseline)
    end

    # Builds the array that represents baseline compiler errors per manifest sorted by affected node count.
    #
    # @param baseline [Boolean] true for baseline, false for preview
    # @return [Array<Hash<Symbol,Object>>] The hash, keyed by manifest paths.
    def compilation_errors(baseline)
      errors = {}
      log_entries('err', baseline).each do |le|
        location = le.location
        manifest_name = location.nil? ? 'General Error' : location.file.path
        manifest_hash = get_hash(errors, manifest_name)
        manifest_hash[:manifest] = manifest_name

        nodes = (manifest_hash[:nodes] ||= Set.new)
        nodes.add(le.compilation.node.name)
        log_message = le.message
        issue_code = log_message.issue.name
        error = {
          :message => log_message.message
        }
        error[:issue_code] = issue_code unless issue_code.nil?
        unless location.nil?
          error[:line] = location.line unless location.line.nil?
          error[:pos] = location.pos unless location.pos.nil?
        end
        manifest_errors = (manifest_hash[:errors] ||= [])
        manifest_errors << error unless manifest_errors.include?(error)
      end
      errors.map { |_, m| m[:nodes] = m[:nodes].to_a; m }.sort { |a, b| b[:nodes].size <=> a[:nodes].size }
    end

    def compilation_errors_to_s(bld, errors, baseline)
      return if errors.nil? || errors.empty?
      bld.puts
      bld << (baseline ? 'Baseline' : 'Preview') << ' Errors (by manifest)' << "\n"
      errors.each do |error|
        bld << '  ' << error[:manifest] << "\n"
        bld << '    Nodes..: ' << error[:nodes].join(', ') << "\n"
        bld << "    Issues.:\n"
        error[:errors].each do |me|
          issue_code = me[:issue_code]
          line = me[:line]
          pos = me[:pos]
          lp = line.nil? ? nil : (pos.nil? ? "line #{line}" : "line #{line}, column #{pos}")
          bld << '      ' << issue_code << ': ' unless issue_code.nil?
          bld << "'" << me[:message] << "'"
          bld << ' at ' << lp << "\n" unless lp.nil?
        end
      end
    end

    # Builds the array that represents counts per issue code for the given _level_
    #
    # @param level [String] The string 'err' och 'warning'
    # @param baseline [Boolean] true for baseline, false for preview
    # @return [Array<Hash<Symbol,Object>>] the created array
    #
    def count_by_issue_code(level, baseline)
      issues = {}
      log_entries(level, baseline).each do |le|
        name = le.message.issue.name
        no_issue_code = name.nil?
        name = le.message.message if no_issue_code
        hash = issues[name]
        if hash.nil?
          hash = {
            no_issue_code ? :message : :issue_code => name,
            :count => 1
          }
          issues[name] = hash
        else
          hash[:count] += 1
        end
        location = le.location
        unless location.nil?
          manifest_name = location.file.path
          manifests = get_hash(hash, :manifests)
          manifests[manifest_name] ||= []
          line = location.line
          unless line.nil?
            pos = location.pos
            manifests[manifest_name] << (pos.nil? ? line.to_s : "#{line}:#{pos}")
          end
        end
      end
      issues.each_value { |issue| issue[:manifests].each_value { |positions| positions.uniq! } }
      issues.values.sort { |a, b| b[:count] <=> a[:count] }
    end

    def count_by_issue_code_to_s(bld, issues, level, baseline)
      return if issues.nil? || issues.empty?
      bld.puts
      count_by_issue_code_or_message_to_s(bld, issues, level, baseline, ' (by issue)', :issue_code)
      count_by_issue_code_or_message_to_s(bld, issues, level, baseline, ' (by message)', :message)
    end

    def count_by_issue_code_or_message_to_s(bld, issues, level, baseline, txt, sym)
      issues = issues.select { |issue| issue.include?(sym) }
      return if issues.empty?
      bld << (baseline ? 'Baseline' : 'Preview') << (level == 'err' ? ' Errors' : ' Warnings') << txt << "\n"
      issues.each do |issue|
        bld << '  ' << issue[sym] << ' (' << issue[:count] << ")\n"
        manifests = issue[:manifests]
        unless manifests.nil?
          manifests.each_pair do |manifest, locations|
            bld << '    ' << manifest
            case locations.size
            when 0
            when 1
              bld << ':' << locations[0]
            else
              bld << ':' << '[' << locations.join(',') << ']'
            end
            bld << "\n"
          end
        end
      end
    end

    # Returns all log entries found in the contained {Overview} for the given _level_ and _baseline_ arguments
    #
    # @param level [String] The string 'err' och 'warning'
    # @param baseline [Boolean] true for baseline, false for preview
    # @return [Array<LogEntry>] the found entries
    def log_entries(level, baseline)
      @overview.of_class(LogEntry).select { |le| le.compilation.baseline? == baseline && le.message.issue.level.name == level }
    end

    # Builds the hash that represents changes per {ResourceType}
    #
    # @return [Hash<String,Hash>] The hash, keyed by resource type name
    #
    def changes_on_resource_types
      rt_changes = {}
      @overview.of_class(ResourceType).each do |t|
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
        { :missing_resources => '(missing, conflicting)',
          :added_resources => '(added, compliant)',
          :compliant_resources => '(diff, compliant)',
          :conflicting_resources => '(diff, conflicting)'
        }.each_pair do |key, key_text|
          per_key = per_type[key]
          next if per_key.nil?
          per_key.each_pair do |title, title_entry|
            title_entry.each_pair do |location, nodes|
              type = key_text
              bld << '    ' << "title: '" << title << "' " << type << ' at: ' << location << ' on ' << nodes.join(', ') << "\n"
            end
          end
        end

        attr_issues = per_type[:attribute_issues]
        next if attr_issues.nil?
        bld << '    Attribute Issues (per name)' << "\n"
        attr_issues.each_pair do |attribute_name, issues|
          { :missing_in => '(missing, conflicting)',
            :added_in => '(added, compliant)',
            :compliant_in => '(diff, compliant)',
            :conflicting_in => '(diff, conflicting)'
          }.each_pair do |key, key_text|
            per_key = issues[key]
            next if per_key.nil?
            bld << "      '" << attribute_name << "'\n"
            per_key.each_pair do |attr_title, title_entry|
              title_entry.each_pair do |location, nodes|
                bld << '        ' << key_text << " in title: '" << attr_title << "' at: " << location << ' on ' << nodes.join(', ') << "\n"
              end
            end
          end
        end
      end
    end

    def all_nodes_to_s(bld, all_nodes, top_ten_only)
      bld.puts
      if top_ten_only
        bld.puts('Top ten nodes with most issues')
        all_nodes = all_nodes.take(10)
      else
        bld.puts('All nodes')
      end
      lbl = 'node name'
      nn_width = all_nodes.reduce(lbl.size) { |w, n| s = n[:name].size; w > s ? w : s }
      bld << '  ' << lbl.center(nn_width) << "  errors  warnings   diffs\n"
      bld << '  '
      nn_width.times  { bld << '-' }
      bld << " -------- -------- --------\n"
      fmt = "  %-#{nn_width}s %8i %8i %8i\n"
      all_nodes.each {|n| bld << sprintf(fmt, n[:name], n[:error_count], n[:warning_count], diff_count(n) ) }
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
end

