# Copyright 2018 Lars Eric Scheidler
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'digest'
require 'fileutils'
require 'json'
require 'socket'

require 'overlay_config'
require 'plugin_manager'

module Versions
  class Registry
    def initialize environment_name:, instance_id: Digest.hexencode(self.class.get_fqdn), version_directory: '/var/tmp', group_ownership: nil
      @environment_name = environment_name
      @instance_id = instance_id
      @version_directory = version_directory
      @group_ownership = group_ownership

      @versions = {}
      @pm = PluginManager.instance
    end

    def [] application_name
      @versions[application_name] ||= Application.new application_name
      @versions[application_name]
    end

    # get all local switched applications
    def get_versions
      Dir.glob(File.join(@version_directory, 'versions.application.*.json')) do |file|
        data = JSON::parse(File.read(file))
        application = self[data.delete('application')]
        if (current=data["version"].find{|x| x["type"] == "current"})
          application.add_current_version version: current["version"], ctime: Time.parse(current["ctime"])
        end
        if (previous=data["version"].find{|x| x["type"] == "previous"})
          application.add_previous_version version: previous["version"], ctime: Time.parse(previous["ctime"])
        end
      end

      @pm.each do |plugin_name, plugin|
        plugin.get_versions
      end
      @versions
    end

    def update_version application:, version:, ctime:, type: nil
      get_versions

      application = self[application]

      case type
      when :previous
        application[:previous] = version
        application.add_previous_version version: version, ctime: ctime
      else
        application.add_previous_version version: application.get_current[:version], ctime: ctime if application.get_current
        application.add_current_version version: version, ctime: ctime
      end

      filename = @version_directory + '/versions.application.' + Digest.hexencode(application.name) + '.json'
      File.open(filename, 'w') do |io|
        io.puts JSON::dump(application)
      end

      if @group_ownership
        begin
          FileUtils.chown nil, @group_ownership, filename
          FileUtils.chmod "g+w", filename
        rescue ArgumentError
        end
      end
    end

    def to_s
      metadata = {last_updated: Time.now, host_name: self.class.get_fqdn, environment: @environment_name, instance_id: @instance_id, applications: get_versions.values}
      JSON::pretty_generate metadata
    end

    def self.get_fqdn
      Socket.gethostname
    end
  end
end
