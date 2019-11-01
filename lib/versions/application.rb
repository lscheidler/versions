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

module Versions
  class Application
    attr_reader :name

    def initialize name
      @name = name
      @versions = []
    end

    def add_current_version version:, ctime:
      add_version version: version, ctime: ctime
    end

    def add_previous_version version:, ctime:
      add_version version: version, ctime: ctime, type: :previous
    end

    def add_version version:, ctime:, type: :current
      @versions << ({type: type, version: version, ctime: ctime})
    end

    def get_current
      if not (list=@versions.find_all{|x| x[:type] == :current}.sort_by{|obj| obj[:ctime]}).empty?
        list.last
      end
    end

    def get_previous
      if not (list=@versions.find_all{|x| x[:type] == :previous}.sort_by{|obj| obj[:ctime]}).empty?
        list.last
      end
    end

    def to_s
      result = get_current[:version]
      result += ' ('+ get_previous[:version] + ')' if get_previous
      result
    end

    def as_json
      result = {application: @name, version: [get_current]}
      result[:version] << get_previous if get_previous
      result
    end

    def to_json(*args)
      as_json.to_json(*args)
    end
  end
end
