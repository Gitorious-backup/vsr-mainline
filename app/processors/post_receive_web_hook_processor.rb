# encoding: utf-8
#--
#   Copyright (C) 2009 Nokia Corporation and/or its subsidiary(-ies)
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

require "uri"
require "net/http"
require "net/https"

class PostReceiveWebHookProcessor < ApplicationProcessor
  subscribes_to :post_receive_web_hook
  
  def on_message(json)
    @data = ActiveSupport::JSON.decode(json)
    @repository = Repository.find(@data['repository_id'])
    @repository.hooks.each do |hook|
      begin
        Timeout.timeout(10) do
          logger.info("#{self.class.name} POST to Hook id:#{hook.id} #{hook.url.inspect}")
          response = post_payload(URI.parse(hook.url), @data['payload'])
          update_hook_response_status(hook, "#{response.code} #{response.message}")
          case response
          when Net::HTTPSuccess
            logger.debug("#{self.class.name} POST successfully. Response: #{response.body}")
            true
          else
            # TODO: N retries
            logger.debug("#{self.class.name} fail POST failed (#{response.code} #{response.msg}). Response: \n#{response.body}")
            false
          end
        end
      rescue Errno::ECONNREFUSED
        logger.info("#{self.class.name} Connection refused for hook #{hook.id} to #{hook.url.inspect}")
        update_hook_response_status(hook, "Connection refused")
      rescue TimeoutError
        logger.info("#{self.class.name} Timed out POST to #{hook.url.inspect}")
        update_hook_response_status(hook, "Connection timed out")
      end
    end
  end
  
  def post_payload(uri, payload_hash)
    logger.debug("#{self.class.name} posting payload to #{uri}")
    Net::HTTP.post_form(uri, payload_hash)
  end
  
  def update_hook_response_status(hook, response)
    hook.update_attributes({
      :last_response => response
    })
  end
  
end