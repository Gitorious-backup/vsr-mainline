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

require File.dirname(__FILE__) + '/../test_helper'

class HooksControllerTest < ActionController::TestCase

  def setup
    @project = projects(:johans)
    @repository = @project.repositories.mainlines.first
    login_as :johan
  end

  should_render_in_global_context
  
  context "index" do
    should "require login" do
      session[:user_id] = nil
      get :index, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_redirected_to(new_sessions_path)
    end
    
    should "require reposítory adminship" do
      login_as :moe
      get :index, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_match(/only repository admins are allowed/, flash[:error])
      assert_redirected_to(project_path(@project))
    end
    
    should "set find the correct owner and repository" do
      get :index, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_equal @project, assigns(:owner)
      assert_equal @repository, assigns(:repository)
    end
    
    should "be successfull" do
      get :index, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_response :success
      assert_not_nil assigns(:hooks)
    end
  end
  
  context "new / create" do
    setup do
      @project = projects(:johans)
      @repository = @project.repositories.mainlines.first
      login_as :johan
    end
    
    should "require login" do
      session[:user_id] = nil
      get :new, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_redirected_to(new_sessions_path)
    end
    
    should "require reposítory adminship" do
      login_as :moe
      get :new, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_match(/only repository admins are allowed/, flash[:error])
      assert_redirected_to(project_path(@project))
    end
    
    should "be successfull" do
      get :new, :project_id => @project.to_param, :repository_id => @repository.to_param
      assert_response :success
      assert assigns(:hook).new_record?
      assert_equal users(:johan), assigns(:hook).user
    end
    
    should "create a new hook" do
      assert_difference("@repository.hooks.count") do
        post :create, :project_id => @project.to_param, 
          :repository_id => @repository.to_param, :hook => {
            :url => "http://google.com"
          }
        assert_response :redirect
      end
      assert_redirected_to project_repository_hooks_path(@project, @repository)
      assert_equal users(:johan), assigns(:hook).user
    end
    
    should "not create a new hook when invalid data is submitted" do
      assert_no_difference("@repository.hooks.count") do
        post :create, :project_id => @project.to_param, 
          :repository_id => @repository.to_param, :hook => {
            :url => ''
          }
      end
      assert_response :success
      assert_template "new"
    end
  end
end
