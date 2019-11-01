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

require "execute"
require "plugin"

module Versions
  module Plugins
    class Docker < Plugin
      include Execute

      plugin_argument :registry
      plugin_argument :docker_repository, optional: true
      plugin_argument :environment_name

      # get all local switched applications
      def get_versions
        cmd = ['docker', 'images', '--format', '{{.ID}} {{.Tag}}']
        cmd << @docker_repository if @docker_repository
        res = execute(cmd)
        images = {}
        res.stdout_lines.each do |line|
          id, tag = line.split(" ")
          images[id] ||= []
          images[id] << tag
        end

        images.each do |id, tags|
          if (tag = tags.find{|x| x =~ /-#{@environment_name}$/})
            application = tag[/^(.*)-#{@environment_name}$/, 1]
            version, ctime = docker_get_version(id)

            @registry[application].add_current_version version: version, ctime: Time.parse(ctime)
          elsif (tag = tags.find{|x| x =~ /-#{@environment_name}-previous$/})
            application = tag[/^(.*)-#{@environment_name}-previous$/, 1]
            version, ctime = docker_get_version(id)

            @registry[application].add_previous_version version: version, ctime: Time.parse(ctime)
          end
        end
      end

      private
      def docker_get_version id
        execute(['docker', 'inspect', id, '--format', '{{.ContainerConfig.Labels.version}}||{{.Created}}']).stdout.strip.split("||")
      end
    end
  end
end
