class ContractsController < InheritedResources::Base
  unloadable

  respond_to :html

  before_filter :find_project
  before_filter :authorize

  def create
    create! { contract_url(@project, resource) }
  end
  
  protected

  def begin_of_association_chain
    @project
  end
  
  private
  
  def find_project
    @project = Project.find(params[:project_id])
  end

end