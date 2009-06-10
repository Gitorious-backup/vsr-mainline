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

require 'uri'
require 'net/http'

class PushEventProcessor < ApplicationProcessor
  subscribes_to :push_event
  attr_reader :oldrev, :newrev, :ref, :action, :user
  attr_accessor :repository
  
  def on_message(message)
    hash = ActiveSupport::JSON.decode(message)
    logger.debug("#{self.class.name} on message #{hash.inspect}")
    logger.info "Push event. Username is #{hash['username']}, commit summary is #{hash['message']}, gitdir is #{hash['gitdir']}"
    if @repository = Repository.find_by_hashed_path(hash['gitdir'])
      @user = User.find_by_login(hash['username'])
      @repository.update_attribute(:last_pushed_at, Time.now.utc)
      self.commit_summary = hash['message']
      log_events
      post_events
    else
      logger.error("#{self.class.name} received message, but couldn't find repo with hashed_path #{hash['gitdir']}")
    end
  end
  
  def log_events
    logger.info("#{self.class.name} logging #{events.size} events")
    events.each do |e|
      log_event(e)
    end
  end

  def post_events
    require 'pp'
    pp payload
    return
    
    json = payload.to_json
    @repository.post_receive_urls.each do |url|
      logger.info("#{self.class.name} posting payload to #{url}")
      res = Net::HTTP.post_form(URI.parse(url), {'payload' => json})
      case res
      when Net::HTTPSuccess
        logger.info("#{self.class.name} posted successfully. Response: #{res.body}")
        true
      when Net::HTTPRedirect
        true
      else
        false
      end
    end
  end
  
  def log_event(an_event)
    @project ||= @repository.project
    event = @project.events.new(
      :action => an_event.event_type, 
      :target => @repository, 
      :user => an_event.user,
      :body => an_event.message,
      :data => an_event.identifier,
      :created_at => an_event.commit_time
      )
    if event.user.blank?
      event.email = an_event.email
    end
    event.save!
    if commits = an_event.commits
      commits.each do |c|
        commit_event = event.build_commit({
          :user => c.user,
          :email => c.email,
          :body => c.message,
          :data => c.identifier
        })
        commit_event.save!
      end
    end
  end
  
  # Sets the commit summary, as served from git
  def commit_summary=(spec)
    @oldrev, @newrev, @ref = spec.split(' ')
    r, name, @identifier = @ref.split("/", 3)
    @head_or_tag = name == 'tags' ? :tag : :head
  end
  
  def head?
    @head_or_tag == :head
  end
  
  def tag?
    @head_or_tag == :tag
  end
  
  def action
    @action ||= if oldrev =~ /^0+$/
      :create
    elsif newrev =~ /^0+$/
      :delete
    else
      :update
    end
  end
  
  def events
    @events ||= fetch_events
  end
  
  class EventForLogging
    attr_accessor :event_type, :identifier, :email, :message, :commit_time
    attr_accessor :user, :statuses, :committer, :author, :commit_object
    attr_reader :commits
    def to_s
      "<PushEventProcessor:EventForLogging type: #{event_type} by #{email} at #{commit_time} with #{identifier}>"
    end
    
    def commits=(commits)
      @commits = commits
    end
  end
  
  def fetch_events
    if tag?
      e = EventForLogging.new
      e.event_type = action == :create ? Action::CREATE_TAG : Action::DELETE_TAG
      e.identifier = @identifier
      rev, message = action == :create ? [@newrev, "Created tag #{@identifier}"] : [@oldrev, "Deleted branch #{@identifier}"]
      logger.debug("Processor: action is #{action}, identifier is #{@identifier}, rev is #{rev}")
      fetch_commit_details(e, rev)
      e.user = user
      e.message = message
      return [e]
    elsif action == :create
      e = EventForLogging.new
      e.event_type = Action::CREATE_BRANCH
      e.message = "New branch"
      e.identifier = @identifier
      e.user = user
      result = [e]
      if @identifier == 'master'
        result = result + events_from_git_log(@newrev)
      end
      return result
    elsif action == :delete
      e = EventForLogging.new
      e.event_type = Action::DELETE_BRANCH
      e.identifier = @identifier
      fetch_commit_details(e, @oldrev, Time.now.utc)
      e.user = user
      return [e]
    else # normal commits push
      e = EventForLogging.new
      e.event_type = Action::PUSH
      e.message = "#{@identifier} changed from #{@oldrev[0,7]} to #{@newrev[0,7]}"
      e.identifier = @identifier
      e.email = user.email
      e.commits = events_from_git_log("#{@oldrev}..#{@newrev}")
      return [e]
    end
  end
    
  def fetch_commit_details(an_event, commit_sha, event_timestamp = nil)
    commit = commits_from_revspec(commit_sha).first
    an_event.email        = commit.author.email
    an_event.commit_time  = event_timestamp || commit.authored_date.utc
    an_event.message      = commit.message
  end
  
  def commits_from_revspec(revspec)
    Grit::Commit.find_all(git_repo, revspec, {:timeout => false})
  end
  
  def events_from_git_log(revspec)
    result = []
    commits_from_revspec(revspec).each do |commit|
      e = EventForLogging.new
      if email = commit.author.email
        if user = User.find_by_email_with_aliases(email)
          e.user = user
        else
          e.email = email
        end
      end
      e.identifier = commit.id # The SHA-1
      e.commit_time = commit.authored_date.utc
      e.event_type = Action::COMMIT
      e.message = commit.message
      e.commit_object = commit
      #e.statuses      = (statuses || "").strip.split("\n").map {|s| s.split("\t")}.inject({}) {|h,(s,p)| h[s] ||= []; h[s] << p; h}
      result << e
    end
    result
  end
  
  def git_repo
    @git_repo ||= @repository.git
  end
  
  def git
    git_repo.git
  end
  
  def encode(data)
    if RUBY_VERSION > '1.9'
      if !data.valid_encoding?
        data = data.force_encoding("utf-8")
        if !data.valid_encoding?
          # If there's something wonky with the data encoding still then brute force
          # conversion to utf-8, replacing bad chars (and potentially more)
          ec = Encoding::Converter.new("ASCII-8BIT", "utf-8", {
            :invalid => :replace, :undef => :replace
          })
          ec.convert(data)
        else
          data
        end
      else
        data
      end
    else
      data
    end
  end

  def payload
    event = events.first
    commit_events = event.commits || events[1..-1] || []
    url = "http://#{GitoriousConfig['gitorious_host']}/#{@repository.url_path}"
    {
      :before     => @oldrev,
      :after      => @newrev,
      :ref        => @ref,
      :pushed_by  => @user.login,
      :pushed_at  => @repository.last_pushed_at.xmlschema,
      :project    =>  {
        :name         => @repository.project.slug,
        :description  => @repository.project.description,
      },
      :repository => {
        :name         => @repository.name,
        :url          => url,
        :description  => @repository.description,
        :clones       => @repository.clones.count,
        :owner        => {
          :name   => @repository.owner.title
        }
      },
      :commits => commit_events.map{|c| c.commit_object.to_hash }.flatten
    }
  end
end
