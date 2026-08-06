#!/usr/bin/env ruby
# Extracts every composite-action `run:` block from actions/*/action.yml
# into standalone .sh files under the given output directory, so they can
# be shellchecked directly. actionlint (used for .github/workflows/*.yml)
# doesn't understand the action.yml schema and won't lint these otherwise.
#
# Usage: extract-run-blocks.rb <output-dir>

require "yaml"
require "fileutils"

out_dir = ARGV[0] or abort "usage: extract-run-blocks.rb <output-dir>"
FileUtils.mkdir_p(out_dir)

Dir.glob("actions/*/action.yml").sort.each do |action_file|
  action_name = File.basename(File.dirname(action_file))
  data = YAML.load_file(action_file)
  steps = data.dig("runs", "steps") || []

  steps.each_with_index do |step, index|
    next unless step["run"]

    shell = step["shell"]
    unless shell == "bash"
      abort "#{action_file}: step #{index} (#{step['name'] || 'unnamed'}) has run: but shell is #{shell.inspect}, expected \"bash\" — extend extract-run-blocks.rb before adding a non-bash shell"
    end

    step_slug = (step["name"] || "step-#{index}").gsub(/[^a-zA-Z0-9]+/, "-").gsub(/^-|-$/, "")
    script_path = File.join(out_dir, "#{action_name}__#{step_slug}.sh")
    File.write(script_path, "#!/usr/bin/env bash\n#{step['run']}")
  end
end
