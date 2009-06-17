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

class HooksController < ApplicationController
  before_filter :login_required
  before_filter :find_repository
  before_filter :require_owner_adminship
  renders_in_global_context
  
  def index
    @hooks = @repository.hooks
    @root = Breadcrumb::RepositoryHooks.new(@repository)
  end
  
  def new
    @hook = @repository.hooks.new
    @hook.user = current_user
    @root = Breadcrumb::RepositoryHooks.new(@repository)
  end
  
  def create
    @hook = @repository.hooks.new(params[:hook])
    @hook.user = current_user
    @root = Breadcrumb::RepositoryHooks.new(@repository)
    if @hook.save
      redirect_to repo_owner_path(@repository, :project_repository_hooks_path,
                    @repository.project, @repository)
    else
      render "new"
    end
  end
  # 
  # def destroy
  #   
  # end
  
  protected
    def find_repository
      find_repository_owner
      @repository = @owner.repositories.find_by_name!(params[:repository_id])
    end
end
