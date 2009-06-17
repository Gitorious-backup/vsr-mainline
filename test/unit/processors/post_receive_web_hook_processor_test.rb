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


require File.dirname(__FILE__) + '/../../test_helper'

class PostReceiveWebHookProcessorTest < ActiveSupport::TestCase
  def setup
    @processor = PostReceiveWebHookProcessor.new
    @repository = repositories(:johans)
    @data = {
      "user" => users(:johan).login,
      "repository_id" => @repository.id,
      "payload" => {
        "before"     => "0000000000000000000000000000000000000000",
        "after"      => "a9934c1d3a56edfa8f45e5f157869874c8dc2c34",
        "ref"        => "refs/heads/master",
      }
    }
    @response = Net::HTTPSuccess.new("HTTP/1.1", "200", "OK")
    @response.stubs(:body).returns("")
  end
  
  def add_hook_url(repository, url)
    repository.hooks.create(:user => users(:johan), :url => url)
  end
  
  should "post to each of the repository hook urls" do
    add_hook_url(@repository, "http://foo")
    add_hook_url(@repository, "http://bar")
    @processor.expects(:post_payload).twice.returns(@response)
    @processor.on_message(@data.to_json)
  end
  
  should "perform a post to the hook url" do
    add_hook_url(@repository, "http:/example.com")
    uri = URI.parse("http://example.com")
    Net::HTTP.expects(:post_form).with(uri, @data["payload"]).returns(@response)
    @processor.post_payload(uri, @data["payload"])
  end
  
  should "update the hook with the reponse string" do
    add_hook_url(@repository, "http:/example.com")
    uri = URI.parse("http://example.com")
    @processor.expects(:post_payload).returns(@response)
    @processor.on_message(@data.to_json)
    assert_equal "200 OK", @repository.hooks.reload.first.last_response
  end
  
end