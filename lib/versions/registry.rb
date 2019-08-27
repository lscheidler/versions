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

##require 'aws-sdk-s3'
require 'digest'
require 'json'
require 'socket'

require 'overlay_config'

module Versions
  class Registry
    def initialize environment_name:, instance_id:, version_directory: '/var/tmp'
      @environment_name = environment_name
      @instance_id = instance_id
      @version_directory = version_directory
    end

    # get all local switched applications
    def get_versions
      unless @versions
        @versions = {}
        Dir.glob(File.join(@version_directory, 'versions.application.*.json')) do |file|
          data = JSON::parse(File.read(file))
          @versions[data.delete('application')] = {
            current: data['current'],
            previous: data['previous'],
          }
        end
      end
      @versions
    end

    def update_version application:, version:
      get_versions
      @versions[application] = {
        application: application,
        current: version,
        previous: (@versions.has_key? application) ? @versions[application][:current] : nil,
      }

      File.open(@version_directory + '/versions.application.' + Digest.hexencode(application) + '.json', 'w') do |io|
        io.puts JSON::dump(@versions[application])
      end
    end

    def to_s
      metadata = {last_updated: Time.now, host_name: self.class.get_fqdn, environment: @environment_name, instance_id: @instance_id, applications: get_versions}
      JSON::pretty_generate metadata
    end

    def self.get_fqdn
      Socket.gethostname
    end
  end
end
