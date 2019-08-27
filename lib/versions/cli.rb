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

require 'versions/registry'

require 'aws-sdk-s3'
require 'digest'
require 'json'
require 'logger'
require 'optparse'
require 'socket'

require 'output_helper'
require 'overlay_config'

module Versions
  class CLI
    def initialize
      set_defaults
      parse_arguments

      @registry = Registry.new(
        environment_name: @config.environment_name,
        instance_id: @config.instance_id,
        version_directory: @config.version_directory,
      )

      begin
        if @config.action
          send @config.action
        else
          warn 'No action was set.'
        end
      rescue NoMethodError => e
        if e.message.include? "Versions"
          warn "No action #{@config.action} found."
        else
          raise
        end
      end
    end

    def set_defaults
      @script_name = File.basename($0)
      @config = OverlayConfig::Config.new(
        config_scope: 'versions',
        defaults: {
          tmp_directory: '/tmp',
          version_directory: '/var/tmp',
          environment_name: 'local',
          instance_id: Digest.hexencode(Registry.get_fqdn),

          # AWS S3 settings
          bucket_name: 'eu-central-1-application-artifacts',
          bucket_region: 'eu-central-1',
          bucket_signature_version: :v4,

          action: :list,
          filter: [],
        }
      )
      @log = Logger.new STDOUT
    end

    # parse command line arguments
    def parse_arguments
      @options = OptionParser.new do |opts|
        opts.on('-a', '--application NAME', 'set application name') do |application|
          @config.application = application
        end

        opts.on('-d', '--debug', 'show debug output') do
          @log.level = Logger::DEBUG
        end

        opts.on('--diff', 'show different versions between production and staging') do
          @config.action = :show_diff
        end

        opts.on('-f', '--filter REGEXP', 's3 key must match filter', 'multiple filters are possible') do |filter|
          @config.filter << /#{filter}/
        end

        opts.on('--generate-metadata-file', 'generate metadata file, which would be uploaded to s3') do
          @config.action = :generate_metadata_file
          @log.level = Logger::DEBUG
        end

        opts.on('-j', '--json', 'json output') do
          @config.json = true
        end

        opts.on('-l', '--list', 'list local versions') do
          @config.action = :list
        end

        opts.on('--list-remote', 'list available versions') do
          @config.action = :list_remote
        end

        opts.on('-m', '--filter-last-modified REGEXP', 'list remote versions, if they match filter', 'example: -m 2017-05') do |filter|
          @config.filter_last_modified = /#{filter}/
        end

        opts.on('--old-diff', 'show different versions between production and staging') do
          @config.action = :show_diff_old
        end

        opts.on('--show-diff', 'show different versions between production and staging') do
          @config.action = :show_diff
        end

        opts.on('-u', '--update', 'update metadata file on s3') do
          @config.action = :update
        end

        opts.on('-v', '--version VERSION', 'set version') do |version|
          @config.version = version
        end

        opts.separator "
Examples:
    # List local versions
    #{opts.program_name} -l

    # Upload local versions file to s3
    #{opts.program_name} -u

    # Update version of application upload local versions file to s3
    #{opts.program_name} -u -a application-name -v 0.1.0

    # list remote versions, which match p1010 and last-modified timestamp matches 2017-05
    #{opts.program_name} --list-remote --filter p1010 --filter-last-modified 2017-05

    # list remote versions, which match accountingser and last-modified timestamp matches 2017-0
    #{opts.program_name} --list-remote --filter accountingser --filter-last-modified 2017-0

    # list remote versions, which match account, production and last-modified timestamp matches 2017-0(4-2|5)
    #{opts.program_name} --list-remote --filter accounting --filter production --filter-last-modified '2017-0(4-2|5)'

    # show diff between production and staging for all applications switched on current machine
    #{opts.program_name} --diff

    # show diff for accounting only
    #{opts.program_name} --diff --filter accounting

    # show diff for bankfileimporter and mailconsumer
    #{opts.program_name} --diff -f '(bankfileimporter|mailconsumer)'
