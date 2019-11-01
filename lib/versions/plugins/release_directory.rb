# Copyright 2019 Lars Eric Scheidler
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

require "find"

require "plugin"

require "versions/application"

module Versions
  module Plugins
    class ReleaseDirectory < Plugin
      plugin_argument :registry
      plugin_argument :parent_release_directory, optional: true

      # get all local switched applications
      def get_versions
        return if not File.directory? @parent_release_directory

        Find.find(@parent_release_directory) do |file|
          begin
            next unless file.end_with? '/current' and File.symlink? file and File.realpath(file)

            application_name = file.slice((@parent_release_directory.length+1)..-9)

            next if application_name == 'sample'

            @registry[application_name].add_current_version version: File.basename(File.readlink(file)), ctime: File.stat(file).ctime

            if File.symlink?(File.dirname(file) + '/previous') and File.realpath(File.dirname(file) + '/previous')
              version = File.basename(File.readlink(File.dirname(file) + '/previous'))
              ctime = File.stat(File.dirname(file) + '/previous').ctime
              @registry[application_name].add_previous_version version: version, ctime: ctime
            end
          rescue Errno::ENOENT
          end
        end
      end
    end
  end
end
