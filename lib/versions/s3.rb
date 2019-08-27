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

require 'aws-sdk-s3'

module Versions
  class S3
    def initialize bucket_name, bucket_region: 'eu-central-1', bucket_signature_version: :v4, access_key_id: nil, secret_access_key: nil
      @bucket_name = bucket_name

      @bucket = get_bucket bucket_region: bucket_region, access_key_id: access_key_id, secret_access_key: secret_access_key
    end

    def get_bucket bucket_region:, access_key_id:, secret_access_key:
      if access_key_id and secret_access_key
        Aws.config.update(
          credentials: Aws::Credentials.new(access_key_id, secret_access_key)
        )
      end

      @s3 = Aws::S3::Resource.new(
        region:               bucket_region
      )
      @s3.bucket(@bucket_name)
    end
  end
end
