class VisitsController < ApplicationController
  def index
    Visit.create!
    render json: { count: Visit.count }
  end
end