"
      end
      @options.parse!
    end

    # generate metadata file, which is going to be uploaded to s3
    def generate_metadata_file
      @metadata_filename = @config.get(:tmp_directory) + '/versions.' + @config.environment_name + '.' + @config.instance_id + '.json'
      File.open(@metadata_filename, 'w') do |io|
        io.print @registry.to_s
      end
      @log.debug 'Generated metadata file ' + @metadata_filename
    end

    # list application versions for current instance
    def list
      data_printer = OutputHelper::Columns.new [:application, :version]

      @registry.get_versions.each do |application, versions|
        next unless filtered? application

        if @config.json
          version = {current: versions[:current]}
          version[:previous] = versions[:previous] if versions[:previous]
        else
          version = versions[:current]
          version += ' ('+ versions[:previous] + ')' if versions[:previous]
        end

        row = {
          application: application,
          version: version
        }
        data_printer << row
      end

      if @config.json
        puts JSON::dump(data_printer.data)
      else
        puts data_printer
      end
    end

    # list application versions in s3
    def list_remote
      unless get_bucket.nil?
        remote = Versions::Remote.new(@config.get(:bucket_name), bucket_region: @config.get(:bucket_region), access_key_id: @access_key_id, secret_access_key: @secret_access_key)

        data = remote.list(filter: @config.filter, filter_last_modified: @config.filter_last_modified)
        data = data.sort{|a,b| a[:last_modified] <=> b[:last_modified]}

        if @config.json
          puts JSON::dump(data)
        else
          data_printer = OutputHelper::Columns.new [:environment, :application, :version, :last_modified]
          data.each do |row|
            data_printer << row
          end
          puts data_printer
        end
      else
        @log.warn 'No credentials found for s3. Abort.'
      end
    rescue Aws::S3::Errors::AccessDenied
      if @access_key_id.nil? or @secret_access_key.nil?
        @log.warn 'No credentials found for s3 upload. Access Denied. Abort.'
      else
        @log.warn 'Wrong credentials for s3 upload. Access Denied. Abort.'
      end
      exit 1
    end

    # show a diff between all applications, which are available localy and on other instances
    def show_diff
      unless get_bucket.nil?
        applications = {}

        begin
          generate_metadata_file
        rescue
        end
        get_version_files.each do |file|
          host_name = file['host_name'].split('.').shift
          environment = file['environment']

          file['applications'].each do |application, versions|
            next unless filtered? application

            applications[application] ||= []
            applications[application] << ({"hostname"=>host_name, "environment"=>environment}).merge(versions)
          end
        end

        printer = OutputHelper::Columns.new ['Application', 'Hostname', 'Environment', 'CurrentVersion', 'PreviousVersion']
        applications.sort{|a,b| a.first <=> b.first}.each do |application, data|
          data.each do |item|
            column = {
              Application: application,
              Hostname: item['hostname'],
              Environment: ((item['environment'] == 'staging') ? item['environment'] : item['environment'].bold),
              CurrentVersion: colorize_version(application: application, version: item['current']),
              #PreviousVersion: colorize_version(application: application, version: item['previous']),
              PreviousVersion: item['previous'],
            }
            printer << column
          end
        end
        puts printer
      end
    end

    def colorize_version application:, version:
      return "" if version.nil?

      # normalize version
      normalize_version = version.sub(/-SNAPSHOT/, '')
      @application_version_color ||= {}

      colors = [
        :green,
        :yellow,
        :red,
        :blue,
        :light_magenta,
        :light_green,
        :light_yellow,
        :light_red,
        :light_blue,
      ]

      @application_version_color[application] ||= []
      @application_version_color[application] << normalize_version unless @application_version_color[application].include? normalize_version

      version.colorize(colors[@application_version_color[application].index(normalize_version)])
    end

    # upload new metadata file to s3
    def update
      unless get_bucket.nil?
        if @config.application and @config.version
          @registry.update_version application: @config.application, version: @config.version
        end

        generate_metadata_file
        upload_to_bucket @metadata_filename, 'versions/' + @config.environment_name + '/' + @config.instance_id + '.json'
      else
        @log.warn 'No credentials found for s3 upload. Abort.'
      end
    end

    private
    # get aws s3 bucket client
    def get_bucket
      if not @bucket
        if @access_key_id and @secret_access_key
          Aws.config.update(
            credentials: Aws::Credentials.new(@access_key_id, @secret_access_key)
          )
        end

        @s3 = Aws::S3::Resource.new(
          region: @config.get(:bucket_region)
        )
        @bucket = @s3.bucket(@config.get(:bucket_name))
      end
      @bucket
    end

    # get all version files from s3
    def get_version_files
      if not @version_files
        @version_files = []
        get_bucket.objects(prefix: 'versions/').sort{|a,b| b.last_modified <=> a.last_modified}.each do |object|
          next if object.key.end_with? '/'

          path = '/tmp/'+object.key.tr('/', '.')
          object.download_file(path)
          content = File.new path
          content.seek 0

          data = JSON::parse(content.read)
          @version_files << data
        end
      end
      @version_files
    rescue Aws::S3::Errors::AccessDenied
      if @access_key_id.nil? or @secret_access_key.nil?
        @log.warn 'No credentials found for s3 upload. Access Denied. Abort.'
      else
        @log.warn 'Wrong credentials for s3 upload. Access Denied. Abort.'
      end
      exit 1
    end

    # upload metadata file to s3
    def upload_to_bucket file, dest
      get_bucket.presigned_post(:key=>dest)
      get_bucket.object(dest).put(body: File.new(file))
    end

    # check, if key is filtered by command line argument --filter
    def filtered? key
      @config.filter.each do |filter|
        return false if key.match(filter).nil?
      end
      true
    end
  end
end
